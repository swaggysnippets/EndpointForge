BeforeAll {
    $script:CimProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:CimManifestPath = Join-Path $script:CimProjectRoot 'EndpointForge.psd1'
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Import-Module $script:CimManifestPath -Force

    $script:NewCimControl = {
        param(
            [string]$Namespace = 'root\cimv2',
            [bool]$DesiredValue = $true,
            [string]$Id = 'CIM-NAMESPACE'
        )
        [pscustomobject]@{
            Id               = $Id
            Title            = 'Windows management information is available'
            Description      = 'Checks one exact local Windows management information area.'
            WhyItMatters     = 'Management tools can depend on this information area.'
            HowChecked       = 'Checks one exact local namespace without returning provider data.'
            WhatWouldChange  = 'Nothing. This check does not change provider data.'
            ManualAction     = 'Review the related Windows component or management agent.'
            SafetyNotes      = 'Access failures are not treated as a missing namespace.'
            RecoveryGuidance = 'EndpointForge makes no change, so there is nothing to undo.'
            Type             = 'CimNamespaceExists'
            Severity         = 'Medium'
            Namespace        = $Namespace
            TimeoutSeconds   = 10
            DesiredValue     = $DesiredValue
            Remediable       = $false
            RequiresReboot   = $false
        }
    }
    $script:NewCimBaseline = {
        param([Parameter(Mandatory)][object[]]$Controls)
        [pscustomobject]@{
            Name        = 'Cim.Namespace.Test'
            Version     = '1.0.0'
            Description = 'CIM namespace test checklist.'
            Controls    = @($Controls)
        }
    }
    $script:CopyCimValue = {
        param([Parameter(Mandatory)][object]$Value)
        $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    }
}

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'CimNamespaceExists checklist validation' {
    It 'accepts exact local root namespace paths and bounded timeouts' {
        foreach ($namespace in @('root', 'ROOT\cimv2', 'root\Microsoft\Windows\Defender')) {
            $control = & $script:NewCimControl -Namespace $namespace
            $validation = Test-EFBaseline -InputObject (& $script:NewCimBaseline @($control)) -PassThru

            $validation.IsValid | Should -BeTrue -Because "'$namespace' is an exact local namespace path"
        }

        $minimumTimeout = & $script:NewCimControl
        $minimumTimeout.TimeoutSeconds = 1
        (Test-EFBaseline -InputObject (& $script:NewCimBaseline @($minimumTimeout)) -PassThru).IsValid |
            Should -BeTrue
    }

    It 'rejects remote, ambiguous, malformed, and unbounded namespace paths' {
        $tooDeep = 'root\' + ((1..16 | ForEach-Object { "Segment$_" }) -join '\')
        $tooLongSegment = 'root\' + ('A' * 129)
        $invalidPaths = @(
            '\\server\root\cimv2', 'root/cimv2', 'root:cimv2', 'root\', 'root\\cimv2',
            'root\.\cimv2', 'root\..\cimv2', 'root\with space', 'root\*', 'root\1invalid',
            'root\bad-name', $tooDeep, $tooLongSegment
        )

        foreach ($namespace in $invalidPaths) {
            $control = & $script:NewCimControl
            $control.Namespace = $namespace
            $validation = Test-EFBaseline -InputObject (& $script:NewCimBaseline @($control)) -PassThru

            $validation.IsValid | Should -BeFalse -Because "'$namespace' must not become a local CIM target"
            $validation.Errors[0] | Should -Match 'Namespace'
        }
    }

    It 'rejects non-string namespaces, invalid timeouts, remediation, restart, and non-Boolean answers' {
        $invalidControls = [Collections.Generic.List[object]]::new()

        $nonString = & $script:NewCimControl
        $nonString.Namespace = 7
        $invalidControls.Add($nonString)

        foreach ($timeout in @(0, 31, 1.5, '10')) {
            $control = & $script:NewCimControl
            $control.TimeoutSeconds = $timeout
            $invalidControls.Add($control)
        }

        $remediable = & $script:NewCimControl
        $remediable.Remediable = $true
        $invalidControls.Add($remediable)

        $restart = & $script:NewCimControl
        $restart.RequiresReboot = $true
        $invalidControls.Add($restart)

        $nonBoolean = & $script:NewCimControl
        $nonBoolean.DesiredValue = 'true'
        $invalidControls.Add($nonBoolean)

        foreach ($control in $invalidControls) {
            (Test-EFBaseline -InputObject (& $script:NewCimBaseline @($control)) -PassThru).IsValid |
                Should -BeFalse
        }
    }

    It 'rejects executable-looking and all other unsupported checklist properties' {
        foreach ($propertyName in @(
            'Command', 'Executable', 'Arguments', 'ScriptBlock', 'Query', 'Wql',
            'ComputerName', 'CimSession', 'Credential'
        )) {
            $control = & $script:NewCimControl -Id "CIM-UNSUPPORTED-$propertyName"
            $control | Add-Member -NotePropertyName $propertyName -NotePropertyValue 'untrusted text'

            $validation = Test-EFBaseline -InputObject (& $script:NewCimBaseline @($control)) -PassThru
            $validation.IsValid | Should -BeFalse
            $validation.Errors[0] | Should -Match 'unsupported checklist properties'
        }
    }

    It 'rejects valid properties that belong to a different checklist item type' {
        foreach ($propertyName in @('HostName', 'Uri', 'Path', 'Text')) {
            $control = & $script:NewCimControl -Id "CIM-UNRELATED-$propertyName"
            $control | Add-Member -NotePropertyName $propertyName -NotePropertyValue 'example.invalid'

            $validation = Test-EFBaseline -InputObject (& $script:NewCimBaseline @($control)) -PassThru
            $validation.IsValid | Should -BeFalse
            $validation.Errors[0] | Should -Match 'does not accept properties for another checklist item type'
        }
    }

    It 'rejects unsupported properties at the checklist document level' {
        $baseline = & $script:NewCimBaseline @((& $script:NewCimControl))
        $baseline | Add-Member -NotePropertyName Command -NotePropertyValue 'untrusted text'

        $validation = Test-EFBaseline -InputObject $baseline -PassThru
        $validation.IsValid | Should -BeFalse
        $validation.Errors[0] | Should -Match 'unsupported checklist properties'
    }

    It 'limits one checklist to 32 namespace checks' {
        $controls = @(
            for ($index = 1; $index -le 33; $index++) {
                & $script:NewCimControl -Id "CIM-NAMESPACE-$index"
            }
        )

        $validation = Test-EFBaseline -InputObject (& $script:NewCimBaseline $controls) -PassThru
        $validation.IsValid | Should -BeFalse
        $validation.Errors[0] | Should -Match '32 CimNamespaceExists'
    }

    It 'publishes the same 32-item limit in the packaged JSON schema' {
        $schemaPath = Join-Path $script:CimProjectRoot 'Data\Baseline.schema.json'
        $controlsSchema = (Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json).properties.Controls

        $controlsSchema.contains.properties.Type.const | Should -Be 'CimNamespaceExists'
        $controlsSchema.minContains | Should -Be 0
        $controlsSchema.maxContains | Should -Be 32
        $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        $schema.additionalProperties | Should -BeFalse
        $schema.'$defs'.control.additionalProperties | Should -BeFalse
    }
}

