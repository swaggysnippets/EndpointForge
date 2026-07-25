BeforeAll {
    $script:IpRangeProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:IpRangeManifestPath = Join-Path $script:IpRangeProjectRoot 'EndpointForge.psd1'
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Import-Module $script:IpRangeManifestPath -Force

    $script:NewIpRangeControl = {
        param(
            [object[]]$ApprovedRanges = @('10.20.0.0/16'),
            [bool]$DesiredValue = $true,
            [string]$Id = 'IP-RANGE'
        )
        [pscustomobject]@{
            Id               = $Id
            Title            = 'The computer is on an approved IP range'
            Description      = 'Checks active local addresses without making a network connection.'
            WhyItMatters     = 'Expected network placement can be required for organizational services.'
            HowChecked       = 'Checks local address membership without returning addresses.'
            WhatWouldChange  = 'Nothing. This item is report-only.'
            ManualAction     = 'Review the connection, VPN, DHCP, and routing configuration.'
            SafetyNotes      = 'A range match alone does not prove connectivity or trust.'
            RecoveryGuidance = 'EndpointForge makes no change, so there is nothing to undo.'
            Type             = 'IpAddressInRange'
            Severity         = 'Medium'
            ApprovedRanges   = @($ApprovedRanges)
            TimeoutSeconds   = 10
            DesiredValue     = $DesiredValue
            Remediable       = $false
            RequiresReboot   = $false
        }
    }
    $script:NewIpRangeBaseline = {
        param([Parameter(Mandatory)][object[]]$Controls)
        [pscustomobject]@{
            Name        = 'Ip.Range.Test'
            Version     = '1.0.0'
            Description = 'IP range test checklist.'
            Controls    = @($Controls)
        }
    }
}

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'IpAddressInRange CIDR parsing and matching' {
    It 'accepts canonical IPv4 and IPv6 networks including exact-address prefixes' {
        InModuleScope EndpointForge {
            foreach ($cidr in @(
                '10.0.0.0/8', '10.0.0.128/25', '255.255.255.255/32',
                '2001:db8::/32', '2001:db8:abcd::/64', '2001:db8::1/128'
            )) {
                $network = ConvertTo-EFIpNetwork -Cidr $cidr
                $network.CanonicalKey | Should -Not -BeNullOrEmpty
            }
        }
    }

    It 'rejects match-all, host-bit, shorthand, legacy, scoped, mapped, and malformed ranges' {
        InModuleScope EndpointForge {
            $invalidRanges = @(
                '0.0.0.0/0', '::/0', '10.0.0.1/24', '2001:db8::1/64',
                '010.0.0.0/8', '1.1.1.010/24', '10.1/16', '0x0A.0.0.0/8',
                '256.0.0.0/8', '10.0.0.0/33', '2001:db8::/129',
                'fe80::%12/64', '::ffff:192.0.2.0/120', '[2001:db8::]/32',
                ' 10.0.0.0/8', 'server.example/24', '10.0.*.0/24',
                '10.0.0.0/255.255.255.0', '10.0.0.1-10.0.0.9',
                "10.0.`e0.0/8"
            )
            foreach ($cidr in $invalidRanges) {
                { ConvertTo-EFIpNetwork -Cidr $cidr } | Should -Throw
            }
        }
    }

    It 'matches IPv4 boundaries in network byte order' {
        InModuleScope EndpointForge {
            $network = ConvertTo-EFIpNetwork -Cidr '10.0.0.128/25'
            (Test-EFIpAddressInNetwork -Address ([Net.IPAddress]::Parse('10.0.0.128')) -Network $network) |
                Should -BeTrue
            (Test-EFIpAddressInNetwork -Address ([Net.IPAddress]::Parse('10.0.0.255')) -Network $network) |
                Should -BeTrue
            (Test-EFIpAddressInNetwork -Address ([Net.IPAddress]::Parse('10.0.0.127')) -Network $network) |
                Should -BeFalse
            (Test-EFIpAddressInNetwork -Address ([Net.IPAddress]::Parse('10.0.1.0')) -Network $network) |
                Should -BeFalse
        }
    }

    It 'matches IPv6 compressed boundaries and keeps address families separate' {
        InModuleScope EndpointForge {
            $network = ConvertTo-EFIpNetwork -Cidr '2001:db8:abcd::/64'
            (Test-EFIpAddressInNetwork -Address ([Net.IPAddress]::Parse('2001:db8:abcd::')) -Network $network) |
                Should -BeTrue
            (Test-EFIpAddressInNetwork -Address ([Net.IPAddress]::Parse('2001:db8:abcd:0:ffff:ffff:ffff:ffff')) -Network $network) |
                Should -BeTrue
            (Test-EFIpAddressInNetwork -Address ([Net.IPAddress]::Parse('2001:db8:abce::')) -Network $network) |
                Should -BeFalse
            (Test-EFIpAddressInNetwork -Address ([Net.IPAddress]::Parse('10.0.0.1')) -Network $network) |
                Should -BeFalse
        }
    }
}

