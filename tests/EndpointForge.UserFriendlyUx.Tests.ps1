$script:UserFriendlyProjectRoot = Split-Path -Parent $PSScriptRoot
$script:UserFriendlyManifestPath = Join-Path $script:UserFriendlyProjectRoot 'EndpointForge.psd1'
Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
Import-Module $script:UserFriendlyManifestPath -Force

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'EndpointForge user-friendly language' {
    It 'explains every built-in checklist item' {
        $checklist = Get-EFBaseline

        foreach ($item in @($checklist.Controls)) {
            $item.WhyItMatters | Should -Not -BeNullOrEmpty
            $item.HowChecked | Should -Not -BeNullOrEmpty
            $item.WhatWouldChange | Should -Not -BeNullOrEmpty
            $item.ManualAction | Should -Not -BeNullOrEmpty
            $item.SafetyNotes | Should -Not -BeNullOrEmpty
            $item.RecoveryGuidance | Should -Not -BeNullOrEmpty
        }
    }

    It 'shows a goal-based main menu without unexplained framework jargon' {
        $script:UserFriendlyMenuLines = [Collections.Generic.List[string]]::new()
        Mock Read-Host -ModuleName EndpointForge { 'Q' }
        Mock Write-Host -ModuleName EndpointForge { $script:UserFriendlyMenuLines.Add([string]$Object) }

        Show-EFMenu -NoPause -NoColor
        $text = $script:UserFriendlyMenuLines -join "`n"

        $text | Should -Match 'Check this computer now'
        $text | Should -Match 'Understand the latest results'
        $text | Should -Match 'Fix selected problems safely'
        $text | Should -Match 'Choosing one never changes Windows'
        $text | Should -Not -Match '\b(baseline|compliance|remediation|WhatIf|controls|elevation|cached)\b'
    }

    It 'translates internal check statuses for the terminal' {
        $script:UserFriendlySummaryLines = [Collections.Generic.List[string]]::new()
        Mock Write-Host -ModuleName EndpointForge { $script:UserFriendlySummaryLines.Add([string]$Object) }
        $summary = [pscustomobject]@{
            ComputerName = 'SAMPLE-PC'; OperatingSystem = 'Windows'; OperatingSystemBuild = '26100';
            OverallStatus = 'Healthy'; Score = 100; HealthStatus = 'Healthy'; HealthScore = 100;
            ComplianceStatus = 'Compliant'; ComplianceScore = 100; DataStatus = 'Complete';
            CoveragePercent = 100; IsRebootPending = $false; Model = 'Sample'; UptimeDays = 1;
            DiskFreePercent = 50; Security = [pscustomobject]@{ Firewall = '3/3 enabled'; Defender = 'Enabled'; BitLocker = 'On'; SecureBoot = 'Enabled'; Tpm = 'Ready' };
            IssueCount = 0; UnknownCount = 0; Findings = @(); NextStep = 'No action is required.'; ExitCode = 0
        }

        $null = $summary | Show-EFEndpointSummary -NoColor
        $text = $script:UserFriendlySummaryLines -join "`n"

        $text | Should -Match 'Looks good'
        $text | Should -Match 'Matches the checklist'
        $text | Should -Not -Match 'Automation exit code'
    }

    It 'does not contain common damaged-encoding artifacts in shipped text' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $files = Get-ChildItem -LiteralPath $projectRoot -Recurse -File |
            Where-Object FullName -NotMatch '[\\/](?:\.git|artifacts|\.build|tests|build)[\\/]' |
            Where-Object Extension -in @('.md', '.txt', '.ps1', '.psm1', '.psd1', '.ps1xml', '.json', '.yml')

        foreach ($file in $files) {
            (Get-Content -LiteralPath $file.FullName -Raw) |
                Should -Not -Match '\u00E2(?:\u20AC|\u2020)|\u00EF\u00BB\u00BF|\uFFFD'
        }
    }
}

