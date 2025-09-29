using module .\DatasetEntry.psm1

param(
    [Parameter(Mandatory=$false)]
    [string]$DatasetPath = "$PSScriptRoot\..\..\dataset\bcbench_nav.jsonl",

    [Parameter(Mandatory=$false)]
    [string]$Country = "w1",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

Import-Module "$PSScriptRoot/BCContainerManagement.psm1" -Force

Write-Host "BC-Bench Evaluation Starting..." -ForegroundColor Green
Write-Host "Dataset Path: $DatasetPath" -ForegroundColor Gray

# Read all dataset entries
try {
    [DatasetEntry[]] $entries = Get-DatasetEntries -DatasetPath $DatasetPath
    Write-Host "Found $($entries.Count) entries in dataset" -ForegroundColor Green
}
catch {
    Write-Error "Failed to read dataset: $($_.Exception.Message)"
    exit 1
}

Write-Host "`nProcessing entries..." -ForegroundColor Green

[int] $successCount = 0
[int] $errorCount = 0

foreach ($entry in $entries) {
    Write-Host "`n--- Processing Entry ---" -ForegroundColor Cyan
    Write-Host "Instance ID: $($entry.instance_id)" -ForegroundColor White

    # Get the environment setup version directly from the property
    [string] $environmentVersion = $entry.environment_setup_version

    if ([string]::IsNullOrEmpty($environmentVersion)) {
        Write-Warning "No environment_setup_version found for entry $($entry.instance_id). Skipping."
        $errorCount++
        continue
    }

    Write-Host "Environment Setup Version: $environmentVersion" -ForegroundColor White

    if ($DryRun) {
        Write-Host "[DRY Run] Would call: Set-BCEnvironment -Version '$environmentVersion' -Country '$Country'" -ForegroundColor Yellow
        $successCount++
    }
    else {
        try {
            [string] $containerName = "bcbench-$($environmentVersion -replace '\.', '')"
            [bool] $ContainerExists = Test-ContainerExists -ContainerName $containerName

            if (-not $ContainerExists) {
                [string] $url = Get-BCArtifactUrl -version $environmentVersion -Country $Country
                Write-Host "Creating container $containerName with artifact $url" -ForegroundColor Green

                New-BCContainer -accept_eula -artifactUrl $url -containerName $containerName
                Initialize-ContainerForDevelopment -ContainerName $containerName -RepoVersion ([System.Version]$environmentVersion)
            } else {
                Write-Host "Container $containerName already exists. Skipping creation." -ForegroundColor Yellow
            }

            Write-Host "Environment setup completed successfully" -ForegroundColor Green
            $successCount++
        }
        catch {
            Write-Error "Failed to setup environment for entry $($entry.instance_id): $($_.Exception.Message)"
            $errorCount++
        }
    }

    # TODO
}

Write-Host "`n--- Evaluation Summary ---" -ForegroundColor Green
Write-Host "Total entries processed: $($entries.Count)" -ForegroundColor White
Write-Host "Successful setups: $successCount" -ForegroundColor Green
Write-Host "Failed setups: $errorCount" -ForegroundColor Red
