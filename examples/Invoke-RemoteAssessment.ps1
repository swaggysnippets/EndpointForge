<#
.SYNOPSIS
Checks several Windows computers without changing them.

.DESCRIPTION
Uses Get-EFFleetSummary to run a read-only EndpointForge checkup on each named computer.
The command does not install software, turn on PowerShell remoting, change Windows
settings, or approve fixes.

Before running this example, each remote computer must already:

- allow PowerShell remoting according to your organization's policy;
- have EndpointForge 0.6.0 or later installed; and
- allow the supplied account (or your current account) to connect.

The saved report can contain computer names, device details, and security findings. Keep
it in an approved location and share it only with authorized people.

If a custom checklist contains TCP, DNS, HTTP, Windows Update, or local-group membership
checks, review every destination, requested account identity, update option, and purpose,
then add AllowNetworkChecks. Resolving a local-group account name can contact an identity
provider. Each remote computer can generate observable network activity.

.EXAMPLE
.\Invoke-RemoteAssessment.ps1 -ComputerName PC-101,PC-102

.EXAMPLE
.\Invoke-RemoteAssessment.ps1 -ComputerName (Get-Content .\computers.txt) `
    -Credential (Get-Credential) -ReportPath .\fleet-check.html -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$ComputerName,

    [object]$Baseline = 'EnterpriseRecommended',

    [PSCredential]$Credential,

    [string]$ReportPath = (Join-Path (Get-Location) 'EndpointForge-fleet-check.html'),

    [switch]$IncludeSoftware,

    [switch]$AllowNetworkChecks,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Import-Module EndpointForge -MinimumVersion 0.6.0 -ErrorAction Stop

$fleetParameters = @{
    ComputerName   = $ComputerName
    Baseline       = $Baseline
    IncludeSoftware = $IncludeSoftware
    AllowNetworkChecks = [bool]$AllowNetworkChecks
}
if ($PSBoundParameters.ContainsKey('Credential')) {
    $fleetParameters.Credential = $Credential
}

$fleetCheck = Get-EFFleetSummary @fleetParameters
$fleetCheck | Export-EFEndpointReport -Path $ReportPath -Force:$Force
$fleetCheck
