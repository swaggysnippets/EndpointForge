function Show-EFEndpointSummary {
    <#
    .SYNOPSIS
    Shows a human-readable EndpointForge dashboard in the terminal.

    .DESCRIPTION
    Renders an EndpointForge endpoint summary with status colors, security posture,
    prioritized findings, and the next recommended command. This command is for people;
    scripts should consume Get-EFEndpointSummary objects instead of parsing this display.

    .PARAMETER InputObject
    A summary returned by Get-EFEndpointSummary.

    .PARAMETER Baseline
    The baseline used when the command collects its own summary.

    .PARAMETER ControlId
    Limits compliance evaluation when the command collects its own summary.

    .PARAMETER IncludeSoftware
    Includes software when the command collects its own summary.

    .PARAMETER MinimumFreeSpacePercent
    Sets the system-drive warning threshold when the command collects its own summary.

    .PARAMETER MaximumUptimeDays
    Sets the uptime warning threshold when the command collects its own summary.

    .PARAMETER Detailed
    Shows full messages and suggested actions for every finding.

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

        & $writeLine ''
        & $writeLine 'EndpointForge endpoint summary' ([ConsoleColor]::Cyan)
        & $writeLine ('=' * 72) ([ConsoleColor]::DarkGray)
        & $writeLine ("{0}  |  {1}  |  Build {2}" -f $summary.ComputerName, $summary.OperatingSystem, $summary.OperatingSystemBuild)
        & $writeLine ("OVERALL      [{0}]  Score {1}/100" -f ([string]$summary.OverallStatus).ToUpperInvariant(), $summary.Score) $statusColor
        & $writeLine ("Health       {0,-14} Score {1}/100" -f $summary.HealthStatus, $summary.HealthScore)
        & $writeLine ("Compliance   {0,-14} Score {1}/100" -f $summary.ComplianceStatus, $summary.ComplianceScore)
        & $writeLine ("Data         {0,-14} Coverage {1}%" -f $summary.DataStatus, $summary.CoveragePercent)
        & $writeLine ("Restart      {0}" -f $(if ($summary.IsRebootPending) { 'Pending' } else { 'Not pending' }))

        & $writeLine ''
        & $writeLine 'Device' ([ConsoleColor]::Cyan)
        & $writeLine ("  Model: {0}   Uptime: {1} days   System drive free: {2}%" -f $summary.Model, $summary.UptimeDays, $summary.DiskFreePercent)
        & $writeLine ("  Firewall: {0}   Defender: {1}   BitLocker: {2}" -f $summary.Security.Firewall, $summary.Security.Defender, $summary.Security.BitLocker)
        & $writeLine ("  Secure Boot: {0}   TPM: {1}" -f $summary.Security.SecureBoot, $summary.Security.Tpm)

        & $writeLine ''
        & $writeLine ("Attention ({0} issue(s), {1} unknown)" -f $summary.IssueCount, $summary.UnknownCount) ([ConsoleColor]::Cyan)
        $findings = @($summary.Findings)
        if ($findings.Count -eq 0) {
            & $writeLine '  [OK] No findings require attention.' ([ConsoleColor]::Green)
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
                & $writeLine ("  [{0}] {1}: {2}" -f ([string]$finding.Status).ToUpperInvariant(), $finding.Id, $finding.Title) $findingColor
                if ($Detailed) {
                    & $writeLine ("         {0}" -f $finding.Message)
                    & $writeLine ("         Next: {0}" -f $finding.SuggestedAction) ([ConsoleColor]::DarkGray)
                }
            }
            if (-not $Detailed -and $findings.Count -gt 5) {
                & $writeLine ("  ... {0} more. Add -Detailed to show every finding." -f ($findings.Count - 5)) ([ConsoleColor]::DarkGray)
            }
        }

        & $writeLine ''
        & $writeLine 'Next step' ([ConsoleColor]::Cyan)
        & $writeLine ("  {0}" -f $summary.NextStep)
        & $writeLine ("  Automation exit code: {0}" -f $summary.ExitCode) ([ConsoleColor]::DarkGray)
        & $writeLine ''

        if ($PassThru) {
            $summary
        }
    }
}
