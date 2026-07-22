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
                'Generate a baseline-aware preview with Get-EFRemediationPlan, then review Invoke-EFEndpointRemediation -WhatIf.'
            }
            else {
                'Review this control and remediate it through your approved enterprise policy or management platform.'
            }
        }
        'Error' {
            if ($Message -match 'elevat|access.+denied|administrator|privilege') {
                'Run the assessment from an elevated PowerShell session, then evaluate this control again.'
            }
            else {
                'Review the error, verify that the Windows capability is available, and evaluate this control again.'
            }
        }
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
        RecommendedAction = $recommendedAction
        EvaluatedAtUtc = [DateTime]::UtcNow
    }
}
