function Show-EFEndpointSummary {
    <#
    .SYNOPSIS
    Shows a plain-language computer checkup in the terminal.

    .DESCRIPTION
    Explains computer health, important Windows settings, items needing attention, and a
    suggested next step. It is designed for someone who does not know PowerShell or
    configuration-management terminology. Showing a result never changes Windows.

    A checklist is simply a list of Windows settings and their expected values. Scripts
    call that checklist a baseline, but the terminal display uses everyday language.

    .PARAMETER InputObject
    A summary returned by Get-EFEndpointSummary.

    .PARAMETER Baseline
    The checklist used when the command collects its own summary.

    .PARAMETER ControlId
    Limits the check to selected checklist item IDs when the command collects a summary.

    .PARAMETER IncludeSoftware
    Includes software when the command collects its own summary.

    .PARAMETER MinimumFreeSpacePercent
    Sets the system-drive warning threshold when the command collects its own summary.

    .PARAMETER MaximumUptimeDays
    Sets the uptime warning threshold when the command collects its own summary.

    .PARAMETER Detailed
    Shows every finding, how it was checked, current and expected values when available,
    the item ID used by scripts, and the script result code.

    .PARAMETER NoColor
    Uses plain terminal text without foreground colors.

    .PARAMETER PassThru
    Returns the summary after rendering it.

    .PARAMETER NoProgress
    Suppresses progress when the command collects its own summary.

    .EXAMPLE
    Get-EFEndpointSummary | Show-EFEndpointSummary

    .EXAMPLE
    Show-EFEndpointSummary -Detailed -NoColor -NoProgress

    .OUTPUTS
    None by default. EndpointForge.EndpointSummary when PassThru is specified.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost',
        '',
        Justification = 'This opt-in Show command intentionally renders a host-only operator dashboard.'
    )]
    [CmdletBinding(DefaultParameterSetName = 'Collect')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')]
        [ValidateNotNull()]
        [object]$InputObject,

        [Parameter(ParameterSetName = 'Collect')]
        [AllowNull()]
        [object]$Baseline = 'EnterpriseRecommended',

        [Parameter(ParameterSetName = 'Collect')]
        [string[]]$ControlId,

        [Parameter(ParameterSetName = 'Collect')]
        [switch]$IncludeSoftware,

        [Parameter(ParameterSetName = 'Collect')]
        [ValidateRange(1, 99)]
        [int]$MinimumFreeSpacePercent = 15,

        [Parameter(ParameterSetName = 'Collect')]
        [ValidateRange(1, 3650)]
        [int]$MaximumUptimeDays = 30,

        [Parameter(ParameterSetName = 'Collect')]
        [switch]$NoProgress,

        [switch]$Detailed,

        [switch]$NoColor,

        [switch]$PassThru
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
            $summary = $InputObject
        }
        else {
            $summaryParameters = @{
                Baseline                = $Baseline
                IncludeSoftware         = $IncludeSoftware
                MinimumFreeSpacePercent = $MinimumFreeSpacePercent
                MaximumUptimeDays       = $MaximumUptimeDays
                NoProgress              = $NoProgress
            }
            if ($PSBoundParameters.ContainsKey('ControlId')) {
                $summaryParameters.ControlId = $ControlId
            }
            $summary = Get-EFEndpointSummary @summaryParameters
        }

        if (-not (Test-EFPropertyPresent -InputObject $summary -Name 'OverallStatus') -or
            -not (Test-EFPropertyPresent -InputObject $summary -Name 'Findings')) {
            throw [System.ArgumentException]::new('InputObject must be an EndpointForge endpoint summary.')
        }

        $writeLine = {
            param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray)
            if ($NoColor) { Write-Host $Text } else { Write-Host $Text -ForegroundColor $Color }
        }
        $statusColor = switch ([string]$summary.OverallStatus) {
            'Healthy' { [ConsoleColor]::Green }
            'Incomplete' { [ConsoleColor]::Yellow }
            'Warning' { [ConsoleColor]::Yellow }
            'Critical' { [ConsoleColor]::Red }
            default { [ConsoleColor]::Gray }
        }
        $friendlyStatus = {
            param([AllowNull()][object]$Value)
            switch ([string]$Value) {
                'Healthy' { 'Looks good' }
                'Unhealthy' { 'Needs attention' }
                'Warning' { 'Needs attention' }
                'Critical' { 'Urgent attention' }
                'Incomplete' { 'Could not check everything' }
                'Compliant' { 'Matches the checklist' }
                'NonCompliant' { 'Does not match the checklist' }
                'Complete' { 'All information collected' }
                'Partial' { 'Some information could not be collected' }
                'Failed' { 'Could not collect information' }
                'Error' { 'Could not check' }
                'Unknown' { 'Could not check' }
                'NotApplicable' { 'Not used on this computer' }
                default { [string]$Value }
            }
        }
        $findingLabel = {
            param([AllowNull()][object]$Value)
            switch ([string]$Value) {
                'NonCompliant' { 'DOES NOT MATCH' }
                'Error' { 'COULD NOT CHECK' }
                'Unknown' { 'COULD NOT CHECK' }
                'Critical' { 'URGENT ATTENTION' }
                'Warning' { 'NEEDS ATTENTION' }
                'Unhealthy' { 'NEEDS ATTENTION' }
                default { ([string]$Value).ToUpperInvariant() }
            }
        }

        & $writeLine ''
        & $writeLine 'EndpointForge computer checkup' ([ConsoleColor]::Cyan)
        & $writeLine ('=' * 72) ([ConsoleColor]::DarkGray)
        & $writeLine 'This check read information only. It did not change Windows.' ([ConsoleColor]::DarkGray)
        & $writeLine ("{0}  |  {1}  |  Build {2}" -f $summary.ComputerName, $summary.OperatingSystem, $summary.OperatingSystemBuild)
        & $writeLine ("OVERALL RESULT        {0}  -  Score {1}/100" -f (& $friendlyStatus $summary.OverallStatus), $summary.Score) $statusColor
        & $writeLine ("Computer health       {0}  -  Score {1}/100" -f (& $friendlyStatus $summary.HealthStatus), $summary.HealthScore)
        & $writeLine ("Recommended settings  {0}  -  Score {1}/100 for settings Windows could answer" -f (& $friendlyStatus $summary.ComplianceStatus), $summary.ComplianceScore)
        & $writeLine ("Check completeness    {0}  -  {1}% checked" -f (& $friendlyStatus $summary.DataStatus), $summary.CoveragePercent)
        & $writeLine ("Restart waiting       {0}" -f $(if ($summary.IsRebootPending) { 'Yes' } else { 'No' }))

        & $writeLine ''
        & $writeLine 'About this computer' ([ConsoleColor]::Cyan)
        & $writeLine ("  Model: {0}   Uptime: {1} days   System drive free: {2}%" -f $summary.Model, $summary.UptimeDays, $summary.DiskFreePercent)
        & $writeLine ("  Firewall: {0}   Defender: {1}   BitLocker: {2}" -f $summary.Security.Firewall, (& $friendlyStatus $summary.Security.Defender), (& $friendlyStatus $summary.Security.BitLocker))
        & $writeLine ("  Secure Boot: {0}   TPM: {1}" -f (& $friendlyStatus $summary.Security.SecureBoot), (& $friendlyStatus $summary.Security.Tpm))

        & $writeLine ''
        & $writeLine ("Items to review ({0} needing attention, {1} not fully checked)" -f $summary.IssueCount, $summary.UnknownCount) ([ConsoleColor]::Cyan)
        $findings = @($summary.Findings)
        if ($findings.Count -eq 0) {
            & $writeLine '  [LOOKS GOOD] Nothing from this check needs attention.' ([ConsoleColor]::Green)
        }
        else {
            $displayFindings = if ($Detailed) { $findings } else { @($findings | Select-Object -First 5) }
            foreach ($finding in $displayFindings) {
                $findingColor = switch ([string]$finding.Severity) {
                    'Critical' { [ConsoleColor]::Red }
                    'High' { [ConsoleColor]::Red }
                    'Warning' { [ConsoleColor]::Yellow }
                    default { [ConsoleColor]::Yellow }
                }
                & $writeLine ("  [{0}] {1}" -f (& $findingLabel $finding.Status), $finding.Title) $findingColor
                if ($Detailed) {
                    & $writeLine ("         Result: {0}" -f (& $friendlyStatus $finding.Status))
                    if (-not [string]::IsNullOrWhiteSpace([string](Get-EFPropertyValue $finding 'WhyItMatters' ''))) {
                        & $writeLine ("         Why it matters: {0}" -f (Get-EFPropertyValue $finding 'WhyItMatters'))
                    }
                    if (Test-EFPropertyPresent $finding 'ActualValue') {
                        & $writeLine ("         Found now: {0}" -f (ConvertTo-EFMenuValue (Get-EFPropertyValue $finding 'ActualValue')))
                    }
                    if (Test-EFPropertyPresent $finding 'DesiredValue') {
                        & $writeLine ("         Expected: {0}" -f (ConvertTo-EFMenuValue (Get-EFPropertyValue $finding 'DesiredValue')))
                    }
                    & $writeLine ("         What happened: {0}" -f $finding.Message)
                    & $writeLine ("         What you can do: {0}" -f $finding.SuggestedAction) ([ConsoleColor]::DarkGray)
                    & $writeLine ("         Item ID for scripts: {0}" -f $finding.Id) ([ConsoleColor]::DarkGray)
                }
            }
            if (-not $Detailed -and $findings.Count -gt 5) {
                & $writeLine ("  ... {0} more. Use the detailed view to explain every item." -f ($findings.Count - 5)) ([ConsoleColor]::DarkGray)
            }
        }
        if ($summary.UnknownCount -gt 0) {
            & $writeLine '  Note: Could not check does not mean failed. Windows may protect that information or the feature may be unavailable.' ([ConsoleColor]::DarkGray)
        }

        & $writeLine ''
        & $writeLine 'Suggested next step' ([ConsoleColor]::Cyan)
        & $writeLine ("  {0}" -f $summary.NextStep)
        if ($Detailed) {
            & $writeLine ("  For scripts: result code {0}" -f $summary.ExitCode) ([ConsoleColor]::DarkGray)
        }
        & $writeLine ''

        if ($PassThru) {
            $summary
        }
    }
}
