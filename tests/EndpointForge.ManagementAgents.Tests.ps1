$script:ManagementAgentProjectRoot = Split-Path -Parent $PSScriptRoot
$script:ManagementAgentManifestPath = Join-Path $script:ManagementAgentProjectRoot 'EndpointForge.psd1'
Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
Import-Module $script:ManagementAgentManifestPath -Force

BeforeAll {
    $script:ManagementAgentProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ManagementAgentManifestPath = Join-Path $script:ManagementAgentProjectRoot 'EndpointForge.psd1'
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManagementAgentManifestPath -Force
}

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'Management agent command contracts' {
    It 'exports a read-only health command with the two canonical agent names' {
        $command = Get-Command Get-EFManagementAgentHealth -Module EndpointForge -ErrorAction Stop
        $validateSet = @(
            $command.Parameters['Agent'].Attributes |
                Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] }
        )[0]

        $command.CommandType | Should -Be 'Function'
        $command.Parameters.Keys | Should -Contain 'TimeoutSeconds'
        @($validateSet.ValidValues).Count | Should -Be 6
        @($validateSet.ValidValues) | Should -Contain 'All'
        @($validateSet.ValidValues) | Should -Contain 'Intune'
        @($validateSet.ValidValues) | Should -Contain 'ConfigurationManager'
        @($validateSet.ValidValues) | Should -Contain 'CCM'
        @($validateSet.ValidValues) | Should -Contain 'SCCM'
        @($validateSet.ValidValues) | Should -Contain 'ConfigMgr'
    }

    It 'exports a high-impact action command with ShouldProcess and explicit safety switches' {
        $command = Get-Command Invoke-EFManagementAgentAction -Module EndpointForge -ErrorAction Stop
        $binding = @(
            $command.ScriptBlock.Attributes |
                Where-Object { $_ -is [Management.Automation.CmdletBindingAttribute] }
        )[0]
        $agentSet = @(
            $command.Parameters['Agent'].Attributes |
                Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] }
        )[0]
        $actionSet = @(
            $command.Parameters['Action'].Attributes |
                Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] }
        )[0]
        $agentParameter = @(
            $command.Parameters['Agent'].Attributes |
                Where-Object { $_ -is [Management.Automation.ParameterAttribute] }
        )[0]

        $binding.SupportsShouldProcess | Should -BeTrue
        $binding.ConfirmImpact | Should -Be 'High'
        $command.Parameters.Keys | Should -Contain 'WhatIf'
        $command.Parameters.Keys | Should -Contain 'Confirm'
        $command.Parameters.Keys | Should -Contain 'AllowManagementTraffic'
        $command.Parameters.Keys | Should -Contain 'TimeoutSeconds'
        $agentParameter.Mandatory | Should -BeTrue
        @($agentSet.ValidValues).Count | Should -Be 5
        @($agentSet.ValidValues) | Should -Contain 'Intune'
        @($agentSet.ValidValues) | Should -Contain 'ConfigurationManager'
        @($agentSet.ValidValues) | Should -Contain 'CCM'
        @($agentSet.ValidValues) | Should -Contain 'SCCM'
        @($agentSet.ValidValues) | Should -Contain 'ConfigMgr'
        @($actionSet.ValidValues).Count | Should -Be 4
        @($actionSet.ValidValues) | Should -Contain 'StartAgentService'
        @($actionSet.ValidValues) | Should -Contain 'RestartAgentService'
        @($actionSet.ValidValues) | Should -Contain 'RequestMachinePolicy'
        @($actionSet.ValidValues) | Should -Contain 'EvaluateMachinePolicy'
    }

    It 'rejects arbitrary agent or action text during parameter binding' {
        InModuleScope EndpointForge {
            Mock Get-EFManagementAgentDefinition { throw 'Definition lookup must not run.' }
            Mock Get-EFManagementAgentState { throw 'Health collection must not run.' }
            Mock Invoke-EFManagementAgentOperation { throw 'An operation must not run.' }
            Mock Test-EFAdministrator { throw 'The administrator gate must not run.' }

            { Get-EFManagementAgentHealth -Agent 'Intune; whoami' } | Should -Throw
            {
                Invoke-EFManagementAgentAction -Agent Intune -Action 'RestartAgentService; whoami' `
                    -AllowManagementTraffic -Confirm:$false
            } | Should -Throw

            Should -Invoke Get-EFManagementAgentDefinition -Times 0 -Exactly
            Should -Invoke Get-EFManagementAgentState -Times 0 -Exactly
            Should -Invoke Invoke-EFManagementAgentOperation -Times 0 -Exactly
            Should -Invoke Test-EFAdministrator -Times 0 -Exactly
        }
    }
}

Describe 'Management agent health' {
    InModuleScope EndpointForge {
        BeforeEach {
            Mock Test-EFWindows { $true }
            Mock Get-EFManagementAgentDefinition {
                param([string]$Agent)

                if ($Agent -eq 'Intune') {
                    return [pscustomobject]@{
                        Agent            = 'Intune'
                        DisplayName      = 'Microsoft Intune Management Extension'
                        ServiceName      = 'IntuneManagementExtension'
                        MainLogPath      = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log'
                        AvailableActions = @('StartAgentService', 'RestartAgentService')
                    }
                }

                [pscustomobject]@{
                    Agent            = 'ConfigurationManager'
                    DisplayName      = 'Microsoft Configuration Manager client'
                    ServiceName      = 'CcmExec'
                    MainLogPath      = 'C:\Windows\CCM\Logs\CcmExec.log'
                    AvailableActions = @(
                        'StartAgentService', 'RestartAgentService',
                        'RequestMachinePolicy', 'EvaluateMachinePolicy'
                    )
                }
            }
            Mock Get-EFManagementAgentState {
                param([object]$Definition, [int]$TimeoutSeconds)
                $null = $TimeoutSeconds

                [pscustomobject]@{
                    Agent                     = $Definition.Agent
                    DisplayName               = $Definition.DisplayName
                    Installed                 = $true
                    ServiceQuerySucceeded     = $true
                    ServiceName               = $Definition.ServiceName
                    ServiceStatus             = 'Running'
                    StartupType               = 'Automatic'
                    ServiceRegistryReadable   = $true
                    MainLogPresent            = $true
                    LastLocalActivityUtc      = [datetime]'2026-07-22T12:00:00Z'
                    Version                   = if ($Definition.Agent -eq 'ConfigurationManager') { '5.00.9128.1000' } else { $null }
                    LocalInterfaceStatus      = 'Available'
                    LocalInterfaceAvailable    = $true
                }
            }
            Mock Invoke-EFManagementAgentOperation { throw 'A health check must never perform an action.' }
            Mock Test-EFAdministrator { throw 'A health check must not require Administrator access.' }
        }

        It 'checks both agents by default and labels identifying local health metadata' {
            $result = @(Get-EFManagementAgentHealth -TimeoutSeconds 17)

            $result.Count | Should -Be 2
            @($result.Agent) | Should -Be @('Intune', 'ConfigurationManager')
            foreach ($item in $result) {
                $item.PSObject.TypeNames | Should -Contain 'EndpointForge.ManagementAgentHealth'
                $item.LocalStatus | Should -Be 'LooksReady'
                $item.Installed | Should -BeTrue
                $item.NetworkActivityPerformed | Should -BeFalse
                $item.SensitiveDataIncluded | Should -BeTrue
                $item.PSObject.Properties.Name | Should -Not -Contain 'TenantId'
                $item.PSObject.Properties.Name | Should -Not -Contain 'SiteCode'
                $item.PSObject.Properties.Name | Should -Not -Contain 'ManagementPoint'
            }
            $result[0].ServiceName | Should -Be 'IntuneManagementExtension'
            $result[1].ServiceName | Should -Be 'CcmExec'
            Should -Invoke Get-EFManagementAgentDefinition -Times 2 -Exactly
            Should -Invoke Get-EFManagementAgentState -Times 2 -Exactly -ParameterFilter {
                $TimeoutSeconds -eq 17
            }
            Should -Invoke Invoke-EFManagementAgentOperation -Times 0 -Exactly
            Should -Invoke Test-EFAdministrator -Times 0 -Exactly
        }

        It 'checks only the explicitly selected agent' {
            $result = @(Get-EFManagementAgentHealth -Agent ConfigurationManager -TimeoutSeconds 9)

            $result.Count | Should -Be 1
            $result[0].Agent | Should -Be 'ConfigurationManager'
            $result[0].ServiceName | Should -Be 'CcmExec'
            Should -Invoke Get-EFManagementAgentDefinition -Times 1 -Exactly -ParameterFilter {
                $Agent -eq 'ConfigurationManager'
            }
            Should -Invoke Get-EFManagementAgentState -Times 1 -Exactly -ParameterFilter {
                $Definition.Agent -eq 'ConfigurationManager' -and $TimeoutSeconds -eq 9
            }
        }

        It 'preserves the four fixed local status outcomes without inventing cloud health' {
            foreach ($expectedStatus in @('LooksReady', 'NeedsAttention', 'NotDetected', 'CouldNotCheck')) {
                Mock Get-EFManagementAgentState {
                    param([object]$Definition, [int]$TimeoutSeconds)
                    $null = $TimeoutSeconds
                    [pscustomobject]@{
                        Agent                    = $Definition.Agent
                        DisplayName              = $Definition.DisplayName
                        Installed                = $expectedStatus -ne 'NotDetected'
                        ServiceQuerySucceeded    = $expectedStatus -ne 'CouldNotCheck'
                        ServiceName              = $Definition.ServiceName
                        ServiceStatus            = if ($expectedStatus -eq 'LooksReady') { 'Running' } else { 'Unknown' }
                        StartupType               = 'Automatic'
                        ServiceRegistryReadable   = $true
                        MainLogPresent            = $false
                        LastLocalActivityUtc      = $null
                        Version                   = $null
                        LocalInterfaceStatus      = 'Available'
                        LocalInterfaceAvailable   = $false
                    }
                }

                $result = Get-EFManagementAgentHealth -Agent Intune

                $result.LocalStatus | Should -Be $expectedStatus
                $result.Summary | Should -Match 'local|does not prove'
                $result.Summary | Should -Not -Match 'is enrolled|successfully checked in|is synchronized'
            }
        }

        It 'uses definitions containing only the fixed services and allowlisted actions' {
            $intune = Get-EFManagementAgentDefinition -Agent Intune
            $configurationManager = Get-EFManagementAgentDefinition -Agent ConfigurationManager

            $intune.ServiceName | Should -Be 'IntuneManagementExtension'
            @($intune.AvailableActions) | Should -Be @('StartAgentService', 'RestartAgentService')
            $configurationManager.ServiceName | Should -Be 'CcmExec'
            @($configurationManager.AvailableActions) | Should -Be @(
                'StartAgentService', 'RestartAgentService',
                'RequestMachinePolicy', 'EvaluateMachinePolicy'
            )
        }
    }
}

Describe 'Guarded management agent actions' {
    InModuleScope EndpointForge {
        BeforeEach {
            Mock Test-EFWindows { $true }
            Mock Test-EFAdministrator { $true }
            Mock Get-EFManagementAgentDefinition {
                param([string]$Agent)

                if ($Agent -eq 'Intune') {
                    return [pscustomobject]@{
                        Agent            = 'Intune'
                        DisplayName      = 'Microsoft Intune Management Extension'
                        ServiceName      = 'IntuneManagementExtension'
                        MainLogPath      = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log'
                        AvailableActions = @('StartAgentService', 'RestartAgentService')
                    }
                }

                [pscustomobject]@{
                    Agent            = 'ConfigurationManager'
                    DisplayName      = 'Microsoft Configuration Manager client'
                    ServiceName      = 'CcmExec'
                    MainLogPath      = 'C:\Windows\CCM\Logs\CcmExec.log'
                    AvailableActions = @(
                        'StartAgentService', 'RestartAgentService',
                        'RequestMachinePolicy', 'EvaluateMachinePolicy'
                    )
                }
            }
            Mock Get-EFManagementAgentState {
                param([object]$Definition, [int]$TimeoutSeconds)
                $null = $TimeoutSeconds
                [pscustomobject]@{
                    Agent                    = $Definition.Agent
                    DisplayName              = $Definition.DisplayName
                    Installed                = $true
                    ServiceQuerySucceeded    = $true
                    ServiceName              = $Definition.ServiceName
                    ServiceStatus            = 'Running'
                    StartupType              = 'Automatic'
                    ServiceRegistryReadable  = $true
                    MainLogPresent           = $true
                    LastLocalActivityUtc     = [datetime]'2026-07-22T12:00:00Z'
                    Version                  = $null
                    LocalInterfaceStatus     = 'Available'
                    LocalInterfaceAvailable   = $true
                }
            }
            Mock Write-EFLog {}
            Mock Invoke-EFManagementAgentOperation {
                param([string]$Agent, [string]$Action, [int]$TimeoutSeconds)
                $null = $Agent
                $null = $TimeoutSeconds
                [pscustomobject]@{
                    Outcome                 = if ($Action -match 'MachinePolicy') { 'RequestAccepted' } else { 'Completed' }
                    IsSuccessful            = $true
                    ChangeMayHaveOccurred   = $true
                    RequestAccepted         = $Action -match 'MachinePolicy'
                    ImmediateEffectVerified = $Action -notmatch 'MachinePolicy'
                    BeforeServiceStatus     = 'Running'
                    AfterServiceStatus      = 'Running'
                    Message                 = if ($Action -match 'MachinePolicy') {
                        'The local Configuration Manager request was accepted.'
                    }
                    else {
                        'The local service action completed.'
                    }
                    NextStep                = 'Review a new local health check.'
                    RecoveryGuidance        = 'No automatic rollback is available.'
                }
            }
        }

        It 'previews without traffic approval, elevation, or an operation call' {
            Mock Test-EFAdministrator { throw 'WhatIf must not run the administrator gate.' }
            Mock Invoke-EFManagementAgentOperation { throw 'WhatIf must never perform the operation.' }

            $receipt = Invoke-EFManagementAgentAction -Agent Intune -Action RestartAgentService `
                -TimeoutSeconds 13 -WhatIf

            $receipt.PSObject.TypeNames | Should -Contain 'EndpointForge.ManagementAgentActionResult'
            $receipt.Agent | Should -Be 'Intune'
            $receipt.Action | Should -Be 'RestartAgentService'
            $receipt.Outcome | Should -Be 'WhatIf'
            $receipt.ChangeMayHaveOccurred | Should -BeFalse
            $receipt.RequestAccepted | Should -BeFalse
            $receipt.ImmediateEffectVerified | Should -BeFalse
            $receipt.NetworkActivityAllowed | Should -BeFalse
            Should -Invoke Get-EFManagementAgentState -Times 1 -Exactly -ParameterFilter {
                $Definition.Agent -eq 'Intune' -and $TimeoutSeconds -eq 13
            }
            Should -Invoke Test-EFAdministrator -Times 0 -Exactly
            Should -Invoke Invoke-EFManagementAgentOperation -Times 0 -Exactly
        }

        It 'blocks real execution until management traffic is explicitly allowed' {
            {
                Invoke-EFManagementAgentAction -Agent Intune -Action RestartAgentService -Confirm:$false
            } | Should -Throw '*AllowManagementTraffic*'

            Should -Invoke Invoke-EFManagementAgentOperation -Times 0 -Exactly
        }

        It 'blocks real execution for a standard user even when traffic is allowed' {
            Mock Test-EFAdministrator { $false }

            {
                Invoke-EFManagementAgentAction -Agent ConfigurationManager -Action RequestMachinePolicy `
                    -AllowManagementTraffic -Confirm:$false
            } | Should -Throw '*Administrator*'

            Should -Invoke Test-EFAdministrator -Times 1 -Exactly
            Should -Invoke Invoke-EFManagementAgentOperation -Times 0 -Exactly
        }

        It 'rejects Configuration Manager policy actions for Intune before any operation' {
            foreach ($action in @('RequestMachinePolicy', 'EvaluateMachinePolicy')) {
                {
                    Invoke-EFManagementAgentAction -Agent Intune -Action $action `
                        -AllowManagementTraffic -Confirm:$false
                } | Should -Throw '*Intune*'
            }

            Should -Invoke Invoke-EFManagementAgentOperation -Times 0 -Exactly
        }

        It 'forwards only the two Intune service operations after both safety gates pass' {
            foreach ($action in @('StartAgentService', 'RestartAgentService')) {
                $receipt = Invoke-EFManagementAgentAction -Agent Intune -Action $action `
                    -AllowManagementTraffic -TimeoutSeconds 19 -Confirm:$false

                $receipt.PSObject.TypeNames | Should -Contain 'EndpointForge.ManagementAgentActionResult'
                $receipt.Outcome | Should -Be 'Completed'
                $receipt.NetworkActivityAllowed | Should -BeTrue
            }

            Should -Invoke Invoke-EFManagementAgentOperation -Times 2 -Exactly -ParameterFilter {
                $Agent -eq 'Intune' -and
                $Action -in @('StartAgentService', 'RestartAgentService') -and
                $TimeoutSeconds -eq 19
            }
        }

        It 'forwards each fixed Configuration Manager operation and no caller-supplied method data' {
            $actions = @(
                'StartAgentService', 'RestartAgentService',
                'RequestMachinePolicy', 'EvaluateMachinePolicy'
            )

            foreach ($action in $actions) {
                $receipt = Invoke-EFManagementAgentAction -Agent ConfigurationManager -Action $action `
                    -AllowManagementTraffic -TimeoutSeconds 23 -Confirm:$false

                $receipt.PSObject.TypeNames | Should -Contain 'EndpointForge.ManagementAgentActionResult'
                $receipt.Agent | Should -Be 'ConfigurationManager'
                $receipt.Action | Should -Be $action
            }

            Should -Invoke Invoke-EFManagementAgentOperation -Times 4 -Exactly -ParameterFilter {
                $Agent -eq 'ConfigurationManager' -and
                $Action -in $actions -and
                $TimeoutSeconds -eq 23
            }
        }

        It 'labels policy calls as accepted requests rather than completed synchronization' {
            foreach ($action in @('RequestMachinePolicy', 'EvaluateMachinePolicy')) {
                $receipt = Invoke-EFManagementAgentAction -Agent ConfigurationManager -Action $action `
                    -AllowManagementTraffic -Confirm:$false

                $receipt.Outcome | Should -Be 'RequestAccepted'
                $receipt.RequestAccepted | Should -BeTrue
                $receipt.ImmediateEffectVerified | Should -BeFalse
                $receipt.Summary | Should -Not -Match 'fixed|synchronized|compliant'
            }
        }

        It 'returns a typed, bounded failure receipt without exposing raw provider details' {
            Mock Invoke-EFManagementAgentOperation {
                [pscustomobject]@{
                    Outcome                 = 'Failed'
                    IsSuccessful            = $false
                    ChangeMayHaveOccurred   = $false
                    RequestAccepted         = $false
                    ImmediateEffectVerified = $false
                    BeforeServiceStatus     = 'Running'
                    AfterServiceStatus      = 'Unknown'
                    Message                 = 'The local Configuration Manager request was not accepted.'
                    NextStep                = 'Review Configuration Manager client health and try again.'
                    RecoveryGuidance        = 'No automatic rollback was attempted.'
                    RawProviderError        = 'PRIVATE-SITE-CODE PRIVATE-MANAGEMENT-POINT'
                }
            }

            $receipt = Invoke-EFManagementAgentAction -Agent ConfigurationManager -Action RequestMachinePolicy `
                -AllowManagementTraffic -Confirm:$false

            $receipt.PSObject.TypeNames | Should -Contain 'EndpointForge.ManagementAgentActionResult'
            $receipt.Outcome | Should -Be 'Failed'
            $receipt.ChangeMayHaveOccurred | Should -BeFalse
            $receipt.RequestAccepted | Should -BeFalse
            $serialized = ConvertTo-Json -InputObject $receipt -Depth 12
            $serialized | Should -Not -Match 'PRIVATE-SITE-CODE'
            $serialized | Should -Not -Match 'PRIVATE-MANAGEMENT-POINT'
            $receipt.PSObject.Properties.Name | Should -Not -Contain 'RawProviderError'
        }
    }
}

