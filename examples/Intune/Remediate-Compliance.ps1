$ErrorActionPreference = 'Stop'

try {
    Import-Module EndpointForge -MinimumVersion 0.2.0 -Force
    Set-EFConfiguration -LogPath '%ProgramData%\EndpointForge\endpointforge.jsonl'
    $report = Invoke-EFEndpointRemediation -Confirm:$false

    Write-Output "Changed=$($report.ChangedCount); Remaining=$($report.RemainingCount); Failures=$($report.FailureCount); RebootRequired=$($report.RebootRequired)"
    if ($report.ExitCode -eq 0) { exit 0 }
    exit 1
}
catch {
    Write-Output "EndpointForge remediation failed: $($_.Exception.Message)"
    exit 1
}
