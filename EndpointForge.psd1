@{
    RootModule        = 'EndpointForge.psm1'
    ModuleVersion     = '0.5.0'
    GUID              = '7566d24f-23a9-4481-8cb1-a5ad1e8a013d'
    Author            = 'Logan Bamborough'
    CompanyName       = 'Logan Bamborough'
    Copyright         = '(c) 2026 Logan Bamborough. All rights reserved.'
    Description       = 'Beginner-friendly, enterprise-safe Windows computer checkups with guided menus, plain-language findings, guarded fix previews, comparisons, fleet checks, and self-contained reports.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    HelpInfoURI       = 'https://github.com/swaggysnippets/EndpointForge/blob/main/README.md'
    FormatsToProcess  = @('EndpointForge.Format.ps1xml')

    FunctionsToExport = @(
        'Compare-EFEndpointSummary'
        'Export-EFEndpointReport'
        'Get-EFBaseline'
        'Get-EFComplianceReport'
        'Get-EFConfiguration'
        'Get-EFEndpointHealth'
        'Get-EFEndpointInventory'
        'Get-EFEndpointReadiness'
        'Get-EFEndpointSummary'
        'Get-EFFleetSummary'
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
                'Inventory', 'Remediation', 'Security', 'Intune', 'RMM', 'Report', 'HTML', 'Fleet',
                'Diagnostics', 'EventLog', 'Monitoring', 'TCP'
            )
            LicenseUri = 'https://opensource.org/license/mit'
            ProjectUri = 'https://github.com/swaggysnippets/EndpointForge'
            ReleaseNotes = 'Adds beginner-friendly report-only checks for exact local files, literal text near the end of logs, recent Windows event IDs, and bounded TCP connections; an editable EverydayChecks template; clear menu explanations; privacy-safe results; and explicit opt-in before TCP checks fan out across a fleet.'
        }
    }
}
