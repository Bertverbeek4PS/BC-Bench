using module .\DatasetEntry.psm1
using module .\BCBenchUtils.psm1

<#
    .Synopsis
    Merges all evaluation result JSONL files into a single JSONL file.
    .Description
    Designed to be run after `gh run download <run-id> --dir .\evaluation_results\ -p "evaluation-results-*"`
#>

param(
    [string] $InputDir = "$PSScriptRoot\..\evaluation_results",
    [string] $DatasetFile = (Get-BCBenchDatasetPath)
)

$resultFolders = Get-ChildItem -Path $InputDir -Directory -Filter "evaluation-results-*"
if ($resultFolders.Count -eq 0) {
    Write-Log "No evaluation-results-* folders found in $InputDir" -Level Error
    exit 1
}

# Group folders by run ID (second segment after splitting by '-')
$foldersByRunId = $resultFolders | Group-Object { ($_.Name -split '-')[2] }
Write-Log "Found $($foldersByRunId.Count) run(s) to process"

$datasetIds = (Get-DatasetEntries -DatasetPath $DatasetFile).instance_id

foreach ($runGroup in $foldersByRunId) {
    $runId = $runGroup.Name
    $runFolders = $runGroup.Group
    $OutputFile = Join-Path $InputDir "$runId.jsonl"

    Write-Log "Merging results for run $runId to $OutputFile"

    # Merge all JSONL files for this run
    $jsonlFiles = $runFolders | ForEach-Object { Get-ChildItem $_.FullName -Filter "*.jsonl" -Recurse }
    $evaluatedIds = $jsonlFiles | Get-Content | Tee-Object -FilePath $OutputFile | ForEach-Object { ($_ | ConvertFrom-Json).instance_id }

    Write-Log "Merged $($evaluatedIds.Count) results from $($jsonlFiles.Count) files" -Level Success

    # Report missing instances
    $missing = $datasetIds | Where-Object { $_ -notin $evaluatedIds }

    if ($missing) {
        Write-Log "Missing $($missing.Count) of $($datasetIds.Count) instances:" -Level Warning
        $missing | ForEach-Object { Write-Log "  $_" -Level Warning }
    }
    else {
        Write-Log "All $($datasetIds.Count) instances evaluated!" -Level Success
    }

    # Cleanup folders for this run
    $runFolders | Remove-Item -Recurse -Force
    Write-Log "Cleaned up $($runFolders.Count) folders for run $runId" -Level Success
}

Write-Host "`nDone! Processed $($foldersByRunId.Count) run(s), deleted $($resultFolders.Count) folders total."
