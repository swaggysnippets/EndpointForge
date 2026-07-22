function Get-EFControlState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Control,

        [hashtable]$EvaluationContext
    )

    $type = [string](Get-EFPropertyValue -InputObject $Control -Name 'Type')
    $desiredValue = Get-EFPropertyValue -InputObject $Control -Name 'DesiredValue'
    if ($null -eq $EvaluationContext) {
        $EvaluationContext = @{
            AllowNetworkChecks = $false
            Cache              = @{}
        }
    }
    if (-not $EvaluationContext.ContainsKey('Cache') -or $null -eq $EvaluationContext.Cache) {
        $EvaluationContext.Cache = @{}
    }
    $allowNetworkChecks = $EvaluationContext.ContainsKey('AllowNetworkChecks') -and
        [bool]$EvaluationContext.AllowNetworkChecks
    $evaluationCache = [hashtable]$EvaluationContext.Cache

    try {
        switch ($type) {
            'Registry' {
                $path = [string](Get-EFPropertyValue -InputObject $Control -Name 'Path')
                $valueName = [string](Get-EFPropertyValue -InputObject $Control -Name 'ValueName')

                if (-not (Test-Path -LiteralPath $path)) {
                    return New-EFControlResult -Control $Control -Status NonCompliant -ActualValue $null `
                        -DesiredValue $desiredValue -Message "Registry path '$path' does not exist."
                }

                $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
                $property = $item.PSObject.Properties[$valueName]
                if ($null -eq $property) {
                    return New-EFControlResult -Control $Control -Status NonCompliant -ActualValue $null `
                        -DesiredValue $desiredValue -Message "Registry value '$valueName' does not exist."
                }

                $actual = $property.Value
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message "Registry value '$path\$valueName' evaluated."
            }

            'Service' {
                $name = [string](Get-EFPropertyValue -InputObject $Control -Name 'Name')
                $service = Get-Service -Name $name -ErrorAction SilentlyContinue
                if ($null -eq $service) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message "Service '$name' is not installed."
                }

                $startupType = Get-EFPropertyValue -InputObject $service -Name 'StartType'
                if ($null -eq $startupType) {
                    $escapedName = $name.Replace("'", "''")
                    $cimService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$escapedName'" -ErrorAction Stop
                    $startupType = switch ([string]$cimService.StartMode) {
                        'Auto' { 'Automatic' }
                        default { [string]$cimService.StartMode }
                    }
                }

                $desiredStartupType = [string](Get-EFPropertyValue -InputObject $Control -Name 'StartupType')
                $desiredStatus = [string](Get-EFPropertyValue -InputObject $Control -Name 'Status')
                $startupMatches = [string]::IsNullOrWhiteSpace($desiredStartupType) -or
                    (Test-EFValueEqual -Actual ([string]$startupType) -Desired $desiredStartupType)
                $statusMatches = [string]::IsNullOrWhiteSpace($desiredStatus) -or
                    (Test-EFValueEqual -Actual ([string]$service.Status) -Desired $desiredStatus)

                $actual = [ordered]@{
                    StartupType = [string]$startupType
                    Status      = [string]$service.Status
                }
                $desired = [ordered]@{
                    StartupType = $desiredStartupType
                    Status      = $desiredStatus
                }
                $resultStatus = if ($startupMatches -and $statusMatches) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $resultStatus -ActualValue $actual `
                    -DesiredValue $desired -Message "Service '$name' evaluated."
            }

            'FirewallProfile' {
                if ($null -eq (Get-Command -Name Get-NetFirewallProfile -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Windows Firewall cmdlets are unavailable.'
                }

                $name = [string](Get-EFPropertyValue -InputObject $Control -Name 'Name')
                $firewallProfile = Get-NetFirewallProfile -Name $name -ErrorAction Stop
                $actual = [bool]$firewallProfile.Enabled
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message "Firewall profile '$name' evaluated."
            }

            'Defender' {
                if ($null -eq (Get-Command -Name Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Microsoft Defender cmdlets are unavailable.'
                }

                $propertyName = [string](Get-EFPropertyValue -InputObject $Control -Name 'Property')
                $defender = Get-MpComputerStatus -ErrorAction Stop
                $property = $defender.PSObject.Properties[$propertyName]
                if ($null -eq $property) {
                    throw "Microsoft Defender does not expose property '$propertyName'."
                }
                $actual = $property.Value
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message "Microsoft Defender property '$propertyName' evaluated."
            }

            'WindowsOptionalFeature' {
                if ($null -eq (Get-Command -Name Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Windows optional feature cmdlets are unavailable.'
                }

                $name = [string](Get-EFPropertyValue -InputObject $Control -Name 'Name')
                $feature = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction SilentlyContinue
                if ($null -eq $feature) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message "Windows optional feature '$name' is unavailable."
                }
                $actual = [string]$feature.State
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message "Windows optional feature '$name' evaluated."
            }

            'PendingRestart' {
                $pendingRestart = Get-EFPendingReboot
                $actual = [bool]$pendingRestart.IsRebootPending
                if (-not $actual -and
                    [int](Get-EFPropertyValue -InputObject $pendingRestart -Name 'ErrorCount' -Default 0) -gt 0) {
                    throw 'Windows could not read every restart indicator, so EndpointForge will not guess that no restart is needed.'
                }

                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $message = if ($actual) {
                    "Windows reports that a restart is pending ($($pendingRestart.DetectionCount) indicator(s))."
                }
                else {
                    'Windows does not report a pending restart.'
                }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message $message
            }

            'DiskSpace' {
                $drive = [Environment]::ExpandEnvironmentVariables(
                    [string](Get-EFPropertyValue -InputObject $Control -Name 'Drive' -Default '%SystemDrive%')
                ).TrimEnd([char]'\')
                $minimumFreePercent = Get-EFPropertyValue -InputObject $Control -Name 'MinimumFreePercent'
                $minimumFreeGB = Get-EFPropertyValue -InputObject $Control -Name 'MinimumFreeGB'
                $escapedDrive = $drive.Replace("'", "''")
                $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$escapedDrive' AND DriveType=3" -ErrorAction Stop
                if ($null -eq $disk) {
                    throw "Windows did not find a fixed local drive named '$drive'."
                }
                if (-not (Test-EFPropertyPresent -InputObject $disk -Name 'Size') -or
                    -not (Test-EFPropertyPresent -InputObject $disk -Name 'FreeSpace') -or
                    $null -eq $disk.Size -or $null -eq $disk.FreeSpace) {
                    throw "Windows did not return complete capacity information for drive '$drive'."
                }
                if ([double]$disk.Size -le 0 -or [double]$disk.FreeSpace -lt 0 -or
                    [double]$disk.FreeSpace -gt [double]$disk.Size) {
                    throw "Windows did not return a usable size for drive '$drive'."
                }

                $freeGBExact = [double]$disk.FreeSpace / 1GB
                $freePercentExact = ([double]$disk.FreeSpace / [double]$disk.Size) * 100
                $freeGB = [math]::Round($freeGBExact, 2)
                $freePercent = [math]::Round($freePercentExact, 1)
                $meetsPercent = $null -eq $minimumFreePercent -or $freePercentExact -ge [double]$minimumFreePercent
                $meetsGB = $null -eq $minimumFreeGB -or $freeGBExact -ge [double]$minimumFreeGB
                $actual = $meetsPercent -and $meetsGB
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $requestedThresholds = @()
                if ($null -ne $minimumFreePercent) { $requestedThresholds += "$minimumFreePercent%" }
                if ($null -ne $minimumFreeGB) { $requestedThresholds += "$minimumFreeGB GB" }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message (
                        "Drive '$drive' has $freeGB GB free ($freePercent%); the checklist requires $($requestedThresholds -join ' and ')."
                    )
            }

            'WindowsUpdateAvailable' {
                if (-not $allowNetworkChecks) {
                    throw 'This item can contact the configured Windows Update or WSUS service. Review the checklist, then run it again with -AllowNetworkChecks.'
                }

                $includeOptional = [bool](Get-EFPropertyValue -InputObject $Control -Name 'IncludeOptional' -Default $false)
                $includeDrivers = [bool](Get-EFPropertyValue -InputObject $Control -Name 'IncludeDrivers' -Default $false)
                $timeoutSeconds = [int](Get-EFPropertyValue -InputObject $Control -Name 'TimeoutSeconds' -Default 120)
                $maximumCount = [int](Get-EFPropertyValue -InputObject $Control -Name 'MaximumCount' -Default 0)
                $cacheKey = "WindowsUpdateAvailable|$includeOptional|$includeDrivers"
                if (-not $evaluationCache.ContainsKey($cacheKey)) {
                    try {
                        $evaluationCache[$cacheKey] = Get-EFWindowsUpdateAvailability `
                            -TimeoutSeconds $timeoutSeconds -IncludeOptional:$includeOptional -IncludeDrivers:$includeDrivers
                    }
                    catch {
                        throw 'Windows Update could not complete a trustworthy availability check within the configured limit. No update or service details were included in the result.'
                    }
                }
                $updateCheck = $evaluationCache[$cacheKey]
                $updateCount = [int]$updateCheck.UpdateCount
                $actual = $updateCount -le $maximumCount
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message (
                        "The configured update service reported $updateCount waiting update(s); the checklist allows no more than $maximumCount. Update titles and metadata are not included in results, and nothing was downloaded or installed."
                    )
            }

            'InstalledApplication' {
                $applicationName = [string](Get-EFPropertyValue -InputObject $Control -Name 'ApplicationName')
                $publisher = [string](Get-EFPropertyValue -InputObject $Control -Name 'Publisher')
                $productCode = [string](Get-EFPropertyValue -InputObject $Control -Name 'ProductCode')
                $scope = [string](Get-EFPropertyValue -InputObject $Control -Name 'Scope' -Default 'Machine')
                $architecture = [string](Get-EFPropertyValue -InputObject $Control -Name 'Architecture' -Default 'All')
                $exactVersion = [string](Get-EFPropertyValue -InputObject $Control -Name 'ExactVersion')
                $minimumVersion = [string](Get-EFPropertyValue -InputObject $Control -Name 'MinimumVersion')
                $nativeArchitecture = if (-not [string]::IsNullOrWhiteSpace($env:PROCESSOR_ARCHITEW6432)) {
                    $env:PROCESSOR_ARCHITEW6432
                }
                else { $env:PROCESSOR_ARCHITECTURE }
                if ($nativeArchitecture -eq 'ARM64' -and $architecture -in @('x64', 'x86')) {
                    throw 'Architecture-specific application filtering is unavailable on Windows on Arm. Use Architecture All.'
                }
                $cacheKeyJson = @($scope, $architecture, $applicationName, $publisher, $productCode) |
                    ConvertTo-Json -Compress
                $cacheKey = 'InstalledApplication|' + [Convert]::ToBase64String(
                    [Text.Encoding]::UTF8.GetBytes($cacheKeyJson)
                )
                if (-not $evaluationCache.ContainsKey($cacheKey)) {
                    $evaluationCache[$cacheKey] = Get-EFInstalledApplicationEvidence -Scope $scope `
                        -ApplicationName $applicationName -Publisher $publisher -ProductCode $productCode `
                        -Architecture $architecture
                }
                $softwareEvidence = $evaluationCache[$cacheKey]
                if ([int]$softwareEvidence.ErrorCount -gt 0) {
                    throw 'Windows could not read every requested installed-application record, so EndpointForge will not guess.'
                }

                $applicationMatches = @($softwareEvidence.Entries | Where-Object {
                    [string]::Equals([string]$_.Name, $applicationName, [StringComparison]::OrdinalIgnoreCase) -and
                    ([string]::IsNullOrWhiteSpace($publisher) -or [string]::Equals([string]$_.Publisher, $publisher, [StringComparison]::OrdinalIgnoreCase)) -and
                    ([string]::IsNullOrWhiteSpace($productCode) -or [string]::Equals([string]$_.ProductCode, $productCode, [StringComparison]::OrdinalIgnoreCase)) -and
                    ($architecture -eq 'All' -or [string]$_.Architecture -eq $architecture)
                })

                $qualifyingMatches = @($applicationMatches)
                if (-not [string]::IsNullOrWhiteSpace($exactVersion)) {
                    $qualifyingMatches = @($applicationMatches | Where-Object {
                        [string]::Equals([string]$_.Version, $exactVersion, [StringComparison]::OrdinalIgnoreCase)
                    })
                    if ($qualifyingMatches.Count -eq 0 -and
                        @($applicationMatches | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Version) }).Count -gt 0) {
                        throw "The requested application is installed, but at least one matching record did not provide a version that can be compared with '$exactVersion'."
                    }
                }
                elseif (-not [string]::IsNullOrWhiteSpace($minimumVersion)) {
                    $requiredVersion = $null
                    if (-not [version]::TryParse($minimumVersion, [ref]$requiredVersion)) {
                        throw "MinimumVersion '$minimumVersion' is not a comparable Windows version."
                    }
                    $comparableApplicationMatches = [Collections.Generic.List[object]]::new()
                    $uncomparableVersionCount = 0
                    foreach ($applicationMatch in $applicationMatches) {
                        $installedVersion = $null
                        if ([version]::TryParse([string]$applicationMatch.Version, [ref]$installedVersion)) {
                            $comparableApplicationMatches.Add([pscustomobject]@{
                                Entry   = $applicationMatch
                                Version = $installedVersion
                            })
                        }
                        else {
                            $uncomparableVersionCount++
                        }
                    }
                    $qualifyingMatches = @($comparableApplicationMatches | Where-Object Version -ge $requiredVersion | ForEach-Object Entry)
                    if ($qualifyingMatches.Count -eq 0 -and $uncomparableVersionCount -gt 0) {
                        throw "The requested application is installed, but at least one matching record did not provide a version that can be compared with '$minimumVersion'."
                    }
                }

                $actual = $qualifyingMatches.Count -gt 0
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $versionDescription = if (-not [string]::IsNullOrWhiteSpace($exactVersion)) {
                    " at exact version '$exactVersion'"
                }
                elseif (-not [string]::IsNullOrWhiteSpace($minimumVersion)) {
                    " at version '$minimumVersion' or later"
                }
                else { '' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message (
                        "Found $($qualifyingMatches.Count) exact installed-application match(es) for '$applicationName'$versionDescription. Windows Installer consistency checks were not used."
                    )
            }

            'ScheduledTaskHealth' {
                if ($null -eq (Get-Command -Name Get-ScheduledTask -ErrorAction SilentlyContinue) -or
                    $null -eq (Get-Command -Name Get-ScheduledTaskInfo -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status Error -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Windows scheduled-task commands are unavailable, so this requested job could not be checked.'
                }
                $taskName = [string](Get-EFPropertyValue -InputObject $Control -Name 'TaskName')
                $taskPath = [string](Get-EFPropertyValue -InputObject $Control -Name 'TaskPath' -Default '\')
                $maximumAgeMinutes = [int](Get-EFPropertyValue -InputObject $Control -Name 'MaximumAgeMinutes')
                $expectedResult = [uint64](Get-EFPropertyValue -InputObject $Control -Name 'ExpectedLastTaskResult' -Default 0)
                $requireEnabled = [bool](Get-EFPropertyValue -InputObject $Control -Name 'RequireEnabled' -Default $true)
                try {
                    $tasks = @(Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop)
                }
                catch {
                    if ($_.FullyQualifiedErrorId -match '^CmdletizationQuery_NotFound(?:,Get-ScheduledTask)?$') {
                        $tasks = @()
                    }
                    else {
                        return New-EFControlResult -Control $Control -Status Error -ActualValue $null `
                            -DesiredValue $desiredValue -Message (
                                "Windows could not open the requested scheduled job '$taskPath$taskName'. Task actions, arguments, and provider details are not included in results."
                            )
                    }
                }

                if ($tasks.Count -eq 0) {
                    $actual = $false
                    $message = "The scheduled job '$taskPath$taskName' was not found."
                }
                elseif ($tasks.Count -gt 1) {
                    throw "Windows returned more than one scheduled job for the exact name '$taskPath$taskName'."
                }
                else {
                    $task = $tasks[0]
                    if (-not (Test-EFPropertyPresent -InputObject $task -Name 'State') -or
                        [string]::IsNullOrWhiteSpace([string]$task.State) -or [string]$task.State -eq 'Unknown') {
                        throw 'Windows did not return a trustworthy enabled state for the requested scheduled job.'
                    }
                    try {
                        $taskInfo = Get-ScheduledTaskInfo -InputObject $task -ErrorAction Stop
                    }
                    catch {
                        return New-EFControlResult -Control $Control -Status Error -ActualValue $null `
                            -DesiredValue $desiredValue -Message (
                                "Windows could not read health information for the requested scheduled job '$taskPath$taskName'. Task actions, arguments, and provider details are not included in results."
                            )
                    }
                    if (-not (Test-EFPropertyPresent -InputObject $taskInfo -Name 'LastRunTime') -or
                        -not (Test-EFPropertyPresent -InputObject $taskInfo -Name 'LastTaskResult') -or
                        $null -eq $taskInfo.LastRunTime -or $null -eq $taskInfo.LastTaskResult) {
                        throw 'Windows did not return complete last-run health information for the requested scheduled job.'
                    }
                    $isEnabled = [string]$task.State -ne 'Disabled'
                    $lastRunTime = [datetime]$taskInfo.LastRunTime
                    $rawTaskResult = [int64]$taskInfo.LastTaskResult
                    $taskResult = if ($rawTaskResult -lt 0) { [uint64](4294967296 + $rawTaskResult) } else { [uint64]$rawTaskResult }
                    $hasRun = $lastRunTime -ge [datetime]'2000-01-01' -and $taskResult -ne [uint64]267011
                    $lastRunTimeUtc = $lastRunTime.ToUniversalTime()
                    if ($hasRun -and $lastRunTimeUtc -gt [DateTime]::UtcNow.AddMinutes(5)) {
                        throw 'The scheduled job has a future last-run time, so its age cannot be trusted.'
                    }
                    $ageMinutesExact = if ($hasRun) {
                        [math]::Max(0.0, ([DateTime]::UtcNow - $lastRunTimeUtc).TotalMinutes)
                    }
                    else { $null }
                    $ageMinutes = if ($hasRun) { [math]::Round($ageMinutesExact, 1) } else { $null }
                    $resultMatches = $taskResult -eq $expectedResult
                    $ageMatches = $hasRun -and $ageMinutesExact -le $maximumAgeMinutes
                    $enabledMatches = -not $requireEnabled -or $isEnabled
                    $actual = $resultMatches -and $ageMatches -and $enabledMatches
                    $ageText = if ($hasRun) { "$ageMinutes minute(s) ago" } else { 'never' }
                    $message = "The scheduled job is $($task.State), last ran $ageText, and returned result $taskResult. Task actions and arguments are not included in results."
                }
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message $message
            }

            'DefenderSignatureHealth' {
                if ($null -eq (Get-Command -Name Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status Error -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Microsoft Defender status commands are unavailable, so threat-definition age could not be checked.'
                }
                if (-not $evaluationCache.ContainsKey('DefenderStatus')) {
                    try {
                        $evaluationCache.DefenderStatus = Get-MpComputerStatus -ErrorAction Stop
                    }
                    catch {
                        throw 'Microsoft Defender health information could not be read. Provider details were not included in the result.'
                    }
                }
                $defenderStatus = $evaluationCache.DefenderStatus
                $antivirusEnabled = Get-EFPropertyValue -InputObject $defenderStatus -Name 'AntivirusEnabled'
                $runningMode = [string](Get-EFPropertyValue -InputObject $defenderStatus -Name 'AMRunningMode')
                if ($null -eq $antivirusEnabled -or $antivirusEnabled -isnot [bool]) {
                    throw 'Microsoft Defender did not return a trustworthy active-antivirus state.'
                }
                if (-not [bool]$antivirusEnabled -or $runningMode -match 'Passive|EDR\s+Block') {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Microsoft Defender Antivirus is not the active antivirus provider on this computer.'
                }
                if (-not (Test-EFPropertyPresent -InputObject $defenderStatus -Name 'AntivirusSignatureAge') -or
                    $null -eq $defenderStatus.AntivirusSignatureAge) {
                    throw 'Microsoft Defender did not return the age of its threat definitions.'
                }

                $maximumAgeDays = [int](Get-EFPropertyValue -InputObject $Control -Name 'MaximumAgeDays' -Default 7)
                $signatureAge = [long]0
                if (-not [long]::TryParse([string]$defenderStatus.AntivirusSignatureAge, [ref]$signatureAge) -or
                    $signatureAge -lt 0) {
                    throw 'Microsoft Defender returned an invalid threat-definition age.'
                }
                $actual = $signatureAge -le $maximumAgeDays
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message (
                        "Microsoft Defender threat definitions are $signatureAge day(s) old; the checklist allows no more than $maximumAgeDays. EndpointForge did not refresh them."
                    )
            }

            'FileExists' {
                $path = Resolve-EFLocalFilePath -Path ([string](Get-EFPropertyValue -InputObject $Control -Name 'Path')) `
                    -CheckExistingAncestors
                try {
                    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                    $actual = -not [bool]$item.PSIsContainer
                    $message = if ($actual) {
                        "The requested file exists at '$path'."
                    }
                    else {
                        "A folder exists at '$path', but the checklist asks for a file."
                    }
                }
                catch [System.Management.Automation.ItemNotFoundException] {
                    $actual = $false
                    $message = "No file exists at '$path'."
                }

                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message $message
            }

            'FileContainsText' {
                $path = Resolve-EFLocalFilePath -Path ([string](Get-EFPropertyValue -InputObject $Control -Name 'Path')) `
                    -CheckExistingAncestors
                $text = [string](Get-EFPropertyValue -InputObject $Control -Name 'Text')
                $tailLines = [int](Get-EFPropertyValue -InputObject $Control -Name 'TailLines' -Default 2000)
                $caseSensitive = [bool](Get-EFPropertyValue -InputObject $Control -Name 'CaseSensitive' -Default $false)
                $encoding = [string](Get-EFPropertyValue -InputObject $Control -Name 'Encoding' -Default 'Utf8')
                $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                if ([bool]$item.PSIsContainer) {
                    throw "The path '$path' is a folder. This checklist item requires a text file."
                }

                $beforeLength = [int64]$item.Length
                $beforeWriteTime = $item.LastWriteTimeUtc
                $tail = Read-EFBoundedTextTail -Path $path -TailLines $tailLines -Encoding $encoding
                $lines = @($tail.Lines)
                $afterItem = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                if ([int64]$afterItem.Length -ne $beforeLength -or $afterItem.LastWriteTimeUtc -ne $beforeWriteTime) {
                    throw "The text file '$path' changed while EndpointForge was reading it. Run the check again for a trustworthy answer."
                }

                $comparison = if ($caseSensitive) { [StringComparison]::Ordinal } else { [StringComparison]::OrdinalIgnoreCase }
                $found = $false
                foreach ($line in $lines) {
                    if (([string]$line).IndexOf($text, $comparison) -ge 0) {
                        $found = $true
                        break
                    }
                }

                $status = if (Test-EFValueEqual -Actual $found -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $finding = if ($found) { 'was found' } else { 'was not found' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $found `
                    -DesiredValue $desiredValue -Message (
                        "Checked up to the most recent $tailLines lines in '$path'; the requested text $finding. File contents are not included in the result."
                    )
            }

            'FileFreshness' {
                $path = Resolve-EFLocalFilePath -Path ([string](Get-EFPropertyValue -InputObject $Control -Name 'Path')) `
                    -CheckExistingAncestors
                $maximumAgeMinutes = [int](Get-EFPropertyValue -InputObject $Control -Name 'MaximumAgeMinutes')
                try {
                    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                }
                catch [System.Management.Automation.ItemNotFoundException] {
                    $item = $null
                }
                if ($null -eq $item) {
                    $actual = $false
                    $message = "No file exists at '$path'."
                }
                elseif ([bool]$item.PSIsContainer) {
                    throw "The path '$path' is a folder. This checklist item requires a file."
                }
                elseif ($item.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddMinutes(5)) {
                    throw "The file '$path' has a future modified time, so its age cannot be trusted."
                }
                else {
                    $ageMinutesExact = [math]::Max(0.0, ([DateTime]::UtcNow - $item.LastWriteTimeUtc).TotalMinutes)
                    $ageMinutes = [math]::Round($ageMinutesExact, 1)
                    $actual = $ageMinutesExact -le $maximumAgeMinutes
                    $message = "The file was updated $ageMinutes minute(s) ago; the checklist allows no more than $maximumAgeMinutes. File contents were not read."
                }
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message $message
            }

            'WindowsEvent' {
                if ($null -eq (Get-Command -Name Get-WinEvent -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status Error -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Windows event log commands are unavailable.'
                }

                $logName = [string](Get-EFPropertyValue -InputObject $Control -Name 'LogName')
                $eventIds = @((Get-EFPropertyValue -InputObject $Control -Name 'EventIds') | ForEach-Object { [int]$_ })
                $providerName = [string](Get-EFPropertyValue -InputObject $Control -Name 'ProviderName')
                $lookbackMinutes = [int](Get-EFPropertyValue -InputObject $Control -Name 'LookbackMinutes' -Default 60)
                $minimumCount = [int](Get-EFPropertyValue -InputObject $Control -Name 'MinimumCount' -Default 1)

                $eventLog = Get-WinEvent -ListLog $logName -ErrorAction Stop
                if ($null -eq $eventLog) {
                    throw "Windows did not return the event log '$logName'. Check the exact LogName."
                }
                if ((Test-EFPropertyPresent -InputObject $eventLog -Name 'IsEnabled') -and
                    -not [bool](Get-EFPropertyValue -InputObject $eventLog -Name 'IsEnabled')) {
                    throw "The Windows event log '$logName' is disabled, so it cannot provide trustworthy recent-event evidence."
                }
                $filter = @{
                    LogName  = $logName
                    Id       = [int[]]$eventIds
                    StartTime = [DateTime]::Now.AddMinutes(-$lookbackMinutes)
                }
                if (-not [string]::IsNullOrWhiteSpace($providerName)) {
                    $filter.ProviderName = $providerName
                }

                try {
                    $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $minimumCount -ErrorAction Stop)
                }
                catch {
                    if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*' -or
                        $_.Exception.Message -match '^No events were found') {
                        $events = @()
                    }
                    else {
                        throw
                    }
                }

                $actual = $events.Count -ge $minimumCount
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $providerDescription = if ([string]::IsNullOrWhiteSpace($providerName)) { '' } else { " from '$providerName'" }
                $countDescription = if ($events.Count -ge $minimumCount) {
                    "Found at least $($events.Count) matching event(s)"
                }
                else {
                    "Found $($events.Count) matching event(s)"
                }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message (
                        "$countDescription$providerDescription in '$logName' during the last $lookbackMinutes minute(s); at least $minimumCount were requested. Event messages are not included in the result."
                    )
            }

            'TcpPort' {
                if (-not $allowNetworkChecks) {
                    throw 'This item opens a TCP connection. Review the host and port, then run it again with -AllowNetworkChecks.'
                }
                $hostName = [string](Get-EFPropertyValue -InputObject $Control -Name 'HostName')
                $port = [int](Get-EFPropertyValue -InputObject $Control -Name 'Port')
                $timeoutMilliseconds = [int](Get-EFPropertyValue -InputObject $Control -Name 'TimeoutMilliseconds' -Default 3000)
                $probe = Test-EFTcpPort -HostName $hostName -Port $port -TimeoutMilliseconds $timeoutMilliseconds
                if ($probe.FailureReason -eq 'NameResolutionFailed') {
                    throw "The host name '$hostName' could not be resolved. Check the spelling and DNS configuration."
                }
                if ([bool]$probe.IsEvaluationError) {
                    throw "Windows could not complete the TCP port check for '$hostName' on port $port ($($probe.FailureReason))."
                }

                $actual = [bool]$probe.Connected
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $outcome = if ($actual) { 'accepted a TCP connection' } else { "did not accept a TCP connection ($($probe.FailureReason))" }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message (
                        "'$hostName' port $port $outcome within $timeoutMilliseconds millisecond(s). EndpointForge opened and closed one TCP connection without sending application data."
                    )
            }

            'DnsResolution' {
                if (-not $allowNetworkChecks) {
                    throw 'This item asks Windows to resolve a server name and may contact DNS. Review the checklist, then run it again with -AllowNetworkChecks.'
                }
                $hostName = [string](Get-EFPropertyValue -InputObject $Control -Name 'HostName')
                $timeoutMilliseconds = [int](Get-EFPropertyValue -InputObject $Control -Name 'TimeoutMilliseconds' -Default 3000)
                $probe = Test-EFDnsResolution -HostName $hostName -TimeoutMilliseconds $timeoutMilliseconds
                if ([bool]$probe.IsEvaluationError) {
                    throw "Windows could not complete the DNS check for '$hostName' ($($probe.FailureReason))."
                }
                $actual = [bool]$probe.Resolved
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $outcome = if ($actual) { 'was found' } else { 'was not found' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message (
                        "The absolute server name '$hostName' $outcome through Windows name resolution within $timeoutMilliseconds millisecond(s). Returned addresses are not included in results."
                    )
            }

            'HttpEndpointHealth' {
                if (-not $allowNetworkChecks) {
                    throw 'This item contacts a web address. Review the checklist, then run it again with -AllowNetworkChecks.'
                }
                $uriText = [string](Get-EFPropertyValue -InputObject $Control -Name 'Uri')
                $uri = [uri]$uriText
                $timeoutMilliseconds = [int](Get-EFPropertyValue -InputObject $Control -Name 'TimeoutMilliseconds' -Default 5000)
                $expectedStatusCode = [int](Get-EFPropertyValue -InputObject $Control -Name 'ExpectedStatusCode' -Default 200)
                $method = [string](Get-EFPropertyValue -InputObject $Control -Name 'Method' -Default 'Head')
                $allowRedirects = [bool](Get-EFPropertyValue -InputObject $Control -Name 'AllowRedirects' -Default $false)
                $probe = Test-EFHttpEndpoint -Uri $uri -TimeoutMilliseconds $timeoutMilliseconds `
                    -Method $method -AllowRedirects:$allowRedirects
                if ([bool]$probe.IsEvaluationError) {
                    throw "The web address could not provide a trustworthy response ($($probe.FailureReason))."
                }
                $responded = [bool]$probe.Responded
                $actual = $responded -and [int]$probe.StatusCode -eq $expectedStatusCode
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $message = if ($responded) {
                    "The web address returned HTTP status $([int]$probe.StatusCode); the checklist expects $expectedStatusCode. Response headers are not included in results, and the response body was not read."
                }
                else {
                    "The web address did not return an HTTP response within $timeoutMilliseconds millisecond(s) ($($probe.FailureReason)). No response body was read."
                }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message $message
            }

            'CertificateExpiry' {
                $storeLocation = [string](Get-EFPropertyValue -InputObject $Control -Name 'StoreLocation' -Default 'LocalMachine')
                $storeName = [string](Get-EFPropertyValue -InputObject $Control -Name 'StoreName' -Default 'My')
                $thumbprint = ([string](Get-EFPropertyValue -InputObject $Control -Name 'Thumbprint')).Replace(' ', '').ToUpperInvariant()
                $minimumDaysRemaining = [int](Get-EFPropertyValue -InputObject $Control -Name 'MinimumDaysRemaining' -Default 30)
                $certificateEvidence = Get-EFCertificateExpiryEvidence -StoreLocation $storeLocation `
                    -StoreName $storeName -Thumbprint $thumbprint -MinimumDaysRemaining $minimumDaysRemaining
                if (-not [bool]$certificateEvidence.Found) {
                    $actual = $false
                    $message = "The requested certificate was not found in $storeLocation\$storeName."
                }
                else {
                    $actual = [bool]$certificateEvidence.MeetsRequirement
                    $message = "The requested certificate has $($certificateEvidence.DaysRemaining) full day(s) remaining; the checklist requires at least $minimumDaysRemaining. Its subject, names, and private-key details are not included in results."
                }
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message $message
            }

            'ProcessRunning' {
                $configuredName = [string](Get-EFPropertyValue -InputObject $Control -Name 'ProcessName')
                $processName = if ($configuredName.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) {
                    $configuredName.Substring(0, $configuredName.Length - 4)
                }
                else { $configuredName }
                $processes = @()
                try {
                    $processes = @([Diagnostics.Process]::GetProcessesByName($processName))
                    $actual = $processes.Count -gt 0
                }
                finally {
                    foreach ($process in $processes) { $process.Dispose() }
                }
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $outcome = if ($actual) { 'is running' } else { 'is not running' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message (
                        "The program '$configuredName' $outcome. Process IDs and other process details are not included in results; command lines, owners, and loaded modules are not read."
                    )
            }

            'LocalGroupMembership' {
                if (-not $allowNetworkChecks) {
                    throw 'This item can ask Windows to resolve an account through a local or organizational identity provider. Review the group and account, then run it again with -AllowNetworkChecks.'
                }
                $groupName = [string](Get-EFPropertyValue -InputObject $Control -Name 'GroupName')
                $memberName = [string](Get-EFPropertyValue -InputObject $Control -Name 'MemberName')
                $timeoutSeconds = [int](Get-EFPropertyValue -InputObject $Control -Name 'TimeoutSeconds' -Default 15)
                try {
                    $membershipCheck = Test-EFLocalGroupMembership -GroupName $groupName `
                        -MemberName $memberName -TimeoutSeconds $timeoutSeconds
                }
                catch {
                    throw 'Windows could not complete the requested direct local-group membership check within the configured limit. No group-member details were included in the result.'
                }
                if (-not [bool]$membershipCheck.ProviderAvailable) {
                    return New-EFControlResult -Control $Control -Status Error -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Windows local-account commands are unavailable, so membership could not be checked. On 64-bit Windows, use 64-bit PowerShell.'
                }
                $actual = [bool]$membershipCheck.IsMember
                $status = if (Test-EFValueEqual -Actual $actual -Desired $desiredValue) { 'Compliant' } else { 'NonCompliant' }
                $message = if (-not [bool]$membershipCheck.GroupFound) {
                    'The requested local group was not found, so the requested direct membership does not exist.'
                }
                else {
                    $outcome = if ($actual) { 'is a direct member' } else { 'is not a direct member' }
                    "The requested account $outcome of the requested local group. Unrelated group members are not included in results."
                }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message $message
            }

            'BitLocker' {
                if ($null -eq (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'BitLocker cmdlets are unavailable.'
                }

                $mountPoint = [Environment]::ExpandEnvironmentVariables(
                    [string](Get-EFPropertyValue -InputObject $Control -Name 'MountPoint' -Default '%SystemDrive%')
                )
                $volume = Get-BitLockerVolume -MountPoint $mountPoint -ErrorAction Stop
                $actual = [string]$volume.ProtectionStatus
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message "BitLocker volume '$mountPoint' evaluated."
            }

            'SecureBoot' {
                if ($null -eq (Get-Command -Name Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'Secure Boot cmdlets are unavailable.'
                }

                try {
                    $actual = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
                }
                catch {
                    $secureBootMessage = $_.Exception.Message
                    $secureBootStatus = if ($secureBootMessage -match 'not supported|not available|not implemented') { 'NotApplicable' } else { 'Error' }
                    return New-EFControlResult -Control $Control -Status $secureBootStatus -ActualValue $null `
                        -DesiredValue $desiredValue -Message "Secure Boot cannot be queried on this device: $secureBootMessage"
                }
                $isMatch = Test-EFValueEqual -Actual $actual -Desired $desiredValue
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message 'Secure Boot evaluated.'
            }

            'Tpm' {
                if ($null -eq (Get-Command -Name Get-Tpm -ErrorAction SilentlyContinue)) {
                    return New-EFControlResult -Control $Control -Status NotApplicable -ActualValue $null `
                        -DesiredValue $desiredValue -Message 'TPM cmdlets are unavailable.'
                }

                $tpm = Get-Tpm -ErrorAction Stop
                if (-not (Test-EFPropertyPresent -InputObject $tpm -Name 'TpmPresent') -or
                    -not (Test-EFPropertyPresent -InputObject $tpm -Name 'TpmReady')) {
                    throw 'TPM status was not returned. Run PowerShell as Administrator to evaluate this control.'
                }
                $actual = [ordered]@{
                    TpmPresent = [bool](Get-EFPropertyValue -InputObject $tpm -Name 'TpmPresent')
                    TpmReady   = [bool](Get-EFPropertyValue -InputObject $tpm -Name 'TpmReady')
                }
                $expectedPresent = [bool](Get-EFPropertyValue -InputObject $desiredValue -Name 'TpmPresent' -Default $true)
                $expectedReady = [bool](Get-EFPropertyValue -InputObject $desiredValue -Name 'TpmReady' -Default $true)
                $isMatch = $actual.TpmPresent -eq $expectedPresent -and $actual.TpmReady -eq $expectedReady
                $status = if ($isMatch) { 'Compliant' } else { 'NonCompliant' }
                return New-EFControlResult -Control $Control -Status $status -ActualValue $actual `
                    -DesiredValue $desiredValue -Message 'Trusted Platform Module state evaluated.'
            }

            default {
                throw "Unsupported baseline control type '$type'."
            }
        }
    }
    catch {
        return New-EFControlResult -Control $Control -Status Error -ActualValue $null `
            -DesiredValue $desiredValue -Message $_.Exception.Message
    }
}
