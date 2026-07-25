$script:OneZeroTruthProjectRoot = Split-Path -Parent $PSScriptRoot
$script:OneZeroTruthManifestPath = Join-Path $script:OneZeroTruthProjectRoot 'EndpointForge.psd1'
Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
Import-Module $script:OneZeroTruthManifestPath -Force

BeforeAll {
    $script:OneZeroTruthProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:OneZeroTruthManifestPath = Join-Path $script:OneZeroTruthProjectRoot 'EndpointForge.psd1'
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Import-Module $script:OneZeroTruthManifestPath -Force
}

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'Endpoint health truth semantics' {
    InModuleScope EndpointForge {
        BeforeEach {
            Mock Test-EFWindows { $true }
            Mock Get-EFEndpointInventory {
                [pscustomobject]@{
                    SystemDrive = [pscustomobject]@{ FreeSpacePercent = 80 }
                    OperatingSystem = [pscustomobject]@{ UptimeDays = 2 }
                    Security = [pscustomobject]@{
                        Firewall = @(
                            [pscustomobject]@{ Name = 'Domain'; Enabled = $true }
                        )
                        Defender = [pscustomobject]@{ RealTimeProtectionEnabled = $true }
                        BitLocker = [pscustomobject]@{ ProtectionStatus = 'On' }
                    }
                    Errors = @()
                }
            }
            Mock Get-EFPendingReboot {
                [pscustomobject]@{
                    IsRebootPending = $false
                    ErrorCount = 1
                    Reasons = @()
                }
            }
        }

        It 'reports Unknown and exit code 3 when a required signal could not be checked' {
            $result = Get-EFEndpointHealth -NoProgress

            $result.Status | Should -Be 'Unknown'
            $result.ExitCode | Should -Be 3
            $result.DataStatus | Should -Be 'Partial'
            $result.UnknownCount | Should -Be 1
            $result.CriticalCount | Should -Be 0
            $result.WarningCount | Should -Be 0
            $result.Summary | Should -Match 'did not report this endpoint as healthy'
            @($result.Checks | Where-Object Id -eq 'PendingReboot')[0].Status | Should -Be 'Unknown'
        }

        It 'reserves Healthy and exit code 0 for complete evidence' {
            Mock Get-EFPendingReboot {
                [pscustomobject]@{
                    IsRebootPending = $false
                    ErrorCount = 0
                    Reasons = @()
                }
            }

            $result = Get-EFEndpointHealth -NoProgress

            $result.Status | Should -Be 'Healthy'
            $result.ExitCode | Should -Be 0
            $result.DataStatus | Should -Be 'Complete'
            $result.UnknownCount | Should -Be 0
        }
    }
}

Describe 'Management agent truth and privacy semantics' {
    InModuleScope EndpointForge {
        BeforeEach {
            Mock Test-EFWindows { $true }
            Mock Get-EFManagementAgentDefinition {
                [pscustomobject]@{
                    Agent = 'Intune'
                    DisplayName = 'Microsoft Intune Management Extension'
                    ServiceName = 'IntuneManagementExtension'
                    MainLogPath = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log'
                    AvailableActions = @('StartAgentService', 'RestartAgentService')
                }
            }
            Mock Get-EFManagementAgentState {
                [pscustomobject]@{
                    Installed = $true
                    ServiceQuerySucceeded = $true
                    ServiceRegistryReadable = $false
                    ServiceStatus = 'Running'
                    StartupType = $null
                    Version = '1.2.3.4'
                    MainLogPresent = $true
                    LastLocalActivityUtc = [datetime]'2026-07-24T12:00:00Z'
                    LocalInterfaceAvailable = $null
                    LocalInterfaceStatus = 'NotRequired'
                }
            }
        }

        It 'does not call partially verified local evidence ready' {
            $result = Get-EFManagementAgentHealth -Agent Intune

            $result.LocalStatus | Should -Be 'NeedsAttention'
            $result.DataStatus | Should -Be 'Partial'
            $result.IsReady | Should -BeFalse
            $result.ExitCode | Should -Be 1
            $result.IssueCount | Should -Be 1
            @($result.Checks | Where-Object Name -eq 'Service startup setting')[0].Result |
                Should -Be 'CouldNotCheck'
            @($result.Findings) | Should -Contain 'The local agent service startup setting could not be checked.'
        }

        It 'marks identifying and local operational metadata as sensitive' {
            $result = Get-EFManagementAgentHealth -Agent Intune

            $result.SensitiveDataIncluded | Should -BeTrue
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
            $result.PSObject.Properties.Name | Should -Contain 'MainLogPath'
            $result.PSObject.Properties.Name | Should -Contain 'LastLocalActivityUtc'
        }

        It 'does not call unavailable detection evidence a complete absence' {
            Mock Get-EFManagementAgentState {
                [pscustomobject]@{
                    Installed = $false
                    ServiceQuerySucceeded = $false
                    ServiceRegistryReadable = $false
                    ServiceStatus = $null
                    StartupType = $null
                    Version = $null
                    MainLogPresent = $false
                    LastLocalActivityUtc = $null
                    LocalInterfaceAvailable = $null
                    LocalInterfaceStatus = 'NotRequired'
                }
            }

            $result = Get-EFManagementAgentHealth -Agent Intune

            $result.LocalStatus | Should -Be 'CouldNotCheck'
            $result.DataStatus | Should -Be 'Failed'
            $result.IsReady | Should -BeFalse
            $result.ExitCode | Should -Be 3
            $result.Summary | Should -Match 'could not determine whether'
            @($result.Checks)[0].Result | Should -Be 'CouldNotCheck'
        }

        It 'uses only the frozen completeness vocabulary when service evidence fails' {
            Mock Get-EFManagementAgentState {
                [pscustomobject]@{
                    Installed = $true
                    ServiceQuerySucceeded = $false
                    ServiceRegistryReadable = $true
                    ServiceStatus = $null
                    StartupType = 'Automatic'
                    Version = $null
                    MainLogPresent = $false
                    LastLocalActivityUtc = $null
                    LocalInterfaceAvailable = $null
                    LocalInterfaceStatus = 'NotRequired'
                }
            }

            $result = Get-EFManagementAgentHealth -Agent Intune

            $result.LocalStatus | Should -Be 'CouldNotCheck'
            $result.DataStatus | Should -Be 'Failed'
            $result.DataStatus | Should -BeIn @('Complete', 'Partial', 'Failed')
            $result.ExitCode | Should -Be 3
        }
    }
}

