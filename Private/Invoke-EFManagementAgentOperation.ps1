function Get-EFManagementAgentServiceController {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName
    )

    Microsoft.PowerShell.Management\Get-Service -Name $ServiceName -ErrorAction Stop
}

function Invoke-EFManagementAgentOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Intune', 'ConfigurationManager')]
        [string]$Agent,

        [Parameter(Mandatory)]
        [ValidateSet('StartAgentService', 'RestartAgentService', 'RequestMachinePolicy', 'EvaluateMachinePolicy')]
        [string]$Action,

        [ValidateRange(5, 300)]
        [int]$TimeoutSeconds = 60
    )

    $definition = Get-EFManagementAgentDefinition -Agent $Agent
    if ($Action -in @('StartAgentService', 'RestartAgentService')) {
        $controller = $null
        $operationTimer = [Diagnostics.Stopwatch]::StartNew()
        $beforeServiceStatus = $null
        $afterServiceStatus = $null
        $changeMayHaveOccurred = $false
        $getRemainingTimeout = {
            $remainingMilliseconds = ($TimeoutSeconds * 1000.0) - $operationTimer.Elapsed.TotalMilliseconds
            if ($remainingMilliseconds -le 0) {
                throw [TimeoutException]::new(
                    "The local management agent service action exceeded its $TimeoutSeconds second overall timeout."
                )
            }

            [TimeSpan]::FromMilliseconds([math]::Max(1, [math]::Floor($remainingMilliseconds)))
        }
        try {
            $controller = Get-EFManagementAgentServiceController -ServiceName ([string]$definition.ServiceName)
            $controller.Refresh()
            $beforeServiceStatus = $controller.Status.ToString()

            if ($Action -eq 'StartAgentService' -and $beforeServiceStatus -eq 'Running') {
                return [pscustomobject][ordered]@{
                    Outcome                = 'NotRequired'
                    IsSuccessful           = $true
                    ChangeMayHaveOccurred  = $false
                    RequestAccepted        = $false
                    ImmediateEffectVerified = $true
                    BeforeServiceStatus    = $beforeServiceStatus
                    AfterServiceStatus     = $beforeServiceStatus
                    Message                = 'The local management agent service is already running. No change was needed.'
                    NextStep               = 'No service action is needed. Use the local health result and your organization management console for any further investigation.'
                    RecoveryGuidance       = 'No change was made.'
                }
            }

            if ($Action -eq 'RestartAgentService' -and $beforeServiceStatus -in @('Running', 'StartPending', 'ContinuePending', 'PausePending', 'Paused')) {
                $hasRunningDependent = $false
                foreach ($dependentService in @($controller.DependentServices)) {
                    if ($dependentService.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
                        $hasRunningDependent = $true
                        break
                    }
                }
                if ($hasRunningDependent) {
                    return [pscustomobject][ordered]@{
                        Outcome                = 'Failed'
                        IsSuccessful           = $false
                        ChangeMayHaveOccurred  = $false
                        RequestAccepted        = $false
                        ImmediateEffectVerified = $false
                        BeforeServiceStatus    = $beforeServiceStatus
                        AfterServiceStatus     = $beforeServiceStatus
                        Message                = 'EndpointForge did not restart the agent because another running Windows service depends on it.'
                        NextStep               = 'Use your approved service-management process to review dependent services before trying again.'
                        RecoveryGuidance       = 'No service change was attempted.'
                    }
                }
                $changeMayHaveOccurred = $true
                $null = & $getRemainingTimeout
                $controller.Stop()
                $controller.WaitForStatus(
                    [System.ServiceProcess.ServiceControllerStatus]::Stopped,
                    (& $getRemainingTimeout)
                )
                $controller.Refresh()
            }
            elseif ($controller.Status -eq [System.ServiceProcess.ServiceControllerStatus]::StopPending) {
                $controller.WaitForStatus(
                    [System.ServiceProcess.ServiceControllerStatus]::Stopped,
                    (& $getRemainingTimeout)
                )
                $controller.Refresh()
            }

            if ($controller.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Running) {
                $changeMayHaveOccurred = $true
                $null = & $getRemainingTimeout
                $controller.Start()
                $controller.WaitForStatus(
                    [System.ServiceProcess.ServiceControllerStatus]::Running,
                    (& $getRemainingTimeout)
                )
                $controller.Refresh()
            }
            $null = & $getRemainingTimeout
            $afterServiceStatus = $controller.Status.ToString()

            $verb = if ($Action -eq 'StartAgentService') { 'started' } else { 'restarted' }
            $message = if ($Agent -eq 'Intune' -and $Action -eq 'RestartAgentService') {
                "The Intune Management Extension service was $verb. Its check-in and any assigned work continue separately."
            }
            else {
                "The local management agent service was $verb and is running. Any management communication or assigned work continues separately."
            }
            return [pscustomobject][ordered]@{
                Outcome                = 'Completed'
                IsSuccessful           = $afterServiceStatus -eq 'Running'
                ChangeMayHaveOccurred  = $changeMayHaveOccurred
                RequestAccepted        = $false
                ImmediateEffectVerified = $afterServiceStatus -eq 'Running'
                BeforeServiceStatus    = $beforeServiceStatus
                AfterServiceStatus     = $afterServiceStatus
                Message                = $message
                NextStep               = 'Wait for the management agent to finish its work, then confirm the device in your organization management console.'
                RecoveryGuidance       = 'EndpointForge cannot undo management work triggered after the service starts. If the service stops again, review its local Windows and agent logs.'
            }
        }
        catch {
            if ($null -ne $controller) {
                try {
                    $controller.Refresh()
                    $afterServiceStatus = $controller.Status.ToString()
                }
                catch { $afterServiceStatus = $null }
            }
            $partial = $changeMayHaveOccurred -and $beforeServiceStatus -ne $afterServiceStatus
            return [pscustomobject][ordered]@{
                Outcome                = if ($partial) { 'PartiallyChanged' } else { 'Failed' }
                IsSuccessful           = $false
                ChangeMayHaveOccurred  = $changeMayHaveOccurred
                RequestAccepted        = $false
                ImmediateEffectVerified = $false
                BeforeServiceStatus    = $beforeServiceStatus
                AfterServiceStatus     = $afterServiceStatus
                Message                = 'The local management agent service action did not complete cleanly. EndpointForge does not assume the agent is working.'
                NextStep               = 'Check the current service state and the agent local logs before trying another action.'
                RecoveryGuidance       = 'If the service is stopped, use your approved Windows service process to start it. EndpointForge cannot roll back management work that may already have begun.'
            }
        }
        finally {
            $operationTimer.Stop()
            if ($null -ne $controller) { $controller.Dispose() }
        }
    }

    $worker = {
        param($InputData)

        $methodName = [string]$InputData.MethodName
        if ($methodName -notin @('RequestMachinePolicy', 'EvaluateMachinePolicy')) {
            return [pscustomobject]@{ Valid = $false; ReturnValue = -1 }
        }
        $cimManifestPath = [IO.Path]::Combine([string]$PSHOME, 'Modules', 'CimCmdlets', 'CimCmdlets.psd1')
        if (-not [IO.File]::Exists($cimManifestPath)) {
            return [pscustomobject]@{ Valid = $false; ReturnValue = -1 }
        }

        try {
            Microsoft.PowerShell.Core\Import-Module -Name $cimManifestPath -Force -ErrorAction Stop
            if ($methodName -eq 'RequestMachinePolicy') {
                $response = CimCmdlets\Invoke-CimMethod -Namespace 'root\ccm' -ClassName 'SMS_Client' `
                    -MethodName 'RequestMachinePolicy' -Arguments @{ uFlags = [uint32]0 } -ErrorAction Stop
            }
            else {
                $response = CimCmdlets\Invoke-CimMethod -Namespace 'root\ccm' -ClassName 'SMS_Client' `
                    -MethodName 'EvaluateMachinePolicy' -ErrorAction Stop
            }
            [pscustomobject]@{
                Valid       = $null -ne $response -and $null -ne $response.PSObject.Properties['ReturnValue']
                ReturnValue = if ($null -ne $response -and $null -ne $response.PSObject.Properties['ReturnValue']) {
                    [int64]$response.ReturnValue
                }
                else { -1 }
            }
        }
        catch {
            [pscustomobject]@{ Valid = $false; ReturnValue = -1 }
        }
    }

    try {
        $response = Invoke-EFIsolatedCheck -ScriptBlock $worker -InputData @{ MethodName = $Action } `
            -TimeoutMilliseconds ($TimeoutSeconds * 1000) -StartupAllowanceMilliseconds 3000 `
            -Activity 'The Configuration Manager client request'
    }
    catch {
        return [pscustomobject][ordered]@{
            Outcome                = 'Failed'
            IsSuccessful           = $false
            ChangeMayHaveOccurred  = $true
            RequestAccepted        = $false
            ImmediateEffectVerified = $false
            BeforeServiceStatus    = $null
            AfterServiceStatus     = $null
            Message                = 'EndpointForge could not confirm whether the Configuration Manager client accepted the request.'
            NextStep               = 'Do not repeat the request immediately. Review the local Configuration Manager client logs and management console first.'
            RecoveryGuidance       = 'The request may have reached the client before the result became unavailable. EndpointForge cannot cancel work that the client already accepted.'
        }
    }

    $valid = $null -ne $response -and
        (Test-EFPropertyPresent -InputObject $response -Name 'Valid') -and
        (Test-EFPropertyPresent -InputObject $response -Name 'ReturnValue') -and
        $response.Valid -is [bool]
    $returnValue = $null
    try { $returnValue = [int64]$response.ReturnValue }
    catch { $valid = $false }
    $accepted = $valid -and [bool]$response.Valid -and $returnValue -eq 0

    if (-not $accepted) {
        return [pscustomobject][ordered]@{
            Outcome                = 'Failed'
            IsSuccessful           = $false
            ChangeMayHaveOccurred  = $valid
            RequestAccepted        = $false
            ImmediateEffectVerified = $false
            BeforeServiceStatus    = $null
            AfterServiceStatus     = $null
            Message                = 'The Configuration Manager client did not return a successful acceptance result.'
            NextStep               = 'Review the local Configuration Manager client health and logs before trying another request.'
            RecoveryGuidance       = 'No successful request was confirmed. If the client did accept work, EndpointForge cannot cancel it.'
        }
    }

    $friendlyAction = if ($Action -eq 'RequestMachinePolicy') { 'machine-policy download' } else { 'local machine-policy evaluation' }
    [pscustomobject][ordered]@{
        Outcome                = 'RequestAccepted'
        IsSuccessful           = $true
        ChangeMayHaveOccurred  = $true
        RequestAccepted        = $true
        ImmediateEffectVerified = $false
        BeforeServiceStatus    = $null
        AfterServiceStatus     = $null
        Message                = "The Configuration Manager client accepted the $friendlyAction request. This does not prove that policy synchronized or finished applying."
        NextStep               = 'Allow the client time to work, then confirm the result in your Configuration Manager console or approved client logs.'
        RecoveryGuidance       = 'An accepted request is asynchronous and cannot be rolled back by EndpointForge. Use your approved Configuration Manager process if downstream work must be investigated.'
    }
}
