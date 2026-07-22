function Test-EFEndpointCompliance {
    <#
    .SYNOPSIS
    Tests whether the local Windows endpoint is compliant.

    .DESCRIPTION
    Returns a Boolean by default so the command behaves naturally in if statements and
    automation conditions. Use PassThru to receive the complete compliance report, or
    call Get-EFComplianceReport directly for reporting and diagnostics.

    .PARAMETER Baseline
    A built-in baseline name, a JSON file path, or a validated baseline object.

    .PARAMETER ControlId
    One or more control identifiers to test. All controls are tested by default.

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
