<#
.SYNOPSIS
    BC-Bench Utilities Module
.DESCRIPTION
    Common utility functions used across BC-Bench PowerShell scripts
#>

<#
.SYNOPSIS
    Creates a PSCredential object from various authentication sources
.DESCRIPTION
    Handles credential creation from parameter or environment variable with conflict detection
.PARAMETER Username
    The username for authentication
.PARAMETER Password
    Optional SecureString password parameter
.PARAMETER EnvironmentVariableName
    Name of environment variable containing password (default: BC_CONTAINER_PASSWORD)
.OUTPUTS
    PSCredential object
.EXAMPLE
    $cred = Get-BCCredential -Username "admin" -Password $securePassword
.EXAMPLE
    $cred = Get-BCCredential -Username "admin" # Uses BC_CONTAINER_PASSWORD env var
#>
function Get-BCCredential {
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $false)]
        [SecureString]$Password,

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentVariableName = "BC_CONTAINER_PASSWORD"
    )

    # Get environment password
    [string] $envPassword = [Environment]::GetEnvironmentVariable($EnvironmentVariableName)
    [bool] $hasParameterPassword = $null -ne $Password
    [bool] $hasEnvPassword = -not [string]::IsNullOrEmpty($envPassword)

    # Check for conflicts
    if ($hasParameterPassword -and $hasEnvPassword) {
        throw "Conflict: Both -Password parameter and $EnvironmentVariableName environment variable are provided. Please use only one method for providing the password."
    }

    # Create credential based on available source
    if ($hasParameterPassword) {
        Write-Verbose "Using Username/Password from parameters"
        return New-Object System.Management.Automation.PSCredential($Username, $Password)
    }
    elseif ($hasEnvPassword) {
        Write-Verbose "Using Username/Password from environment variable: $EnvironmentVariableName"
        $secureEnvPassword = ConvertTo-SecureString -String $envPassword -AsPlainText -Force
        return New-Object System.Management.Automation.PSCredential($Username, $secureEnvPassword)
    }
    else {
        throw "Authentication credentials are required. Provide either: 1. -Password parameter, 2. $EnvironmentVariableName environment variable"
    }
}

<#
.SYNOPSIS
    Clones a Git repository with authentication and retry logic
.DESCRIPTION
    Clones a repository using token authentication with configurable retry attempts
.PARAMETER RepoUrl
    Base URL of the repository (without authentication)
.PARAMETER Token
    Authentication token for repository access
.PARAMETER Branch
    Specific branch to clone
.PARAMETER ClonePath
    Local path where repository should be cloned
.PARAMETER MaxRetries
    Maximum number of retry attempts (default: 2)
.PARAMETER RetryDelaySeconds
    Delay between retry attempts in seconds (default: 5)
.PARAMETER SparseCheckoutPaths
    Optional list of paths to include via sparse checkout. Enables git sparse checkout when provided.
.PARAMETER PrefetchCommits
    Optional list of commit SHAs to prefetch after cloning to warm required objects.
.EXAMPLE
    Invoke-GitCloneWithRetry -RepoUrl "https://example.com/repo.git" -Token $token -Branch "main" -ClonePath "C:\temp\repo"
