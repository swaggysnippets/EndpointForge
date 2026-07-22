function Test-EFEndpointCompliance {
    <#
    .SYNOPSIS
    Tests whether checked Windows settings match a checklist.

    .DESCRIPTION
    A checklist is a list of expected Windows settings; scripts call it a baseline and
    call a matching result compliant. This command reads settings without changing them
    and returns True only when every checked value matches and none were unreadable. Use
    PassThru for the full results, including why an item could not be checked.

    .PARAMETER Baseline
    A built-in checklist name, checklist JSON file, or validated checklist object.

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
