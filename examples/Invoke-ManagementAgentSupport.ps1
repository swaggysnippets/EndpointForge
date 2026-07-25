# EndpointForge 0.9.0 - local Intune and Configuration Manager support examples
#
# The health command reads only fixed local evidence. It does not contact a management
# service, read log contents, or return tenant, site, device, account, or server identifiers.
[CmdletBinding()]
param(
    [switch]$ApplyApprovedAction
)

$health = Get-EFManagementAgentHealth
$health | Select-Object Agent, LocalStatus, ServiceStatus, StartupType, Summary, NextStep

# The Microsoft Intune Management Extension is installed only when assigned work needs it.
# NotDetected for that extension alone does not prove the computer is not Intune-enrolled.
Get-EFManagementAgentHealth -Agent Intune

# Familiar Configuration Manager names are accepted: ConfigurationManager, ConfigMgr,
# SCCM, or CCM.
Get-EFManagementAgentHealth -Agent ConfigMgr

# Always preview an action first. WhatIf changes nothing and starts no management traffic.
Invoke-EFManagementAgentAction `
    -Agent Intune `
    -Action RestartAgentService `
    -WhatIf

# Run an actual action only after approval and from PowerShell opened with
# Run as administrator. AllowManagementTraffic acknowledges that the action can contact
# the configured service and begin assigned applications, scripts, policy, updates, or
# other work. Normal high-impact PowerShell confirmation still applies.
if ($ApplyApprovedAction) {
    Invoke-EFManagementAgentAction `
        -Agent ConfigurationManager `
        -Action RequestMachinePolicy `
        -AllowManagementTraffic

    # A successful result means the local client accepted the request. Policy work is
    # asynchronous; acceptance does not prove that synchronization or assigned work
    # finished.
    Get-EFManagementAgentHealth -Agent ConfigurationManager
}
else {
    Write-Verbose 'No management action requested. Add -ApplyApprovedAction only after approval.'
}
