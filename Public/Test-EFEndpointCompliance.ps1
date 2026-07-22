function Test-EFEndpointCompliance {
    <#
    .SYNOPSIS
    Tests whether every checked item matches a checklist.

    .DESCRIPTION
    A checklist is a list of things expected to be true; scripts call it a baseline and
    call a matching result compliant. Items can cover settings, restart and update state,
    storage, applications, jobs, files, certificates, events, processes, account
    relationships, and approved network services. This command does not apply fixes or
    change Windows.

    TcpPort, DnsResolution, HttpEndpointHealth, WindowsUpdateAvailable, and
    LocalGroupMembership are network-active. They are blocked unless AllowNetworkChecks is
    supplied. Contacted services, identity providers, or monitoring tools may record the
    activity.

    The command returns True only when every checked value matches and every check
    completed. Matching log lines, event messages, and event data are not included in the
    result. Use PassThru for full status and guidance.

    .PARAMETER Baseline
    A built-in checklist name, checklist JSON file, or validated checklist object. Review
    every target and network-active item before running it.

    .PARAMETER ControlId
    One or more checklist item IDs to test. Every item is tested by default.

    .PARAMETER AllowNetworkChecks
    Allows the five network-active types after their destinations, requested account
    identities, update options, and purposes have been reviewed. This is an explicit
    acknowledgement, not a network authorization system.

    .PARAMETER PassThru
    Returns the EndpointForge.ComplianceReport instead of a Boolean.

    .PARAMETER NoProgress
    Suppresses the progress display for non-interactive automation hosts.

    .EXAMPLE
    if (Test-EFEndpointCompliance) { 'Compliant' } else { 'Attention required' }

    .EXAMPLE
    $report = Test-EFEndpointCompliance -PassThru -NoProgress

    .EXAMPLE
    Test-EFEndpointCompliance -Baseline .\Contoso.EverydayChecks.json -AllowNetworkChecks -NoProgress

    Returns a Boolean for the expanded everyday checklist after approved network activity.

    .OUTPUTS
    System.Boolean
    EndpointForge.ComplianceReport when PassThru is specified.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object]$Baseline = 'EnterpriseRecommended',

        [string[]]$ControlId,

        [switch]$AllowNetworkChecks,

        [switch]$PassThru,

        [switch]$NoProgress
    )

    $parameters = @{
        Baseline   = $Baseline
        NoProgress = $NoProgress
        AllowNetworkChecks = [bool]$AllowNetworkChecks
    }
    if ($PSBoundParameters.ContainsKey('ControlId')) {
        $parameters.ControlId = $ControlId
    }

    $report = Get-EFComplianceReport @parameters
    if ($PassThru) {
        return $report
    }
    return [bool]$report.IsCompliant
}
