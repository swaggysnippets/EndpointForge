@{
    RootModule        = 'EndpointForge.psm1'
    ModuleVersion     = '0.3.0'
    GUID              = '7566d24f-23a9-4481-8cb1-a5ad1e8a013d'
    Author            = 'Logan Bamborough'
    CompanyName       = 'Logan Bamborough'
    Copyright         = '(c) 2026 Logan Bamborough. All rights reserved.'
    Description       = 'Enterprise-safe Windows endpoint automation with a guided console menu, inventory, health, compliance, guarded remediation, and reporting.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    HelpInfoURI       = 'https://github.com/swaggysnippets/EndpointForge/blob/main/README.md'
    FormatsToProcess  = @('EndpointForge.Format.ps1xml')

    FunctionsToExport = @(
        'Export-EFEndpointReport'
        'Get-EFBaseline'
        'Get-EFComplianceReport'
        'Get-EFConfiguration'
        'Get-EFEndpointHealth'
        'Get-EFEndpointInventory'
        'Get-EFEndpointSummary'
        'Get-EFInstalledSoftware'
        'Get-EFPendingReboot'
        'Get-EFRemediationPlan'
        'Invoke-EFEndpointRemediation'
        'New-EFBaseline'
        'Set-EFConfiguration'
        'Show-EFMenu'
        'Show-EFEndpointSummary'
        'Test-EFBaseline'
        'Test-EFEndpointCompliance'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags = @(
                'Windows', 'Endpoint', 'Enterprise', 'Automation', 'Compliance',
                'Inventory', 'Remediation', 'Security', 'Intune', 'RMM'
            )
            LicenseUri = 'https://opensource.org/license/mit'
            ProjectUri = 'https://github.com/swaggysnippets/EndpointForge'
            ReleaseNotes = 'Guided console menu with scoped remediation and export, hardened custom-baseline validation, packaged security guidance, pinned CI tooling, and verified publish-readiness gates.'
        }
    }
}
