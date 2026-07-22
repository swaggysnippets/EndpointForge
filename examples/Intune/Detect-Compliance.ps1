$ErrorActionPreference = 'Stop'

try {
    Import-Module EndpointForge -MinimumVersion 0.6.0 -Force
    $report = Get-EFComplianceReport -NoProgress

    if ($report.IsCompliant) {
        Write-Output "Matches checklist: $($report.CompliantCount) applicable item(s) passed."
        exit 0
    }

    $failedIds = @($report.Results | Where-Object Status -in @('NonCompliant', 'Error') | ForEach-Object ControlId)
    Write-Output "Needs attention or could not check: $($failedIds -join ', ')"
    exit 1
}
catch {
    Write-Output "EndpointForge detection failed: $($_.Exception.Message)"
    exit 1
}
