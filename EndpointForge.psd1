@{
    RootModule        = 'EndpointForge.psm1'
    ModuleVersion     = '0.6.0'
    GUID              = '7566d24f-23a9-4481-8cb1-a5ad1e8a013d'
    Author            = 'Logan Bamborough'
    CompanyName       = 'Logan Bamborough'
    Copyright         = '(c) 2026 Logan Bamborough. All rights reserved.'
    Description       = 'User-friendly, enterprise-safe Windows computer checkups with guided menus, plain-language findings, guarded fix previews, comparisons, fleet checks, and self-contained reports.'
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
                'Diagnostics', 'EventLog', 'Monitoring', 'TCP', 'WindowsUpdate', 'DNS', 'HTTP',
                'Certificate', 'ScheduledTask'
            )
            LicenseUri = 'https://opensource.org/license/mit'
            ProjectUri = 'https://github.com/swaggysnippets/EndpointForge'
            ReleaseNotes = 'Adds 12 report-only checklist types for pending restarts, disk space, available Windows updates, installed applications, scheduled job health, Defender definition age, file freshness, certificate expiry, DNS, HTTP endpoints, running programs, and local group membership. Includes a 24-item capability guide, expanded editable examples, privacy-minimized results, bounded checks, and explicit approval for network-active items.'
        }
    }
}
