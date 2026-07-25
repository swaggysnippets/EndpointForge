function Get-EFFleetSummary {
    <#
    .SYNOPSIS
    Checks several Windows computers without changing them.

    .DESCRIPTION
    Runs the same EndpointForge computer checkup on each named computer and returns one
    combined result. This command never installs EndpointForge, turns on remote
    management, changes a Windows setting, or runs a fix. TcpPort, DnsResolution,
    HttpEndpointHealth, WindowsUpdateAvailable, and LocalGroupMembership can create
    observable activity from every remote computer and are blocked unless
    AllowNetworkChecks is supplied.

    Each remote computer must already allow PowerShell remoting and must already have
    a contract-compatible EndpointForge 0.8.0 or later installed. Your account must have
    permission to connect. EndpointForge 1.x requires a 1.x remote module and summary
    schema 1.0 so incompatible results cannot be presented as trustworthy.
    These requirements are intentionally not changed for you.

    EndpointForge calls its list of expected settings and everyday checks a baseline in
    scripts. In the menu and documentation, that is described simply as a checklist.
    Matching log lines, event messages, and event data are not included in fleet results.

    .PARAMETER ComputerName
    One through 256 computer names to check. Duplicate names are checked once. Names must
    be exact host names or IP addresses; wildcards and paths are not accepted.

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
    Allows the five network-active types after every destination, requested account
    identity, purpose, update-scan option, and source computer has been reviewed. Each
    remote computer performs its own activity. Contacted services, identity providers,
    firewalls, proxies, and monitoring tools may record it. This acknowledgement does not
    grant network authorization.

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

    Explicitly allows the reviewed network-active checks from each remote computer.

    .OUTPUTS
    EndpointForge.FleetSummary

    .LINK
    Get-EFEndpointSummary
    #>
    [CmdletBinding()]
    [OutputType('EndpointForge.FleetSummary')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [Parameter(Position = 1)]
        [AllowNull()]
        [object]$Baseline = 'EnterpriseRecommended',

        [pscredential]$Credential,

        [ValidateRange(1, 64)]
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
        $parsedAddress = $null
        $isIpAddress = [Net.IPAddress]::TryParse($trimmedName, [ref]$parsedAddress)
        $hostLabels = @($trimmedName -split '\.')
        $isHostName = $trimmedName.Length -le 253 -and
            $hostLabels.Count -gt 0 -and
            @($hostLabels | Where-Object {
                $_.Length -lt 1 -or $_.Length -gt 63 -or
                $_ -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$'
            }).Count -eq 0
        if ((-not $isIpAddress -and -not $isHostName) -or
            [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($trimmedName)) {
            throw [System.ArgumentException]::new(
                "ComputerName '$trimmedName' must be one exact host name or IP address no longer than 255 characters, without whitespace, a path, or wildcard."
            )
        }
        if ($seenTargets.Add($trimmedName)) {
            $targets.Add($trimmedName)
        }
    }
    if ($targets.Count -eq 0) {
        throw [System.ArgumentException]::new('Provide at least one computer name.')
    }
    if ($targets.Count -gt 256) {
        throw [System.ArgumentException]::new(
            'A fleet check is limited to 256 unique computers. Split a larger inventory into reviewed batches.'
        )
    }

    $resolvedBaseline = Resolve-EFBaseline -Baseline $Baseline
    $localModuleVersion = [version]$MyInvocation.MyCommand.Module.Version
    $requiredContractMajor = $localModuleVersion.Major
    $fleetBaselineProperties = [ordered]@{}
    if (Test-EFPropertyPresent -InputObject $resolvedBaseline -Name '$schema') {
        $fleetBaselineProperties['$schema'] = Get-EFPropertyValue -InputObject $resolvedBaseline -Name '$schema'
    }
    $fleetBaselineProperties.FormatVersion = [string](
        Get-EFPropertyValue -InputObject $resolvedBaseline -Name 'FormatVersion' -Default '1.0'
    )
    $fleetBaselineProperties.Name = [string]$resolvedBaseline.Name
    $fleetBaselineProperties.Version = [string]$resolvedBaseline.Version
    $fleetBaselineProperties.Description = [string]$resolvedBaseline.Description
    $fleetBaselineProperties.Controls = @($resolvedBaseline.Controls)
    $fleetBaseline = [pscustomobject]$fleetBaselineProperties
    $networkControls = @($resolvedBaseline.Controls | Where-Object { Test-EFControlUsesNetwork -Control $_ })
    if ($networkControls.Count -gt 0 -and -not $AllowNetworkChecks) {
        $networkTypes = @($networkControls.Type | Sort-Object -Unique) -join ', '
        throw [System.InvalidOperationException]::new(
            "This checklist contains $($networkControls.Count) network-active check(s): $networkTypes. " +
            "Across $($targets.Count) computer(s), that activity would originate from every remote computer and may be recorded. " +
            'Review the checklist, then add -AllowNetworkChecks to permit them.'
        )
    }
    $startedAtUtc = [DateTime]::UtcNow
    $remoteScript = {
        param(
            $Checklist,
            $CollectSoftware,
            $FreeSpaceThreshold,
            $UptimeThreshold,
            $PermitNetworkChecks,
            $ExpectedContractMajor
        )

        $remoteModule = Import-Module EndpointForge -MinimumVersion 0.8.0 -Force -PassThru -ErrorAction Stop
        if ([int]$ExpectedContractMajor -ge 1 -and $remoteModule.Version.Major -ne [int]$ExpectedContractMajor) {
            throw "Remote EndpointForge $($remoteModule.Version) is not compatible with the required $ExpectedContractMajor.x contract."
        }
        $parameters = @{
            Baseline                = $Checklist
            IncludeSoftware         = [bool]$CollectSoftware
            MinimumFreeSpacePercent = [int]$FreeSpaceThreshold
            MaximumUptimeDays       = [int]$UptimeThreshold
            NoProgress              = $true
            AllowNetworkChecks      = [bool]$PermitNetworkChecks
        }
        $checkup = Get-EFEndpointSummary @parameters
        $summarySchemaVersion = [string]$checkup.SchemaVersion
        if ([int]$ExpectedContractMajor -ge 1 -and $summarySchemaVersion -ne '1.0') {
            throw "Remote EndpointForge returned summary schema '$summarySchemaVersion'; schema 1.0 is required."
        }
        [pscustomobject]@{
            RemoteComputerName  = $env:COMPUTERNAME
            RemoteModuleVersion = $remoteModule.Version.ToString()
            SummarySchemaVersion = $summarySchemaVersion
            Checkup             = $checkup
        }
    }

    $invokeParameters = @{
        ComputerName  = $targets.ToArray()
        ScriptBlock   = $remoteScript
        ArgumentList  = @(
            $fleetBaseline,
            [bool]$IncludeSoftware,
            $MinimumFreeSpacePercent,
            $MaximumUptimeDays,
            [bool]$AllowNetworkChecks,
            $requiredContractMajor
        )
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
            RemoteModuleVersion   = [string](Get-EFPropertyValue -InputObject $response -Name 'RemoteModuleVersion' -Default 'NotReported')
            SummarySchemaVersion  = [string](Get-EFPropertyValue -InputObject $response -Name 'SummarySchemaVersion' -Default (
                Get-EFPropertyValue -InputObject $checkup -Name 'SchemaVersion' -Default 'NotReported'
            ))
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
                'The computer did not return a compatible checkup. Confirm its name, network access, PowerShell remoting permission, and that a contract-compatible EndpointForge 0.8.0 or later is already installed there.'
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
