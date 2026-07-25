$script:FleetProjectRoot = Split-Path -Parent $PSScriptRoot
$script:FleetModulePath = Join-Path $script:FleetProjectRoot 'EndpointForge.psm1'
Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
Import-Module $script:FleetModulePath -Force

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'EndpointForge fleet checkup' {
    InModuleScope EndpointForge {
        BeforeEach {
            $script:capturedFleetScript = $null
            Mock Resolve-EFBaseline {
                [pscustomobject]@{
                    Name        = 'TestChecklist'
                    Version     = '1.2.3'
                    Description = 'A test checklist.'
                    Controls    = @()
                }
            }
            Mock Invoke-EFEndpointRemediation {
                throw 'A fleet checkup must never invoke remediation.'
            }
        }

        It 'deduplicates computer names without regard to letter case' {
            Mock Invoke-Command {
                $script:capturedFleetScript = [string]$ScriptBlock
                foreach ($target in $ComputerName) {
                    [pscustomobject]@{
                        PSComputerName      = $target
                        RemoteComputerName  = $target
                        Checkup             = [pscustomobject]@{
                            ComputerName   = $target
                            OverallStatus  = 'Healthy'
                            Score          = 100
                            IssueCount     = 0
                            UnknownCount   = 0
                            CompletedAtUtc = [DateTime]::UtcNow
                            NextStep       = 'No action is required.'
                        }
                    }
                }
            }

            $result = Get-EFFleetSummary -ComputerName 'PC-01', 'pc-01', ' PC-02 '

            $result.TargetCount | Should -Be 2
            $result.SucceededCount | Should -Be 2
            @($result.Results.RequestedComputerName) | Should -Be @('PC-01', 'PC-02')
            Should -Invoke Resolve-EFBaseline -Times 1 -Exactly
            Should -Invoke Invoke-Command -Times 1 -Exactly -ParameterFilter {
                @($ComputerName).Count -eq 2 -and
                $ComputerName[0] -ceq 'PC-01' -and
                $ComputerName[1] -ceq 'PC-02'
            }
        }

        It 'aggregates successful, urgent, and unreachable computer results' {
            Mock Invoke-Command {
                $script:capturedFleetScript = [string]$ScriptBlock
                @(
                    [pscustomobject]@{
                        PSComputerName     = 'PC-GOOD'
                        RemoteComputerName = 'PC-GOOD'
                        Checkup            = [pscustomobject]@{
                            ComputerName   = 'PC-GOOD'
                            OverallStatus  = 'Healthy'
                            Score          = 100
                            IssueCount     = 0
                            UnknownCount   = 0
                            CompletedAtUtc = [DateTime]::UtcNow
                            NextStep       = 'No action is required.'
                        }
                    }
                    [pscustomobject]@{
                        PSComputerName     = 'PC-URGENT'
                        RemoteComputerName = 'PC-URGENT'
                        Checkup            = [pscustomobject]@{
                            ComputerName   = 'PC-URGENT'
                            OverallStatus  = 'Critical'
                            Score          = 35
                            IssueCount     = 3
                            UnknownCount   = 0
                            CompletedAtUtc = [DateTime]::UtcNow
                            NextStep       = 'Review urgent findings.'
                        }
                    }
                )
            }

            $result = Get-EFFleetSummary -ComputerName 'PC-GOOD', 'PC-URGENT', 'PC-OFFLINE'

            $result.PSObject.TypeNames | Should -Contain 'EndpointForge.FleetSummary'
            $result.TargetCount | Should -Be 3
            $result.SucceededCount | Should -Be 2
            $result.FailedCount | Should -Be 1
            $result.HealthyCount | Should -Be 1
            $result.WarningCount | Should -Be 0
            $result.CriticalCount | Should -Be 1
            $result.IncompleteCount | Should -Be 0
            $result.IsComplete | Should -BeFalse
            $result.ExitCode | Should -Be 3
            @($result.Failures).Count | Should -Be 1
            $result.Failures[0].ComputerName | Should -Be 'PC-OFFLINE'
            $result.Failures[0].Message | Should -Match 'did not return a compatible checkup'
            $result.Summary | Should -Match '2 of 3 computer\(s\) were checked'
        }

        It 'uses credentials for the connection but never returns them' {
            Mock Invoke-Command {
                $script:capturedFleetScript = [string]$ScriptBlock
                [pscustomobject]@{
                    PSComputerName     = 'PC-SECURE'
                    RemoteComputerName = 'PC-SECURE'
                    Checkup            = [pscustomobject]@{
                        ComputerName   = 'PC-SECURE'
                        OverallStatus  = 'Healthy'
                        Score          = 100
                        IssueCount     = 0
                        UnknownCount   = 0
                        CompletedAtUtc = [DateTime]::UtcNow
                        NextStep       = 'No action is required.'
                    }
                }
            }
            $securePassword = New-Object System.Security.SecureString
            $credential = New-Object Management.Automation.PSCredential ('CONTOSO\EndpointReader', $securePassword)
            $secureTarget = 'PC-SECURE'

            $result = Get-EFFleetSummary -ComputerName $secureTarget -Credential $credential

            Should -Invoke Invoke-Command -Times 1 -Exactly -ParameterFilter {
                $Credential.UserName -eq 'CONTOSO\EndpointReader'
            }
            $result.PSObject.Properties.Name | Should -Not -Contain 'Credential'
            $result.Results[0].PSObject.Properties.Name | Should -Not -Contain 'Credential'
            $result.Failures.PSObject.Properties.Name | Should -Not -Contain 'Credential'
            (ConvertTo-Json -InputObject $result -Depth 12) | Should -Not -Match 'fleet-test-password'
        }

        It 'uses a read-only remote script and passes the resolved checklist' {
            Mock Invoke-Command {
                $script:capturedFleetScript = [string]$ScriptBlock
                [pscustomobject]@{
                    PSComputerName     = 'PC-READONLY'
                    RemoteComputerName = 'PC-READONLY'
                    Checkup            = [pscustomobject]@{
                        ComputerName   = 'PC-READONLY'
                        OverallStatus  = 'Warning'
                        Score          = 82
                        IssueCount     = 1
                        UnknownCount   = 0
                        CompletedAtUtc = [DateTime]::UtcNow
                        NextStep       = 'Review the finding.'
                    }
                }
            }

            $readOnlyTarget = 'PC-READONLY'
            $result = Get-EFFleetSummary -ComputerName $readOnlyTarget -IncludeSoftware

            $result.SucceededCount | Should -Be 1
            $script:capturedFleetScript | Should -Match 'Get-EFEndpointSummary'
            $script:capturedFleetScript | Should -Not -Match 'Invoke-EFEndpointRemediation'
            $script:capturedFleetScript | Should -Not -Match 'Install-Module'
            $script:capturedFleetScript | Should -Not -Match 'Enable-PSRemoting'
            $script:capturedFleetScript | Should -Not -Match 'Set-Item\s+.*WSMan'
            Should -Invoke Invoke-EFEndpointRemediation -Times 0 -Exactly
            Should -Invoke Invoke-Command -Times 1 -Exactly -ParameterFilter {
                $ArgumentList[0].Name -eq 'TestChecklist' -and
                $ArgumentList[1] -eq $true -and
                $ErrorAction -eq 'SilentlyContinue'
            }
        }

        It 'sends only source checklist fields that remain valid after remoting serialization' {
            Mock Resolve-EFBaseline {
                [pscustomobject]@{
                    PSTypeName      = 'EndpointForge.Baseline'
                    Name            = 'DecoratedChecklist'
                    Version         = '1.2.3'
                    Description     = 'A decorated test checklist.'
                    Controls        = @(
                        [pscustomobject]@{
                            Id = 'LOCAL-RANGE'; Title = 'The computer uses an approved IP range';
                            Type = 'IpAddressInRange'; Severity = 'Low';
                            ApprovedRanges = @('10.20.0.0/16'); TimeoutSeconds = 10;
                            DesiredValue = $true;
                            Remediable = $false; RequiresReboot = $false
                        }
                    )
                    SourcePath      = 'C:\Program Files\WindowsPowerShell\Modules\EndpointForge\Data\EnterpriseRecommended.json'
                    ControlCount    = 1
                    RemediableCount = 0
                }
            }
            Mock Invoke-Command {
                $script:fleetBaselineArgument = $ArgumentList[0]
                [pscustomobject]@{
                    PSComputerName     = 'PC-SERIALIZED'
                    RemoteComputerName = 'PC-SERIALIZED'
                    Checkup            = [pscustomobject]@{
                        ComputerName = 'PC-SERIALIZED'; OverallStatus = 'Healthy'; Score = 100;
                        IssueCount = 0; UnknownCount = 0; CompletedAtUtc = [DateTime]::UtcNow;
                        NextStep = 'No action is required.'
                    }
                }
            }

            $serializedTarget = 'PC-SERIALIZED'
            $result = Get-EFFleetSummary -ComputerName $serializedTarget
            $roundTrip = [Management.Automation.PSSerializer]::Deserialize(
                [Management.Automation.PSSerializer]::Serialize($script:fleetBaselineArgument)
            )

            $result.SucceededCount | Should -Be 1
            $script:fleetBaselineArgument.PSObject.Properties.Name | Should -Not -Contain 'SourcePath'
            $script:fleetBaselineArgument.PSObject.Properties.Name | Should -Not -Contain 'ControlCount'
            $script:fleetBaselineArgument.PSObject.Properties.Name | Should -Not -Contain 'RemediableCount'
            @($roundTrip.Controls[0].ApprovedRanges).Count | Should -Be 1
            $roundTrip.Controls[0].ApprovedRanges[0] | Should -Be '10.20.0.0/16'
            { Assert-EFBaseline -Baseline $roundTrip } | Should -Not -Throw
        }

        It 'rejects invalid names and more than 256 unique targets before remoting' {
            $invalidTarget = 'PC-01;whoami'
            { Get-EFFleetSummary -ComputerName $invalidTarget } |
                Should -Throw '*exact host name or IP address*'

            $tooManyTargets = @(1..257 | ForEach-Object { "PC-{0:D3}" -f $_ })
            { Get-EFFleetSummary -ComputerName $tooManyTargets } |
                Should -Throw '*limited to 256 unique computers*'
        }

        It 'returns remote module and summary-schema compatibility evidence' {
            Mock Invoke-Command {
                [pscustomobject]@{
                    PSComputerName      = 'PC-CONTRACT'
                    RemoteComputerName  = 'PC-CONTRACT'
                    RemoteModuleVersion = '0.9.0'
                    SummarySchemaVersion = '1.0'
                    Checkup             = [pscustomobject]@{
                        SchemaVersion  = '1.0'
                        ComputerName   = 'PC-CONTRACT'
                        OverallStatus  = 'Healthy'
                        Score          = 100
                        IssueCount     = 0
                        UnknownCount   = 0
                        CompletedAtUtc = [DateTime]::UtcNow
                        NextStep       = 'No action is required.'
                    }
                }
            }

            $contractTarget = 'PC-CONTRACT'
            $result = Get-EFFleetSummary -ComputerName $contractTarget

            $result.Results[0].RemoteModuleVersion | Should -Be '0.9.0'
            $result.Results[0].SummarySchemaVersion | Should -Be '1.0'
        }
    }
}
