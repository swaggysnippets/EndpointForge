$script:ReadinessProjectRoot = Split-Path -Parent $PSScriptRoot
$script:ReadinessModulePath = Join-Path $script:ReadinessProjectRoot 'EndpointForge.psm1'
Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
Import-Module $script:ReadinessModulePath -Force

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'EndpointForge endpoint readiness capability' {
    InModuleScope EndpointForge {
        BeforeEach {
            Mock Test-EFWindows { $true }
            Mock Test-EFAdministrator { $true }
            Mock Get-Command { [pscustomobject]@{ Name = [string]$Name } }
            Mock Resolve-EFBaseline {
                [pscustomobject]@{
                    Name = 'RecommendedWindowsProtection'
                    Version = '1.0.0'
                    Controls = @(
                        [pscustomobject]@{
                            Id = 'EF-FW-DOMAIN'; Title = 'Domain firewall'; Type = 'FirewallProfile';
                            Severity = 'Critical'; Name = 'Domain'; DesiredValue = $true;
                            Remediable = $true; RequiresReboot = $false
                        }
                    )
                }
            }
        }

        It 'reports a fully capable elevated Windows session without changing endpoint state' {
            Mock Invoke-EFEndpointRemediation { throw 'Readiness must not invoke remediation.' }

            $result = Get-EFEndpointReadiness

            $result.PSObject.TypeNames | Should -Contain 'EndpointForge.EndpointReadiness'
            $result.Status | Should -Be 'Ready'
            $result.AssessmentReady | Should -BeTrue
            $result.CompleteCheckLikely | Should -BeTrue
            $result.FixReady | Should -BeTrue
            $result.ControlCount | Should -Be 1
            $result.AvailableControlCount | Should -Be 1
            $result.ChecklistDefinition | Should -Match 'list of expected Windows settings'
            Should -Invoke Invoke-EFEndpointRemediation -Times 0 -Exactly
        }

        It 'allows standard-user checks while clearly withholding automatic fixes' {
            Mock Test-EFAdministrator { $false }

            $result = Get-EFEndpointReadiness

            $result.Status | Should -Be 'Limited'
            $result.AssessmentReady | Should -BeTrue
            $result.CompleteCheckLikely | Should -BeTrue
            $result.FixReady | Should -BeFalse
            $result.FixNowCount | Should -Be 0
            $result.Limitations | Should -Contain 'This standard-user PowerShell window can check settings, but it cannot apply automatic fixes.'
            ($result.Checks | Where-Object Name -eq 'PowerShell access').PlainLanguage | Should -Match 'standard user'
        }

        It 'identifies protected checks that may be incomplete without administrator access' {
            Mock Test-EFAdministrator { $false }
            Mock Resolve-EFBaseline {
                [pscustomobject]@{
                    Name = 'SecurityAudit'
                    Version = '1.0.0'
                    Controls = @(
                        [pscustomobject]@{
                            Id = 'EF-TPM'; Title = 'TPM is ready'; Type = 'Tpm'; Severity = 'High';
                            DesiredValue = [pscustomobject]@{ TpmPresent = $true; TpmReady = $true };
                            Remediable = $false; RequiresReboot = $false
                        }
                    )
                }
            }

            $result = Get-EFEndpointReadiness

            $result.AssessmentReady | Should -BeTrue
            $result.CompleteCheckLikely | Should -BeFalse
            $result.PrivilegedCheckCount | Should -Be 1
            $result.ControlCapabilities[0].FixStatus | Should -Be 'NotOffered'
            $result.ControlCapabilities[0].WhatWouldChange | Should -Match '^Nothing\.'
        }

        It 'reports unavailable Windows providers without guessing at the check result' {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-NetFirewallProfile' }

            $result = Get-EFEndpointReadiness

            $result.Status | Should -Be 'Limited'
            $result.AssessmentReady | Should -BeTrue
            $result.CompleteCheckLikely | Should -BeFalse
            $result.UnavailableControlCount | Should -Be 1
            $result.ControlCapabilities[0].MissingCheckCommands | Should -Contain 'Get-NetFirewallProfile'
            $result.ControlCapabilities[0].PlainLanguage | Should -Match 'does not provide the command'
        }

        It 'returns a blocked report with actionable wording for an invalid checklist' {
            Mock Resolve-EFBaseline { throw 'The custom JSON checklist is not valid.' }

            $result = Get-EFEndpointReadiness

            $result.Status | Should -Be 'Blocked'
            $result.AssessmentReady | Should -BeFalse
            $result.ChecklistName | Should -Be 'Unavailable'
            $result.Limitations[0] | Should -Match 'custom JSON checklist is not valid'
            $result.NextStep | Should -Match 'correct the custom checklist'
        }

        It 'explains when the active PowerShell window targets a remote PC' {
            Mock Get-Variable { [pscustomobject]@{ ComputerName = 'REMOTE-PC' } } -ParameterFilter { $Name -eq 'PSSenderInfo' }

            $result = Get-EFEndpointReadiness

            $result.IsRemoteSession | Should -BeTrue
            ($result.Checks | Where-Object Name -eq 'Target PC').Status | Should -Be 'Warning'
            ($result.Checks | Where-Object Name -eq 'Target PC').PlainLanguage | Should -Match 'another PC'
            $result.Limitations | Should -Match 'remote PC'
        }

        It 'renders the readiness definition and safety boundary without pipeline output' {
            $script:readinessLines = [Collections.Generic.List[string]]::new()
            Mock Write-EFMenuLine { $script:readinessLines.Add([string]$Text) }
            $result = Get-EFEndpointReadiness

            $output = @(Write-EFMenuReadiness -Readiness $result -NoColor -Width 80)

            $output.Count | Should -Be 0
            ($script:readinessLines -join "`n") | Should -Match 'Checking only reads Windows settings'
            ($script:readinessLines -join "`n") | Should -Match 'A checklist is simply the list of expected Windows settings'
        }
    }
}
