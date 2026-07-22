function Get-EFRemediationPlan {
    <#
    .SYNOPSIS
    Gets a read-only plan for fixing supported Windows settings.

    .DESCRIPTION
    Checks selected checklist items and separates changes EndpointForge can preview,
    items that need a person, items that could not be checked, and items that already
    match. It never changes Windows. EndpointForge calls checklist items controls in
    script output so existing automation remains compatible.

    .PARAMETER Baseline
    The checklist to use: a built-in name, JSON path, or validated checklist object.

    .PARAMETER ControlId
    Limits the plan to selected checklist item IDs.

    .PARAMETER IncludeCompliant
    Includes compliant and non-applicable steps in the Steps collection.

    .PARAMETER NoProgress
    Hides the checklist-check progress display.

    .EXAMPLE
    Get-EFRemediationPlan

    .EXAMPLE
    Get-EFRemediationPlan -ControlId EF-UAC-ENABLED -IncludeCompliant -NoProgress

    .OUTPUTS
    EndpointForge.RemediationPlan
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object]$Baseline = 'EnterpriseRecommended',

        [string[]]$ControlId,

        [switch]$IncludeCompliant,

        [switch]$NoProgress
    )

    $resolvedBaseline = Resolve-EFBaseline -Baseline $Baseline
    $reportParameters = @{
        Baseline   = $resolvedBaseline
        NoProgress = $NoProgress
    }
    if ($PSBoundParameters.ContainsKey('ControlId')) {
        $reportParameters.ControlId = $ControlId
    }
    $compliance = Get-EFComplianceReport @reportParameters

    $controlsById = @{}
    $baselineCommandArgument = Get-EFBaselineCommandArgument -Baseline $resolvedBaseline
    foreach ($control in @($resolvedBaseline.Controls)) {
        $controlsById[[string]$control.Id] = $control
    }

    $allSteps = @(
        foreach ($result in @($compliance.Results)) {
            $control = $controlsById[[string]$result.ControlId]
            $isRemediable = [bool](Get-EFPropertyValue -InputObject $control -Name 'Remediable' -Default $false)
            $requiresReboot = [bool](Get-EFPropertyValue -InputObject $control -Name 'RequiresReboot' -Default $false)
            $action = switch ([string]$result.Status) {
                'Compliant' { 'NoAction' }
                'NotApplicable' { 'NotApplicable' }
                'Error' { 'Blocked' }
                'NonCompliant' { if ($isRemediable) { 'Automatic' } else { 'Manual' } }
            }
            $commandPreview = if ($action -eq 'Automatic' -and $null -ne $baselineCommandArgument) {
                "Invoke-EFEndpointRemediation $baselineCommandArgument -ControlId '$($result.ControlId)' -WhatIf"
            }
            else { $null }

            [pscustomobject]@{
                PSTypeName        = 'EndpointForge.RemediationPlanStep'
                ControlId         = [string]$result.ControlId
                Title             = [string]$result.Title
                Type              = [string](Get-EFPropertyValue -InputObject $control -Name 'Type')
                Severity          = [string]$result.Severity
                CurrentStatus     = [string]$result.Status
                CurrentValue      = $result.ActualValue
                DesiredValue      = $result.DesiredValue
                Action            = $action
                RequiresElevation = $action -eq 'Automatic'
                RequiresReboot    = $requiresReboot
                Message           = [string]$result.Message
                RecommendedAction = [string]$result.RecommendedAction
                CanFixAutomatically = $action -eq 'Automatic'
                WhyItMatters      = [string](Get-EFPropertyValue -InputObject $control -Name 'WhyItMatters' -Default (
                    Get-EFPropertyValue -InputObject $result -Name 'WhyItMatters' -Default ''
                ))
                HowChecked        = [string](Get-EFPropertyValue -InputObject $control -Name 'HowChecked' -Default (
                    Get-EFPropertyValue -InputObject $result -Name 'HowChecked' -Default ''
                ))
                WhatWouldChange   = [string](Get-EFPropertyValue -InputObject $control -Name 'WhatWouldChange' -Default (
                    Get-EFPropertyValue -InputObject $result -Name 'WhatWouldChange' -Default ''
                ))
                ManualAction      = [string](Get-EFPropertyValue -InputObject $control -Name 'ManualAction' -Default (
                    Get-EFPropertyValue -InputObject $result -Name 'ManualAction' -Default $result.RecommendedAction
                ))
                SafetyNotes       = [string](Get-EFPropertyValue -InputObject $control -Name 'SafetyNotes' -Default (
                    Get-EFPropertyValue -InputObject $result -Name 'SafetyNotes' -Default ''
                ))
                RecoveryGuidance  = [string](Get-EFPropertyValue -InputObject $control -Name 'RecoveryGuidance' -Default (
                    Get-EFPropertyValue -InputObject $result -Name 'RecoveryGuidance' -Default ''
                ))
                CommandPreview    = $commandPreview
            }
        }
    )

    $automaticCount = @($allSteps | Where-Object Action -eq 'Automatic').Count
    $manualCount = @($allSteps | Where-Object Action -eq 'Manual').Count
    $blockedCount = @($allSteps | Where-Object Action -eq 'Blocked').Count
    $noActionCount = @($allSteps | Where-Object Action -eq 'NoAction').Count
    $notApplicableCount = @($allSteps | Where-Object Action -eq 'NotApplicable').Count
    $candidateCount = $automaticCount + $manualCount
    $planSteps = if ($IncludeCompliant) {
        $allSteps
    }
    else {
        @($allSteps | Where-Object Action -notin @('NoAction', 'NotApplicable'))
    }
    $summary = if ($blockedCount -gt 0) {
        "$candidateCount item(s) need attention; $blockedCount could not be checked. No settings were changed."
    }
    elseif ($candidateCount -gt 0) {
        "EndpointForge can preview $automaticCount supported fix(es); $manualCount item(s) need a person to review them."
    }
    else {
        'Every checked item already matches, is not used on this computer, or needs no supported fix.'
    }
    $nextStep = if ($blockedCount -gt 0) {
        'Review the items that could not be checked. If they need administrator permission, reopen PowerShell as Administrator and check again.'
    }
    elseif ($automaticCount -gt 0) {
        'Preview the supported fixes. The preview shows what would change without changing Windows.'
    }
    elseif ($manualCount -gt 0) {
        'Review the manual guidance and follow your organization''s approved process.'
    }
    else {
        'No action is required.'
    }

    [pscustomobject]@{
        PSTypeName         = 'EndpointForge.RemediationPlan'
        ComputerName       = $env:COMPUTERNAME
        BaselineName       = [string]$resolvedBaseline.Name
        BaselineVersion    = [string]$resolvedBaseline.Version
        CreatedAtUtc       = [DateTime]::UtcNow
        IsReady            = $blockedCount -eq 0
        RequiresElevation  = $automaticCount -gt 0
        PotentialReboot    = @($allSteps | Where-Object { $_.Action -eq 'Automatic' -and $_.RequiresReboot }).Count -gt 0
        CandidateCount     = $candidateCount
        WouldChangeCount   = $automaticCount
        AutomaticCount     = $automaticCount
        ManualCount        = $manualCount
        BlockedCount       = $blockedCount
        NoActionCount      = $noActionCount
        NotApplicableCount = $notApplicableCount
        ExitCode           = if ($blockedCount -gt 0) { 3 } elseif ($candidateCount -gt 0) { 2 } else { 0 }
        Summary            = $summary
        NextStep           = $nextStep
        AutomationHint     = if ($automaticCount -gt 0) { 'Invoke-EFEndpointRemediation -ControlId <approved item IDs> -WhatIf' } else { $null }
        Steps              = @($planSteps)
        Compliance         = $compliance
    }
}
