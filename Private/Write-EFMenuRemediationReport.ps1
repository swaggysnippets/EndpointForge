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
    $heading = if ($isPreview) { 'Preview - Windows was not changed' } else { 'Before-and-after change receipt' }
    $headingColor = if ([int]$Report.ExitCode -eq 0) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
    Write-EFMenuLine -Text '' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text $heading -Color Cyan -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ('-' * [math]::Min(72, $Width)) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ([string]$Report.Summary) -Color $headingColor -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("Selected changes: {0}   Completed: {1}   Preview only: {2}   Could not complete: {3}" -f `
        $Report.CandidateCount, $Report.ChangedCount, $Report.PreviewCount, $Report.FailureCount) `
        -NoColor:$NoColor -Width $Width
    foreach ($result in @($Report.Results)) {
        $resultColor = switch ([string]$result.Outcome) {
            'Changed' { [ConsoleColor]::Green }
            'PartiallyChanged' { [ConsoleColor]::Red }
            'NotRequired' { [ConsoleColor]::Green }
            'WhatIf' { [ConsoleColor]::Yellow }
            'Failed' { [ConsoleColor]::Red }
            'EvaluationFailed' { [ConsoleColor]::Red }
            'VerificationFailed' { [ConsoleColor]::Red }
            default { [ConsoleColor]::Gray }
        }
        $outcomeLabel = switch ([string]$result.Outcome) {
            'Changed' { 'CHANGED AND CHECKED' }
            'PartiallyChanged' { 'CHANGED, BUT NOT COMPLETED' }
            'WhatIf' { 'PREVIEW ONLY - NOT CHANGED' }
            'NotRequired' { 'ALREADY MATCHES' }
            'NotApplicable' { 'NOT USED ON THIS COMPUTER' }
            'NotRemediable' { 'YOU NEED TO REVIEW' }
            'Skipped' { 'NOT APPROVED' }
            default { 'COULD NOT COMPLETE' }
        }
        Write-EFMenuLine -Text ("[{0}] {1}" -f $outcomeLabel, $result.Title) `
            -Color $resultColor -NoColor:$NoColor -Width $Width -Indent 2
        if (Test-EFPropertyPresent $result 'BeforeValue') {
            Write-EFMenuLine -Text ("Before: {0}   Expected: {1}   After: {2}" -f `
                (ConvertTo-EFMenuValue $result.BeforeValue), (ConvertTo-EFMenuValue $result.DesiredValue), `
                (ConvertTo-EFMenuValue $result.AfterValue)) -NoColor:$NoColor -Width $Width -Indent 4
        }
        if (-not [string]::IsNullOrWhiteSpace([string](Get-EFPropertyValue $result 'WhatChanged' ''))) {
            Write-EFMenuLine -Text ([string]$result.WhatChanged) -NoColor:$NoColor -Width $Width -Indent 4
        }
        $recoveryMayBeNeeded = [bool](Get-EFPropertyValue $result 'ChangeWasApplied' $false) -or
            [bool](Get-EFPropertyValue $result 'ChangeMayHaveOccurred' $false)
        if ($recoveryMayBeNeeded -and -not [string]::IsNullOrWhiteSpace([string](Get-EFPropertyValue $result 'RecoveryGuidance' ''))) {
            Write-EFMenuLine -Text ("If recovery is needed: {0}" -f $result.RecoveryGuidance) -Color Yellow -NoColor:$NoColor -Width $Width -Indent 4
        }
    }
    Write-EFMenuLine -Text ("What to do next: {0}" -f $Report.NextStep) -NoColor:$NoColor -Width $Width
}
