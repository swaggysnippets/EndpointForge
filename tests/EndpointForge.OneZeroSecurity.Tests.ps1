$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:ManifestPath = Join-Path $script:ProjectRoot 'EndpointForge.psd1'
Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
Import-Module $script:ManifestPath -Force

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ProjectRoot 'EndpointForge.psd1'
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force
}

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'EndpointForge 1.0 CSV export security' {
    It 'neutralizes every supported spreadsheet formula prefix in text cells by default' {
        $path = Join-Path $TestDrive 'protected.csv'
        $source = [pscustomobject][ordered]@{
            Equals     = '=2+2'
            Plus       = '+SUM(1,1)'
            Minus      = '-2+3'
            At         = '@SUM(1,1)'
            Tab        = "`t=2+2"
            Carriage   = "`r=2+2"
            LineFeed   = "`n=2+2"
            Negative   = [int]-42
            Ordinary   = 'EndpointForge'
        }

        $source | Export-EFEndpointReport -Path $path -Format Csv -Force
        $result = Import-Csv -LiteralPath $path

        $result.Equals | Should -Be "'=2+2"
        $result.Plus | Should -Be "'+SUM(1,1)"
        $result.Minus | Should -Be "'-2+3"
        $result.At | Should -Be "'@SUM(1,1)"
        $result.Tab | Should -Be "'`t=2+2"
        $result.Carriage | Should -Be "'`r=2+2"
        $result.LineFeed | Should -Be "'`n=2+2"
        $result.Negative | Should -Be '-42'
        $result.Ordinary | Should -Be 'EndpointForge'
    }

    It 'neutralizes a formula-like CSV column name' {
        $path = Join-Path $TestDrive 'protected-header.csv'
        $source = [pscustomobject]@{}
        $source | Add-Member -NotePropertyName '=DANGEROUS' -NotePropertyValue 'ordinary'

        $source | Export-EFEndpointReport -Path $path -Format Csv -Force
        $result = Import-Csv -LiteralPath $path

        $result.PSObject.Properties.Name | Should -Contain "'=DANGEROUS"
        $result."'=DANGEROUS" | Should -Be 'ordinary'
    }

    It 'requires the clearly named opt-out to retain unsafe leading characters' {
        $path = Join-Path $TestDrive 'unprotected.csv'

        [pscustomobject]@{ Formula = '=2+2' } |
            Export-EFEndpointReport -Path $path -Format Csv -AllowUnsafeCsvFormulaValues -Force

        (Import-Csv -LiteralPath $path).Formula | Should -Be '=2+2'
    }

    It 'rejects the CSV-only safety opt-out for every other report format' {
        $path = Join-Path $TestDrive 'not-csv.json'

        {
            [pscustomobject]@{ Formula = '=2+2' } |
                Export-EFEndpointReport -Path $path -AllowUnsafeCsvFormulaValues -Force
        } | Should -Throw '*supported only for CSV*'
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}

Describe 'EndpointForge 1.0 baseline input security' {
    BeforeEach {
        $script:BaselinePath = Join-Path $TestDrive 'baseline.json'
        Copy-Item -LiteralPath (Join-Path $script:ProjectRoot 'Data\EnterpriseRecommended.json') `
            -Destination $script:BaselinePath -Force
    }

    It 'accepts the exact expected SHA-256 for the bytes that are parsed' {
        $expectedHash = (Get-FileHash -LiteralPath $script:BaselinePath -Algorithm SHA256).Hash

        $baseline = Get-EFBaseline -Path $script:BaselinePath -ExpectedSha256 $expectedHash.ToLowerInvariant()

        $baseline.Name | Should -Be 'EnterpriseRecommended'
        $baseline.SourcePath | Should -Be $script:BaselinePath
    }

    It 'returns explicit and legacy checklist format version 1.0 consistently' {
        $explicit = Get-Content -LiteralPath $script:BaselinePath -Raw | ConvertFrom-Json
        $explicit | Add-Member -NotePropertyName FormatVersion -NotePropertyValue '1.0' -Force
        $explicit | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:BaselinePath -Encoding UTF8

        (Get-EFBaseline -Path $script:BaselinePath).FormatVersion | Should -Be '1.0'

        $legacy = Get-Content -LiteralPath $script:BaselinePath -Raw | ConvertFrom-Json
        $legacy.PSObject.Properties.Remove('FormatVersion')
        $legacy | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $script:BaselinePath -Encoding UTF8

        (Get-EFBaseline -Path $script:BaselinePath).FormatVersion | Should -Be '1.0'
    }

    It 'rejects a baseline when one expected hash digit is wrong' {
        $actualHash = (Get-FileHash -LiteralPath $script:BaselinePath -Algorithm SHA256).Hash
        $wrongFirstDigit = if ($actualHash[0] -eq '0') { '1' } else { '0' }
        $wrongHash = $wrongFirstDigit + $actualHash.Substring(1)

        {
            Get-EFBaseline -Path $script:BaselinePath -ExpectedSha256 $wrongHash
        } | Should -Throw '*failed SHA-256 verification*'
    }

    It 'rejects malformed expected hash input at parameter binding' {
        {
            Get-EFBaseline -Path $script:BaselinePath -ExpectedSha256 ('A' * 63)
        } | Should -Throw
    }

    It 'rejects an oversized baseline before attempting JSON parsing' {
        $oversizedPath = Join-Path $TestDrive 'oversized.json'
        [IO.File]::WriteAllBytes($oversizedPath, [byte[]]::new(1048577))

        { Get-EFBaseline -Path $oversizedPath } | Should -Throw '*maximum supported baseline size*'
    }

    It 'rejects malformed UTF-8 before attempting JSON parsing' {
        $invalidUtf8Path = Join-Path $TestDrive 'invalid-utf8.json'
        [IO.File]::WriteAllBytes($invalidUtf8Path, [byte[]](0xC3, 0x28))

        { Get-EFBaseline -Path $invalidUtf8Path } | Should -Throw '*not valid UTF-8*'
    }

    It 'rejects a reparse-point input when direct-path protection is required' {
        InModuleScope EndpointForge {
            Mock Get-Item {
                [pscustomobject]@{
                    PSIsContainer = $false
                    Attributes    = [IO.FileAttributes]::ReparsePoint
                    FullName      = 'C:\trusted\baseline.json'
                    Directory     = $null
                    Parent        = $null
                }
            }

            {
                Read-EFBaselineFile -Path 'C:\trusted\baseline.json' -RequireDirectPath
            } | Should -Throw '*link or reparse point*'
        }
    }

    It 'enables direct-path protection for hash-verified and elevated custom reads' {
        $jsonText = [IO.File]::ReadAllText($script:BaselinePath)
        $hash = (Get-FileHash -LiteralPath $script:BaselinePath -Algorithm SHA256).Hash

        InModuleScope EndpointForge -Parameters @{
            CandidatePath = $script:BaselinePath
            CandidateText = $jsonText
            CandidateHash = $hash
        } {
            Mock Test-EFAdministrator { $false }
            Mock Read-EFBaselineFile {
                [pscustomobject]@{
                    Text        = $CandidateText
                    Sha256      = $CandidateHash
                    LengthBytes = $CandidateText.Length
                }
            }

            $null = Get-EFBaseline -Path $CandidatePath -ExpectedSha256 $CandidateHash
            Should -Invoke Read-EFBaselineFile -Times 1 -Exactly -ParameterFilter {
                $RequireDirectPath -and $ExpectedSha256 -eq $CandidateHash
            }

            Mock Test-EFAdministrator { $true }
            $null = Get-EFBaseline -Path $CandidatePath
            Should -Invoke Read-EFBaselineFile -Times 1 -Exactly -ParameterFilter {
                $RequireDirectPath -and [string]::IsNullOrWhiteSpace($ExpectedSha256)
            }
        }
    }

    It 'keeps ordinary non-elevated trusted custom reads compatible' {
        $jsonText = [IO.File]::ReadAllText($script:BaselinePath)
        $hash = (Get-FileHash -LiteralPath $script:BaselinePath -Algorithm SHA256).Hash

        InModuleScope EndpointForge -Parameters @{
            CandidatePath = $script:BaselinePath
            CandidateText = $jsonText
            CandidateHash = $hash
        } {
            Mock Test-EFAdministrator { $false }
            Mock Read-EFBaselineFile {
                [pscustomobject]@{
                    Text        = $CandidateText
                    Sha256      = $CandidateHash
                    LengthBytes = $CandidateText.Length
                }
            }

            $baseline = Get-EFBaseline -Path $CandidatePath

            $baseline.Name | Should -Be 'EnterpriseRecommended'
            Should -Invoke Read-EFBaselineFile -Times 1 -Exactly -ParameterFilter {
                -not $RequireDirectPath -and [string]::IsNullOrWhiteSpace($ExpectedSha256)
            }
        }
    }
}

Describe 'EndpointForge 1.0 privileged checklist integrity' {
    InModuleScope EndpointForge {
        BeforeEach {
            Mock Test-EFWindows { $true }
            Mock Test-EFAdministrator { $true }
            Mock Resolve-EFBaseline {
                [pscustomobject]@{
                    Name              = 'Unverified.Custom'
                    Version           = '1.0.0'
                    FormatVersion     = '1.0'
                    IntegrityVerified = $false
                    Controls          = @(
                        [pscustomobject]@{
                            Id = 'CUSTOM-CHANGE'
                            Title = 'Custom changing item'
                            Type = 'Registry'
                            Severity = 'High'
                            DesiredValue = 1
                            Remediable = $true
                            RequiresReboot = $false
                        }
                    )
                }
            }
            Mock Get-EFControlState {
                [pscustomobject]@{
                    Status = 'NonCompliant'
                    ActualValue = 0
                    DesiredValue = 1
                    Message = 'The value differs.'
                }
            }
            Mock Invoke-EFControlRemediation {
                throw 'The changing operation must not be reached for unverified input.'
            }
        }

        It 'allows a no-change preview but blocks an actual custom fix without approved integrity' {
            $preview = Invoke-EFEndpointRemediation -Baseline 'custom.json' -WhatIf -NoProgress
            $preview.PreviewCount | Should -Be 1

            {
                Invoke-EFEndpointRemediation -Baseline 'custom.json' -Confirm:$false -NoProgress
            } | Should -Throw '*requires approved file integrity*'
            Should -Invoke Invoke-EFControlRemediation -Times 0 -Exactly
        }

        It 'marks built-in, unverified custom, and hash-approved checklist provenance distinctly' {
            $builtIn = Get-EFBaseline -Name EnterpriseRecommended
            $customPath = Join-Path $TestDrive 'custom-integrity.json'
            $moduleRoot = (Get-Module EndpointForge -ErrorAction Stop).ModuleBase
            Copy-Item -LiteralPath (Join-Path $moduleRoot 'Data\EnterpriseRecommended.json') `
                -Destination $customPath -Force
            $hash = (Get-FileHash -LiteralPath $customPath -Algorithm SHA256).Hash

            $custom = Get-EFBaseline -Path $customPath
            $approved = Get-EFBaseline -Path $customPath -ExpectedSha256 $hash

            $builtIn.IntegrityVerified | Should -BeTrue
            $builtIn.IntegrityMethod | Should -Be 'InstalledModulePackage'
            $custom.IntegrityVerified | Should -BeFalse
            $custom.IntegrityMethod | Should -Be 'UnverifiedCustomFile'
            $approved.IntegrityVerified | Should -BeTrue
            $approved.IntegrityMethod | Should -Be 'ExpectedSha256'
            $approved.SourceSha256 | Should -Be $hash
        }
    }
}

