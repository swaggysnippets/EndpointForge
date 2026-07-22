BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ProjectRoot 'EndpointForge.psd1'
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force
}

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'EndpointForge module contract' {
    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports only the documented public commands' {
        $expected = @(
            'Export-EFEndpointReport', 'Get-EFBaseline', 'Get-EFComplianceReport',
            'Get-EFConfiguration', 'Get-EFEndpointHealth', 'Get-EFEndpointInventory',
            'Get-EFEndpointSummary', 'Get-EFInstalledSoftware', 'Get-EFPendingReboot',
            'Get-EFRemediationPlan', 'Invoke-EFEndpointRemediation', 'New-EFBaseline',
            'Set-EFConfiguration', 'Show-EFEndpointSummary', 'Show-EFMenu', 'Test-EFBaseline',
            'Test-EFEndpointCompliance'
        ) | Sort-Object
        $actual = @(Get-Command -Module EndpointForge -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
        $actual | Should -Be $expected
    }

    It 'provides meaningful help for every public command' {
        foreach ($command in Get-Command -Module EndpointForge -CommandType Function) {
            (Get-Help $command.Name).Synopsis | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'EndpointForge configuration' {
    AfterEach {
        Set-EFConfiguration -Reset
    }

    It 'uses safe defaults' {
        $configuration = Get-EFConfiguration
        $configuration.LogPath | Should -BeNullOrEmpty
        $configuration.LogLevel | Should -Be 'Information'
        $configuration.RetryCount | Should -Be 2
        $configuration.RetryDelaySeconds | Should -Be 2
    }

    It 'round-trips session settings' {
        $configuration = Set-EFConfiguration -LogPath '%TEMP%\endpointforge.jsonl' -LogLevel Debug `
            -RetryCount 0 -RetryDelaySeconds 0 -PassThru
        $configuration.LogPath | Should -Be '%TEMP%\endpointforge.jsonl'
        $configuration.LogLevel | Should -Be 'Debug'
        $configuration.RetryCount | Should -Be 0
        $configuration.RetryDelaySeconds | Should -Be 0
    }
}

Describe 'EndpointForge baselines' {
    It 'loads and validates the built-in baseline' {
        $baseline = Get-EFBaseline
        $baseline.Name | Should -Be 'EnterpriseRecommended'
        @($baseline.Controls).Count | Should -Be 10
        @($baseline.Controls | Group-Object Id | Where-Object Count -gt 1).Count | Should -Be 0
    }

    It 'lists the built-in baseline' {
        $available = @(Get-EFBaseline -ListAvailable)
        $available.Name | Should -Contain 'EnterpriseRecommended'
    }

    It 'rejects duplicate control identifiers' {
        $badBaseline = [pscustomobject]@{
            Name = 'Invalid'
            Version = '1.0.0'
            Description = 'Duplicate identifier test baseline.'
            Controls = @(
                [pscustomobject]@{ Id = 'DUPLICATE'; Title = 'One'; Type = 'Registry'; Severity = 'Medium'; DesiredValue = 1; Remediable = $false; Path = 'HKLM:\Software\Example'; ValueName = 'Value' },
                [pscustomobject]@{ Id = 'DUPLICATE'; Title = 'Two'; Type = 'Registry'; Severity = 'Medium'; DesiredValue = 1; Remediable = $false; Path = 'HKLM:\Software\Example'; ValueName = 'Value' }
            )
        }
        InModuleScope EndpointForge -Parameters @{ Candidate = $badBaseline } {
            { Assert-EFBaseline -Baseline $Candidate } | Should -Throw '*duplicate*'
        }
    }

    It 'rejects unsafe identifiers and non-Boolean remediation flags' {
        $unsafeId = [pscustomobject]@{
            Name        = 'Invalid'
            Version     = '1.0.0'
            Description = 'Invalid identifier test baseline.'
            Controls    = @(
                [pscustomobject]@{ Id = 'BAD ID'; Title = 'Bad identifier'; Type = 'Registry'; Severity = 'Medium'; DesiredValue = 1; Remediable = $false; Path = 'HKLM:\Software\Example'; ValueName = 'Value' }
            )
        }
        $stringFlag = [pscustomobject]@{
            Name        = 'Invalid'
            Version     = '1.0.0'
            Description = 'Invalid remediation flag test baseline.'
            Controls    = @(
                [pscustomobject]@{ Id = 'BAD-FLAG'; Title = 'Bad flag'; Type = 'Registry'; Severity = 'Medium'; DesiredValue = 1; Remediable = 'false'; Path = 'HKLM:\Software\Example'; ValueName = 'Value' }
            )
        }

        InModuleScope EndpointForge -Parameters @{ UnsafeId = $unsafeId; StringFlag = $stringFlag } {
            { Assert-EFBaseline -Baseline $UnsafeId } | Should -Throw '*only letters*'
            { Assert-EFBaseline -Baseline $StringFlag } | Should -Throw '*JSON Boolean*'
        }
    }

    It 'rejects automatic remediation for audit-only control types' {
        $badBaseline = [pscustomobject]@{
            Name        = 'Invalid'
            Version     = '1.0.0'
            Description = 'Audit-only remediation test baseline.'
            Controls    = @(
                [pscustomobject]@{ Id = 'BAD-SECUREBOOT'; Title = 'Secure Boot'; Type = 'SecureBoot'; Severity = 'High'; DesiredValue = $true; Remediable = $true }
            )
        }

        InModuleScope EndpointForge -Parameters @{ Candidate = $badBaseline } {
            { Assert-EFBaseline -Baseline $Candidate } | Should -Throw '*audit-only*'
        }
    }

    It 'rejects non-Registry provider paths for Registry controls' {
        $badBaseline = [pscustomobject]@{
            Name        = 'Invalid'
            Version     = '1.0.0'
            Description = 'Provider boundary test baseline.'
            Controls    = @(
                [pscustomobject]@{ Id = 'BAD-PROVIDER'; Title = 'Bad provider'; Type = 'Registry'; Severity = 'High'; DesiredValue = 1; Remediable = $true; Path = 'C:\ProgramData\EndpointForge'; ValueName = 'Value'; ValueType = 'DWord' }
            )
        }

        InModuleScope EndpointForge -Parameters @{ Candidate = $badBaseline } {
            { Assert-EFBaseline -Baseline $Candidate } | Should -Throw '*HKLM*HKCU*'
        }
    }

    It 'rejects control characters from operator-facing baseline text' {
        $badBaseline = [pscustomobject]@{
            Name        = 'Invalid'
            Version     = '1.0.0'
            Description = 'Control character test baseline.'
            Controls    = @(
                [pscustomobject]@{ Id = 'BAD-TITLE'; Title = "Safe title`n[FAKE SUCCESS]"; Type = 'Registry'; Severity = 'High'; DesiredValue = 1; Remediable = $false; Path = 'HKLM:\Software\EndpointForge'; ValueName = 'Value' }
            )
        }

        InModuleScope EndpointForge -Parameters @{ Candidate = $badBaseline } {
            { Assert-EFBaseline -Baseline $Candidate } | Should -Throw '*control characters*'
        }
    }
}

Describe 'EndpointForge report export' {
    It 'round-trips JSON data' {
        $path = Join-Path $TestDrive 'report.json'
        [pscustomobject]@{ Name = 'Test'; Nested = [pscustomobject]@{ Value = 42 } } |
            Export-EFEndpointReport -Path $path -Force | Out-Null
        $result = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $result.Name | Should -Be 'Test'
        $result.Nested.Value | Should -Be 42
    }

    It 'writes ISO 8601 dates as UTF-8 without a BOM' {
        $path = Join-Path $TestDrive 'portable.json'
        $date = [DateTime]::SpecifyKind([DateTime]'2026-07-20T12:34:56', [DateTimeKind]::Utc)

        [pscustomobject]@{ CapturedAtUtc = $date } | Export-EFEndpointReport -Path $path -Force

        $text = [IO.File]::ReadAllText($path)
        $bytes = [IO.File]::ReadAllBytes($path)
        $text | Should -Match '2026-07-20T12:34:56.*Z'
        $text | Should -Not -Match '/Date\('
        ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }

    It 'preserves a one-item array when AsArray is requested' {
        $path = Join-Path $TestDrive 'array.json'

        [pscustomobject]@{ Name = 'Only' } | Export-EFEndpointReport -Path $path -AsArray -Force

        (Get-Content -LiteralPath $path -Raw).TrimStart().StartsWith('[') | Should -BeTrue
    }

    It 'writes explicit null input as valid JSON' {
        $path = Join-Path $TestDrive 'null.json'

        Export-EFEndpointReport -InputObject $null -Path $path -Force

        (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be 'null'
    }

    It 'infers format and rejects an extension mismatch' {
        $path = Join-Path $TestDrive 'inferred.csv'

        [pscustomobject]@{ Name = 'Test' } | Export-EFEndpointReport -Path $path -Force

        (Get-Content -LiteralPath $path -First 1) | Should -Match '"Name"'
        { [pscustomobject]@{ Name = 'Test' } | Export-EFEndpointReport -Path $path -Format Json -Force } |
            Should -Throw '*does not match*'
    }

    It 'does not overwrite without Force' {
        $path = Join-Path $TestDrive 'existing.json'
        Set-Content -LiteralPath $path -Value '{}'
        { [pscustomobject]@{ Name = 'Test' } | Export-EFEndpointReport -Path $path } | Should -Throw '*-Force*'
    }

    It 'honors WhatIf' {
        $path = Join-Path $TestDrive 'whatif.json'
        [pscustomobject]@{ Name = 'Test' } | Export-EFEndpointReport -Path $path -WhatIf
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}

Describe 'EndpointForge installed software experience' {
    It 'ignores sparse uninstall entries without StrictMode errors' {
        Mock Test-EFWindows -ModuleName EndpointForge { $true }
        Mock Get-ItemProperty -ModuleName EndpointForge {
            @(
                [pscustomobject]@{ PSChildName = 'SparseEntry' },
                [pscustomobject]@{ PSChildName = 'ValidEntry'; DisplayName = 'Contoso App'; DisplayVersion = '1.0' }
            )
        }

        { Get-EFInstalledSoftware -Scope CurrentUser -ErrorAction Stop } | Should -Not -Throw
        $result = @(Get-EFInstalledSoftware -Scope CurrentUser -ErrorAction Stop)
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'Contoso App'
        $result[0].UninstallString | Should -BeNullOrEmpty
    }
}

Describe 'EndpointForge Boolean compliance experience' {
    It 'returns a scalar Boolean by default' {
        Mock Get-EFComplianceReport -ModuleName EndpointForge {
            [pscustomobject]@{
                PSTypeName  = 'EndpointForge.ComplianceReport'
                IsCompliant = $false
                ExitCode    = 2
            }
        }

        $result = Test-EFEndpointCompliance -NoProgress

        $result.GetType().FullName | Should -Be 'System.Boolean'
        $result | Should -BeFalse
        Should -Invoke Get-EFComplianceReport -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter { $NoProgress }
    }

    It 'returns the rich report when PassThru is requested' {
        Mock Get-EFComplianceReport -ModuleName EndpointForge {
            [pscustomobject]@{
                PSTypeName  = 'EndpointForge.ComplianceReport'
                IsCompliant = $true
                ExitCode    = 0
                Results     = @()
            }
        }

        $result = Test-EFEndpointCompliance -PassThru -NoProgress

        $result.PSObject.TypeNames | Should -Contain 'EndpointForge.ComplianceReport'
        $result.IsCompliant | Should -BeTrue
        $result.Results.Count | Should -Be 0
    }
}

Describe 'EndpointForge baseline validation experience' {
    It 'returns a scalar Boolean for a valid pipeline baseline' {
        $baseline = Get-EFBaseline

        $result = $baseline | Test-EFBaseline

        $result.GetType().FullName | Should -Be 'System.Boolean'
        $result | Should -BeTrue
    }

    It 'returns false instead of throwing for an invalid in-memory baseline' {
        $invalidBaseline = [pscustomobject]@{
            Name     = 'Invalid'
            Version  = 'not-a-version'
            Controls = @()
        }

        $result = Test-EFBaseline -InputObject $invalidBaseline

        $result.GetType().FullName | Should -Be 'System.Boolean'
        $result | Should -BeFalse
    }

    It 'returns actionable validation details with PassThru' {
        $invalidBaseline = [pscustomobject]@{
            Name        = 'Invalid'
            Version     = '1.0.0'
            Description = 'Invalid test baseline.'
            Controls    = @()
        }

        $result = Test-EFBaseline -InputObject $invalidBaseline -PassThru

        $result.PSObject.TypeNames | Should -Contain 'EndpointForge.BaselineValidation'
        $result.IsValid | Should -BeFalse
        $result.ErrorCount | Should -BeGreaterThan 0
        @($result.Errors).Count | Should -Be $result.ErrorCount
        $result.Errors[0] | Should -Match 'control'
        $result.PSObject.Properties.Name | Should -Contain 'Warnings'
    }

    It 'turns a missing file into a validation result instead of a terminating error' {
        $missingPath = Join-Path $TestDrive 'missing-baseline.json'

        $result = Test-EFBaseline -Path $missingPath -PassThru

        $result.IsValid | Should -BeFalse
        $result.Errors[0] | Should -Match 'not found'
    }
}

Describe 'EndpointForge baseline creation experience' {
    It 'does not create a file or parent directory under WhatIf' {
        $parent = Join-Path $TestDrive 'whatif\nested'

        $result = New-EFBaseline -Name 'Contoso.WhatIf' -Path $parent -WhatIf

        $result | Should -BeNullOrEmpty
        Test-Path -LiteralPath $parent | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $parent 'Contoso.WhatIf.json') | Should -BeFalse
    }

    It 'creates a valid BOM-less baseline and returns next-step metadata' {
        $path = Join-Path $TestDrive 'created\Contoso.Workstation.json'

        $result = New-EFBaseline -Name 'Contoso.Workstation' -Description 'Test workstation policy.' `
            -Version '2.1.0' -Template Starter -Path $path

        $result.PSObject.TypeNames | Should -Contain 'EndpointForge.BaselineCreationResult'
        $result.Path | Should -Be $path
        $result.Name | Should -Be 'Contoso.Workstation'
        $result.Version | Should -Be '2.1.0'
        $result.Template | Should -Be 'Starter'
        $result.ControlCount | Should -Be 5
        @($result.NextSteps).Count | Should -BeGreaterThan 1
        Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $result.SchemaPath -PathType Leaf | Should -BeTrue
        (Test-EFBaseline -Path $path) | Should -BeTrue

        $createdJson = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $createdJson.'$schema' | Should -Be './EndpointForge.Baseline.schema.json'

        $bytes = [IO.File]::ReadAllBytes($path)
        $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $hasUtf8Bom | Should -BeFalse
    }

    It 'preserves an existing file unless Force is specified' {
        $path = Join-Path $TestDrive 'existing-baseline.json'
        Set-Content -LiteralPath $path -Value 'keep me'

        { New-EFBaseline -Name 'Contoso.Existing' -Path $path } | Should -Throw '*-Force*'
        (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be 'keep me'
    }
}

Describe 'EndpointForge remediation planning experience' {
    It 'classifies automatic, manual, blocked, and already-satisfied controls without changing state' {
        $baseline = [pscustomobject]@{
            Name        = 'PlanTest'
            Version     = '1.0.0'
            Description = 'Remediation plan test baseline.'
            Controls    = @(
                [pscustomobject]@{ Id = 'PLAN-AUTO'; Title = 'Automatic'; Type = 'Registry'; Severity = 'High'; DesiredValue = 1; Remediable = $true; RequiresReboot = $true; Path = 'HKLM:\Software\EndpointForge'; ValueName = 'Automatic'; ValueType = 'DWord' }
                [pscustomobject]@{ Id = 'PLAN-MANUAL'; Title = 'Manual'; Type = 'Registry'; Severity = 'Medium'; DesiredValue = 1; Remediable = $false; RequiresReboot = $false; Path = 'HKLM:\Software\EndpointForge'; ValueName = 'Manual'; ValueType = 'DWord' }
                [pscustomobject]@{ Id = 'PLAN-BLOCKED'; Title = 'Blocked'; Type = 'Registry'; Severity = 'High'; DesiredValue = 1; Remediable = $true; RequiresReboot = $false; Path = 'HKLM:\Software\EndpointForge'; ValueName = 'Blocked'; ValueType = 'DWord' }
                [pscustomobject]@{ Id = 'PLAN-COMPLIANT'; Title = 'Compliant'; Type = 'Registry'; Severity = 'Low'; DesiredValue = 1; Remediable = $true; RequiresReboot = $false; Path = 'HKLM:\Software\EndpointForge'; ValueName = 'Compliant'; ValueType = 'DWord' }
                [pscustomobject]@{ Id = 'PLAN-NA'; Title = 'Not applicable'; Type = 'Registry'; Severity = 'Low'; DesiredValue = 1; Remediable = $false; RequiresReboot = $false; Path = 'HKLM:\Software\EndpointForge'; ValueName = 'NotApplicable'; ValueType = 'DWord' }
            )
        }
        Mock Get-EFComplianceReport -ModuleName EndpointForge {
            [pscustomobject]@{
                PSTypeName  = 'EndpointForge.ComplianceReport'
                IsCompliant = $false
                Results     = @(
                    [pscustomobject]@{ ControlId = 'PLAN-AUTO'; Title = 'Automatic'; Severity = 'High'; Status = 'NonCompliant'; ActualValue = 0; DesiredValue = 1; Message = 'Change available.'; RecommendedAction = 'Preview remediation.' }
                    [pscustomobject]@{ ControlId = 'PLAN-MANUAL'; Title = 'Manual'; Severity = 'Medium'; Status = 'NonCompliant'; ActualValue = 0; DesiredValue = 1; Message = 'Manual action required.'; RecommendedAction = 'Use enterprise policy.' }
                    [pscustomobject]@{ ControlId = 'PLAN-BLOCKED'; Title = 'Blocked'; Severity = 'High'; Status = 'Error'; ActualValue = $null; DesiredValue = 1; Message = 'Access denied.'; RecommendedAction = 'Run elevated.' }
                    [pscustomobject]@{ ControlId = 'PLAN-COMPLIANT'; Title = 'Compliant'; Severity = 'Low'; Status = 'Compliant'; ActualValue = 1; DesiredValue = 1; Message = 'Already compliant.'; RecommendedAction = 'No action required.' }
                    [pscustomobject]@{ ControlId = 'PLAN-NA'; Title = 'Not applicable'; Severity = 'Low'; Status = 'NotApplicable'; ActualValue = $null; DesiredValue = 1; Message = 'Feature unavailable.'; RecommendedAction = 'No action required.' }
                )
            }
        }
        Mock Invoke-EFEndpointRemediation -ModuleName EndpointForge { throw 'A plan must never invoke remediation.' }

        $plan = Get-EFRemediationPlan -Baseline $baseline -NoProgress

        $plan.PSObject.TypeNames | Should -Contain 'EndpointForge.RemediationPlan'
        $plan.AutomaticCount | Should -Be 1
        $plan.ManualCount | Should -Be 1
        $plan.BlockedCount | Should -Be 1
        $plan.NoActionCount | Should -Be 1
        $plan.NotApplicableCount | Should -Be 1
        $plan.RequiresElevation | Should -BeTrue
        $plan.PotentialReboot | Should -BeTrue
        $plan.IsReady | Should -BeFalse
        @($plan.Steps).Count | Should -Be 3
        ($plan.Steps | Where-Object ControlId -eq 'PLAN-AUTO').Action | Should -Be 'Automatic'
        ($plan.Steps | Where-Object ControlId -eq 'PLAN-AUTO').CommandPreview | Should -BeNullOrEmpty
        ($plan.Steps | Where-Object ControlId -eq 'PLAN-MANUAL').Action | Should -Be 'Manual'
        ($plan.Steps | Where-Object ControlId -eq 'PLAN-BLOCKED').Action | Should -Be 'Blocked'

        $completePlan = Get-EFRemediationPlan -Baseline $baseline -IncludeCompliant -NoProgress
        @($completePlan.Steps).Count | Should -Be 5
        Should -Invoke Get-EFComplianceReport -ModuleName EndpointForge -Times 2 -Exactly -ParameterFilter { $NoProgress }
        Should -Invoke Invoke-EFEndpointRemediation -ModuleName EndpointForge -Times 0 -Exactly
    }

    It 'includes the custom baseline path in safe command previews' {
        $path = Join-Path $TestDrive 'planning\Contoso.Plan.json'
        $null = New-EFBaseline -Name 'Contoso.Plan' -Description 'Planning preview baseline.' `
            -Template Starter -Path $path
        Mock Get-EFComplianceReport -ModuleName EndpointForge {
            [pscustomobject]@{
                PSTypeName = 'EndpointForge.ComplianceReport'
                Results    = @(
                    [pscustomobject]@{
                        ControlId = 'EF-FW-DOMAIN'; Title = 'Domain firewall'; Severity = 'Critical';
                        Status = 'NonCompliant'; ActualValue = $false; DesiredValue = $true;
                        Message = 'Firewall is disabled.'; RecommendedAction = 'Preview remediation.'
                    }
                )
            }
        }

        $plan = Get-EFRemediationPlan -Baseline $path -ControlId 'EF-FW-DOMAIN' -NoProgress
        $preview = ($plan.Steps | Where-Object ControlId -eq 'EF-FW-DOMAIN').CommandPreview

        $preview | Should -Match ([regex]::Escape("-Baseline '$path'"))
        $preview | Should -Match '-WhatIf$'
    }
}

Describe 'EndpointForge combined summary experience' {
    It 'distinguishes incomplete privileged collection from a known unhealthy endpoint' {
        Mock Get-EFEndpointHealth -ModuleName EndpointForge {
            [pscustomobject]@{
                PSTypeName      = 'EndpointForge.EndpointHealth'
                Status          = 'Healthy'
                Score           = 90
                DataStatus      = 'Partial'
                CoveragePercent = 80
                Checks          = @(
                    [pscustomobject]@{ Id = 'InventoryCollection'; Severity = 'Warning'; Status = 'Unknown'; Message = 'BitLocker: Access denied.' }
                )
                PendingReboot   = [pscustomobject]@{ IsRebootPending = $false }
                Inventory       = [pscustomobject]@{
                    ComputerName          = 'TEST-PC'
                    OperatingSystemName   = 'Microsoft Windows 11 Enterprise'
                    OperatingSystemBuild  = '26100'
                    DeviceModel           = 'Virtual Machine'
                    UptimeDays            = 4.5
                    SystemDriveFreePercent = 42.0
                    Security              = [pscustomobject]@{
                        Firewall   = @()
                        Defender   = $null
                        BitLocker  = $null
                        SecureBoot = $null
                        Tpm         = $null
                    }
                }
            }
        }
        Mock Get-EFComplianceReport -ModuleName EndpointForge {
            [pscustomobject]@{
                PSTypeName         = 'EndpointForge.ComplianceReport'
                Score              = 80
                DataStatus         = 'Partial'
                CoveragePercent    = 60
                NonCompliantCount  = 0
                ErrorCount         = 1
                Results            = @(
                    [pscustomobject]@{
                        ControlId = 'EF-BITLOCKER-OS'; Title = 'BitLocker posture'; Severity = 'High';
                        Status = 'Error'; Message = 'Access denied.'; RecommendedAction = 'Run the assessment from an elevated PowerShell session.'
                    }
                )
            }
        }
        Mock Write-Progress -ModuleName EndpointForge {}

        $summary = Get-EFEndpointSummary -ControlId 'EF-BITLOCKER-OS' -IncludeSoftware `
            -MinimumFreeSpacePercent 20 -MaximumUptimeDays 14 -NoProgress

        $summary.PSObject.TypeNames | Should -Contain 'EndpointForge.EndpointSummary'
        $summary.ComputerName | Should -Be 'TEST-PC'
        $summary.OverallStatus | Should -Be 'Incomplete'
        $summary.ComplianceStatus | Should -Be 'Incomplete'
        $summary.DataStatus | Should -Be 'Partial'
        $summary.Score | Should -Be 85
        $summary.CoveragePercent | Should -Be 70
        $summary.IssueCount | Should -Be 0
        $summary.UnknownCount | Should -Be 1
        $summary.ExitCode | Should -Be 3
        @($summary.Findings | Where-Object RequiresElevation).Count | Should -Be 1
        $summary.NextStep | Should -Match 'elevat'

        Should -Invoke Get-EFEndpointHealth -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $IncludeSoftware -and $MinimumFreeSpacePercent -eq 20 -and $MaximumUptimeDays -eq 14 -and $NoProgress
        }
        Should -Invoke Get-EFComplianceReport -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $NoProgress -and $ControlId -contains 'EF-BITLOCKER-OS'
        }
        Should -Invoke Write-Progress -ModuleName EndpointForge -Times 0 -Exactly
    }
}

Describe 'EndpointForge terminal summary experience' {
    AfterEach {
        Remove-Item Env:ENDPOINTFORGE_TEST_HOST_CAPTURE -ErrorAction SilentlyContinue
        Remove-Item Env:ENDPOINTFORGE_TEST_COLOR_CAPTURE -ErrorAction SilentlyContinue
    }

    It 'renders identical plain content and returns nothing unless PassThru is requested' {
        $summary = [pscustomobject]@{
            PSTypeName           = 'EndpointForge.EndpointSummary'
            ComputerName         = 'TEST-PC'
            OperatingSystem      = 'Windows 11 Enterprise'
            OperatingSystemBuild = '26100'
            OverallStatus        = 'Warning'
            Score                = 82
            HealthStatus         = 'Warning'
            HealthScore          = 90
            ComplianceStatus     = 'NonCompliant'
            ComplianceScore      = 74
            DataStatus           = 'Complete'
            CoveragePercent      = 100
            IsRebootPending      = $false
            Model                = 'Virtual Machine'
            UptimeDays           = 3.2
            DiskFreePercent      = 35
            Security             = [pscustomobject]@{ Firewall = '3/3 enabled'; Defender = 'Enabled'; BitLocker = 'On'; SecureBoot = 'Enabled'; Tpm = 'Ready' }
            IssueCount           = 1
            UnknownCount         = 0
            Findings             = @(
                [pscustomobject]@{ Status = 'NonCompliant'; Severity = 'High'; Id = 'TEST-CONTROL'; Title = 'Test control'; Message = 'A test finding.'; SuggestedAction = 'Review it.' }
            )
            NextStep             = 'Review the remediation plan.'
            ExitCode             = 2
        }
        $env:ENDPOINTFORGE_TEST_HOST_CAPTURE = Join-Path $TestDrive 'host-lines.txt'
        $env:ENDPOINTFORGE_TEST_COLOR_CAPTURE = Join-Path $TestDrive 'host-colors.txt'
        Mock Write-Host -ModuleName EndpointForge {
            Add-Content -LiteralPath $env:ENDPOINTFORGE_TEST_HOST_CAPTURE -Value ([string]$Object)
            if ($null -ne $ForegroundColor) {
                Add-Content -LiteralPath $env:ENDPOINTFORGE_TEST_COLOR_CAPTURE -Value 'color'
            }
        }

        $plainOutput = @($summary | Show-EFEndpointSummary -NoColor)
        $plainLines = @(Get-Content -LiteralPath $env:ENDPOINTFORGE_TEST_HOST_CAPTURE)
        $plainColorCalls = if (Test-Path -LiteralPath $env:ENDPOINTFORGE_TEST_COLOR_CAPTURE) {
            @(Get-Content -LiteralPath $env:ENDPOINTFORGE_TEST_COLOR_CAPTURE).Count
        }
        else { 0 }

        Clear-Content -LiteralPath $env:ENDPOINTFORGE_TEST_HOST_CAPTURE
        Remove-Item -LiteralPath $env:ENDPOINTFORGE_TEST_COLOR_CAPTURE -ErrorAction SilentlyContinue
        $passThruOutput = @($summary | Show-EFEndpointSummary -PassThru)
        $colorLines = @(Get-Content -LiteralPath $env:ENDPOINTFORGE_TEST_HOST_CAPTURE)
        $colorCallCount = @(Get-Content -LiteralPath $env:ENDPOINTFORGE_TEST_COLOR_CAPTURE).Count

        $plainOutput.Count | Should -Be 0
        $plainColorCalls | Should -Be 0
        ($plainLines -join "`n") | Should -Be ($colorLines -join "`n")
        ($plainLines -join "`n") | Should -Match 'TEST-PC'
        ($plainLines -join "`n") | Should -Match 'Review the remediation plan'
        $colorCallCount | Should -BeGreaterThan 0
        $passThruOutput.Count | Should -Be 1
        [object]::ReferenceEquals($summary, $passThruOutput[0]) | Should -BeTrue
    }

    It 'can collect a summary itself and forwards collection options' {
        Mock Get-EFEndpointSummary -ModuleName EndpointForge {
            [pscustomobject]@{
                PSTypeName = 'EndpointForge.EndpointSummary'; ComputerName = 'COLLECTED-PC';
                OperatingSystem = 'Windows'; OperatingSystemBuild = '26100'; OverallStatus = 'Healthy'; Score = 100;
                HealthStatus = 'Healthy'; HealthScore = 100; ComplianceStatus = 'Compliant'; ComplianceScore = 100;
                DataStatus = 'Complete'; CoveragePercent = 100; IsRebootPending = $false; Model = 'Model'; UptimeDays = 1;
                DiskFreePercent = 50; Security = [pscustomobject]@{ Firewall = '3/3 enabled'; Defender = 'Enabled'; BitLocker = 'On'; SecureBoot = 'Enabled'; Tpm = 'Ready' };
                IssueCount = 0; UnknownCount = 0; Findings = @(); NextStep = 'No action is required.'; ExitCode = 0
            }
        }
        Mock Write-Host -ModuleName EndpointForge {}

        $result = Show-EFEndpointSummary -ControlId 'EF-UAC-ENABLED' -IncludeSoftware `
            -MinimumFreeSpacePercent 25 -MaximumUptimeDays 10 -NoProgress -NoColor -PassThru

        $result.ComputerName | Should -Be 'COLLECTED-PC'
        Should -Invoke Get-EFEndpointSummary -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $IncludeSoftware -and $MinimumFreeSpacePercent -eq 25 -and $MaximumUptimeDays -eq 10 -and
                $NoProgress -and $ControlId -contains 'EF-UAC-ENABLED'
        }
    }
}

Describe 'EndpointForge guided menu experience' {
    BeforeEach {
        $script:EFMenuInputs = [Collections.Generic.Queue[string]]::new()
        Mock Write-Host -ModuleName EndpointForge {}
        Mock Test-EFAdministrator -ModuleName EndpointForge { $false }
    }

    AfterEach {
        Remove-Variable EFMenuInputs -Scope Script -ErrorAction SilentlyContinue
    }

    It 'quits without collecting data, changing state, or creating the report directory' {
        $reportDirectory = Join-Path $TestDrive 'unused-reports'
        $script:EFMenuInputs.Enqueue('Q')
        Mock Read-Host -ModuleName EndpointForge { $script:EFMenuInputs.Dequeue() }
        Mock Get-EFEndpointSummary -ModuleName EndpointForge { throw 'Must not collect.' }
        Mock Get-EFRemediationPlan -ModuleName EndpointForge { throw 'Must not plan.' }
        Mock Invoke-EFEndpointRemediation -ModuleName EndpointForge { throw 'Must not remediate.' }
        Mock Export-EFEndpointReport -ModuleName EndpointForge { throw 'Must not export.' }

        $output = @(Show-EFMenu -ReportDirectory $reportDirectory -NoPause -NoColor)

        $output.Count | Should -Be 0
        Test-Path -LiteralPath $reportDirectory | Should -BeFalse
        Should -Invoke Get-EFEndpointSummary -ModuleName EndpointForge -Times 0 -Exactly
        Should -Invoke Get-EFRemediationPlan -ModuleName EndpointForge -Times 0 -Exactly
        Should -Invoke Invoke-EFEndpointRemediation -ModuleName EndpointForge -Times 0 -Exactly
        Should -Invoke Export-EFEndpointReport -ModuleName EndpointForge -Times 0 -Exactly
    }

    It 'recovers from invalid input and returns exactly one typed session with PassThru' {
        $script:EFMenuInputs.Enqueue('not-an-option')
        $script:EFMenuInputs.Enqueue('Q')
        Mock Read-Host -ModuleName EndpointForge { $script:EFMenuInputs.Dequeue() }

        $output = @(Show-EFMenu -NoPause -NoColor -PassThru)

        $output.Count | Should -Be 1
        $output[0].PSObject.TypeNames | Should -Contain 'EndpointForge.MenuSession'
        $output[0].ExitReason | Should -Be 'Quit'
        $output[0].ActionCount | Should -Be 0
        $output[0].ErrorCount | Should -Be 0
        Should -Invoke Write-Host -ModuleName EndpointForge -ParameterFilter { [string]$Object -match '\[INVALID\]' }
        Should -Invoke Write-Host -ModuleName EndpointForge -Times 0 -Exactly -ParameterFilter { $null -ne $ForegroundColor }
    }

    It 'forwards assessment settings and keeps subordinate objects out of the pipeline' {
        $summary = [pscustomobject]@{
            PSTypeName = 'EndpointForge.EndpointSummary'; ComputerName = 'MENU-PC'; OverallStatus = 'Healthy';
            CompletedAtUtc = [DateTime]::UtcNow; IssueCount = 0; UnknownCount = 0
        }
        $script:EFMenuInputs.Enqueue('1')
        $script:EFMenuInputs.Enqueue('Q')
        Mock Read-Host -ModuleName EndpointForge { $script:EFMenuInputs.Dequeue() }
        Mock Get-EFEndpointSummary -ModuleName EndpointForge { $summary }
        Mock Show-EFEndpointSummary -ModuleName EndpointForge { 'unexpected pipeline output' }

        $output = @(Show-EFMenu -Baseline EnterpriseRecommended -IncludeSoftware `
            -MinimumFreeSpacePercent 25 -MaximumUptimeDays 10 -NoProgress -NoPause -NoColor -PassThru)

        $output.Count | Should -Be 1
        [object]::ReferenceEquals($summary, $output[0].LastSummary) | Should -BeTrue
        $output[0].ActionCount | Should -Be 1
        Should -Invoke Get-EFEndpointSummary -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $Baseline -eq 'EnterpriseRecommended' -and $IncludeSoftware -and
                $MinimumFreeSpacePercent -eq 25 -and $MaximumUptimeDays -eq 10 -and $NoProgress
        }
        Should -Invoke Show-EFEndpointSummary -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $InputObject.ComputerName -eq 'MENU-PC' -and $NoColor
        }
    }

    It 'shows an action error and returns to the main menu' {
        $script:EFMenuInputs.Enqueue('1')
        $script:EFMenuInputs.Enqueue('Q')
        Mock Read-Host -ModuleName EndpointForge { $script:EFMenuInputs.Dequeue() }
        Mock Get-EFEndpointSummary -ModuleName EndpointForge { throw 'Synthetic collection failure.' }

        $session = Show-EFMenu -NoPause -NoColor -PassThru

        $session.ExitReason | Should -Be 'Quit'
        $session.ErrorCount | Should -Be 1
        $session.Errors[0].Action | Should -Be 'Assessment'
        $session.Errors[0].Message | Should -Match 'Synthetic collection failure'
        Should -Invoke Read-Host -ModuleName EndpointForge -Times 2 -Exactly
        Should -Invoke Write-Host -ModuleName EndpointForge -ParameterFilter { [string]$Object -match '\[ERROR\]' }
    }

    It 'builds a read-only plan without invoking remediation' {
        $plan = [pscustomobject]@{
            PSTypeName = 'EndpointForge.RemediationPlan'; BaselineName = 'EnterpriseRecommended'; BaselineVersion = '1.0.0';
            AutomaticCount = 0; ManualCount = 0; BlockedCount = 0; PotentialReboot = $false;
            Summary = 'No remediation candidates were found.'; Steps = @()
        }
        $script:EFMenuInputs.Enqueue('3')
        $script:EFMenuInputs.Enqueue('Q')
        Mock Read-Host -ModuleName EndpointForge { $script:EFMenuInputs.Dequeue() }
        Mock Get-EFRemediationPlan -ModuleName EndpointForge { $plan }
        Mock Invoke-EFEndpointRemediation -ModuleName EndpointForge { throw 'Planning must not remediate.' }

        $session = Show-EFMenu -NoProgress -NoPause -NoColor -PassThru

        [object]::ReferenceEquals($plan, $session.LastPlan) | Should -BeTrue
        Should -Invoke Get-EFRemediationPlan -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter { $NoProgress }
        Should -Invoke Invoke-EFEndpointRemediation -ModuleName EndpointForge -Times 0 -Exactly
    }

    It 'previews only selected automatic controls with WhatIf' {
        $plan = [pscustomobject]@{
            PSTypeName = 'EndpointForge.RemediationPlan'; BaselineName = 'EnterpriseRecommended'; BaselineVersion = '1.0.0';
            AutomaticCount = 2; ManualCount = 0; BlockedCount = 0; PotentialReboot = $true; Summary = 'Two changes.';
            Steps = @(
                [pscustomobject]@{ Action = 'Automatic'; ControlId = 'AUTO-ONE'; Title = 'First'; CurrentValue = 0; DesiredValue = 1; RequiresElevation = $true; RequiresReboot = $false }
                [pscustomobject]@{ Action = 'Automatic'; ControlId = 'AUTO-TWO'; Title = 'Second'; CurrentValue = 0; DesiredValue = 1; RequiresElevation = $true; RequiresReboot = $true }
            )
        }
        $preview = [pscustomobject]@{
            PSTypeName = 'EndpointForge.RemediationReport'; ExitCode = 0; Summary = 'One change previewed.';
            CandidateCount = 1; ChangedCount = 0; PreviewCount = 1; FailureCount = 0;
            Results = @([pscustomobject]@{ Outcome = 'WhatIf'; ControlId = 'AUTO-TWO'; Title = 'Second' }); NextStep = 'Apply when approved.'
        }
        @('4', '2', 'Q') | ForEach-Object { $script:EFMenuInputs.Enqueue($_) }
        Mock Read-Host -ModuleName EndpointForge { $script:EFMenuInputs.Dequeue() }
        Mock Get-EFRemediationPlan -ModuleName EndpointForge { $plan }
        Mock Invoke-EFEndpointRemediation -ModuleName EndpointForge { $preview }

        $session = Show-EFMenu -NoProgress -NoPause -NoColor -PassThru

        [object]::ReferenceEquals($preview, $session.LastPreview) | Should -BeTrue
        Should -Invoke Invoke-EFEndpointRemediation -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $WhatIf -and $Confirm -eq $false -and $NoProgress -and
                @($ControlId).Count -eq 1 -and $ControlId -contains 'AUTO-TWO'
        }
    }

    It 'requires the APPLY acknowledgement even with NoPause and cancels safely' {
        Mock Test-EFAdministrator -ModuleName EndpointForge { $true }
        $plan = [pscustomobject]@{
            PSTypeName = 'EndpointForge.RemediationPlan'; BaselineName = 'EnterpriseRecommended'; BaselineVersion = '1.0.0';
            AutomaticCount = 1; ManualCount = 0; BlockedCount = 0; PotentialReboot = $false; Summary = 'One change.';
            Steps = @(
                [pscustomobject]@{ Action = 'Automatic'; ControlId = 'AUTO-ONE'; Title = 'First'; CurrentValue = 0; DesiredValue = 1; RequiresElevation = $true; RequiresReboot = $false }
            )
        }
        $preview = [pscustomobject]@{
            PSTypeName = 'EndpointForge.RemediationReport'; ExitCode = 0; Summary = 'One change previewed.';
            CandidateCount = 1; ChangedCount = 0; PreviewCount = 1; FailureCount = 0;
            Results = @([pscustomobject]@{ Outcome = 'WhatIf'; ControlId = 'AUTO-ONE'; Title = 'First' }); NextStep = 'Apply when approved.'
        }
        @('5', 'A', 'cancel', 'Q') | ForEach-Object { $script:EFMenuInputs.Enqueue($_) }
        Mock Read-Host -ModuleName EndpointForge { $script:EFMenuInputs.Dequeue() }
        Mock Get-EFRemediationPlan -ModuleName EndpointForge { $plan }
        Mock Invoke-EFEndpointRemediation -ModuleName EndpointForge { $preview }

        $session = Show-EFMenu -NoProgress -NoPause -NoColor -PassThru

        $session.LastRemediation | Should -BeNullOrEmpty
        Should -Invoke Invoke-EFEndpointRemediation -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter { $WhatIf }
        Should -Invoke Invoke-EFEndpointRemediation -ModuleName EndpointForge -Times 0 -Exactly -ParameterFilter { -not $WhatIf }
        ($session.History | Where-Object Action -eq 'Apply remediation').Status | Should -Contain 'Cancelled'
    }

    It 'clears cached results when the active baseline changes' {
        $summary = [pscustomobject]@{
            PSTypeName = 'EndpointForge.EndpointSummary'; ComputerName = 'MENU-PC'; OverallStatus = 'Healthy';
            CompletedAtUtc = [DateTime]::UtcNow; IssueCount = 0; UnknownCount = 0
        }
        @('1', '7', 'EnterpriseRecommended', 'Q') | ForEach-Object { $script:EFMenuInputs.Enqueue($_) }
        Mock Read-Host -ModuleName EndpointForge { $script:EFMenuInputs.Dequeue() }
        Mock Get-EFEndpointSummary -ModuleName EndpointForge { $summary }
        Mock Show-EFEndpointSummary -ModuleName EndpointForge {}

        $session = Show-EFMenu -NoPause -NoColor -PassThru

        $session.LastSummary | Should -BeNullOrEmpty
        $session.BaselineName | Should -Be 'EnterpriseRecommended'
        ($session.History | Where-Object Action -eq 'Select baseline').Status | Should -Contain 'Completed'
    }

    It 'returns actionable guidance when the host cannot prompt for input' {
        Mock Read-Host -ModuleName EndpointForge { throw [System.Management.Automation.PSInvalidOperationException]::new('Host is non-interactive.') }

        { Show-EFMenu -NoColor } | Should -Throw '*requires an interactive PowerShell host*'
    }

    It 'exports a typed session bundle only after results exist' {
        $reportDirectory = Join-Path $TestDrive 'menu-reports'
        $summary = [pscustomobject]@{
            PSTypeName = 'EndpointForge.EndpointSummary'; ComputerName = 'MENU-PC'; OverallStatus = 'Healthy';
            CompletedAtUtc = [DateTime]::UtcNow; IssueCount = 0; UnknownCount = 0
        }
        @('1', '6', 'Q') | ForEach-Object { $script:EFMenuInputs.Enqueue($_) }
        Mock Read-Host -ModuleName EndpointForge { $script:EFMenuInputs.Dequeue() }
        Mock Get-EFEndpointSummary -ModuleName EndpointForge { $summary }
        Mock Show-EFEndpointSummary -ModuleName EndpointForge {}
        Mock Export-EFEndpointReport -ModuleName EndpointForge { [IO.FileInfo]::new($Path) }

        $session = Show-EFMenu -ReportDirectory $reportDirectory -NoPause -NoColor -PassThru

        $session.LastExportPath | Should -Match ([regex]::Escape($reportDirectory))
        $session.LastExportPath | Should -Match '\.json$'
        Should -Invoke Export-EFEndpointReport -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            $PassThru -and $Path -like '*.json' -and $InputObject.PSObject.TypeNames -contains 'EndpointForge.MenuReport'
        }
    }

    It 'applies only after preview and exact acknowledgement, then verifies endpoint state' {
        Mock Test-EFAdministrator -ModuleName EndpointForge { $true }
        $plan = [pscustomobject]@{
            PSTypeName = 'EndpointForge.RemediationPlan'; BaselineName = 'EnterpriseRecommended'; BaselineVersion = '1.0.0';
            AutomaticCount = 1; ManualCount = 0; BlockedCount = 0; PotentialReboot = $false; Summary = 'One change.';
            Steps = @(
                [pscustomobject]@{ Action = 'Automatic'; ControlId = 'AUTO-ONE'; Title = 'First'; CurrentValue = 0; DesiredValue = 1; RequiresElevation = $true; RequiresReboot = $false }
            )
        }
        $preview = [pscustomobject]@{
            PSTypeName = 'EndpointForge.RemediationReport'; ExitCode = 0; Summary = 'One change previewed.';
            CandidateCount = 1; ChangedCount = 0; PreviewCount = 1; FailureCount = 0;
            Results = @([pscustomobject]@{ Outcome = 'WhatIf'; ControlId = 'AUTO-ONE'; Title = 'First' }); NextStep = 'Apply when approved.'
        }
        $applied = [pscustomobject]@{
            PSTypeName = 'EndpointForge.RemediationReport'; ExitCode = 0; Summary = 'One change completed.';
            CandidateCount = 1; ChangedCount = 1; PreviewCount = 0; FailureCount = 0;
            Results = @([pscustomobject]@{ Outcome = 'Changed'; ControlId = 'AUTO-ONE'; Title = 'First' }); NextStep = 'Verify compliance.'
        }
        $summary = [pscustomobject]@{
            PSTypeName = 'EndpointForge.EndpointSummary'; ComputerName = 'MENU-PC'; OverallStatus = 'Healthy';
            CompletedAtUtc = [DateTime]::UtcNow; IssueCount = 0; UnknownCount = 0
        }
        @('5', 'A', 'APPLY', 'Q') | ForEach-Object { $script:EFMenuInputs.Enqueue($_) }
        Mock Read-Host -ModuleName EndpointForge { $script:EFMenuInputs.Dequeue() }
        Mock Get-EFRemediationPlan -ModuleName EndpointForge { $plan }
        Mock Invoke-EFEndpointRemediation -ModuleName EndpointForge { if ($WhatIf) { $preview } else { $applied } }
        Mock Get-EFEndpointSummary -ModuleName EndpointForge { $summary }
        Mock Show-EFEndpointSummary -ModuleName EndpointForge {}

        $session = Show-EFMenu -NoProgress -NoPause -NoColor -PassThru

        [object]::ReferenceEquals($applied, $session.LastRemediation) | Should -BeTrue
        [object]::ReferenceEquals($summary, $session.LastSummary) | Should -BeTrue
        $session.LastPlan | Should -BeNullOrEmpty
        Should -Invoke Invoke-EFEndpointRemediation -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter { $WhatIf }
        Should -Invoke Invoke-EFEndpointRemediation -ModuleName EndpointForge -Times 1 -Exactly -ParameterFilter {
            -not $WhatIf -and $Confirm -eq $false -and @($ControlId).Count -eq 1 -and $ControlId -contains 'AUTO-ONE'
        }
        Should -Invoke Get-EFEndpointSummary -ModuleName EndpointForge -Times 1 -Exactly
    }
}