Describe 'IpAddressInRange checklist validation' {
    It 'accepts a one-range JSON array' {
        $control = & $script:NewIpRangeControl -ApprovedRanges @('10.20.0.0/16')
        (Test-EFBaseline -InputObject (& $script:NewIpRangeBaseline @($control)) -PassThru).IsValid |
            Should -BeTrue
    }

    It 'accepts multiple unique ranges and an optional exact connection name' {
        $control = & $script:NewIpRangeControl -ApprovedRanges @(
            '0.0.0.0/32', '104.0.0.0/32', '10.20.0.0/16',
            '192.0.2.0/24', '2001:db8::/32'
        )
        $control | Add-Member -NotePropertyName InterfaceName -NotePropertyValue 'Contoso VPN'

        (Test-EFBaseline -InputObject (& $script:NewIpRangeBaseline @($control)) -PassThru).IsValid |
            Should -BeTrue
    }

    It 'requires ApprovedRanges to be a JSON array with strict unique CIDRs' {
        $invalidValues = [Collections.Generic.List[object]]::new()
        $invalidValues.Add('10.20.0.0/16')
        $invalidValues.Add([object[]]@())
        $invalidValues.Add([object[]]@('10.20.0.0/16', '10.20.0.0/16'))
        $invalidValues.Add([object[]]@('2001:db8::/32', '2001:0db8::/32'))
        $invalidValues.Add([object[]]@(1))
        $invalidValues.Add([object[]]@(1..33 | ForEach-Object { "10.$_.0.0/16" }))
        foreach ($value in $invalidValues) {
            $control = & $script:NewIpRangeControl
            $control.ApprovedRanges = $value
            (Test-EFBaseline -InputObject (& $script:NewIpRangeBaseline @($control)) -PassThru).IsValid |
                Should -BeFalse
        }
    }

    It 'rejects terminal control characters without copying them into validation errors' {
        $escapeCharacter = [string][char]0x1B
        $control = & $script:NewIpRangeControl -ApprovedRanges @("10.0.${escapeCharacter}0.0/8")
        $validation = Test-EFBaseline -InputObject (
            & $script:NewIpRangeBaseline @($control)
        ) -PassThru

        $validation.IsValid | Should -BeFalse
        ($validation.Errors -join [string]::Empty).Contains($escapeCharacter) | Should -BeFalse
    }

    It 'keeps terminal control characters out of common-field and property-name errors' {
        $escapeCharacter = [string][char]0x1B
        $mutators = @(
            { param($candidate, $escape) $candidate.Name = "Bad${escape}Name" },
            { param($candidate, $escape) $candidate.Version = "1.0.${escape}0" },
            { param($candidate, $escape) $candidate.Description = "Bad${escape}Description" },
            { param($candidate, $escape) $candidate.Controls[0].Id = "Bad${escape}Id" },
            { param($candidate, $escape) $candidate.Controls[0].Title = "Bad${escape}Title" },
            { param($candidate, $escape) $candidate.Controls[0].Type = "Bad${escape}Type" },
            { param($candidate, $escape) $candidate.Controls[0].Severity = "Bad${escape}Severity" },
            {
                param($candidate, $escape)
                $candidate | Add-Member -NotePropertyName "Bad${escape}Property" -NotePropertyValue $true
            },
            {
                param($candidate, $escape)
                $candidate.Controls[0] | Add-Member -NotePropertyName "Bad${escape}Property" `
                    -NotePropertyValue $true
            },
            {
                param($candidate, $escape)
                $candidate.Controls[0] | Add-Member -NotePropertyName ValueType `
                    -NotePropertyValue "Bad${escape}ValueType"
            }
        )

        foreach ($mutator in $mutators) {
            $candidate = & $script:NewIpRangeBaseline @(& $script:NewIpRangeControl)
            & $mutator $candidate $escapeCharacter
            $validation = Test-EFBaseline -InputObject $candidate -PassThru
            $validation.IsValid | Should -BeFalse
            ($validation.Errors -join [string]::Empty).Contains($escapeCharacter) |
                Should -BeFalse
        }
    }

    It 'rejects unsafe connection names, timeout values, remediation, and unrelated fields' {
        $invalidControls = [Collections.Generic.List[object]]::new()
        foreach ($interfaceName in @('', ' Ethernet', 'Ethernet ', 'Ether*', "Bad`nName", ('A' * 257))) {
            $control = & $script:NewIpRangeControl
            $control | Add-Member -NotePropertyName InterfaceName -NotePropertyValue $interfaceName
            $invalidControls.Add($control)
        }
        foreach ($timeout in @(0, 31, 1.5, '10')) {
            $control = & $script:NewIpRangeControl
            $control.TimeoutSeconds = $timeout
            $invalidControls.Add($control)
        }
        $remediable = & $script:NewIpRangeControl
        $remediable.Remediable = $true
        $invalidControls.Add($remediable)
        $unrelated = & $script:NewIpRangeControl
        $unrelated | Add-Member -NotePropertyName HostName -NotePropertyValue 'remote.example'
        $invalidControls.Add($unrelated)

        foreach ($control in $invalidControls) {
            (Test-EFBaseline -InputObject (& $script:NewIpRangeBaseline @($control)) -PassThru).IsValid |
                Should -BeFalse
        }
    }

    It 'limits one checklist to 16 IP range items' {
        $controls = @(
            for ($index = 1; $index -le 17; $index++) {
                & $script:NewIpRangeControl -Id "IP-RANGE-$index"
            }
        )
        $validation = Test-EFBaseline -InputObject (& $script:NewIpRangeBaseline $controls) -PassThru
        $validation.IsValid | Should -BeFalse
        $validation.Errors[0] | Should -Match '16 IpAddressInRange'
    }

    It 'publishes the same shape and limits in the packaged schema' {
        $schemaPath = Join-Path $script:IpRangeProjectRoot 'Data\Baseline.schema.json'
        $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        $ipLimit = @($schema.properties.Controls.allOf)[0]
        $ipLimit.contains.properties.Type.const | Should -Be 'IpAddressInRange'
        $ipLimit.maxContains | Should -Be 16

        $ipRule = @($schema.'$defs'.control.allOf | Where-Object {
            $_.if.properties.Type.const -eq 'IpAddressInRange'
        })[0]
        $ipRule.then.required | Should -Contain 'ApprovedRanges'
        $ipRule.then.properties.ApprovedRanges.maxItems | Should -Be 32
        $rangePattern = [regex]$ipRule.then.properties.ApprovedRanges.items.pattern
        $rangePattern.IsMatch('10.20.0.0/16') | Should -BeTrue
        $rangePattern.IsMatch("10.0.$([char]0x1B)0.0/8") | Should -BeFalse
        $ipRule.then.propertyNames.enum | Should -Contain 'InterfaceName'
        $interfacePattern = [regex]$ipRule.then.properties.InterfaceName.pattern
        $interfacePattern.IsMatch('Contoso VPN') | Should -BeTrue
        $interfacePattern.IsMatch([string][char]0x07) | Should -BeFalse
        $interfacePattern.IsMatch([string][char]0x7F) | Should -BeFalse
    }
}

