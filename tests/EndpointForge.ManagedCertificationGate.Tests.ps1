BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:CertificationGate = Join-Path $script:ProjectRoot 'build\Test-ManagedCertificationEvidence.ps1'

    function Initialize-EFManagedCertificationEvidenceSet {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [string]$Version = '1.0.0'
        )

        $null = New-Item -ItemType Directory -Path $Path -Force
        foreach ($ring in @('Unmanaged', 'Intune', 'ConfigurationManager', 'CoManaged')) {
            foreach ($edition in @('Desktop', 'Core')) {
                foreach ($identity in @('StandardUser', 'Administrator', 'SYSTEM')) {
                    $expectIntune = $ring -in @('Intune', 'CoManaged')
                    $expectConfigurationManager = $ring -in @('ConfigurationManager', 'CoManaged')
                    $liveActions = @()
                    if ($identity -eq 'Administrator' -and $expectIntune) {
                        $liveActions += [pscustomobject]@{ Agent = 'Intune'; IsSuccessful = $true }
                    }
                    if ($identity -eq 'Administrator' -and $expectConfigurationManager) {
                        $liveActions += [pscustomobject]@{ Agent = 'ConfigurationManager'; IsSuccessful = $true }
                    }
                    $record = [pscustomobject][ordered]@{
                        EvidenceVersion               = '1.0'
                        Ring                          = $ring
                        ModuleVersion                 = $Version
                        WindowsCaption                = 'Microsoft Windows 11 Enterprise'
                        WindowsBuild                  = '26200'
                        Architecture                  = '64-bit'
                        PowerShellEdition             = $edition
                        PowerShellVersion             = if ($edition -eq 'Desktop') { '5.1.26100.1' } else { '7.6.4' }
                        ExecutionIdentity             = $identity
                        RuntimeSmokePassed            = $true
                        IntuneExpected                = $expectIntune
                        IntuneDetected                = $expectIntune
                        IntuneLocalStatus             = if ($expectIntune) { 'LooksReady' } else { 'NotDetected' }
                        ConfigurationManagerExpected  = $expectConfigurationManager
                        ConfigurationManagerDetected  = $expectConfigurationManager
                        ConfigurationManagerLocalStatus = if ($expectConfigurationManager) { 'LooksReady' } else { 'NotDetected' }
                        WhatIfResults                 = @(
                            [pscustomobject]@{ Agent = 'Intune'; Outcome = 'WhatIf'; ChangeMayHaveOccurred = $false }
                            [pscustomobject]@{ Agent = 'ConfigurationManager'; Outcome = 'WhatIf'; ChangeMayHaveOccurred = $false }
                        )
                        ChangingActionsRequested      = $identity -eq 'Administrator' -and $ring -ne 'Unmanaged'
                        ChangingActionResults         = @($liveActions)
                        Passed                        = $true
                        ErrorCount                    = 0
                    }
                    $fileName = '{0}-{1}-{2}.json' -f $ring, $edition, $identity
                    $record | ConvertTo-Json -Depth 8 |
                        Set-Content -LiteralPath (Join-Path $Path $fileName) -Encoding UTF8
                }
            }
        }
    }
}

Describe 'EndpointForge stable managed-certification release gate' {
    It 'accepts the complete passing four-ring, two-host, three-identity matrix' {
        $evidencePath = Join-Path $TestDrive 'complete'
        Initialize-EFManagedCertificationEvidenceSet -Path $evidencePath

        $result = & $script:CertificationGate -ModuleVersion 1.0.0 -EvidenceDirectory $evidencePath

        $result.IsValid | Should -BeTrue
        $result.EvidenceRecords | Should -Be 24
    }

    It 'rejects an incomplete evidence matrix' {
        $evidencePath = Join-Path $TestDrive 'incomplete'
        Initialize-EFManagedCertificationEvidenceSet -Path $evidencePath
        Remove-Item -LiteralPath (Join-Path $evidencePath 'Unmanaged-Core-SYSTEM.json') -Force

        {
            & $script:CertificationGate -ModuleVersion 1.0.0 -EvidenceDirectory $evidencePath
        } | Should -Throw '*at least 24 JSON records*'
    }

    It 'rejects evidence for a different module version' {
        $evidencePath = Join-Path $TestDrive 'wrong-version'
        Initialize-EFManagedCertificationEvidenceSet -Path $evidencePath -Version 0.9.0

        {
            & $script:CertificationGate -ModuleVersion 1.0.0 -EvidenceDirectory $evidencePath
        } | Should -Throw '*not a passing EndpointForge 1.0.0 evidence record*'
    }

    It 'rejects managed-ring evidence without an approved successful live action' {
        $evidencePath = Join-Path $TestDrive 'missing-live-action'
        Initialize-EFManagedCertificationEvidenceSet -Path $evidencePath
        $intuneAdminPath = Join-Path $evidencePath 'Intune-Core-Administrator.json'
        $intuneAdmin = Get-Content -LiteralPath $intuneAdminPath -Raw | ConvertFrom-Json
        $intuneAdmin.ChangingActionResults = @()
        $intuneAdmin | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $intuneAdminPath -Encoding UTF8
        $intuneDesktopAdminPath = Join-Path $evidencePath 'Intune-Desktop-Administrator.json'
        $intuneDesktopAdmin = Get-Content -LiteralPath $intuneDesktopAdminPath -Raw | ConvertFrom-Json
        $intuneDesktopAdmin.ChangingActionResults = @()
        $intuneDesktopAdmin | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $intuneDesktopAdminPath -Encoding UTF8

        {
            & $script:CertificationGate -ModuleVersion 1.0.0 -EvidenceDirectory $evidencePath
        } | Should -Throw '*does not contain a successful approved Intune action*'
    }
}