Describe 'EndpointForge change receipts' {
    InModuleScope EndpointForge {
        It 'records before expected and after values during a no-change preview' {
            $control = [pscustomobject]@{
                Id = 'TEST-RECEIPT'; Title = 'Sample setting'; Description = 'Sample';
                Type = 'Registry'; Severity = 'High'; Path = 'HKLM:\SOFTWARE\EndpointForgeTest';
                ValueName = 'Enabled'; ValueType = 'DWord'; DesiredValue = 1; Remediable = $true;
                RequiresReboot = $false; WhatWouldChange = 'Set the sample value to 1.';
                SafetyNotes = 'Test only.'; RecoveryGuidance = 'Use the before value through the approved process.'
            }
            $checklist = [pscustomobject]@{
                Name = 'ReceiptTest'; Version = '1.0.0'; Description = 'Receipt test checklist.'; Controls = @($control)
            }
            Mock Test-EFWindows { $true }
            Mock Resolve-EFBaseline { $checklist }
            Mock Get-EFControlState {
                [pscustomobject]@{
                    Status = 'NonCompliant'; ActualValue = 0; DesiredValue = 1; Message = 'Sample differs.';
                    RecommendedAction = 'Preview it.'
                }
            }
            Mock Invoke-EFControlRemediation { throw 'A preview must not change the setting.' }

            $report = Invoke-EFEndpointRemediation -ControlId TEST-RECEIPT -WhatIf -Confirm:$false -NoProgress

            $report.PreviewCount | Should -Be 1
            $report.CanAutomaticallyRollback | Should -BeFalse
            $report.Results[0].BeforeValue | Should -Be 0
            $report.Results[0].DesiredValue | Should -Be 1
            $report.Results[0].AfterValue | Should -Be 0
            $report.Results[0].ChangeWasApplied | Should -BeFalse
            $report.Results[0].RecoveryGuidance | Should -Match 'before value'
            Should -Invoke Invoke-EFControlRemediation -Times 0 -Exactly
        }

        It 'records an observed partial change when a supported fix reports an error' {
            $control = [pscustomobject]@{
                Id = 'TEST-PARTIAL'; Title = 'Sample service'; Description = 'Sample';
                Type = 'Service'; Severity = 'High'; Name = 'SampleService'; StartupType = 'Manual'; Status = 'Running';
                DesiredValue = $null; Remediable = $true; RequiresReboot = $false;
                RecoveryGuidance = 'Use the before value through the approved process.'
            }
            $checklist = [pscustomobject]@{
                Name = 'PartialReceiptTest'; Version = '1.0.0'; Description = 'Partial receipt test checklist.'; Controls = @($control)
            }
            $script:partialStateRead = 0
            Mock Test-EFWindows { $true }
            Mock Test-EFAdministrator { $true }
            Mock Resolve-EFBaseline { $checklist }
            Mock Get-EFControlState {
                $script:partialStateRead++
                if ($script:partialStateRead -eq 1) {
                    [pscustomobject]@{
                        Status = 'NonCompliant'; ActualValue = [ordered]@{ StartupType = 'Disabled'; Status = 'Stopped' };
                        DesiredValue = [ordered]@{ StartupType = 'Manual'; Status = 'Running' }; Message = 'Sample differs.';
                        RecommendedAction = 'Preview it.'
                    }
                }
                else {
                    [pscustomobject]@{
                        Status = 'NonCompliant'; ActualValue = [ordered]@{ StartupType = 'Manual'; Status = 'Stopped' };
                        DesiredValue = [ordered]@{ StartupType = 'Manual'; Status = 'Running' }; Message = 'Only part of the requested state was reached.';
                        RecommendedAction = 'Review it.'
                    }
                }
            }
            Mock Invoke-EFControlRemediation { throw 'The service could not be started.' }

            $report = Invoke-EFEndpointRemediation -ControlId TEST-PARTIAL -Confirm:$false -NoProgress

            $report.FailureCount | Should -Be 1
            $report.PartialChangeCount | Should -Be 1
            $report.Results[0].Outcome | Should -Be 'PartiallyChanged'
            $report.Results[0].ChangeWasApplied | Should -BeTrue
            $report.Results[0].AfterStateWasObserved | Should -BeTrue
            $report.Results[0].AfterValue.StartupType | Should -Be 'Manual'
            $report.Results[0].WhatChanged | Should -Match 'reported an error'
            Should -Invoke Get-EFControlState -Times 2 -Exactly
        }

        It 'counts a changed value when verification does not reach the expected result' {
            $control = [pscustomobject]@{
                Id = 'TEST-VERIFY'; Title = 'Sample setting'; Description = 'Sample';
                Type = 'Registry'; Severity = 'High'; Path = 'HKLM:\SOFTWARE\EndpointForgeTest';
                ValueName = 'Enabled'; ValueType = 'DWord'; DesiredValue = 2; Remediable = $true;
                RequiresReboot = $true; RecoveryGuidance = 'Review the before and after values.'
            }
            $checklist = [pscustomobject]@{
                Name = 'VerificationReceiptTest'; Version = '1.0.0'; Description = 'Verification receipt test checklist.'; Controls = @($control)
            }
            $script:verificationStateRead = 0
            Mock Test-EFWindows { $true }
            Mock Test-EFAdministrator { $true }
            Mock Resolve-EFBaseline { $checklist }
            Mock Get-EFControlState {
                $script:verificationStateRead++
                $value = if ($script:verificationStateRead -eq 1) { 0 } else { 1 }
                [pscustomobject]@{
                    Status = 'NonCompliant'; ActualValue = $value; DesiredValue = 2;
                    Message = 'The value does not match.'; RecommendedAction = 'Review it.'
                }
            }
            Mock Invoke-EFControlRemediation { [pscustomobject]@{ RebootRequired = $true } }

            $report = Invoke-EFEndpointRemediation -ControlId TEST-VERIFY -Confirm:$false -NoProgress

            $report.Results[0].Outcome | Should -Be 'VerificationFailed'
            $report.Results[0].ChangeWasApplied | Should -BeTrue
            $report.Results[0].AfterValue | Should -Be 1
            $report.ObservedChangeCount | Should -Be 1
            $report.PartialChangeCount | Should -Be 1
            $report.Summary | Should -Match '1 error result\(s\) showed a changed after-value'
            $report.RebootRequired | Should -BeTrue
            $report.NextStep | Should -Match 'Review every error'
            $report.NextStep | Should -Match 'review the errors before restarting'
        }

        It 'shows recovery guidance when a failed change attempt cannot be read afterward' {
            $control = [pscustomobject]@{
                Id = 'TEST-UNKNOWN-AFTER'; Title = 'Unreadable setting'; Description = 'Sample';
                Type = 'Registry'; Severity = 'High'; Path = 'HKLM:\SOFTWARE\EndpointForgeTest';
                ValueName = 'Enabled'; ValueType = 'DWord'; DesiredValue = 1; Remediable = $true;
                RequiresReboot = $false; RecoveryGuidance = 'Inspect the setting manually before retrying.'
            }
            $checklist = [pscustomobject]@{
                Name = 'UnreadableReceiptTest'; Version = '1.0.0'; Description = 'Unreadable receipt test checklist.'; Controls = @($control)
            }
            $script:unreadableStateRead = 0
            Mock Test-EFWindows { $true }
            Mock Test-EFAdministrator { $true }
            Mock Resolve-EFBaseline { $checklist }
            Mock Get-EFControlState {
                $script:unreadableStateRead++
                if ($script:unreadableStateRead -eq 1) {
                    [pscustomobject]@{
                        Status = 'NonCompliant'; ActualValue = 0; DesiredValue = 1;
                        Message = 'The value differs.'; RecommendedAction = 'Review it.'
                    }
                }
                else {
                    [pscustomobject]@{
                        Status = 'Error'; ActualValue = $null; DesiredValue = 1;
                        Message = 'Access denied after the attempt.'; RecommendedAction = 'Inspect it.'
                    }
                }
            }
            Mock Invoke-EFControlRemediation { throw 'The write reported an error.' }

            $report = Invoke-EFEndpointRemediation -ControlId TEST-UNKNOWN-AFTER -Confirm:$false -NoProgress
            $script:unreadableReceiptLines = [Collections.Generic.List[string]]::new()
            Mock Write-EFMenuLine { $script:unreadableReceiptLines.Add([string]$Text) }
            Write-EFMenuRemediationReport -Report $report -NoColor

            $report.Results[0].Outcome | Should -Be 'Failed'
            $report.Results[0].ChangeWasApplied | Should -BeFalse
            $report.Results[0].ChangeMayHaveOccurred | Should -BeTrue
            $report.Results[0].AfterStateWasObserved | Should -BeFalse
            $report.Results[0].AfterValue | Should -BeNullOrEmpty
            ($script:unreadableReceiptLines -join "`n") | Should -Match 'Inspect the setting manually before retrying'
        }
    }
}
