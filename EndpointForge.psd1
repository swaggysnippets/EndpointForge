@{
    RootModule        = 'EndpointForge.psm1'
    ModuleVersion     = '0.9.0'
    GUID              = '7566d24f-23a9-4481-8cb1-a5ad1e8a013d'
    Author            = 'Logan Bamborough'
    CompanyName       = 'Logan Bamborough'
    Copyright         = '(c) 2026 Logan Bamborough. All rights reserved.'
    Description       = 'User-friendly, enterprise-safe Windows computer checkups with guided menus, plain-language findings, guarded fix previews, comparisons, fleet checks, and self-contained reports.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
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
        'Get-EFManagementAgentHealth'
        'Get-EFPendingReboot'
        'Get-EFRemediationPlan'
        'Invoke-EFEndpointRemediation'
        'Invoke-EFManagementAgentAction'
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
                'Certificate', 'ScheduledTask', 'WMI', 'CIM', 'Networking', 'CIDR', 'IPv4', 'IPv6',
                'ConfigurationManager', 'ConfigMgr', 'SCCM', 'CCM', 'ManagementAgent'
            )
            LicenseUri = 'https://opensource.org/license/mit'
            ProjectUri = 'https://github.com/swaggysnippets/EndpointForge'
            ReleaseNotes = 'Preview release and contract candidate for EndpointForge 1.0. Adds safe WMI/CIM namespace and local IP-range checklist items; guarded local Intune and Configuration Manager health/support tooling; truthful unknown-result semantics; CSV formula protection; hash-pinned, size-bounded custom checklist loading; module-owned privileged checklist-integrity enforcement; versioned public and checklist contracts; bounded fleet compatibility evidence; complete support and migration documentation; managed-endpoint certification tooling; and hardened signed release automation. The 0.7 and 0.8 development milestones were not separately published, so their capabilities first ship in 0.9.0. Stable EndpointForge 1.0 remains gated on trusted Authenticode signing and recorded managed-device certification.'
        }
    }
}