Describe 'CimNamespaceExists evaluation behavior' {
    It 'appears in the 26-item menu catalog with a practical question' {
        InModuleScope EndpointForge {
            $catalog = @(Get-EFChecklistTypeCatalog)
            $catalog.Count | Should -Be 26
            $item = $catalog | Where-Object Type -eq 'CimNamespaceExists'
            $item.Question | Should -Be 'Does this Windows management information area exist?'
            $item.Activity | Should -Match 'local Windows management information area'
        }
    }

    It 'maps present, missing, and expected-absent results without returning provider data' {
        $control = & $script:NewCimControl
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            $script:CimNamespaceMode = 'Present'
            Mock Test-EFCimNamespace {
                [pscustomobject]@{
                    ProviderAvailable = $true
                    Exists = $script:CimNamespaceMode -eq 'Present'
                    IsEvaluationError = $false
                    FailureReason = if ($script:CimNamespaceMode -eq 'Present') { 'None' } else { 'NotFound' }
                    PrivateProviderData = 'PRIVATE-WMI-VALUE'
                }
            }

            $context = @{ Cache = @{}; AllowNetworkChecks = $false }
            $present = Get-EFControlState -Control $Control -EvaluationContext $context
            $present.Status | Should -Be 'Compliant'
            $present.ActualValue | Should -BeTrue
            (ConvertTo-Json $present -Depth 10) | Should -Not -Match 'PRIVATE-WMI-VALUE'

            $script:CimNamespaceMode = 'Missing'
            $missing = Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }
            $missing.Status | Should -Be 'NonCompliant'
            $missing.ActualValue | Should -BeFalse

            $Control.DesiredValue = $false
            (Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }).Status |
                Should -Be 'Compliant'
        }
    }

    It 'keeps permission, provider, timeout, and untrustworthy evidence as errors' {
        $control = & $script:NewCimControl
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            $script:CimFailureReason = 'PermissionDenied'
            Mock Test-EFCimNamespace {
                [pscustomobject]@{
                    ProviderAvailable = $script:CimFailureReason -ne 'ProviderUnavailable'
                    Exists = $false
                    IsEvaluationError = $true
                    FailureReason = $script:CimFailureReason
                    PrivateError = 'PRIVATE-WMI-ERROR'
                }
            }

            foreach ($reason in @('PermissionDenied', 'ProviderError', 'TimedOut', 'UnexpectedResult', 'ProviderUnavailable')) {
                $script:CimFailureReason = $reason
                $result = Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }
                $result.Status | Should -Be 'Error' -Because $reason
                $result.ActualValue | Should -BeNullOrEmpty
                (ConvertTo-Json $result -Depth 10) | Should -Not -Match 'PRIVATE-WMI-ERROR'
            }
        }
    }

    It 'caches one local query per namespace during an assessment' {
        $control = & $script:NewCimControl
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            Mock Test-EFCimNamespace {
                [pscustomobject]@{
                    ProviderAvailable = $true; Exists = $true; IsEvaluationError = $false; FailureReason = 'None'
                }
            }

            $context = @{ Cache = @{}; AllowNetworkChecks = $false }
            (Get-EFControlState -Control $Control -EvaluationContext $context).Status | Should -Be 'Compliant'
            (Get-EFControlState -Control $Control -EvaluationContext $context).Status | Should -Be 'Compliant'
            Should -Invoke Test-EFCimNamespace -Times 1 -Exactly
        }
    }

    It 'does not reuse cached evidence across different timeout settings' {
        $quickControl = & $script:NewCimControl -Id 'CIM-QUICK'
        $quickControl.TimeoutSeconds = 1
        $patientControl = & $script:NewCimControl -Id 'CIM-PATIENT'
        $patientControl.TimeoutSeconds = 30
        InModuleScope EndpointForge -Parameters @{ Quick = $quickControl; Patient = $patientControl } {
            Mock Test-EFCimNamespace {
                [pscustomobject]@{
                    ProviderAvailable = $true; Exists = $true; IsEvaluationError = $false; FailureReason = 'None'
                }
            }

            $context = @{ Cache = @{}; AllowNetworkChecks = $false }
            (Get-EFControlState -Control $Quick -EvaluationContext $context).Status | Should -Be 'Compliant'
            (Get-EFControlState -Control $Patient -EvaluationContext $context).Status | Should -Be 'Compliant'
            Should -Invoke Test-EFCimNamespace -Times 2 -Exactly
        }
    }

    It 'runs without network approval and is not classified as network-active' {
        $control = & $script:NewCimControl
        $baseline = & $script:NewCimBaseline @($control)
        InModuleScope EndpointForge -Parameters @{ Baseline = $baseline; Control = $control } {
            Mock Test-EFWindows { $true }
            Mock Test-EFCimNamespace {
                [pscustomobject]@{
                    ProviderAvailable = $true; Exists = $true; IsEvaluationError = $false; FailureReason = 'None'
                }
            }

            (Test-EFControlUsesNetwork -Control $Control) | Should -BeFalse
            $report = Get-EFComplianceReport -Baseline $Baseline -NoProgress
            $report.IsCompliant | Should -BeTrue
            $report.NetworkCheckCount | Should -Be 0
            Should -Invoke Test-EFCimNamespace -Times 1 -Exactly
        }
    }
}

