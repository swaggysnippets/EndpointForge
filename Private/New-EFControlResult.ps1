function New-EFControlResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This private constructor only returns an in-memory result object and does not change state.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Control,

        [Parameter(Mandatory)]
        [ValidateSet('Compliant', 'NonCompliant', 'NotApplicable', 'Error')]
        [string]$Status,

        [AllowNull()]
        [object]$ActualValue,

        [AllowNull()]
        [object]$DesiredValue,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $controlId = [string](Get-EFPropertyValue -InputObject $Control -Name 'Id')
    $remediable = [bool](Get-EFPropertyValue -InputObject $Control -Name 'Remediable' -Default $false)
    $recommendedAction = switch ($Status) {
        'Compliant' { 'No action required.' }
        'NotApplicable' { 'No action is required on this endpoint.' }
        'NonCompliant' {
            if ($remediable) {
                'Review a fix plan, then preview the exact change before an administrator approves it.'
            }
            else {
                'Review this item and follow the manual guidance approved by your organization.'
            }
        }
        'Error' {
            if ($Message -match 'elevat|access.+denied|administrator|privilege') {
                'Open PowerShell as Administrator and run the check again. No setting was changed.'
            }
            else {
                'Review why the item could not be checked, then run the check again. No setting was changed.'
            }
        }
    }
    $defaultWhatWouldChange = if ($remediable) {
        'EndpointForge can preview the supported setting change before an administrator approves it.'
    }
    else {
        'Nothing. EndpointForge reports this item but does not change it automatically.'
    }
    $defaultHowChecked = [string](
        Get-EFControlCapability -Control $Control -IsWindowsPlatform $true -IsAdministrator $false
    ).HowChecked
    $defaultSafetyNotes = if ($remediable) {
        'Review the current and expected values before making any change.'
    }
    else {
        'This is a report-only item. Review the result in context before taking manual action.'
    }
    $defaultRecoveryGuidance = if ($remediable) {
        'Use the before value in the change receipt and your approved Windows management process if recovery is needed.'
    }
    else {
        'EndpointForge makes no change for this item, so there is no EndpointForge change to undo.'
    }

    [pscustomobject]@{
        PSTypeName    = 'EndpointForge.ControlResult'
        ControlId     = $controlId
        Title         = [string](Get-EFPropertyValue -InputObject $Control -Name 'Title')
        Type          = [string](Get-EFPropertyValue -InputObject $Control -Name 'Type')
        Severity      = [string](Get-EFPropertyValue -InputObject $Control -Name 'Severity' -Default 'Medium')
        Status        = $Status
        ActualValue   = $ActualValue
        DesiredValue  = $DesiredValue
        Message       = $Message
        Remediable    = $remediable
        CanFixAutomatically = $remediable
        WhyItMatters  = [string](Get-EFPropertyValue -InputObject $Control -Name 'WhyItMatters' -Default (
            Get-EFPropertyValue -InputObject $Control -Name 'Description' -Default 'This item is part of the selected checklist.'
        ))
        HowChecked    = [string](Get-EFPropertyValue -InputObject $Control -Name 'HowChecked' -Default $defaultHowChecked)
        WhatWouldChange = [string](Get-EFPropertyValue -InputObject $Control -Name 'WhatWouldChange' -Default $defaultWhatWouldChange)
        ManualAction  = [string](Get-EFPropertyValue -InputObject $Control -Name 'ManualAction' -Default 'Ask your IT administrator to review this item using your organization''s approved process.')
        SafetyNotes   = [string](Get-EFPropertyValue -InputObject $Control -Name 'SafetyNotes' -Default $defaultSafetyNotes)
        RecoveryGuidance = [string](Get-EFPropertyValue -InputObject $Control -Name 'RecoveryGuidance' -Default $defaultRecoveryGuidance)
        RecommendedAction = $recommendedAction
        EvaluatedAtUtc = [DateTime]::UtcNow
    }
}
