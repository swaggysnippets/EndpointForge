function Get-EFEndpointSummary {
    <#
    .SYNOPSIS
    Gets one combined endpoint health and compliance summary.

    .DESCRIPTION
    Provides the recommended first-run experience for EndpointForge. It combines device
    identity, inventory, operational health, pending restart, compliance, data coverage,
    actionable findings, and stable exit codes in one pipeline-friendly object.

    .PARAMETER Baseline
    A built-in baseline name, JSON path, or validated baseline object.

    .PARAMETER ControlId
    Limits compliance evaluation to selected controls.

    .PARAMETER IncludeSoftware
    Includes installed software in the nested Inventory object.

    .PARAMETER MinimumFreeSpacePercent
    The system-drive free-space warning threshold.

    .PARAMETER MaximumUptimeDays
    The endpoint uptime warning threshold.

    .PARAMETER NoProgress
    Suppresses the progress display for non-interactive automation hosts.

    .EXAMPLE
    Get-EFEndpointSummary

    .EXAMPLE
    Get-EFEndpointSummary -NoProgress | Show-EFEndpointSummary -Detailed

    .OUTPUTS
    EndpointForge.EndpointSummary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object]$Baseline = 'EnterpriseRecommended',

        [string[]]$ControlId,

        [switch]$IncludeSoftware,

        [ValidateRange(1, 99)]
        [int]$MinimumFreeSpacePercent = 15,

        [ValidateRange(1, 3650)]
        [int]$MaximumUptimeDays = 30,

        [switch]$NoProgress
    )

    $null = Test-EFWindows -Throw
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $correlationId = [guid]::NewGuid().ToString()
    try {
        if (-not $NoProgress) {
            Write-Progress -Id 1100 -Activity 'EndpointForge endpoint summary' -Status 'Collecting inventory and health' -PercentComplete 10
        }
        $health = Get-EFEndpointHealth -MinimumFreeSpacePercent $MinimumFreeSpacePercent `
            -MaximumUptimeDays $MaximumUptimeDays -IncludeSoftware:$IncludeSoftware -NoProgress

        if (-not $NoProgress) {
            Write-Progress -Id 1100 -Activity 'EndpointForge endpoint summary' -Status 'Evaluating compliance' -PercentComplete 60
        }
        $complianceParameters = @{
            Baseline   = $Baseline
            NoProgress = $true
        }
        if ($PSBoundParameters.ContainsKey('ControlId')) {
            $complianceParameters.ControlId = $ControlId
        }
        $compliance = Get-EFComplianceReport @complianceParameters

        if (-not $NoProgress) {
            Write-Progress -Id 1100 -Activity 'EndpointForge endpoint summary' -Status 'Prioritizing findings' -PercentComplete 90
        }

        $findings = [Collections.Generic.List[object]]::new()
        foreach ($check in @($health.Checks | Where-Object { $_.Status -ne 'Healthy' -and $_.Id -ne 'InventoryCollection' })) {
            $suggestedAction = if ($check.Status -eq 'Unknown') {
                'Review collection details and rerun elevated if the capability requires administrator privileges.'
            }
            else {
                'Review the health check details and address the reported threshold or protection state.'
            }
            $findingTitle = switch -Wildcard ([string]$check.Id) {
                'DiskFreeSpace' { 'System drive free space' }
                'Uptime' { 'Endpoint uptime' }
                'PendingReboot' { 'Pending restart' }
                'Firewall*' { ([string]$check.Id).Replace('Firewall', '') + ' firewall profile' }
                'DefenderRealTimeProtection' { 'Microsoft Defender real-time protection' }
                'BitLockerProtection' { 'BitLocker system-drive protection' }
                default { [string]$check.Id }
            }
            $findings.Add([pscustomobject]@{
                Source            = 'Health'
                Id                = [string]$check.Id
                Title             = $findingTitle
                Severity          = [string]$check.Severity
                Status            = [string]$check.Status
                Message           = [string]$check.Message
                SuggestedAction   = $suggestedAction
                RequiresElevation = $false
            })
        }
        foreach ($controlResult in @($compliance.Results | Where-Object Status -in @('NonCompliant', 'Error'))) {
            $requiresElevation = $controlResult.Status -eq 'Error' -and
                $controlResult.Message -match 'elevat|access.+denied|administrator|privilege'
            $findings.Add([pscustomobject]@{
                Source            = 'Compliance'
                Id                = [string]$controlResult.ControlId
                Title             = [string]$controlResult.Title
                Severity          = [string]$controlResult.Severity
                Status            = [string]$controlResult.Status
                Message           = [string]$controlResult.Message
                SuggestedAction   = [string]$controlResult.RecommendedAction
                RequiresElevation = [bool]$requiresElevation
            })
        }

        $criticalComplianceCount = @($compliance.Results | Where-Object {
            $_.Status -eq 'NonCompliant' -and $_.Severity -eq 'Critical'
        }).Count
        $actualIssueCount = @($findings | Where-Object Status -notin @('Unknown', 'Error')).Count
        $unknownCount = @($findings | Where-Object Status -in @('Unknown', 'Error')).Count
        $overallStatus = if ($health.Status -eq 'Critical' -or $criticalComplianceCount -gt 0) {
            'Critical'
        }
        elseif ($actualIssueCount -gt 0 -or $health.Status -eq 'Warning') {
            'Warning'
        }
        elseif ($unknownCount -gt 0) {
            'Incomplete'
        }
        else {
            'Healthy'
        }
        $complianceStatus = if ($compliance.NonCompliantCount -gt 0) {
            'NonCompliant'
        }
        elseif ($compliance.ErrorCount -gt 0) {
            'Incomplete'
        }
        else {
            'Compliant'
        }
        $dataStatus = if ($health.DataStatus -eq 'Failed' -or $compliance.DataStatus -eq 'Failed') {
            'Failed'
        }
        elseif ($health.DataStatus -eq 'Partial' -or $compliance.DataStatus -eq 'Partial') {
            'Partial'
        }
        else {
            'Complete'
        }
        $coveragePercent = [math]::Round(($health.CoveragePercent + $compliance.CoveragePercent) / 2, 1)
        $score = [math]::Round(($health.Score + $compliance.Score) / 2, 1)
        $exitCode = if ($dataStatus -eq 'Failed' -or $compliance.ErrorCount -gt 0) {
            3
        }
        elseif ($overallStatus -eq 'Critical' -or $compliance.NonCompliantCount -gt 0) {
            2
        }
        elseif ($overallStatus -eq 'Warning' -or $dataStatus -eq 'Partial') {
            1
        }
        else {
            0
        }

        $inventory = $health.Inventory
        $firewallProfiles = @($inventory.Security.Firewall)
        $enabledFirewallProfiles = @($firewallProfiles | Where-Object Enabled).Count
        $defender = $inventory.Security.Defender
        $bitLocker = $inventory.Security.BitLocker
        $security = [pscustomobject]@{
            Firewall = if ($firewallProfiles.Count -eq 0) { 'Unknown' } else { "$enabledFirewallProfiles/$($firewallProfiles.Count) enabled" }
            Defender = if ($null -eq $defender) { 'Unknown' } elseif ($defender.RealTimeProtectionEnabled) { 'Enabled' } else { 'Disabled' }
            BitLocker = if ($null -eq $bitLocker) { 'Unknown' } else { [string]$bitLocker.ProtectionStatus }
            SecureBoot = if ($null -eq $inventory.Security.SecureBoot) { 'Unknown' } elseif ($inventory.Security.SecureBoot) { 'Enabled' } else { 'Disabled' }
            Tpm = if ($null -eq $inventory.Security.Tpm) { 'Unknown' } elseif ($inventory.Security.Tpm.Ready) { 'Ready' } else { 'NotReady' }
        }

        $sortedFindings = @($findings | Sort-Object `
            @{ Expression = {
                switch ($_.Severity) { 'Critical' { 0 } 'High' { 1 } 'Warning' { 2 } 'Medium' { 3 } 'Low' { 4 } default { 5 } }
            } }, Source, Id)
        $nextStep = if ($compliance.ErrorCount -gt 0) {
            'Resolve incomplete checks, often by running elevated, then run Get-EFEndpointSummary again.'
        }
        elseif ($compliance.NonCompliantCount -gt 0) {
            'Run Get-EFRemediationPlan, then preview approved changes with Invoke-EFEndpointRemediation -WhatIf.'
        }
        elseif ($health.Status -ne 'Healthy') {
            'Review Findings and address the health warnings before the next assessment.'
        }
        else {
            'No action is required.'
        }

        $timer.Stop()
        [pscustomobject]@{
            PSTypeName          = 'EndpointForge.EndpointSummary'
            SchemaVersion       = '1.0'
            ModuleVersion       = [string](Get-Module EndpointForge).Version
            ComputerName        = $inventory.ComputerName
            OverallStatus       = $overallStatus
            HealthStatus        = $health.Status
            ComplianceStatus    = $complianceStatus
            DataStatus          = $dataStatus
            Score               = $score
            HealthScore         = $health.Score
            ComplianceScore     = $compliance.Score
            CoveragePercent     = $coveragePercent
            IssueCount          = $actualIssueCount
            UnknownCount        = $unknownCount
            IsRebootPending     = $health.PendingReboot.IsRebootPending
            ExitCode            = $exitCode
            OperatingSystem     = $inventory.OperatingSystemName
            OperatingSystemBuild = $inventory.OperatingSystemBuild
            Model               = $inventory.DeviceModel
            UptimeDays          = $inventory.UptimeDays
            DiskFreePercent     = $inventory.SystemDriveFreePercent
            Security            = $security
            NextStep            = $nextStep
            CorrelationId       = $correlationId
            StartedAtUtc        = [DateTime]::UtcNow.Subtract($timer.Elapsed)
            CompletedAtUtc      = [DateTime]::UtcNow
            DurationMilliseconds = $timer.ElapsedMilliseconds
            Findings            = $sortedFindings
            Inventory           = $inventory
            Health              = $health
            Compliance          = $compliance
        }
    }
    finally {
        if (-not $NoProgress) {
            Write-Progress -Id 1100 -Activity 'EndpointForge endpoint summary' -Completed
        }
        if ($timer.IsRunning) {
            $timer.Stop()
        }
    }
}