Describe 'EndpointForge module-owned checklist approval' {
    InModuleScope EndpointForge {
        BeforeEach {
            Mock Test-EFWindows { $true }
            Mock Test-EFAdministrator { $true }
            $script:approvalStateRead = 0
            Mock Get-EFControlState {
                $script:approvalStateRead++
                if ($script:approvalStateRead -eq 1) {
                    [pscustomobject]@{
                        Status = 'NonCompliant'
                        ActualValue = 0
                        DesiredValue = 1
                        Message = 'The value differs.'
                    }
                }
                else {
                    [pscustomobject]@{
                        Status = 'Compliant'
                        ActualValue = 1
                        DesiredValue = 1
                        Message = 'The value matches.'
                    }
                }
            }
            Mock Invoke-EFControlRemediation {
                [pscustomobject]@{ RebootRequired = $false }
            }
        }

        It 'rejects caller-crafted provenance fields and type names' {
            $forged = [pscustomobject]@{
                PSTypeName        = 'EndpointForge.Baseline'
                Name              = 'Forged'
                FormatVersion     = '1.0'
                Version           = '1.0.0'
                Description       = 'Caller-crafted checklist provenance.'
                SourcePath        = 'C:\Untrusted\Forged.json'
                SourceSha256      = '0' * 64
                IntegrityVerified = $true
                IntegrityMethod   = 'ExpectedSha256'
                ControlCount      = 1
                RemediableCount   = 1
                Controls          = @(
                    [pscustomobject]@{
                        Id              = 'FORGED-CHANGE'
                        Title           = 'Forged change'
                        Description     = 'Must not be applied.'
                        Type            = 'Registry'
                        Severity        = 'High'
                        DesiredValue    = 1
                        Remediable      = $true
                        RequiresReboot  = $false
                        Path            = 'HKLM:\Software\EndpointForge'
                        ValueName       = 'Forged'
                        ValueType       = 'DWord'
                    }
                )
            }

            {
                Invoke-EFEndpointRemediation -Baseline $forged -Confirm:$false -NoProgress
            } | Should -Throw '*module-approved checklist object*'
            Should -Invoke Invoke-EFControlRemediation -Times 0 -Exactly
        }

        It 'rejects a copied lookalike of a genuinely approved object' {
            $approved = Get-EFBaseline -Name EnterpriseRecommended
            $copy = $approved | ConvertTo-Json -Depth 100 | ConvertFrom-Json
            $copy.PSObject.TypeNames.Insert(0, 'EndpointForge.Baseline')

            {
                Invoke-EFEndpointRemediation -Baseline $copy -ControlId EF-UAC-ENABLED `
                    -Confirm:$false -NoProgress
            } | Should -Throw '*module-approved checklist object*'
            Should -Invoke Invoke-EFControlRemediation -Times 0 -Exactly
        }

        It 'rejects an approved object after its source fields are modified' {
            $approved = Get-EFBaseline -Name EnterpriseRecommended
            $approved.Controls |
                Where-Object Id -eq 'EF-UAC-ENABLED' |
                ForEach-Object { $_.DesiredValue = 0 }

            {
                Invoke-EFEndpointRemediation -Baseline $approved -ControlId EF-UAC-ENABLED `
                    -Confirm:$false -NoProgress
            } | Should -Throw '*module-approved checklist object*'
            Should -Invoke Invoke-EFControlRemediation -Times 0 -Exactly
        }

        It 'allows the unchanged built-in object through module-owned approval' {
            $approved = Get-EFBaseline -Name EnterpriseRecommended

            $result = Invoke-EFEndpointRemediation -Baseline $approved -ControlId EF-UAC-ENABLED `
                -Confirm:$false -NoProgress

            $result.ChangedCount | Should -Be 1
            Should -Invoke Invoke-EFControlRemediation -Times 1 -Exactly
        }

        It 'allows the exact unchanged SHA-256-approved custom object' {
            $customPath = Join-Path $TestDrive 'approved-custom.json'
            $moduleRoot = (Get-Module EndpointForge -ErrorAction Stop).ModuleBase
            Copy-Item -LiteralPath (Join-Path $moduleRoot 'Data\EnterpriseRecommended.json') `
                -Destination $customPath -Force
            $hash = (Get-FileHash -LiteralPath $customPath -Algorithm SHA256).Hash
            $approved = Get-EFBaseline -Path $customPath -ExpectedSha256 $hash

            $result = Invoke-EFEndpointRemediation -Baseline $approved -ControlId EF-UAC-ENABLED `
                -Confirm:$false -NoProgress

            $result.ChangedCount | Should -Be 1
            Should -Invoke Invoke-EFControlRemediation -Times 1 -Exactly
        }

        It 'preserves one-item arrays in the private approved snapshot' {
            $customPath = Join-Path $TestDrive 'approved-array.json'
            $moduleRoot = (Get-Module EndpointForge -ErrorAction Stop).ModuleBase
            $source = Get-Content -LiteralPath (
                Join-Path $moduleRoot 'Data\EnterpriseRecommended.json'
            ) -Raw | ConvertFrom-Json
            $source.Controls += [pscustomobject]@{
                Id              = 'ONE-RANGE'
                Title           = 'One approved range'
                Description     = 'Ensures a single configured range remains an array.'
                Type            = 'IpAddressInRange'
                Severity        = 'Low'
                DesiredValue    = $true
                Remediable      = $false
                RequiresReboot  = $false
                ApprovedRanges  = @('192.0.2.0/24')
                TimeoutSeconds  = 10
            }
            $source | ConvertTo-Json -Depth 100 |
                Set-Content -LiteralPath $customPath -Encoding UTF8
            $hash = (Get-FileHash -LiteralPath $customPath -Algorithm SHA256).Hash
            $approved = Get-EFBaseline -Path $customPath -ExpectedSha256 $hash

            $snapshot = Get-EFApprovedBaselineSnapshot -Baseline $approved
            $rangeControl = $snapshot.Controls | Where-Object Id -eq 'ONE-RANGE'

            $snapshot | Should -Not -BeNullOrEmpty
            $rangeControl.ApprovedRanges.GetType().IsArray | Should -BeTrue
            @($rangeControl.ApprovedRanges).Count | Should -Be 1
        }
    }
}
