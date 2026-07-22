function Get-EFEndpointHealth {
    <#
    .SYNOPSIS
    Produces an operational health summary for the local Windows endpoint.

    .DESCRIPTION
    Combines inventory and pending-reboot signals into a compact health report suitable
    for RMM, Intune proactive remediation, scheduled tasks, and monitoring ingestion.
    ExitCode is 0 for Healthy, 1 for Warning, and 2 for Critical.

    .PARAMETER MinimumFreeSpacePercent
    The system-drive free-space percentage below which a warning is reported.

    .PARAMETER MaximumUptimeDays
    The uptime threshold after which a pending maintenance warning is reported.

    .PARAMETER IncludeSoftware
    Includes installed software in the nested Inventory object.

    .PARAMETER NoProgress
    Suppresses the progress display for non-interactive automation hosts.

    .EXAMPLE
    Get-EFEndpointHealth -MinimumFreeSpacePercent 15 -MaximumUptimeDays 30
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 99)]
        [int]$MinimumFreeSpacePercent = 15,

        [ValidateRange(1, 3650)]
        [int]$MaximumUptimeDays = 30,

        [switch]$IncludeSoftware,

        [switch]$NoProgress
    )

    $null = Test-EFWindows -Throw
    $inventory = Get-EFEndpointInventory -IncludeSoftware:$IncludeSoftware -NoProgress:$NoProgress
    $pendingReboot = Get-EFPendingReboot
    $checks = [Collections.Generic.List[object]]::new()

    $freePercent = Get-EFPropertyValue -InputObject $inventory.SystemDrive -Name 'FreeSpacePercent'
    if ($null -eq $freePercent) {
        $checks.Add([pscustomobject]@{
            Id = 'DiskFreeSpace'; Severity = 'Information'; Status = 'Unknown'
            Message = 'System drive free space could not be collected.'
            ActualValue = $null; Threshold = $MinimumFreeSpacePercent
        })
    }
    elseif ([double]$freePercent -lt $MinimumFreeSpacePercent) {
        $severity = if ([double]$freePercent -lt [math]::Max(5, $MinimumFreeSpacePercent / 2)) { 'Critical' } else { 'Warning' }
        $checks.Add([pscustomobject]@{
            Id = 'DiskFreeSpace'; Severity = $severity; Status = 'Unhealthy'
            Message = "System drive free space is $freePercent%; threshold is $MinimumFreeSpacePercent%."
            ActualValue = $freePercent; Threshold = $MinimumFreeSpacePercent
        })
    }
    else {
        $checks.Add([pscustomobject]@{
            Id = 'DiskFreeSpace'; Severity = 'Information'; Status = 'Healthy'
            Message = 'System drive free space is within threshold.'
            ActualValue = $freePercent; Threshold = $MinimumFreeSpacePercent
        })
    }

    $uptimeDays = Get-EFPropertyValue -InputObject $inventory.OperatingSystem -Name 'UptimeDays'
    if ($null -eq $uptimeDays) {
        $checks.Add([pscustomobject]@{
            Id = 'Uptime'; Severity = 'Information'; Status = 'Unknown'
            Message = 'Endpoint uptime could not be collected.'
            ActualValue = $null; Threshold = $MaximumUptimeDays
        })
    }
    else {
        $uptimeHealthy = [double]$uptimeDays -le $MaximumUptimeDays
        $checks.Add([pscustomobject]@{
            Id = 'Uptime'; Severity = if ($uptimeHealthy) { 'Information' } else { 'Warning' }
            Status = if ($uptimeHealthy) { 'Healthy' } else { 'Unhealthy' }
            Message = if ($uptimeHealthy) { 'Endpoint uptime is within threshold.' } else { "Endpoint uptime is $uptimeDays days; threshold is $MaximumUptimeDays days." }
            ActualValue = $uptimeDays; Threshold = $MaximumUptimeDays
        })
    }

    $pendingRebootErrorCount = [int](Get-EFPropertyValue -InputObject $pendingReboot -Name 'ErrorCount' -Default 0)
    $checks.Add([pscustomobject]@{
        Id = 'PendingReboot'
        Severity = if ($pendingReboot.IsRebootPending -or $pendingRebootErrorCount -gt 0) { 'Warning' } else { 'Information' }
        Status = if ($pendingReboot.IsRebootPending) { 'Unhealthy' } elseif ($pendingRebootErrorCount -gt 0) { 'Unknown' } else { 'Healthy' }
        Message = if ($pendingReboot.IsRebootPending -and $pendingRebootErrorCount -gt 0) {
            'Windows confirmed that a restart is pending, although it could not read every other restart indicator.'
        }
        elseif ($pendingRebootErrorCount -gt 0) {
            'Windows could not read every pending-restart indicator, so EndpointForge did not assume that no restart is needed.'
        }
        elseif ($pendingReboot.IsRebootPending) { "Restart pending: $($pendingReboot.Reasons -join ', ')." }
        else { 'No pending restart was detected.' }
        ActualValue = if ($pendingReboot.IsRebootPending) { $true } elseif ($pendingRebootErrorCount -gt 0) { $null } else { $false }
        Threshold = $false
    })

    foreach ($firewallProfile in @($inventory.Security.Firewall)) {
        $enabled = [bool](Get-EFPropertyValue -InputObject $firewallProfile -Name 'Enabled')
        $profileName = [string](Get-EFPropertyValue -InputObject $firewallProfile -Name 'Name')
        $checks.Add([pscustomobject]@{
            Id = "Firewall$profileName"; Severity = if ($enabled) { 'Information' } else { 'Critical' }
            Status = if ($enabled) { 'Healthy' } else { 'Unhealthy' }
            Message = if ($enabled) { "$profileName firewall profile is enabled." } else { "$profileName firewall profile is disabled." }
            ActualValue = $enabled; Threshold = $true
        })
    }

    $defender = $inventory.Security.Defender
    if ($null -ne $defender) {
        $realtimeEnabled = [bool](Get-EFPropertyValue -InputObject $defender -Name 'RealTimeProtectionEnabled')
        $checks.Add([pscustomobject]@{
            Id = 'DefenderRealTimeProtection'; Severity = if ($realtimeEnabled) { 'Information' } else { 'Critical' }
            Status = if ($realtimeEnabled) { 'Healthy' } else { 'Unhealthy' }
            Message = if ($realtimeEnabled) { 'Microsoft Defender real-time protection is enabled.' } else { 'Microsoft Defender real-time protection is disabled.' }
            ActualValue = $realtimeEnabled; Threshold = $true
        })
    }

    $bitLocker = $inventory.Security.BitLocker
    if ($null -ne $bitLocker) {
        $protected = [string](Get-EFPropertyValue -InputObject $bitLocker -Name 'ProtectionStatus') -eq 'On'
        $checks.Add([pscustomobject]@{
            Id = 'BitLockerProtection'; Severity = if ($protected) { 'Information' } else { 'Warning' }
            Status = if ($protected) { 'Healthy' } else { 'Unhealthy' }
            Message = if ($protected) { 'BitLocker protection is on for the system drive.' } else { 'BitLocker protection is not on for the system drive.' }
            ActualValue = Get-EFPropertyValue -InputObject $bitLocker -Name 'ProtectionStatus'; Threshold = 'On'
        })
    }

    foreach ($inventoryError in @($inventory.Errors)) {
        $checks.Add([pscustomobject]@{
            Id = 'InventoryCollection'; Severity = 'Information'; Status = 'Unknown'
            Message = [string]$inventoryError; ActualValue = $null; Threshold = $null
        })
    }

    $criticalCount = @($checks | Where-Object Severity -eq 'Critical').Count
    $warningCount = @($checks | Where-Object Severity -eq 'Warning').Count
    $unknownCount = @($checks | Where-Object Status -eq 'Unknown').Count
    $knownCount = $checks.Count - $unknownCount
    $coveragePercent = if ($checks.Count -eq 0) { 0 } else { [math]::Round(($knownCount / $checks.Count) * 100, 1) }
    $dataStatus = if ($unknownCount -eq 0) { 'Complete' } elseif ($knownCount -eq 0) { 'Failed' } else { 'Partial' }
    $status = if ($criticalCount -gt 0) { 'Critical' } elseif ($warningCount -gt 0) { 'Warning' } else { 'Healthy' }
    $exitCode = if ($criticalCount -gt 0) { 2 } elseif ($warningCount -gt 0) { 1 } else { 0 }
    $score = [math]::Max(0, 100 - ($criticalCount * 25) - ($warningCount * 10))
    $summaryText = switch ($status) {
        'Healthy' { 'No operational health issues were detected.' }
        'Warning' { "$warningCount warning(s) require attention." }
        'Critical' { "$criticalCount critical issue(s) and $warningCount warning(s) require attention." }
    }
    $nextStep = if ($status -eq 'Healthy') {
        'Run Get-EFEndpointSummary for one plain-language health and Windows settings checkup.'
    }
    else {
        'Review the Checks property or run Show-EFEndpointSummary -Detailed.'
    }

    [pscustomobject]@{
        PSTypeName      = 'EndpointForge.EndpointHealth'
        ComputerName    = $env:COMPUTERNAME
        CheckedAtUtc    = [DateTime]::UtcNow
        Status          = $status
        Score           = $score
        ExitCode        = $exitCode
        Summary         = $summaryText
        NextStep        = $nextStep
        CriticalCount   = $criticalCount
        WarningCount    = $warningCount
        UnknownCount    = $unknownCount
        DataStatus      = $dataStatus
        CoveragePercent = $coveragePercent
        CollectionErrors = @($inventory.Errors)
        Checks          = @($checks)
        Inventory       = $inventory
        PendingReboot   = $pendingReboot
    }
}
