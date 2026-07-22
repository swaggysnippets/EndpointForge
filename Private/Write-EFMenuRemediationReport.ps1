function Write-EFMenuRemediationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Report,

        [switch]$NoColor,

        [ValidateRange(20, 240)]
        [int]$Width = 80
    )

    $isPreview = [int]$Report.PreviewCount -gt 0
    $heading = if ($isPreview) { 'Remediation preview' } else { 'Remediation result' }
    $headingColor = if ([int]$Report.ExitCode -eq 0) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
    Write-EFMenuLine -Text '' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text $heading -Color Cyan -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ('-' * [math]::Min(72, $Width)) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ([string]$Report.Summary) -Color $headingColor -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("Candidates: {0}   Changed: {1}   Previewed: {2}   Failed: {3}" -f `
        $Report.CandidateCount, $Report.ChangedCount, $Report.PreviewCount, $Report.FailureCount) `
        -NoColor:$NoColor -Width $Width
    foreach ($result in @($Report.Results)) {
        $resultColor = switch ([string]$result.Outcome) {
            'Changed' { [ConsoleColor]::Green }
            'NotRequired' { [ConsoleColor]::Green }
            'WhatIf' { [ConsoleColor]::Yellow }
            'Failed' { [ConsoleColor]::Red }
            'EvaluationFailed' { [ConsoleColor]::Red }
            'VerificationFailed' { [ConsoleColor]::Red }
            default { [ConsoleColor]::Gray }
        }
        Write-EFMenuLine -Text ("[{0}] {1} - {2}" -f ([string]$result.Outcome).ToUpperInvariant(), $result.ControlId, $result.Title) `
            -Color $resultColor -NoColor:$NoColor -Width $Width -Indent 2
    }
    Write-EFMenuLine -Text ("Next: {0}" -f $Report.NextStep) -NoColor:$NoColor -Width $Width
}
