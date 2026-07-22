function Get-EFFleetSummary {
    <#
    .SYNOPSIS
    Checks several Windows computers without changing them.

    .DESCRIPTION
    Runs the same EndpointForge computer checkup on each named computer and returns one
    combined result. This command never installs EndpointForge, turns on remote
    management, changes a Windows setting, or runs a fix. A checklist containing TCP port
    checks can make observable network connections from every remote computer and is
    blocked unless AllowNetworkChecks is explicitly supplied.

    Each remote computer must already allow PowerShell remoting and must already have
    EndpointForge 0.5.0 or later installed. Your account must have permission to connect.
    These requirements are intentionally not changed for you.

    EndpointForge calls its list of expected settings and everyday checks a baseline in
    scripts. In the menu and documentation, that is described simply as a checklist.
    Matching log lines, event messages, and event data are not included in fleet results.

    .PARAMETER ComputerName
    One or more computer names to check. Duplicate names are checked once.

    .PARAMETER Baseline
    The checklist to use. Supply the built-in checklist name, a checklist JSON file, or a
    checklist object. The default is EnterpriseRecommended.

    .PARAMETER Credential
    An optional account that already has permission to connect. The credential is used
    only for the remote connection and is not included in the returned report.

    .PARAMETER ThrottleLimit
    The largest number of remote checks that may run at the same time.

    .PARAMETER IncludeSoftware
    Also collects installed-software details. This makes the report larger and can take
    longer. It still does not change a computer.

    .PARAMETER AllowNetworkChecks
    Allows checklist items that make one TCP connection attempt to a named host and port.
    In a fleet run, each remote computer makes its own attempt. Destinations, firewalls,
    and monitoring tools may record it. No application data is sent.

    .PARAMETER MinimumFreeSpacePercent
    The system-drive free-space level that should produce a warning.

    .PARAMETER MaximumUptimeDays
    The number of days running without a restart that should produce a warning.

    .EXAMPLE
    Get-EFFleetSummary -ComputerName PC-101,PC-102

    Checks two computers with the built-in checklist and returns one combined result.

    .EXAMPLE
    Get-EFFleetSummary -ComputerName (Get-Content .\computers.txt) -Credential (Get-Credential)

    Checks names from a text file using an account that already has remote access.

    .EXAMPLE
    Get-EFFleetSummary -ComputerName PC-101,PC-102 -Baseline .\Contoso.EverydayChecks.json -AllowNetworkChecks

    Explicitly allows the named TCP checks to run once from each remote computer.

    .OUTPUTS
    EndpointForge.FleetSummary

    .LINK
    Get-EFEndpointSummary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [Parameter(Position = 1)]
        [AllowNull()]
        [object]$Baseline = 'EnterpriseRecommended',

        [pscredential]$Credential,

        [ValidateRange(1, 128)]
        [int]$ThrottleLimit = 16,

        [switch]$IncludeSoftware,

        [switch]$AllowNetworkChecks,

        [ValidateRange(1, 99)]
        [int]$MinimumFreeSpacePercent = 15,

        [ValidateRange(1, 3650)]
        [int]$MaximumUptimeDays = 30
    )

    $targets = [Collections.Generic.List[string]]::new()
    $seenTargets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $ComputerName) {
        $trimmedName = [string]$name
        if ($null -ne $trimmedName) { $trimmedName = $trimmedName.Trim() }
        if ([string]::IsNullOrWhiteSpace($trimmedName)) {
            throw [System.ArgumentException]::new('ComputerName cannot contain an empty value.')
        }
        if ($seenTargets.Add($trimmedName)) {
            $targets.Add($trimmedName)
        }
    }
    if ($targets.Count -eq 0) {
        throw [System.ArgumentException]::new('Provide at least one computer name.')
    }

    $resolvedBaseline = Resolve-EFBaseline -Baseline $Baseline
    $networkControls = @($resolvedBaseline.Controls | Where-Object Type -eq 'TcpPort')
    if ($networkControls.Count -gt 0 -and -not $AllowNetworkChecks) {
        $destinationCount = @($networkControls | ForEach-Object {
            '{0}:{1}' -f $_.HostName, $_.Port
        } | Select-Object -Unique).Count
        throw [System.InvalidOperationException]::new(
            "This checklist contains $($networkControls.Count) TCP connection check(s) for $destinationCount destination(s). " +
            "Across $($targets.Count) computer(s), those attempts would originate from every remote computer and may be recorded. " +
            'Review the checklist, then add -AllowNetworkChecks to permit them.'
        )
    }
    $startedAtUtc = [DateTime]::UtcNow
    $remoteScript = {
        param($Checklist, $CollectSoftware, $FreeSpaceThreshold, $UptimeThreshold)

        Import-Module EndpointForge -MinimumVersion 0.5.0 -Force -ErrorAction Stop
        $parameters = @{
            Baseline                = $Checklist
            IncludeSoftware         = [bool]$CollectSoftware
            MinimumFreeSpacePercent = [int]$FreeSpaceThreshold
            MaximumUptimeDays       = [int]$UptimeThreshold
            NoProgress              = $true
        }
        $checkup = Get-EFEndpointSummary @parameters
        [pscustomobject]@{
            RemoteComputerName = $env:COMPUTERNAME
            Checkup            = $checkup
        }
    }

    $invokeParameters = @{
        ComputerName  = $targets.ToArray()
        ScriptBlock   = $remoteScript
        ArgumentList  = @($resolvedBaseline, [bool]$IncludeSoftware, $MinimumFreeSpacePercent, $MaximumUptimeDays)
        ThrottleLimit = $ThrottleLimit
        ErrorAction   = 'SilentlyContinue'
        ErrorVariable = 'fleetRemoteErrors'
    }
    if ($PSBoundParameters.ContainsKey('Credential')) {
        $invokeParameters.Credential = $Credential
    }

    $fleetRemoteErrors = @()
    $responses = @()
    try {
        $responses = @(Invoke-Command @invokeParameters)
    }
    catch {
        $fleetRemoteErrors += $_
    }

    $resultList = [Collections.Generic.List[object]]::new()
    $completedTargets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($response in $responses) {
        if ($null -eq $response) { continue }
        $remoteTarget = [string](Get-EFPropertyValue -InputObject $response -Name 'PSComputerName' -Default '')
        if ([string]::IsNullOrWhiteSpace($remoteTarget)) {
            $remoteTarget = [string](Get-EFPropertyValue -InputObject $response -Name 'RemoteComputerName' -Default '')
        }
        $checkup = Get-EFPropertyValue -InputObject $response -Name 'Checkup'
        if ($null -eq $checkup) { continue }

        $requestedTarget = @($targets | Where-Object { $_ -ieq $remoteTarget } | Select-Object -First 1)
        if ($requestedTarget.Count -eq 0) { $requestedTarget = @($remoteTarget) }
        $requestedName = [string]$requestedTarget[0]
        if (-not [string]::IsNullOrWhiteSpace($requestedName)) {
            $null = $completedTargets.Add($requestedName)
        }
        $resultList.Add([pscustomobject]@{
            PSTypeName            = 'EndpointForge.FleetComputerResult'
            RequestedComputerName = $requestedName
            ComputerName          = [string](Get-EFPropertyValue -InputObject $checkup -Name 'ComputerName' -Default $remoteTarget)
            OverallStatus         = [string](Get-EFPropertyValue -InputObject $checkup -Name 'OverallStatus' -Default 'Incomplete')
            Score                 = Get-EFPropertyValue -InputObject $checkup -Name 'Score'
            IssueCount            = [int](Get-EFPropertyValue -InputObject $checkup -Name 'IssueCount' -Default 0)
            UnknownCount          = [int](Get-EFPropertyValue -InputObject $checkup -Name 'UnknownCount' -Default 0)
            CompletedAtUtc        = Get-EFPropertyValue -InputObject $checkup -Name 'CompletedAtUtc'
            NextStep              = [string](Get-EFPropertyValue -InputObject $checkup -Name 'NextStep' -Default '')
            Checkup               = $checkup
        })
    }

    $failureList = [Collections.Generic.List[object]]::new()
    foreach ($target in $targets) {
        if ($completedTargets.Contains($target)) { continue }

        $matchingErrors = @($fleetRemoteErrors | Where-Object {
            $errorTarget = ''
            if ($null -ne $_.OriginInfo) { $errorTarget = [string]$_.OriginInfo.PSComputerName }
            if ([string]::IsNullOrWhiteSpace($errorTarget)) { $errorTarget = [string]$_.TargetObject }
            $errorTarget -ieq $target -or [string]$_.Exception.Message -match [regex]::Escape($target)
        })
        $message = if ($matchingErrors.Count -gt 0) {
            [string]$matchingErrors[0].Exception.Message
        }
        else {
            'The computer did not return a checkup. Confirm its name, network access, PowerShell remoting permission, and that EndpointForge 0.5.0 or later is already installed there.'
        }
        $failureList.Add([pscustomobject]@{
            PSTypeName   = 'EndpointForge.FleetFailure'
            ComputerName = [string]$target
            Message      = $message
        })
    }

    $healthyCount = @($resultList | Where-Object OverallStatus -eq 'Healthy').Count
    $warningCount = @($resultList | Where-Object OverallStatus -eq 'Warning').Count
    $criticalCount = @($resultList | Where-Object OverallStatus -eq 'Critical').Count
    $incompleteCount = @($resultList | Where-Object OverallStatus -eq 'Incomplete').Count
    $failedCount = $failureList.Count
    $exitCode = if ($failedCount -gt 0 -or $incompleteCount -gt 0) {
        3
    }
    elseif ($criticalCount -gt 0) {
        2
    }
    elseif ($warningCount -gt 0) {
        1
    }
    else {
        0
    }
    $summary = if ($failedCount -gt 0) {
        "$($resultList.Count) of $($targets.Count) computer(s) were checked; $failedCount could not be checked."
    }
    elseif ($criticalCount -gt 0) {
        "All $($targets.Count) computer(s) were checked; $criticalCount need urgent attention."
    }
    elseif ($warningCount -gt 0 -or $incompleteCount -gt 0) {
        "All $($targets.Count) computer(s) were checked; some results need attention or were incomplete."
    }
    else {
        "All $($targets.Count) computer(s) were checked and look good."
    }
    $nextStep = if ($failedCount -gt 0) {
        'Review Failures. EndpointForge will not turn on remote access or install itself on another computer.'
    }
    elseif ($criticalCount -gt 0 -or $warningCount -gt 0) {
        'Review Results, then check an affected computer directly before approving any fixes.'
    }
    elseif ($incompleteCount -gt 0) {
        'Review incomplete results and permissions, then run the check again.'
    }
    else {
        'No action is required.'
    }

    [pscustomobject]@{
        PSTypeName       = 'EndpointForge.FleetSummary'
        SchemaVersion    = '1.0'
        ChecklistName    = [string]$resolvedBaseline.Name
        BaselineName     = [string]$resolvedBaseline.Name
        BaselineVersion  = [string]$resolvedBaseline.Version
        NetworkCheckCount = $networkControls.Count
        NetworkChecksAllowed = [bool]$AllowNetworkChecks
        StartedAtUtc     = $startedAtUtc
        CompletedAtUtc   = [DateTime]::UtcNow
        TargetCount      = $targets.Count
        SucceededCount   = $resultList.Count
        FailedCount      = $failedCount
        HealthyCount     = $healthyCount
        WarningCount     = $warningCount
        CriticalCount    = $criticalCount
        IncompleteCount  = $incompleteCount
        IsComplete       = $failedCount -eq 0 -and $incompleteCount -eq 0
        ExitCode          = $exitCode
        Summary           = $summary
        NextStep          = $nextStep
        Results           = $resultList.ToArray()
        Failures          = $failureList.ToArray()
    }
}
