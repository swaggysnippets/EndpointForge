function Invoke-EFManagementAgentAction {
    <#
    .SYNOPSIS
    Previews or requests one guarded Intune or Configuration Manager support action.

    .DESCRIPTION
    Offers a fixed allowlist of local management-agent actions. Intune and Configuration
    Manager can start or restart their agent service. Configuration Manager can also
    request machine policy or evaluate machine policy that is already local.

    Every action can contact the configured management service and can lead to assigned
    applications, scripts, policy, updates, or other work. Use WhatIf first. Actual actions
    require Administrator permission, AllowManagementTraffic, and normal PowerShell
    confirmation. This command does not prove that asynchronous check-in or policy work
    finished successfully.

    EndpointForge does not expose arbitrary commands, services, CIM methods, schedule IDs,
    remote computers, cache deletion, re-enrollment, reinstall, or policy reset through
    this command.

    .PARAMETER Agent
    The one local agent to use. ConfigurationManager is also commonly called ConfigMgr,
    SCCM, or CCM; those familiar names are accepted.

    .PARAMETER Action
    StartAgentService or RestartAgentService can be used with either agent.
    RequestMachinePolicy and EvaluateMachinePolicy can be used only with
    ConfigurationManager.

    .PARAMETER AllowManagementTraffic
    Confirms that the action is allowed to contact this computer's configured management
    service and may begin assigned management work. It does not bypass WhatIf, confirmation,
    Administrator permission, or the fixed action allowlist.

    .PARAMETER TimeoutSeconds
    Maximum time to wait for the local service transition or Configuration Manager client
    request. A timeout after a request begins can leave the result uncertain.

    .EXAMPLE
    Invoke-EFManagementAgentAction -Agent Intune -Action RestartAgentService -WhatIf

    .EXAMPLE
    Invoke-EFManagementAgentAction -Agent ConfigurationManager -Action RequestMachinePolicy -AllowManagementTraffic -Confirm:$false

    .OUTPUTS
    EndpointForge.ManagementAgentActionResult

    .LINK
    Get-EFManagementAgentHealth
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('EndpointForge.ManagementAgentActionResult')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Intune', 'ConfigurationManager', 'CCM', 'SCCM', 'ConfigMgr')]
        [string]$Agent,

        [Parameter(Mandatory)]
        [ValidateSet('StartAgentService', 'RestartAgentService', 'RequestMachinePolicy', 'EvaluateMachinePolicy')]
        [string]$Action,

        [switch]$AllowManagementTraffic,

        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 60
    )

    $null = Test-EFWindows -Throw
    $canonicalAgent = if ($Agent -eq 'Intune') { 'Intune' } else { 'ConfigurationManager' }
    $definition = Get-EFManagementAgentDefinition -Agent $canonicalAgent
    if ($Action -notin @($definition.AvailableActions)) {
        throw [System.ArgumentException]::new(
            "Action '$Action' is not available for $canonicalAgent. Available actions: $($definition.AvailableActions -join ', ')."
        )
    }

    $correlationId = [guid]::NewGuid().ToString()
    $startedAtUtc = [DateTime]::UtcNow
    $before = Get-EFManagementAgentHealth -Agent $canonicalAgent -TimeoutSeconds ([math]::Min(30, $TimeoutSeconds))
    $computerName = [string]$before.ComputerName
    $target = "$computerName/$canonicalAgent"
    $actionDescription = switch ($Action) {
        'StartAgentService' { 'Start the local management agent service; management traffic and assigned work may begin' }
        'RestartAgentService' { 'Restart the local management agent service; active work may be interrupted and a management check-in may begin' }
        'RequestMachinePolicy' { 'Ask the local Configuration Manager client to contact its configured service for machine policy' }
        'EvaluateMachinePolicy' { 'Ask the local Configuration Manager client to evaluate already-downloaded machine policy' }
    }

    if (-not $PSCmdlet.ShouldProcess($target, $actionDescription)) {
        $outcome = if ($WhatIfPreference) { 'WhatIf' } else { 'Skipped' }
        $summary = if ($WhatIfPreference) {
            "Preview only: EndpointForge would request $Action for $canonicalAgent. Windows was not changed and no management traffic was initiated."
        }
        else {
            'The action was not approved. Windows was not changed and no management traffic was initiated.'
        }
        return [pscustomobject][ordered]@{
            PSTypeName              = 'EndpointForge.ManagementAgentActionResult'
            ReceiptVersion          = '1.0'
            CorrelationId           = $correlationId
            ComputerName            = $computerName
            Agent                   = $canonicalAgent
            Action                  = $Action
            StartedAtUtc            = $startedAtUtc
            CompletedAtUtc          = [DateTime]::UtcNow
            Outcome                 = $outcome
            IsSuccessful            = $outcome -eq 'WhatIf'
            ChangeMayHaveOccurred   = $false
            RequestAccepted         = $false
            ImmediateEffectVerified = $false
            BeforeStatus            = [string]$before.LocalStatus
            AfterStatus             = [string]$before.LocalStatus
            BeforeServiceStatus     = [string]$before.ServiceStatus
            AfterServiceStatus      = [string]$before.ServiceStatus
            NetworkActivityExpected = $true
            NetworkActivityAllowed  = [bool]$AllowManagementTraffic
            RebootRequired          = $false
            CanAutomaticallyRollback = $false
            Summary                 = $summary
            NextStep                = if ($outcome -eq 'WhatIf') { 'Review the preview. An administrator can approve the same fixed action after management traffic is authorized.' } else { 'No action is required unless you choose to request it again.' }
            RecoveryGuidance        = 'No change was made.'
            SafetyNotes             = 'Starting or restarting a management agent can contact its configured service and begin assigned work. A restart can interrupt work already in progress.'
        }
    }

    if (-not $AllowManagementTraffic) {
        throw [System.InvalidOperationException]::new(
            'This action can contact the configured management service and begin assigned work. Review the action, then add -AllowManagementTraffic when that activity is approved.'
        )
    }
    if (-not (Test-EFAdministrator)) {
        throw [System.UnauthorizedAccessException]::new(
            'Requesting a management-agent action requires PowerShell opened with Run as Administrator. Use -WhatIf for a no-change preview.'
        )
    }

    Write-EFLog -Message "Management agent action started for $canonicalAgent." -CorrelationId $correlationId `
        -Data @{ agent = $canonicalAgent; action = $Action; managementTrafficAllowed = $true }
    try {
        $operation = Invoke-EFManagementAgentOperation -Agent $canonicalAgent -Action $Action -TimeoutSeconds $TimeoutSeconds
    }
    catch {
        $operation = [pscustomobject]@{
            Outcome                 = 'Failed'
            IsSuccessful            = $false
            ChangeMayHaveOccurred   = $true
            RequestAccepted         = $false
            ImmediateEffectVerified = $false
            BeforeServiceStatus     = [string]$before.ServiceStatus
            AfterServiceStatus      = $null
            Message                 = 'The management-agent action ended without a trustworthy result. EndpointForge does not assume it completed.'
            NextStep                = 'Check the current local agent state and approved agent logs before trying another action.'
            RecoveryGuidance        = 'The action may have begun before the result became unavailable. EndpointForge cannot automatically undo management work that may already have started.'
        }
    }
    $requiredOperationProperties = @(
        'Outcome', 'IsSuccessful', 'ChangeMayHaveOccurred', 'RequestAccepted',
        'ImmediateEffectVerified', 'BeforeServiceStatus', 'AfterServiceStatus',
        'Message', 'NextStep', 'RecoveryGuidance'
    )
    $operationResultIsComplete = $true
    foreach ($requiredOperationProperty in $requiredOperationProperties) {
        if (-not (Test-EFPropertyPresent -InputObject $operation -Name $requiredOperationProperty)) {
            $operationResultIsComplete = $false
            break
        }
    }
    if (-not $operationResultIsComplete) {
        $operation = [pscustomobject]@{
            Outcome                 = 'Failed'
            IsSuccessful            = $false
            ChangeMayHaveOccurred   = $true
            RequestAccepted         = $false
            ImmediateEffectVerified = $false
            BeforeServiceStatus     = [string]$before.ServiceStatus
            AfterServiceStatus      = $null
            Message                 = 'The management-agent action returned an incomplete result. EndpointForge does not assume it completed.'
            NextStep                = 'Check the current local agent state and approved agent logs before trying another action.'
            RecoveryGuidance        = 'The action may have begun before the result became unavailable. EndpointForge cannot automatically undo management work that may already have started.'
        }
    }
    $after = try {
        Get-EFManagementAgentHealth -Agent $canonicalAgent -TimeoutSeconds ([math]::Min(30, $TimeoutSeconds))
    }
    catch {
        $null
    }

    $afterStatus = if ($null -ne $after) { [string]$after.LocalStatus } else { 'CouldNotCheck' }
    $afterServiceStatus = [string](Get-EFPropertyValue -InputObject $operation -Name 'AfterServiceStatus' -Default '')
    if ([string]::IsNullOrWhiteSpace($afterServiceStatus) -and $null -ne $after) {
        $afterServiceStatus = [string]$after.ServiceStatus
    }
    $result = [pscustomobject][ordered]@{
        PSTypeName              = 'EndpointForge.ManagementAgentActionResult'
        ReceiptVersion          = '1.0'
        CorrelationId           = $correlationId
        ComputerName            = $computerName
        Agent                   = $canonicalAgent
        Action                  = $Action
        StartedAtUtc            = $startedAtUtc
        CompletedAtUtc          = [DateTime]::UtcNow
        Outcome                 = [string]$operation.Outcome
        IsSuccessful            = [bool]$operation.IsSuccessful
        ChangeMayHaveOccurred   = [bool]$operation.ChangeMayHaveOccurred
        RequestAccepted         = [bool]$operation.RequestAccepted
        ImmediateEffectVerified = [bool]$operation.ImmediateEffectVerified
        BeforeStatus            = [string]$before.LocalStatus
        AfterStatus             = $afterStatus
        BeforeServiceStatus     = if ([string]::IsNullOrWhiteSpace([string]$operation.BeforeServiceStatus)) { [string]$before.ServiceStatus } else { [string]$operation.BeforeServiceStatus }
        AfterServiceStatus      = $afterServiceStatus
        NetworkActivityExpected = $true
        NetworkActivityAllowed  = $true
        RebootRequired          = $false
        CanAutomaticallyRollback = $false
        Summary                 = [string]$operation.Message
        NextStep                = [string]$operation.NextStep
        RecoveryGuidance        = [string]$operation.RecoveryGuidance
        SafetyNotes             = 'Starting or restarting a management agent can contact its configured service and begin assigned work. A restart can interrupt work already in progress.'
    }

    Write-EFLog -Message "Management agent action finished for $canonicalAgent." `
        -Level $(if ($result.IsSuccessful) { 'Information' } else { 'Warning' }) -CorrelationId $correlationId `
        -Data @{ agent = $canonicalAgent; action = $Action; outcome = $result.Outcome; changeMayHaveOccurred = $result.ChangeMayHaveOccurred }
    return $result
}
