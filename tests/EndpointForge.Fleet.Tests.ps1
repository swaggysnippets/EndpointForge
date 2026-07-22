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
            $result.Failures[0].Message | Should -Match 'did not return a checkup'
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
    }
}