Describe 'IpAddressInRange evaluation behavior' {
    It 'appears in the 26-item menu catalog using a practical question' {
        InModuleScope EndpointForge {
            $catalog = @(Get-EFChecklistTypeCatalog)
            $catalog.Count | Should -Be 26
            $item = $catalog | Where-Object Type -eq 'IpAddressInRange'
            $item.Question | Should -Be 'Is this computer on an approved IP range?'
            $item.Activity | Should -Match 'does not contact a service'
        }
    }

    It 'maps matching, nonmatching, and expected-absent evidence to Boolean results only' {
        $control = & $script:NewIpRangeControl
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            $script:IpRangeMatches = $true
            Mock Test-EFIpRange {
                [pscustomobject]@{
                    ProviderAvailable = $true
                    Matches = $script:IpRangeMatches
                    IsEvaluationError = $false
                    FailureReason = 'None'
                    DetectedAddress = '198.51.100.77'
                }
            }

            $present = Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{} }
            $present.Status | Should -Be 'Compliant'
            $present.ActualValue | Should -BeTrue
            (ConvertTo-Json $present -Depth 10) | Should -Not -Match '198\.51\.100\.77|10\.20\.0\.0/16'

            $script:IpRangeMatches = $false
            $missing = Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{} }
            $missing.Status | Should -Be 'NonCompliant'
            $missing.ActualValue | Should -BeFalse

            $Control.DesiredValue = $false
            (Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{} }).Status |
                Should -Be 'Compliant'
        }
    }

    It 'keeps missing or unavailable named connections and provider failures as errors' {
        $control = & $script:NewIpRangeControl
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            $script:IpRangeFailure = 'InterfaceNotFound'
            Mock Test-EFIpRange {
                [pscustomobject]@{
                    ProviderAvailable = $script:IpRangeFailure -ne 'ProviderUnavailable'
                    Matches = $false
                    IsEvaluationError = $true
                    FailureReason = $script:IpRangeFailure
                }
            }

            foreach ($reason in @(
                'InterfaceNotFound', 'InterfaceUnavailable', 'AmbiguousInterface',
                'ProviderError', 'SafetyLimitExceeded', 'TimedOut', 'ProviderUnavailable'
            )) {
                $script:IpRangeFailure = $reason
                $result = Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{} }
                $result.Status | Should -Be 'Error' -Because $reason
                $result.ActualValue | Should -BeNullOrEmpty
            }
        }
    }

    It 'caches order-independent range evidence without cache-key delimiter collisions' {
        $first = & $script:NewIpRangeControl -ApprovedRanges @(
            '0.0.0.0/32', '104.0.0.0/32', '10.20.0.0/16', '2001:db8::/32'
        ) -Id 'IP-FIRST'
        $first | Add-Member -NotePropertyName InterfaceName -NotePropertyValue 'VPN|Primary,Blue'
        $second = & $script:NewIpRangeControl -ApprovedRanges @(
            '2001:db8::/32', '10.20.0.0/16', '104.0.0.0/32', '0.0.0.0/32'
        ) -Id 'IP-SECOND'
        $second | Add-Member -NotePropertyName InterfaceName -NotePropertyValue 'VPN|Primary,Blue'
        InModuleScope EndpointForge -Parameters @{ First = $first; Second = $second } {
            Mock Test-EFIpRange {
                [pscustomobject]@{
                    ProviderAvailable = $true; Matches = $true; IsEvaluationError = $false; FailureReason = 'None'
                }
            }

            $context = @{ Cache = @{} }
            (Get-EFControlState -Control $First -EvaluationContext $context).Status | Should -Be 'Compliant'
            (Get-EFControlState -Control $Second -EvaluationContext $context).Status | Should -Be 'Compliant'
            Should -Invoke Test-EFIpRange -Times 1 -Exactly
        }
    }

    It 'is local-only and runs without network approval' {
        $control = & $script:NewIpRangeControl
        $baseline = & $script:NewIpRangeBaseline @($control)
        InModuleScope EndpointForge -Parameters @{ Baseline = $baseline; Control = $control } {
            Mock Test-EFWindows { $true }
            Mock Test-EFIpRange {
                [pscustomobject]@{
                    ProviderAvailable = $true; Matches = $true; IsEvaluationError = $false; FailureReason = 'None'
                }
            }

            (Test-EFControlUsesNetwork -Control $Control) | Should -BeFalse
            $report = Get-EFComplianceReport -Baseline $Baseline -NoProgress
            $report.IsCompliant | Should -BeTrue
            $report.NetworkCheckCount | Should -Be 0
            Should -Invoke Test-EFIpRange -Times 1 -Exactly
        }
    }
}

