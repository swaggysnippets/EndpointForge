[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$ComputerName,

    [string]$Baseline = 'EnterpriseRecommended',

    [PSCredential]$Credential,

    [string]$ReportPath = (Join-Path (Get-Location) 'EndpointForge-remote-summary.json')
)

$ErrorActionPreference = 'Stop'
$invokeParameters = @{
    ComputerName = $ComputerName
    ArgumentList = $Baseline
    ScriptBlock  = {
        param($SelectedBaseline)
        Import-Module EndpointForge -MinimumVersion 0.2.0 -ErrorAction Stop
        Get-EFEndpointSummary -Baseline $SelectedBaseline -NoProgress
    }
}
if ($PSBoundParameters.ContainsKey('Credential')) {
    $invokeParameters.Credential = $Credential
}

$summaries = @(Invoke-Command @invokeParameters)
$summaries | Export-EFEndpointReport -Path $ReportPath -AsArray -Force
$summaries