Describe 'Configuration Manager operation safety boundary' {
    InModuleScope EndpointForge {
        BeforeEach {
            $script:CapturedManagementWorker = $null
            $script:CapturedManagementInput = $null
            Mock Invoke-EFIsolatedCheck {
                param(
                    [scriptblock]$ScriptBlock,
                    [object]$InputData,
                    [int]$TimeoutMilliseconds,
                    [int]$StartupAllowanceMilliseconds,
                    [string]$Activity
                )
                $null = $TimeoutMilliseconds
                $null = $StartupAllowanceMilliseconds
                $null = $Activity
                $script:CapturedManagementWorker = $ScriptBlock.ToString()
                $script:CapturedManagementInput = $InputData
                [pscustomobject]@{ Valid = $true; ReturnValue = 0 }
            }
        }

        It 'pins policy requests to the local SMS_Client interface and two fixed methods' {
            foreach ($action in @('RequestMachinePolicy', 'EvaluateMachinePolicy')) {
                $result = Invoke-EFManagementAgentOperation -Agent ConfigurationManager `
                    -Action $action -TimeoutSeconds 21

                $result.Outcome | Should -Be 'RequestAccepted'
                $result.RequestAccepted | Should -BeTrue
                @($script:CapturedManagementInput.Keys).Count | Should -Be 1
                @($script:CapturedManagementInput.Keys) | Should -Contain 'MethodName'
                $script:CapturedManagementInput.MethodName | Should -Be $action
            }

            $script:CapturedManagementWorker | Should -Match "-Namespace\s+'root\\ccm'"
            $script:CapturedManagementWorker | Should -Match "-ClassName\s+'SMS_Client'"
            $script:CapturedManagementWorker | Should -Match "-MethodName\s+'RequestMachinePolicy'"
            $script:CapturedManagementWorker | Should -Match "uFlags\s*=\s*\[uint32\]0"
            $script:CapturedManagementWorker | Should -Match "-MethodName\s+'EvaluateMachinePolicy'"
            $script:CapturedManagementWorker | Should -Match 'CimCmdlets\.psd1'
            $script:CapturedManagementWorker | Should -Not -Match '-ComputerName|-CimSession|-Credential'
            Should -Invoke Invoke-EFIsolatedCheck -Times 2 -Exactly -ParameterFilter {
                $TimeoutMilliseconds -eq 21000 -and
                $StartupAllowanceMilliseconds -eq 3000 -and
                $Activity -eq 'The Configuration Manager client request'
            }
        }

        It 'does not call the isolated interface for an arbitrary policy action' {
            {
                Invoke-EFManagementAgentOperation -Agent ConfigurationManager `
                    -Action 'RequestMachinePolicy; whoami' -TimeoutSeconds 21
            } | Should -Throw

            Should -Invoke Invoke-EFIsolatedCheck -Times 0 -Exactly
        }

        It 'returns bounded failure evidence for a timeout or nonzero provider result' {
            Mock Invoke-EFIsolatedCheck { throw [TimeoutException]::new('PRIVATE-PROVIDER-TIMEOUT') }
            $timeout = Invoke-EFManagementAgentOperation -Agent ConfigurationManager `
                -Action RequestMachinePolicy -TimeoutSeconds 5

            $timeout.Outcome | Should -Be 'Failed'
            $timeout.RequestAccepted | Should -BeFalse
            $timeout.ChangeMayHaveOccurred | Should -BeTrue
            (ConvertTo-Json -InputObject $timeout -Depth 8) | Should -Not -Match 'PRIVATE-PROVIDER-TIMEOUT'

            Mock Invoke-EFIsolatedCheck { [pscustomobject]@{ Valid = $true; ReturnValue = 7 } }
            $rejected = Invoke-EFManagementAgentOperation -Agent ConfigurationManager `
                -Action EvaluateMachinePolicy -TimeoutSeconds 5

            $rejected.Outcome | Should -Be 'Failed'
            $rejected.RequestAccepted | Should -BeFalse
            $rejected.ChangeMayHaveOccurred | Should -BeTrue
            $rejected.PSObject.Properties.Name | Should -Not -Contain 'ReturnValue'
        }
    }
}

