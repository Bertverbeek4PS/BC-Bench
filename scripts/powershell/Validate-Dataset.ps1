using module .\DatasetEntry.psm1
using module .\BCBenchUtils.psm1

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,

    [Parameter(Mandatory=$false)]
    [string]$DatasetPath = "$PSScriptRoot\..\..\dataset\bcbench_nav.jsonl",

    [Parameter(Mandatory=$false)]
    [string]$NAVClonePath
)

Write-Log "Running BC Bench Dataset Validation for version $Version, , Dataset Path: $DatasetPath ..." -Level Info

# If NAVClonePath is not provided, determine it from the standard location
if (-not $NAVClonePath) {
    $NAVClonePath = Join-Path -Path $env:TEMP -ChildPath "NAV-$Version"
    Write-Log "Using default NAV clone path: $NAVClonePath" -Level Info
} else {
    Write-Log "Using provided NAV clone path: $NAVClonePath" -Level Info
}

if (-not (Test-Path $NAVClonePath)) {
    Write-Error "NAV repository not found at: $NAVClonePath. Please run Setup-ValidationEnvironment.ps1 first."
    exit 1
}

Write-Log "Loading dataset entries for version $Version..." -Level Info
try {
    [DatasetEntry[]] $entries = Get-DatasetEntries -DatasetPath $DatasetPath
    [DatasetEntry[]] $versionEntries = $entries | Where-Object { $_.environment_setup_version -eq $Version }

    if ($versionEntries.Count -eq 0) {
        Write-Log "No dataset entries found for version $Version" -Level Warning
        exit 0
    }

    Write-Log "Found $($versionEntries.Count) entries for version $Version" -Level Info
}
catch {
    Write-Error "Failed to load dataset entries: $($_.Exception.Message)"
    exit 1
}

# Validate each dataset entry
$validationResults = @()
$successCount = 0
$failureCount = 0

foreach ($entry in $versionEntries) {
    Write-Log "Validating entry: $($entry.instance_id)" -Level Info

    try {
        Push-Location $NAVClonePath

        Write-Log "Checking out base commit: $($entry.base_commit)" -Level Info
        $checkoutResult = git checkout $entry.base_commit 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Successfully checked out base commit for $($entry.instance_id)" -Level Success
            $validationResults += [PSCustomObject]@{
                InstanceId = $entry.instance_id
                BaseCommit = $entry.base_commit
                Status = "Success"
                Message = "Base commit checkout successful"
            }
            $successCount++
        } else {
            Write-Log "Failed to checkout base commit for $($entry.instance_id): $checkoutResult" -Level Error
            $validationResults += [PSCustomObject]@{
                InstanceId = $entry.instance_id
                BaseCommit = $entry.base_commit
                Status = "Failed"
                Message = "Git checkout failed: $checkoutResult"
            }
            $failureCount++
        }
    }
    catch {
        Write-Log "Exception while validating $($entry.instance_id): $($_.Exception.Message)" -Level Error
        $validationResults += [PSCustomObject]@{
            InstanceId = $entry.instance_id
            BaseCommit = $entry.base_commit
            Status = "Error"
            Message = $_.Exception.Message
        }
        $failureCount++
    }
    finally {
        Pop-Location
    }
}

# Summary
Write-Host "`n" -NoNewline
Write-Log "=== Validation Summary ===" -Level Info
Write-Log "Total entries processed: $($versionEntries.Count)" -Level Info
Write-Log "Successful validations: $successCount" -Level Success
Write-Log "Failed validations: $failureCount" -Level $(if ($failureCount -gt 0) { "Error" } else { "Info" })

if ($env:RUNNER_DEBUG -eq '1') {
    Write-Host "`n" -NoNewline
    Write-Log "Detailed Results:" -Level Warning
    $validationResults | Format-Table -Property InstanceId, Status, Message -AutoSize
}

# Exit with appropriate code
if ($failureCount -gt 0) {
    Write-Log "Dataset validation completed with failures" -Level Error
    exit 1
} else {
    Write-Log "Dataset validation completed successfully" -Level Success
    exit 0
}