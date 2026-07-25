function Write-EFMenuManagementAgentAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Result,

        [switch]$NoColor,

        [ValidateRange(20, 240)]
        [int]$Width = 80
    )

    $label = switch ([string]$Result.Outcome) {
        'WhatIf' { '[PREVIEW ONLY]' }
        'Completed' { '[LOCAL ACTION COMPLETED]' }
        'RequestAccepted' { '[REQUEST ACCEPTED]' }
        'NotRequired' { '[NO CHANGE NEEDED]' }
        'Skipped' { '[CANCELLED]' }
        'PartiallyChanged' { '[PARTIAL OR UNCERTAIN CHANGE]' }
        default { '[ACTION FAILED]' }
    }
    $color = if ([bool]$Result.IsSuccessful) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
    if ([string]$Result.Outcome -in @('Failed', 'PartiallyChanged')) { $color = [ConsoleColor]::Red }

    Write-EFMenuLine -Text '' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ("{0} {1} - {2}" -f $label, $Result.Agent, $Result.Action) -Color $color -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ([string]$Result.Summary) -NoColor:$NoColor -Width $Width -Indent 2
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.BeforeServiceStatus) -or
        -not [string]::IsNullOrWhiteSpace([string]$Result.AfterServiceStatus)) {
        Write-EFMenuLine -Text ("Local service before: {0}; after: {1}" -f $Result.BeforeServiceStatus, $Result.AfterServiceStatus) -NoColor:$NoColor -Width $Width -Indent 2
    }
    if ([bool]$Result.RequestAccepted -and -not [bool]$Result.ImmediateEffectVerified) {
        Write-EFMenuLine -Text 'The client accepted an asynchronous request. EndpointForge cannot claim that synchronization or policy work finished.' -Color Yellow -NoColor:$NoColor -Width $Width -Indent 2
    }
    if ([bool]$Result.ChangeMayHaveOccurred -and -not [bool]$Result.IsSuccessful) {
        Write-EFMenuLine -Text 'A change or request may have begun even though a successful result was not confirmed.' -Color Red -NoColor:$NoColor -Width $Width -Indent 2
    }
    Write-EFMenuLine -Text ("Next step: {0}" -f $Result.NextStep) -NoColor:$NoColor -Width $Width -Indent 2
    Write-EFMenuLine -Text ("Recovery: {0}" -f $Result.RecoveryGuidance) -NoColor:$NoColor -Width $Width -Indent 2
}