Describe 'Management agent menu experience' {
    BeforeEach {
        $script:ManagementMenuInputs = [Collections.Generic.Queue[string]]::new()
        $script:ManagementMenuLines = [Collections.Generic.List[string]]::new()
        $script:ManagementMenuHealth = @(
            [pscustomobject]@{
                PSTypeName = 'EndpointForge.ManagementAgentHealth'
                Agent = 'Intune'; Installed = $true; LocalStatus = 'LooksReady'
                ServiceName = 'IntuneManagementExtension'; ServiceStatus = 'Running'
                Summary = 'The Intune agent looks ready from local evidence.'
            },
            [pscustomobject]@{
                PSTypeName = 'EndpointForge.ManagementAgentHealth'
                Agent = 'ConfigurationManager'; Installed = $true; LocalStatus = 'LooksReady'
                ServiceName = 'CcmExec'; ServiceStatus = 'Running'
                Summary = 'The Configuration Manager agent looks ready from local evidence.'
            }
        )
        $script:ManagementMenuPreview = [pscustomobject]@{
            PSTypeName = 'EndpointForge.ManagementAgentActionResult'
            Agent = 'ConfigurationManager'; Action = 'RequestMachinePolicy'; Outcome = 'WhatIf'
            IsSuccessful = $true; ChangeMayHaveOccurred = $false; RequestAccepted = $false
            Summary = 'Preview only. No management action was requested.'
            NextStep = 'Review the preview.'
        }
        $script:ManagementMenuApplied = [pscustomobject]@{
            PSTypeName = 'EndpointForge.ManagementAgentActionResult'
            Agent = 'ConfigurationManager'; Action = 'RequestMachinePolicy'; Outcome = 'RequestAccepted'
            IsSuccessful = $true; ChangeMayHaveOccurred = $true; RequestAccepted = $true
            Summary = 'The local Configuration Manager request was accepted.'
            NextStep = 'Review a new local health check.'
        }

        Mock Read-Host -ModuleName EndpointForge { $script:ManagementMenuInputs.Dequeue() }
        Mock Write-Host -ModuleName EndpointForge { $script:ManagementMenuLines.Add([string]$Object) }
        Mock Test-EFAdministrator -ModuleName EndpointForge { $false }
        Mock Get-EFManagementAgentHealth -ModuleName EndpointForge {
            if ($Agent -eq 'All') { return $script:ManagementMenuHealth }
            @($script:ManagementMenuHealth | Where-Object Agent -eq $Agent)
        }
        Mock Invoke-EFManagementAgentAction -ModuleName EndpointForge { $script:ManagementMenuPreview }
        Mock Write-EFMenuManagementAgentHealth -ModuleName EndpointForge {}
        Mock Write-EFMenuManagementAgentAction -ModuleName EndpointForge {}
    }

    AfterEach {
        Remove-Variable ManagementMenuInputs -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable ManagementMenuLines -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable ManagementMenuHealth -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable ManagementMenuPreview -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable ManagementMenuApplied -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable ManagementMenuInvocationOrder -Scope Script -ErrorAction SilentlyContinue
    }

    It 'runs option 7 health as a local read-only check and keeps the result in the session' {
        @('7', '1', 'B', 'Q') | ForEach-Object { $script:ManagementMenuInputs.Enqueue($_) }

        $session = Show-EFMenu -NoPause -NoColor -PassThru
        $menuText = $script:ManagementMenuLines -join "`n"

        $session.SchemaVersion | Should -Be '1.2'
        @($session.LastManagementHealth).Count | Should -Be 2
        @($session.LastManagementHealth.Agent) | Should -Be @('Intune', 'ConfigurationManager')
        $session.LastManagementAction | Should -BeNullOrEmpty
        $menuText | Should -Match 'Health checks below read only fixed local evidence'
        $menuText | Should -Match 'do not contact a management service'
        Should -Invoke Get-EFManagementAgentHealth -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $Agent -eq 'All'
        }
        Should -Invoke Invoke-EFManagementAgentAction -ModuleName EndpointForge -Times 0 -Exactly
    }

    It 'always previews an action but never offers apply to a standard user' {
        @('7', '4', '1', '2', 'B', 'Q') | ForEach-Object { $script:ManagementMenuInputs.Enqueue($_) }

        $session = Show-EFMenu -NoPause -NoColor -PassThru
        $menuText = $script:ManagementMenuLines -join "`n"

        $session.LastManagementAction.Outcome | Should -Be 'WhatIf'
        $menuText | Should -Match 'Required no-change preview'
        $menuText | Should -Match '\[PREVIEW ONLY\].*Run as administrator'
        Should -Invoke Invoke-EFManagementAgentAction -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $Agent -eq 'Intune' -and $Action -eq 'RestartAgentService' -and
            $WhatIf -and $Confirm -eq $false -and -not $AllowManagementTraffic
        }
        Should -Invoke Invoke-EFManagementAgentAction -ModuleName EndpointForge -Times 0 -Exactly -ParameterFilter {
            -not $WhatIf
        }
    }

    It 'cancels unless NETWORK and APPLY are each entered with exact casing' {
        Mock Test-EFAdministrator -ModuleName EndpointForge { $true }
        @(
            '7', '4', '2', '3', 'network',
            '4', '2', '3', 'NETWORK', 'apply',
            'B', 'Q'
        ) | ForEach-Object { $script:ManagementMenuInputs.Enqueue($_) }

        $session = Show-EFMenu -NoPause -NoColor -PassThru

        $session.LastManagementAction.Outcome | Should -Be 'WhatIf'
        @($session.History | Where-Object {
            $_.Action -eq 'Management-agent action' -and $_.Status -eq 'Cancelled'
        }).Count | Should -Be 2
        @($session.History.Message) | Should -Contain 'NETWORK approval was not entered.'
        @($session.History.Message) | Should -Contain 'APPLY approval was not entered.'
        Should -Invoke Invoke-EFManagementAgentAction -ModuleName EndpointForge -Times 2 -Exactly -ParameterFilter {
            $WhatIf
        }
        Should -Invoke Invoke-EFManagementAgentAction -ModuleName EndpointForge -Times 0 -Exactly -ParameterFilter {
            -not $WhatIf
        }
    }

    It 'applies once after preview and exact approval, then persists the new health and action' {
        Mock Test-EFAdministrator -ModuleName EndpointForge { $true }
        $script:ManagementMenuInvocationOrder = [Collections.Generic.List[string]]::new()
        Mock Invoke-EFManagementAgentAction -ModuleName EndpointForge {
            $script:ManagementMenuInvocationOrder.Add('Preview')
            return $script:ManagementMenuPreview
        } -ParameterFilter { $WhatIf }
        Mock Invoke-EFManagementAgentAction -ModuleName EndpointForge {
            $script:ManagementMenuInvocationOrder.Add('Apply')
            return $script:ManagementMenuApplied
        } -ParameterFilter { -not $WhatIf }
        @('7', '4', '2', '3', 'NETWORK', 'APPLY', 'B', 'Q') |
            ForEach-Object { $script:ManagementMenuInputs.Enqueue($_) }

        $session = Show-EFMenu -NoPause -NoColor -PassThru

        $session.SchemaVersion | Should -Be '1.2'
        @($script:ManagementMenuInvocationOrder) | Should -Be @('Preview', 'Apply')
        [object]::ReferenceEquals($script:ManagementMenuApplied, $session.LastManagementAction) | Should -BeTrue
        @($session.LastManagementHealth).Count | Should -Be 1
        @($session.LastManagementHealth.Agent) | Should -Be @('ConfigurationManager')
        Should -Invoke Invoke-EFManagementAgentAction -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $Agent -eq 'ConfigurationManager' -and $Action -eq 'RequestMachinePolicy' -and
            $WhatIf -and $Confirm -eq $false -and -not $AllowManagementTraffic
        }
        Should -Invoke Invoke-EFManagementAgentAction -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $Agent -eq 'ConfigurationManager' -and $Action -eq 'RequestMachinePolicy' -and
            -not $WhatIf -and $AllowManagementTraffic -and $Confirm -eq $false
        }
        Should -Invoke Get-EFManagementAgentHealth -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $Agent -eq 'ConfigurationManager'
        }
    }
}