Describe 'Management agent service query compatibility' {
    InModuleScope EndpointForge {
        BeforeEach {
            $script:OneZeroStateController = [pscustomobject]@{
                Status = 'Running'
                Disposed = $false
            }
            $script:OneZeroStateController | Add-Member -MemberType ScriptMethod -Name Refresh -Value {}
            $script:OneZeroStateController | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
                $this.Disposed = $true
            }
            Mock Get-EFManagementAgentServiceController { $script:OneZeroStateController }
        }

        AfterEach {
            Remove-Variable OneZeroStateController -Scope Script -ErrorAction SilentlyContinue
        }

        It 'queries the service through the Windows PowerShell-safe controller helper' {
            $definition = [pscustomobject]@{
                ServiceRegistryPath = 'SYSTEM\CurrentControlSet\Services\EndpointForgeMissingTestService'
                ServiceName = 'EndpointForgeMissingTestService'
                VersionFilePath = 'C:\EndpointForge\missing.exe'
                MainLogPath = 'C:\EndpointForge\missing.log'
                RequiresLocalInterface = $false
                LocalInterfaceName = $null
            }

            $state = Get-EFManagementAgentState -Definition $definition

            $state.Installed | Should -BeTrue
            $state.ServiceQuerySucceeded | Should -BeTrue
            $state.ServiceStatus | Should -Be 'Running'
            $script:OneZeroStateController.Disposed | Should -BeTrue
            Should -Invoke Get-EFManagementAgentServiceController -Times 1 -Exactly -ParameterFilter {
                $ServiceName -eq 'EndpointForgeMissingTestService'
            }
            (Get-Command Get-EFManagementAgentState).ScriptBlock.ToString() |
                Should -Not -Match 'ServiceController\]::new'
        }
    }
}

Describe 'Management agent restart deadline' {
    InModuleScope EndpointForge {
        BeforeEach {
            Add-Type -AssemblyName System.ServiceProcess -ErrorAction Stop
            Mock Get-EFManagementAgentDefinition {
                [pscustomobject]@{
                    ServiceName = 'EndpointForgeTestAgent'
                }
            }

            $script:OneZeroFakeController = [pscustomobject]@{
                Status = [System.ServiceProcess.ServiceControllerStatus]::Running
                DependentServices = @()
                WaitTimeouts = [Collections.Generic.List[double]]::new()
                Disposed = $false
            }
            $script:OneZeroFakeController | Add-Member -MemberType ScriptMethod -Name Refresh -Value {}
            $script:OneZeroFakeController | Add-Member -MemberType ScriptMethod -Name Stop -Value {
                $this.Status = [System.ServiceProcess.ServiceControllerStatus]::StopPending
            }
            $script:OneZeroFakeController | Add-Member -MemberType ScriptMethod -Name Start -Value {
                $this.Status = [System.ServiceProcess.ServiceControllerStatus]::StartPending
            }
            $script:OneZeroFakeController | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value {
                param(
                    [System.ServiceProcess.ServiceControllerStatus]$DesiredStatus,
                    [TimeSpan]$Timeout
                )

                $this.WaitTimeouts.Add($Timeout.TotalMilliseconds)
                Start-Sleep -Milliseconds 75
                $this.Status = $DesiredStatus
            }
            $script:OneZeroFakeController | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
                $this.Disposed = $true
            }

            Mock Get-EFManagementAgentServiceController { $script:OneZeroFakeController }
        }

        AfterEach {
            Remove-Variable OneZeroFakeController -Scope Script -ErrorAction SilentlyContinue
        }

        It 'uses decreasing remaining time from one monotonic overall deadline' {
            $result = Invoke-EFManagementAgentOperation -Agent Intune `
                -Action RestartAgentService -TimeoutSeconds 5

            $result.Outcome | Should -Be 'Completed'
            $result.IsSuccessful | Should -BeTrue
            @($script:OneZeroFakeController.WaitTimeouts).Count | Should -Be 2
            $script:OneZeroFakeController.WaitTimeouts[0] | Should -BeGreaterThan 0
            $script:OneZeroFakeController.WaitTimeouts[0] | Should -BeLessOrEqual 5000
            $script:OneZeroFakeController.WaitTimeouts[1] |
                Should -BeLessThan $script:OneZeroFakeController.WaitTimeouts[0]
            (Get-Command Invoke-EFManagementAgentOperation).ScriptBlock.ToString() |
                Should -Match 'Diagnostics\.Stopwatch'
        }
    }
}
