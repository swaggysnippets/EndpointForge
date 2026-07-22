function Test-EFEndpointCompliance {
    <#
    .SYNOPSIS
    Tests whether every checked item matches a checklist.

    .DESCRIPTION
    A checklist is a list of things expected to be true; scripts call it a baseline and
    call a matching result compliant. Items can cover Windows settings, exact local files,
    literal text near the end of a log, recent Windows event IDs, or one TCP host and
    port. This command does not apply fixes or change Windows. A TcpPort item does make
    one real, observable connection attempt and sends no application data.

    The command returns True only when every checked value matches and every check
    completed. Matching log lines, event messages, and event data are not included in the
    result. Use PassThru for full status and guidance.

    .PARAMETER Baseline
    A built-in checklist name, checklist JSON file, or validated checklist object. Review
    custom paths, event queries, hosts, and ports before running it.

    .PARAMETER ControlId
    One or more checklist item IDs to test. Every item is tested by default.

    .PARAMETER PassThru
    Returns the EndpointForge.ComplianceReport instead of a Boolean.

    .PARAMETER NoProgress
    Suppresses the progress display for non-interactive automation hosts.

    .EXAMPLE
    if (Test-EFEndpointCompliance) { 'Compliant' } else { 'Attention required' }

    .EXAMPLE
    $report = Test-EFEndpointCompliance -PassThru -NoProgress

    .EXAMPLE
    Test-EFEndpointCompliance -Baseline .\Contoso.EverydayChecks.json -NoProgress

    Returns a Boolean for the everyday custom checklist. A TcpPort item can create an
    observable connection attempt even though the check does not change Windows.

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

        [switch]$PassThru,

        [switch]$NoProgress
    )

    $parameters = @{
        Baseline   = $Baseline
        NoProgress = $NoProgress
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
