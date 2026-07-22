function Get-EFRemediationPlan {
    <#
    .SYNOPSIS
    Gets a read-only remediation plan for the local endpoint.

    .DESCRIPTION
    Evaluates selected controls and separates automatic changes, manual actions,
    blockers, compliant controls, and non-applicable controls. It never changes endpoint
    state and should be reviewed before Invoke-EFEndpointRemediation.

    .PARAMETER Baseline
    A built-in baseline name, JSON path, or validated baseline object.

    .PARAMETER ControlId
    Limits the plan to selected control identifiers.

    .PARAMETER IncludeCompliant
    Includes compliant and non-applicable steps in the Steps collection.

    .PARAMETER NoProgress
    Suppresses the compliance progress display.

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
        "$candidateCount remediation candidate(s); $blockedCount control(s) are blocked by evaluation errors."
    }
    elseif ($candidateCount -gt 0) {
        "$automaticCount automatic change(s) and $manualCount manual action(s) are recommended."
    }
    else {
        'No remediation candidates were found.'
    }
    $nextStep = if ($blockedCount -gt 0) {
        'Resolve blocked evaluations, often by running elevated, then generate the plan again.'
    }
    elseif ($automaticCount -gt 0) {
        'Preview automatic changes with Invoke-EFEndpointRemediation -WhatIf.'
    }
    elseif ($manualCount -gt 0) {
        'Review manual actions and apply them through your approved enterprise process.'
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
        Steps              = @($planSteps)
        Compliance         = $compliance
    }
}
