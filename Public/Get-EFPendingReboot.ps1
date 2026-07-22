function Get-EFPendingReboot {
    <#
    .SYNOPSIS
    Determines whether Windows reports a pending restart.

    .DESCRIPTION
    Checks servicing, Windows Update, file rename, installer, and computer rename
    indicators. The command is read-only and returns the individual reasons.

    .EXAMPLE
    $reboot = Get-EFPendingReboot
    if ($reboot.IsRebootPending) { $reboot.Reasons }
    #>
    [CmdletBinding()]
    param()

    $null = Test-EFWindows -Throw
    $indicators = [ordered]@{
        ComponentBasedServicing = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        WindowsUpdate           = Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        PendingFileRename       = $false
        UpdateExeVolatile       = $false
        PendingComputerRename   = $false
    }

    try {
        $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations -ErrorAction Stop
        $indicators.PendingFileRename = @($sessionManager.PendingFileRenameOperations).Count -gt 0
    }
    catch { Write-Verbose "Pending file rename indicator is absent or unavailable: $($_.Exception.Message)" }

    try {
        $volatile = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Updates' -Name UpdateExeVolatile -ErrorAction Stop
        $indicators.UpdateExeVolatile = [int]$volatile -ne 0
    }
    catch { Write-Verbose "UpdateExeVolatile indicator is absent or unavailable: $($_.Exception.Message)" }

    try {
        $activeName = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop
        $configuredName = Get-ItemPropertyValue -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop
        $indicators.PendingComputerRename = -not [string]::Equals($activeName, $configuredName, [StringComparison]::OrdinalIgnoreCase)
    }
    catch { Write-Verbose "Computer rename indicator is unavailable: $($_.Exception.Message)" }

    $reasons = @($indicators.GetEnumerator() | Where-Object Value | ForEach-Object Key)
    $reasonSummary = if ($reasons.Count -eq 0) { 'None' } else { $reasons -join ', ' }
    [pscustomobject]@{
        PSTypeName       = 'EndpointForge.PendingReboot'
        ComputerName     = $env:COMPUTERNAME
        CheckedAtUtc     = [DateTime]::UtcNow
        IsRebootPending  = $reasons.Count -gt 0
        DetectionCount   = $reasons.Count
        ReasonSummary    = $reasonSummary
        Reasons          = $reasons
        Indicators       = [pscustomobject]$indicators
    }
}