#>
function Invoke-GitCloneWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoUrl,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$Branch,

        [Parameter(Mandatory = $true)]
        [string]$ClonePath,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 2,

        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 5,

        [Parameter(Mandatory = $false)]
        [string[]]$SparseCheckoutPaths,

        [Parameter(Mandatory = $false)]
        [string[]]$PrefetchCommits
    )

    # Remove existing clone if it exists
    if (Test-Path $ClonePath) {
        Write-Log "Removing existing directory at $ClonePath" -Level Warning
        Remove-Item -Path $ClonePath -Recurse -Force
    }

    # Extract domain and path from URL for authentication
    $uri = [System.Uri]$RepoUrl
    $authenticatedUrl = "https://$($Token)@$($uri.Authority)$($uri.PathAndQuery)"

    [int] $retryCount = 0
    [bool] $cloneSuccess = $false

    while ($retryCount -lt $MaxRetries -and -not $cloneSuccess) {
        $retryCount++
        try {
            Write-Log "Attempting repository clone (Attempt $retryCount/$MaxRetries)..." -Level Info

            $cloneArgs = "--filter=blob:none --single-branch --no-tags"
            if ($SparseCheckoutPaths -and $SparseCheckoutPaths.Count -gt 0) {
                $cloneArgs += " --sparse"
            }

            $cloneCommand = "git clone $cloneArgs -b `"$Branch`" `"$authenticatedUrl`" `"$ClonePath`""
            $cloneResult = Invoke-Expression $cloneCommand 2>&1

            if ($LASTEXITCODE -eq 0) {
                $cloneSuccess = $true
                Write-Log "Repository cloned successfully to $ClonePath" -Level Success

                if ($SparseCheckoutPaths -and $SparseCheckoutPaths.Count -gt 0) {
                    Write-Log "Configuring sparse checkout for paths: $($SparseCheckoutPaths -join ', ')" -Level Debug

                    $sparseInitResult = & git -C $ClonePath sparse-checkout init --cone 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Log "Failed to initialize sparse checkout: $sparseInitResult" -Level Error
                        return $false
                    }

                    $sparseSetResult = & git -C $ClonePath sparse-checkout set @SparseCheckoutPaths 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Log "Failed to set sparse checkout paths: $sparseSetResult" -Level Error
                        return $false
                    }

                    Write-Log "Sparse checkout configured successfully" -Level Success
                }

                if ($PrefetchCommits -and $PrefetchCommits.Count -gt 0) {
                    foreach ($commit in $PrefetchCommits) {
                        if ([string]::IsNullOrWhiteSpace($commit)) { continue }
                        Write-Log "Prefetching commit $commit" -Level Info
                        $fetchResult = & git -C $ClonePath fetch origin $commit 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            Write-Log "Failed to prefetch commit $commit\: $fetchResult" -Level Error
                            return $false
                        }
                    }

                    Write-Log "Prefetch completed for specified commits" -Level Success
                }

                return $true
            } else {
                throw "Git clone failed with exit code $LASTEXITCODE`: $cloneResult"
            }
        }
        catch {
            Write-Log "Clone attempt $retryCount failed: $($_.Exception.Message)" -Level Error
            if ($retryCount -eq $MaxRetries) {
                Write-Log "Failed to clone repository after $MaxRetries attempts" -Level Error
                return $false
            } else {
                Write-Log "Retrying in $RetryDelaySeconds seconds..." -Level Warning
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    return $false
}

<#
.SYNOPSIS
    Monitors a PowerShell job until completion
.DESCRIPTION
    Monitors job progress with periodic status updates and handles completion/failure
.PARAMETER Job
    The PowerShell job to monitor
.PARAMETER PollingIntervalSeconds
    How often to check job status in seconds (default: 60)
.PARAMETER StatusMessage
    Custom status message to display during monitoring
.PARAMETER TimeoutMinutes
    Maximum time to wait for job completion in minutes (default: 20)
.OUTPUTS
    Returns $true if job completed successfully, $false otherwise
.EXAMPLE
    $job = Start-Job -ScriptBlock { Start-Sleep 30 }
    $success = Wait-JobWithProgress -Job $job -StatusMessage "Processing data"
.EXAMPLE
    $success = Wait-JobWithProgress -Job $job -StatusMessage "Long task" -TimeoutMinutes 30
#>
function Wait-JobWithProgress {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Job]$Job,

        [Parameter(Mandatory = $false)]
        [int]$PollingIntervalSeconds = 60,

        [Parameter(Mandatory = $false)]
        [string]$StatusMessage = "Job",

        [Parameter(Mandatory = $false)]
        [int]$TimeoutMinutes = 20
    )

    Write-Log "Waiting for $StatusMessage to complete (timeout: $TimeoutMinutes minutes)..." -Level Info

    # Calculate timeout
    $timeoutSeconds = $TimeoutMinutes * 60
    $startTime = Get-Date
    $elapsedSeconds = 0

    # Monitor job progress
    do {
        Start-Sleep -Seconds $PollingIntervalSeconds
        $elapsedSeconds = ((Get-Date) - $startTime).TotalSeconds
        $remainingMinutes = [math]::Max(0, [math]::Round(($timeoutSeconds - $elapsedSeconds) / 60, 1))

        $jobState = Get-Job -Id $Job.Id | Select-Object -ExpandProperty State
        Write-Log "$StatusMessage status: $jobState (${remainingMinutes}min remaining)" -Level Info

        # Check for timeout
        if ($elapsedSeconds -ge $timeoutSeconds) {
            Write-Log "$StatusMessage timed out after $TimeoutMinutes minutes" -Level Warning
            Stop-Job $Job -ErrorAction SilentlyContinue
            Remove-Job $Job -Force -ErrorAction SilentlyContinue
            return $false
        }
    } while ($jobState -eq "Running")

    # Check job results
    if ($jobState -eq "Completed") {
        Write-Log "$StatusMessage completed successfully" -Level Success
        Remove-Job $Job
        return $true
    } else {
        # Get error details
        $jobError = Receive-Job $Job -ErrorAction SilentlyContinue
        $jobOutput = Receive-Job $Job
        Write-Log "$StatusMessage failed. State: $jobState" -Level Error
        if ($jobError) { Write-Log "Error details: $jobError" -Level Error }
        if ($jobOutput) { Write-Log "Output: $jobOutput" -Level Debug }
        Remove-Job $Job
        return $false
    }
}

<#
.SYNOPSIS
    Writes colorful log messages with standardized formatting
.DESCRIPTION
    Provides consistent logging output with color coding for different log levels.
    Optimized for GitHub Actions with proper formatting and colors.
.PARAMETER Message
    The message to log
.PARAMETER Level
    Log level: Info, Warning, Error, Success, Debug (default: Info)
.EXAMPLE
    Write-Log "Operation completed successfully" -Level Success
    Write-Log "Missing configuration file" -Level Warning
    Write-Log "Authentication failed" -Level Error
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Success", "Debug")]
        [string]$Level = "Info"
    )

    $logConfig = @{
        "Info"    = @{ Color = "White"; AnsiColor = "`e[37m" }      # White
        "Warning" = @{ Color = "Yellow"; AnsiColor = "`e[33m" }  # Yellow
        "Error"   = @{ Color = "Red"; AnsiColor = "`e[31m" }       # Red
        "Success" = @{ Color = "Green"; AnsiColor = "`e[32m" }   # Green
        "Debug"   = @{ Color = "Cyan"; AnsiColor = "`e[36m" }      # Cyan
    }

    $config = $logConfig[$Level]
    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $formattedMessage = "[$timestamp] $Message"

    if ($env:CI -eq "true") {
        # Reset ANSI color code
        $resetColor = "`e[0m"

        # Using Console.Out preserves ANSI escape sequences in GitHub Actions logs
        [Console]::Out.WriteLine("$($config.AnsiColor)$formattedMessage$resetColor")
    } else {
        # Local execution - write with color
        Write-Host $formattedMessage -ForegroundColor $config.Color
    }
}

Export-ModuleMember -Function Get-BCCredential, Invoke-GitCloneWithRetry, Wait-JobWithProgress, Get-EnvironmentVariable, Write-Log