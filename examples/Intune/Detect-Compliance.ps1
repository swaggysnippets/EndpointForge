$ErrorActionPreference = 'Stop'

try {
    Import-Module EndpointForge -MinimumVersion 0.2.0 -Force
    $report = Get-EFComplianceReport -NoProgress

    if ($report.IsCompliant) {
        Write-Output "Compliant: $($report.CompliantCount) controls passed."
        exit 0
    }

    $failedIds = @($report.Results | Where-Object Status -in @('NonCompliant', 'Error') | ForEach-Object ControlId)
    Write-Output "Noncompliant: $($failedIds -join ', ')"
    exit 1
}
catch {
    Write-Output "EndpointForge detection failed: $($_.Exception.Message)"
    exit 1
}