Describe 'CimNamespaceExists isolated provider check' {
    It 'finds the standard local root\cimv2 namespace' {
        InModuleScope EndpointForge {
            $probe = Test-EFCimNamespace -Namespace 'root\cimv2' -TimeoutSeconds 10

            $probe.ProviderAvailable | Should -BeTrue
            $probe.Exists | Should -BeTrue
            $probe.IsEvaluationError | Should -BeFalse
            $probe.FailureReason | Should -Be 'None'
        }
    }

    It 'returns a known missing answer for a namespace that does not exist' {
        InModuleScope EndpointForge {
            $probe = Test-EFCimNamespace `
                -Namespace 'root\EndpointForgeNamespaceThatDoesNotExist987654321' -TimeoutSeconds 10

            $probe.ProviderAvailable | Should -BeTrue
            $probe.Exists | Should -BeFalse
            $probe.IsEvaluationError | Should -BeFalse
            $probe.FailureReason | Should -Be 'NotFound'
        }
    }

    It 'maps isolated worker timeouts and malformed evidence to fixed failure categories' {
        InModuleScope EndpointForge {
            Mock Invoke-EFIsolatedCheck { throw [TimeoutException]::new('PRIVATE-TIMEOUT-DETAIL') }
            $timedOut = Test-EFCimNamespace -Namespace 'root\cimv2' -TimeoutSeconds 1
            $timedOut.IsEvaluationError | Should -BeTrue
            $timedOut.FailureReason | Should -Be 'TimedOut'

            Mock Invoke-EFIsolatedCheck { [pscustomobject]@{ PrivateValue = 'PRIVATE-WMI-DATA' } }
            $unexpected = Test-EFCimNamespace -Namespace 'root\cimv2' -TimeoutSeconds 1
            $unexpected.IsEvaluationError | Should -BeTrue
            $unexpected.FailureReason | Should -Be 'UnexpectedResult'
            (ConvertTo-Json $unexpected) | Should -Not -Match 'PRIVATE-WMI-DATA'

            Mock Invoke-EFIsolatedCheck {
                [pscustomobject]@{
                    ProviderAvailable = $true
                    Exists = $true
                    IsEvaluationError = $false
                    FailureReason = 'PermissionDenied'
                }
            }
            $inconsistent = Test-EFCimNamespace -Namespace 'root\cimv2' -TimeoutSeconds 1
            $inconsistent.Exists | Should -BeFalse
            $inconsistent.IsEvaluationError | Should -BeTrue
            $inconsistent.FailureReason | Should -Be 'UnexpectedResult'
        }
    }

    It 'pins the worker to the CimCmdlets manifest shipped with the active PowerShell engine' {
        InModuleScope EndpointForge {
            $script:CimWorkerText = $null
            Mock Invoke-EFIsolatedCheck {
                $script:CimWorkerText = $ScriptBlock.ToString()
                [pscustomobject]@{
                    ProviderAvailable = $true; Exists = $true; IsEvaluationError = $false; FailureReason = 'None'
                }
            }

            $probe = Test-EFCimNamespace -Namespace 'root\cimv2' -TimeoutSeconds 10
            $probe.Exists | Should -BeTrue
            $script:CimWorkerText | Should -Match "\[IO\.Path\]::Combine"
            $script:CimWorkerText | Should -Match "CimCmdlets\.psd1"
            $script:CimWorkerText | Should -Not -Match 'Get-Module\s+-ListAvailable'
            $script:CimWorkerText | Should -Not -Match 'Import-Module\s+CimCmdlets'
        }
    }
}