Describe 'IpAddressInRange isolated worker boundary' {
    It 'sanitizes private worker fields and rejects incoherent evidence' {
        InModuleScope EndpointForge {
            Mock Invoke-EFIsolatedCheck {
                [pscustomobject]@{
                    ProviderAvailable = $true
                    Matches = $true
                    IsEvaluationError = $false
                    FailureReason = 'None'
                    PrivateAddress = '203.0.113.91'
                }
            }
            $valid = Test-EFIpRange -ApprovedRanges @('10.20.0.0/16')
            $valid.Matches | Should -BeTrue
            (ConvertTo-Json $valid) | Should -Not -Match '203\.0\.113\.91'

            Mock Invoke-EFIsolatedCheck {
                [pscustomobject]@{
                    ProviderAvailable = $true
                    Matches = $true
                    IsEvaluationError = $true
                    FailureReason = 'ProviderError'
                }
            }
            $inconsistent = Test-EFIpRange -ApprovedRanges @('10.20.0.0/16')
            $inconsistent.Matches | Should -BeFalse
            $inconsistent.IsEvaluationError | Should -BeTrue
            $inconsistent.FailureReason | Should -Be 'UnexpectedResult'
        }
    }

    It 'maps hard worker timeouts to a fixed unavailable result' {
        InModuleScope EndpointForge {
            Mock Invoke-EFIsolatedCheck { throw [TimeoutException]::new('PRIVATE-TIMEOUT') }
            $result = Test-EFIpRange -ApprovedRanges @('10.20.0.0/16') -TimeoutSeconds 1
            $result.Matches | Should -BeFalse
            $result.IsEvaluationError | Should -BeTrue
            $result.FailureReason | Should -Be 'TimedOut'
            (ConvertTo-Json $result) | Should -Not -Match 'PRIVATE-TIMEOUT'
        }
    }
}
