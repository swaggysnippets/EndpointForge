function Show-EFMenu {
    <#
    .SYNOPSIS
    Opens the beginner-friendly EndpointForge menu.

    .DESCRIPTION
    Helps a person check one or more Windows computers, understand the results, preview
    supported fixes, save reports, compare checkups, and choose a checklist.
    Every choice explains whether it reads information, writes a file, or can change a
    Windows setting.

    A checklist is a list of things expected to be true, such as a Windows setting, a
    required file, a recent event, or an available network service. Scripts call it a
    baseline. Selecting a checklist never runs it. A computer check and a preview never
    change Windows, although a TCP item makes one observable network connection attempt.

    Applying a supported fix requires selecting the item, completing a fresh preview,
    running PowerShell as Administrator, and typing APPLY exactly. EndpointForge records
    before and after values, never restarts a computer, and does not promise automatic
    rollback because organization policy or later Windows changes may control a setting.

    The menu is for people. Scripts should use the object-based EndpointForge commands.
    Use PassThru to receive a record of the menu session when it closes.

    .PARAMETER Baseline
    The starting checklist: a built-in name, custom JSON path, or validated checklist
    object. The parameter keeps its Baseline name for compatibility with PowerShell
    automation.

    .PARAMETER ReportDirectory
    Where HTML and JSON reports are saved. The directory is created only when you save a
    report. The default is EndpointForge Reports under Documents.

    .PARAMETER IncludeSoftware
    Includes installed software in computer checkups. This can take longer and makes
    reports contain more private device information.

    .PARAMETER MinimumFreeSpacePercent
    The system-drive free-space level that should be described as needing attention.

    .PARAMETER MaximumUptimeDays
    The number of days without a restart that should be described as needing attention.

    .PARAMETER NoColor
    Uses plain terminal text without colors.

    .PARAMETER NoProgress
    Hides progress bars while checks and previews run.

    .PARAMETER NoPause
    Skips Press Enter pauses. It never skips a selection or the APPLY confirmation.

    .PARAMETER PassThru
    Returns one EndpointForge.MenuSession object after the menu closes.

    .EXAMPLE
    Show-EFMenu

    .EXAMPLE
    Show-EFMenu -Baseline .\Contoso.Workstation.json -IncludeSoftware

    .OUTPUTS
    None by default. EndpointForge.MenuSession when PassThru is specified.

    .LINK
    Get-EFEndpointSummary

    .LINK
    Get-EFEndpointReadiness

    .LINK
    Compare-EFEndpointSummary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object]$Baseline = 'EnterpriseRecommended',

        [string]$ReportDirectory,

        [switch]$IncludeSoftware,

        [ValidateRange(1, 99)]
        [int]$MinimumFreeSpacePercent = 15,

        [ValidateRange(1, 3650)]
        [int]$MaximumUptimeDays = 30,

        [switch]$NoColor,

        [switch]$NoProgress,

        [switch]$NoPause,

        [switch]$PassThru
    )

    $null = Test-EFWindows -Throw
    $startedAtUtc = [DateTime]::UtcNow
    $computerName = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { [Environment]::MachineName } else { $env:COMPUTERNAME }
    $safeComputerName = $computerName -replace '[^A-Za-z0-9._-]', '_'
    $width = Get-EFConsoleWidth
    $effectiveNoColor = [bool]$NoColor -or -not [string]::IsNullOrEmpty($env:NO_COLOR)
    try { $effectiveNoColor = $effectiveNoColor -or [Console]::IsOutputRedirected }
    catch { Write-Verbose 'The console redirection state is unavailable; using the requested color preference.' }
    $skipPauses = [bool]$NoPause
    $menuSummaryParameters = @{
        IncludeSoftware         = [bool]$IncludeSoftware
        MinimumFreeSpacePercent = $MinimumFreeSpacePercent
        MaximumUptimeDays       = $MaximumUptimeDays
        NoProgress              = [bool]$NoProgress
    }

    if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
        $documentsPath = [Environment]::GetFolderPath('MyDocuments')
        $reportRoot = if ([string]::IsNullOrWhiteSpace($documentsPath)) { (Get-Location).Path } else { $documentsPath }
        $ReportDirectory = Join-Path $reportRoot 'EndpointForge Reports'
    }
    $resolvedReportDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDirectory)

    try {
        $resolvedBaseline = Resolve-EFBaseline -Baseline $Baseline
    }
    catch {
        throw [System.ArgumentException]::new("The starting checklist could not be used: $($_.Exception.Message)", $_.Exception)
    }
    $activeBaseline = $Baseline
    $readiness = Get-EFEndpointReadiness -Baseline $activeBaseline

    $history = [Collections.Generic.List[object]]::new()
    $menuErrors = [Collections.Generic.List[object]]::new()
    $lastSummary = $null
    $previousSummary = $null
    $lastComparison = $null
    $lastPlan = $null
    $lastPreview = $null
    $lastRemediation = $null
    $lastFleet = $null
    $lastExportPath = $null
    $networkNoticeState = [pscustomobject]@{ ChecklistKey = '' }
    $actionCount = 0
    $exitReason = 'Quit'
    $isAdministrator = Test-EFAdministrator
    $isRemoteSession = [bool](Get-EFPropertyValue $readiness 'IsRemoteSession' $false)

    $addHistory = {
        param([string]$Action, [string]$Status, [string]$Message)
        $history.Add([pscustomobject]@{
            PSTypeName = 'EndpointForge.MenuHistoryEntry'
            AtUtc      = [DateTime]::UtcNow
            Action     = $Action
            Status     = $Status
            Message    = $Message
        })
    }
    $getNewSummary = {
        $networkControls = @($resolvedBaseline.Controls | Where-Object Type -eq 'TcpPort')
        $checklistKey = '{0}|{1}' -f $resolvedBaseline.Name, $resolvedBaseline.Version
        if ($networkControls.Count -gt 0 -and $networkNoticeState.ChecklistKey -ne $checklistKey) {
            Write-EFMenuLine -Text (
                "[NETWORK NOTE] This checklist contains $($networkControls.Count) connection check(s). " +
                'EndpointForge will briefly contact each named host and port, then disconnect without sending application data. The destination may record the attempt.'
            ) -Color Yellow -NoColor:$effectiveNoColor -Width $width
            $networkNoticeState.ChecklistKey = $checklistKey
        }
        Get-EFEndpointSummary -Baseline $activeBaseline @menuSummaryParameters
    }
    $pause = {
        if ($skipPauses) { return $true }
        $pauseInput = Read-EFMenuInput -Prompt 'Press Enter to continue'
        return $null -ne $pauseInput
    }
    $writeChecklistItems = {
        Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ("What the '{0}' checklist checks" -f $resolvedBaseline.Name) -Color Cyan -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'Showing a checklist only explains it. Nothing is checked or changed.' -Color Green -NoColor:$effectiveNoColor -Width $width
        $itemNumber = 0
        foreach ($item in @($resolvedBaseline.Controls)) {
            $itemNumber++
            $fixText = if ([bool]$item.Remediable) {
                'EndpointForge can preview a supported fix after a check finds a difference'
            }
            else {
                'EndpointForge reports the answer but never changes this automatically'
            }
            Write-EFMenuLine -Text ("{0}. {1}" -f $itemNumber, $item.Title) -NoColor:$effectiveNoColor -Width $width -Indent 2
            Write-EFMenuLine -Text ("Why: {0}" -f (Get-EFPropertyValue $item 'WhyItMatters' $item.Description)) -NoColor:$effectiveNoColor -Width $width -Indent 4
            Write-EFMenuLine -Text ("How: {0}" -f (Get-EFPropertyValue $item 'HowChecked' 'EndpointForge reads only the information needed for this item.')) -NoColor:$effectiveNoColor -Width $width -Indent 4
            Write-EFMenuLine -Text ("If it does not match: {0}." -f $fixText) -NoColor:$effectiveNoColor -Width $width -Indent 4
        }
    }

    $running = $true
    :MainLoop while ($running) {
        $isAdministrator = Test-EFAdministrator
        $latestText = if ($null -eq $lastSummary) {
            'Not run yet - choose 1 to begin'
        }
        else {
            $latestLabel = switch ([string]$lastSummary.OverallStatus) {
                'Healthy' { 'Looks good' }
                'Warning' { 'Needs attention' }
                'Critical' { 'Urgent attention' }
                default { 'Could not check everything' }
            }
            "$latestLabel at $(([DateTime]$lastSummary.CompletedAtUtc).ToLocalTime().ToString('g'))"
        }
        $readyText = switch ([string]$readiness.Status) {
            'Ready' { 'Ready to check' }
            'Limited' { 'Ready with limits - checks work, but some protected details or fixes may need Administrator permission' }
            default { 'Not ready - review the readiness explanation' }
        }

        Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'EndpointForge - Windows computer helper' -Color Cyan -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'Checks health, settings, files, events, and connections; explains problems; and safely previews supported fixes.' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ('=' * [math]::Min(72, $width)) -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'THIS SESSION' -Color Cyan -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ("Computer: {0}{1}" -f $computerName, $(if ($isRemoteSession) { ' (connected remotely)' } else { '' })) -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ("Permission: {0}" -f $(if ($isAdministrator) { 'Administrator - checks, previews, and approved supported fixes are available' } else { 'Check and preview only - Administrator permission is needed to apply fixes' })) `
            -Color $(if ($isAdministrator) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }) -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ("Checklist: {0} {1} - {2} item(s) to check" -f $resolvedBaseline.Name, $resolvedBaseline.Version, @($resolvedBaseline.Controls).Count) -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ("Ready: {0}" -f $readyText) -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ("Latest check: {0}" -f $latestText) -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'A checklist is a list of things you expect to be true. Choosing one never changes Windows and does not run the checklist.' -NoColor:$effectiveNoColor -Width $width
        if ($isRemoteSession) {
            Write-EFMenuLine -Text '[IMPORTANT] Checks and approved fixes affect the remote computer named above.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
        }

        Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '1. Check this computer now              [does not change Windows]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '2. Understand the latest results        [does not change Windows]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '3. Fix selected problems safely         [can change settings after approval]' -Color Yellow -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '4. Save reports or compare checks       [creates files only when you choose Save]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '5. Check other computers                [no setting changes; TCP items contact named hosts]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '6. Change what EndpointForge checks     [does not change Windows]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'A. Tools for IT scripts and troubleshooting' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'H. Help - explain every choice' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'Q. Exit EndpointForge' -NoColor:$effectiveNoColor -Width $width

        $choice = Read-EFMenuInput -Prompt 'Choose an option'
        if ($null -eq $choice) { $exitReason = 'InputClosed'; break MainLoop }
        $normalizedChoice = $choice.Trim().ToUpperInvariant()
        $currentAction = $normalizedChoice

        try {
            switch -Regex ($normalizedChoice) {
                '^(1|CHECK|START)$' {
                    $currentAction = 'Check this computer'
                    $actionCount++
                    Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'Checking this computer' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'This check does not change Windows. A TCP item, if present, makes one brief connection that may be recorded.' -Color Green -NoColor:$effectiveNoColor -Width $width
                    if (-not $readiness.AssessmentReady) {
                        Write-EFMenuReadiness -Readiness $readiness -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Computer check' 'Blocked' $readiness.Summary
                        if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
                        break
                    }
                    if ($null -ne $lastSummary) { $previousSummary = $lastSummary }
                    $lastSummary = & $getNewSummary
                    $lastPlan = $null
                    $lastPreview = $null
                    if ($null -ne $previousSummary) {
                        try { $lastComparison = Compare-EFEndpointSummary -Before $previousSummary -After $lastSummary } catch { $lastComparison = $null }
                    }
                    $null = Show-EFEndpointSummary -InputObject $lastSummary -NoColor:$effectiveNoColor
                    & $addHistory 'Computer check' 'Completed' $lastSummary.OverallStatus
                    if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
                    break
                }

                '^(2|RESULT|RESULTS|UNDERSTAND)$' {
                    :ResultsLoop while ($running) {
                        Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'Understand the latest results' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'Every choice here only reads information.' -Color Green -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '1. Show a simple overview' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '2. Explain every problem' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '3. Show what changed since the previous check' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '4. Show computer and protection details' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'B. Back to the main menu' -NoColor:$effectiveNoColor -Width $width
                        $resultChoice = Read-EFMenuInput -Prompt 'Choose a result view'
                        if ($null -eq $resultChoice) { $exitReason = 'InputClosed'; $running = $false; break ResultsLoop }
                        switch ($resultChoice.Trim().ToUpperInvariant()) {
                            { $_ -in @('1', '2', '4') } {
                                $actionCount++
                                if ($null -eq $lastSummary) {
                                    Write-EFMenuLine -Text 'No check exists yet, so EndpointForge will run a read-only check now.' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                                    $lastSummary = & $getNewSummary
                                }
                                if ($_ -eq '1') {
                                    $null = Show-EFEndpointSummary -InputObject $lastSummary -NoColor:$effectiveNoColor
                                    & $addHistory 'Simple results' 'Viewed' $lastSummary.OverallStatus
                                }
                                elseif ($_ -eq '2') {
                                    $null = Show-EFEndpointSummary -InputObject $lastSummary -Detailed -NoColor:$effectiveNoColor
                                    & $addHistory 'Detailed results' 'Viewed' "$($lastSummary.IssueCount) item(s) need attention"
                                }
                                else {
                                    Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                                    Write-EFMenuLine -Text 'Computer and protection details' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                                    Write-EFMenuLine -Text ("Computer: {0}" -f $lastSummary.ComputerName) -NoColor:$effectiveNoColor -Width $width
                                    Write-EFMenuLine -Text ("Windows: {0}, build {1}" -f $lastSummary.OperatingSystem, $lastSummary.OperatingSystemBuild) -NoColor:$effectiveNoColor -Width $width
                                    Write-EFMenuLine -Text ("Model: {0}; running for {1} day(s); system drive free {2}%" -f $lastSummary.Model, $lastSummary.UptimeDays, $lastSummary.DiskFreePercent) -NoColor:$effectiveNoColor -Width $width
                                    Write-EFMenuLine -Text ("Firewall: {0}; Defender: {1}; BitLocker: {2}" -f $lastSummary.Security.Firewall, $lastSummary.Security.Defender, $lastSummary.Security.BitLocker) -NoColor:$effectiveNoColor -Width $width
                                    Write-EFMenuLine -Text ("Secure Boot: {0}; TPM: {1}; restart waiting: {2}" -f $lastSummary.Security.SecureBoot, $lastSummary.Security.Tpm, $(if ($lastSummary.IsRebootPending) { 'Yes' } else { 'No' })) -NoColor:$effectiveNoColor -Width $width
                                    & $addHistory 'Computer details' 'Viewed' $lastSummary.ComputerName
                                }
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ResultsLoop }
                            }
                            '3' {
                                $actionCount++
                                if ($null -eq $lastSummary -or $null -eq $previousSummary) {
                                    Write-EFMenuLine -Text '[NOT READY] Two checks from this computer are needed. Choose 1 on the main menu twice, or load an earlier JSON report under Save reports or compare checks.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                }
                                else {
                                    $lastComparison = Compare-EFEndpointSummary -Before $previousSummary -After $lastSummary
                                    Write-EFMenuComparison -Comparison $lastComparison -NoColor:$effectiveNoColor -Width $width
                                    & $addHistory 'Compare checks' 'Completed' $lastComparison.Summary
                                }
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ResultsLoop }
                            }
                            { $_ -in @('B', 'BACK', 'Q') } { break ResultsLoop }
                            default { Write-EFMenuLine -Text '[INVALID] Choose 1-4 or B.' -Color Yellow -NoColor:$effectiveNoColor -Width $width }
                        }
                    }
                    if (-not $running) { break MainLoop }
                    break
                }

                '^(3|FIX|REPAIR)$' {
                    $currentAction = 'Safe fix assistant'
                    $actionCount++
                    Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'Safe fix assistant' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'First EndpointForge explains the options, then you select items, then it runs a preview that cannot change Windows.' -Color Green -NoColor:$effectiveNoColor -Width $width
                    if ($null -eq $lastSummary) {
                        Write-EFMenuLine -Text 'A read-only check is needed first. Running it now...' -NoColor:$effectiveNoColor -Width $width
                        $lastSummary = & $getNewSummary
                    }
                    $beforeFixSummary = $lastSummary
                    $lastPlan = Get-EFRemediationPlan -Baseline $activeBaseline -NoProgress:$NoProgress
                    Write-EFMenuPlan -Plan $lastPlan -NoColor:$effectiveNoColor -Width $width
                    if ([int]$lastPlan.AutomaticCount -eq 0) {
                        Write-EFMenuLine -Text '[NO SUPPORTED FIXES] Review the manual guidance above. EndpointForge will not change those items.' -Color Green -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Safe fix assistant' 'NotRequired' $lastPlan.Summary
                        if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
                        break
                    }

                    $selectedControlIds = @(Select-EFMenuControlId -Steps $lastPlan.Steps -NoColor:$effectiveNoColor -Width $width)
                    if ($selectedControlIds.Count -eq 0) {
                        Write-EFMenuLine -Text '[CANCELLED] No items were selected. Windows was not changed.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Safe fix assistant' 'Cancelled' 'No checklist items were selected.'
                        if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
                        break
                    }

                    Write-EFMenuLine -Text 'Running the required preview now. A preview cannot change Windows...' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    $lastPreview = Invoke-EFEndpointRemediation -Baseline $activeBaseline -ControlId $selectedControlIds `
                        -NoProgress:$NoProgress -WhatIf -Confirm:$false
                    Write-EFMenuRemediationReport -Report $lastPreview -NoColor:$effectiveNoColor -Width $width
                    if ([int]$lastPreview.FailureCount -gt 0) {
                        Write-EFMenuLine -Text '[STOPPED] The preview could not confirm every selected item. Nothing will be applied.' -Color Red -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Safe fix assistant' 'Blocked' 'The required preview was incomplete.'
                        if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
                        break
                    }
                    if ([int]$lastPreview.PreviewCount -eq 0) {
                        Write-EFMenuLine -Text '[NO CHANGE NEEDED] The selected items no longer require a supported change.' -Color Green -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Safe fix assistant' 'NotRequired' 'No selected setting still needed a change.'
                        if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
                        break
                    }
                    if (-not (Test-EFAdministrator)) {
                        Write-EFMenuLine -Text '[PREVIEW COMPLETE] This PowerShell window can preview but cannot apply fixes.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'To continue later, close this window, open PowerShell with Run as administrator, start EndpointForge, and select the same items. A new preview will run before approval.' -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Safe fix assistant' 'PreviewOnly' 'Administrator permission is required to apply.'
                        if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
                        break
                    }

                    $selectedSteps = @($lastPlan.Steps | Where-Object { $_.ControlId -in $selectedControlIds })
                    Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'FINAL APPROVAL' -Color Red -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text ("Computer that would change: {0}" -f $computerName) -NoColor:$effectiveNoColor -Width $width
                    foreach ($step in $selectedSteps) {
                        Write-EFMenuLine -Text ("- {0}: found {1}; expected {2}{3}" -f $step.Title,
                            (ConvertTo-EFMenuValue $step.CurrentValue), (ConvertTo-EFMenuValue $step.DesiredValue),
                            $(if ($step.RequiresReboot) { '; restart may be needed' } else { '' })) -NoColor:$effectiveNoColor -Width $width -Indent 2
                    }
                    Write-EFMenuLine -Text 'EndpointForge will save before-and-after values in this session. It will not restart Windows and cannot promise automatic rollback.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                    $acknowledgement = Read-EFMenuInput -Prompt 'Type APPLY exactly to make these selected changes; anything else cancels'
                    if ($null -eq $acknowledgement -or $acknowledgement.Trim() -cne 'APPLY') {
                        Write-EFMenuLine -Text '[CANCELLED] Windows was not changed.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Safe fix assistant' 'Cancelled' 'The APPLY approval was not entered.'
                        if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
                        break
                    }

                    $lastRemediation = Invoke-EFEndpointRemediation -Baseline $activeBaseline -ControlId $selectedControlIds `
                        -NoProgress:$NoProgress -Confirm:$false
                    Write-EFMenuRemediationReport -Report $lastRemediation -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'Running a fresh read-only check to verify the result...' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    $previousSummary = $beforeFixSummary
                    $lastSummary = & $getNewSummary
                    $lastComparison = Compare-EFEndpointSummary -Before $previousSummary -After $lastSummary
                    Write-EFMenuComparison -Comparison $lastComparison -NoColor:$effectiveNoColor -Width $width
                    $lastPlan = $null
                    & $addHistory 'Safe fix assistant' 'Completed' $lastRemediation.Summary
                    if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
                    break
                }

                '^(4|REPORT|REPORTS|COMPARE|SAVE)$' {
                    :ReportLoop while ($running) {
                        Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'Save reports or compare checks' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'Reports may contain private computer names, device details, and security findings. Store them in an approved location.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '1. Save an easy-to-read HTML report     [recommended for people]' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '2. Save a JSON report                   [for scripts and support tools]' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '3. Compare the latest check with an earlier JSON report' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '4. View the changes or preview from this session' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'B. Back to the main menu' -NoColor:$effectiveNoColor -Width $width
                        $reportChoice = Read-EFMenuInput -Prompt 'Choose a report action'
                        if ($null -eq $reportChoice) { $exitReason = 'InputClosed'; $running = $false; break ReportLoop }
                        $normalizedReportChoice = $reportChoice.Trim().ToUpperInvariant()
                        if ($normalizedReportChoice -in @('B', 'BACK', 'Q')) { break ReportLoop }

                        switch ($normalizedReportChoice) {
                            { $_ -in @('1', '2') } {
                                $actionCount++
                                if ($null -eq $lastSummary) {
                                    Write-EFMenuLine -Text '[NOT READY] Run a computer check first so the report has useful results.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                }
                                else {
                                    $reportBundle = New-EFMenuReport -ComputerName $computerName -Checklist $resolvedBaseline `
                                        -Readiness $readiness -Summary $lastSummary -PreviousSummary $previousSummary `
                                        -Comparison $lastComparison -Plan $lastPlan -Preview $lastPreview `
                                        -Remediation $lastRemediation -Fleet $lastFleet -History @($history)
                                    $timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')
                                    $format = if ($_ -eq '1') { 'Html' } else { 'Json' }
                                    $extension = if ($format -eq 'Html') { 'html' } else { 'json' }
                                    $exportPath = Join-Path $resolvedReportDirectory "EndpointForge-$safeComputerName-$timestamp.$extension"
                                    $createdFile = $reportBundle | Export-EFEndpointReport -Path $exportPath -Format $format -PassThru
                                    $lastExportPath = $createdFile.FullName
                                    Write-EFMenuLine -Text ("[SAVED] {0}" -f $lastExportPath) -Color Green -NoColor:$effectiveNoColor -Width $width
                                    & $addHistory "Save $format report" 'Completed' $lastExportPath
                                }
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ReportLoop }
                            }
                            '3' {
                                $actionCount++
                                if ($null -eq $lastSummary) {
                                    Write-EFMenuLine -Text '[NOT READY] Run a computer check first.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                }
                                else {
                                    $earlierPath = Read-EFMenuInput -Prompt 'Path to the earlier EndpointForge JSON report; press Enter to cancel'
                                    if (-not [string]::IsNullOrWhiteSpace($earlierPath)) {
                                        $lastComparison = Compare-EFEndpointSummary -Before $earlierPath.Trim() -After $lastSummary
                                        Write-EFMenuComparison -Comparison $lastComparison -NoColor:$effectiveNoColor -Width $width
                                        & $addHistory 'Compare saved check' 'Completed' $lastComparison.Summary
                                    }
                                    else { Write-EFMenuLine -Text '[CANCELLED] No report was loaded.' -Color Yellow -NoColor:$effectiveNoColor -Width $width }
                                }
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ReportLoop }
                            }
                            '4' {
                                $actionCount++
                                if ($null -ne $lastRemediation) {
                                    Write-EFMenuRemediationReport -Report $lastRemediation -NoColor:$effectiveNoColor -Width $width
                                    Write-EFMenuLine -Text 'This receipt includes before and after values plus recovery guidance. It is not an automatic rollback guarantee.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                }
                                elseif ($null -ne $lastPreview) {
                                    Write-EFMenuRemediationReport -Report $lastPreview -NoColor:$effectiveNoColor -Width $width
                                }
                                else {
                                    Write-EFMenuLine -Text '[NOT READY] No preview or approved change has happened in this session.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                }
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ReportLoop }
                            }
                            default { Write-EFMenuLine -Text '[INVALID] Choose 1-4 or B.' -Color Yellow -NoColor:$effectiveNoColor -Width $width }
                        }
                    }
                    if (-not $running) { break MainLoop }
                    break
                }

                '^(5|FLEET|OTHER|REMOTE)$' {
                    $currentAction = 'Check other computers'
                    $actionCount++
                    Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'Check other computers - no Windows setting changes' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'EndpointForge will not install itself, turn on remote access, change settings, or run fixes on those computers. TCP checklist items can make brief, observable network connections from each computer.' -Color Green -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'Before this works, each computer must already allow PowerShell remoting, already have EndpointForge 0.5.0 or later installed, and allow your signed-in account to connect.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                    $targetInput = Read-EFMenuInput -Prompt 'Computer names separated by commas; enter B to cancel'
                    if ($null -eq $targetInput -or $targetInput.Trim() -match '^(?i:B|BACK|Q)$') {
                        Write-EFMenuLine -Text '[CANCELLED] No other computer was contacted.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                    }
                    else {
                        $targetNames = @($targetInput -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                        if ($targetNames.Count -eq 0) { throw [System.ArgumentException]::new('Enter at least one computer name.') }
                        $fleetApproved = $true
                        $allowFleetNetworkChecks = $false
                        $networkControls = @($resolvedBaseline.Controls | Where-Object Type -eq 'TcpPort')
                        if ($networkControls.Count -gt 0) {
                            $destinationCount = @($networkControls | ForEach-Object {
                                '{0}:{1}' -f $_.HostName, $_.Port
                            } | Select-Object -Unique).Count
                            Write-EFMenuLine -Text (
                                "[CONFIRM NETWORK ACTIVITY] Each of $($targetNames.Count) computer(s) will make $($networkControls.Count) brief TCP attempt(s) across $destinationCount destination(s). " +
                                'The destinations or network monitoring tools may record them. No application data is sent.'
                            ) -Color Yellow -NoColor:$effectiveNoColor -Width $width
                            $networkApproval = Read-EFMenuInput -Prompt 'Type NETWORK to allow these connection checks; anything else cancels'
                            if ($networkApproval -cne 'NETWORK') {
                                $fleetApproved = $false
                                Write-EFMenuLine -Text '[CANCELLED] No other computer was contacted.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                & $addHistory 'Check other computers' 'Cancelled' 'Network connection checks were not approved.'
                            }
                            else {
                                $allowFleetNetworkChecks = $true
                            }
                        }
                        if ($fleetApproved) {
                            $lastFleet = Get-EFFleetSummary -ComputerName $targetNames -Baseline $activeBaseline `
                                -IncludeSoftware:$IncludeSoftware -AllowNetworkChecks:$allowFleetNetworkChecks
                            Write-EFMenuFleetSummary -Fleet $lastFleet -NoColor:$effectiveNoColor -Width $width
                            & $addHistory 'Check other computers' 'Completed' $lastFleet.Summary
                        }
                    }
                    if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
                    break
                }

                '^(6|CHECKLIST|SETTINGS)$' {
                    :ChecklistLoop while ($running) {
                        Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'Change what EndpointForge checks' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'A checklist describes things you expect to be true. Selecting, viewing, validating, or creating one does not run checks or change Windows.' -Color Green -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'Custom checklists can include required files, exact text near the end of a log, recent Windows event IDs, and named TCP connections.' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text ("Current checklist: {0} {1}" -f $resolvedBaseline.Name, $resolvedBaseline.Version) -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '1. Use the built-in recommended checklist' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '2. Load my organization''s checklist JSON file' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '3. Explain every item in the current checklist' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '4. Check whether a checklist file is valid' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '5. Create an editable settings or everyday-check template' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'B. Back to the main menu' -NoColor:$effectiveNoColor -Width $width
                        $checklistChoice = Read-EFMenuInput -Prompt 'Choose a checklist action'
                        if ($null -eq $checklistChoice) { $exitReason = 'InputClosed'; $running = $false; break ChecklistLoop }
                        switch ($checklistChoice.Trim().ToUpperInvariant()) {
                            '1' {
                                $actionCount++
                                $activeBaseline = 'EnterpriseRecommended'
                                $resolvedBaseline = Resolve-EFBaseline -Baseline $activeBaseline
                                $readiness = Get-EFEndpointReadiness -Baseline $activeBaseline
                                $networkNoticeState.ChecklistKey = ''
                                $lastSummary = $null; $previousSummary = $null; $lastComparison = $null
                                $lastPlan = $null; $lastPreview = $null; $lastRemediation = $null; $lastFleet = $null
                                Write-EFMenuLine -Text '[SELECTED] The built-in recommended checklist is active. Earlier results were cleared so they cannot be confused with this checklist.' -Color Green -NoColor:$effectiveNoColor -Width $width
                                & $addHistory 'Select checklist' 'Completed' "$($resolvedBaseline.Name) $($resolvedBaseline.Version)"
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ChecklistLoop }
                            }
                            '2' {
                                $actionCount++
                                $checklistPath = Read-EFMenuInput -Prompt 'Path to the checklist JSON file; press Enter to cancel'
                                if ([string]::IsNullOrWhiteSpace($checklistPath)) {
                                    Write-EFMenuLine -Text '[CANCELLED] The checklist was not changed.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                }
                                else {
                                    $candidate = Resolve-EFBaseline -Baseline $checklistPath.Trim()
                                    $activeBaseline = $checklistPath.Trim()
                                    $resolvedBaseline = $candidate
                                    $readiness = Get-EFEndpointReadiness -Baseline $activeBaseline
                                    $networkNoticeState.ChecklistKey = ''
                                    $lastSummary = $null; $previousSummary = $null; $lastComparison = $null
                                    $lastPlan = $null; $lastPreview = $null; $lastRemediation = $null; $lastFleet = $null
                                    Write-EFMenuLine -Text ("[SELECTED] {0} {1}. Earlier results were cleared." -f $resolvedBaseline.Name, $resolvedBaseline.Version) -Color Green -NoColor:$effectiveNoColor -Width $width
                                    & $addHistory 'Select checklist' 'Completed' "$($resolvedBaseline.Name) $($resolvedBaseline.Version)"
                                }
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ChecklistLoop }
                            }
                            '3' {
                                $actionCount++
                                & $writeChecklistItems
                                & $addHistory 'Explain checklist' 'Viewed' "$(@($resolvedBaseline.Controls).Count) item(s)"
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ChecklistLoop }
                            }
                            '4' {
                                $actionCount++
                                $validationPath = Read-EFMenuInput -Prompt 'Path to the checklist JSON file; press Enter to cancel'
                                if (-not [string]::IsNullOrWhiteSpace($validationPath)) {
                                    $validation = Test-EFBaseline -Path $validationPath.Trim() -PassThru
                                    if ($validation.IsValid) {
                                        Write-EFMenuLine -Text ("[VALID] {0} {1} contains {2} checklist item(s). Valid means the file is safe to read; it does not apply settings." -f $validation.Name, $validation.Version, $validation.ControlCount) -Color Green -NoColor:$effectiveNoColor -Width $width
                                    }
                                    else {
                                        Write-EFMenuLine -Text '[NOT VALID] The file cannot be used:' -Color Red -NoColor:$effectiveNoColor -Width $width
                                        foreach ($validationError in @($validation.Errors)) { Write-EFMenuLine -Text ("- {0}" -f $validationError) -NoColor:$effectiveNoColor -Width $width -Indent 2 }
                                    }
                                    & $addHistory 'Validate checklist' $(if ($validation.IsValid) { 'Completed' } else { 'Failed' }) $validation.Input
                                }
                                else { Write-EFMenuLine -Text '[CANCELLED] No file was checked.' -Color Yellow -NoColor:$effectiveNoColor -Width $width }
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ChecklistLoop }
                            }
                            '5' {
                                $actionCount++
                                Write-EFMenuLine -Text 'This creates editable JSON and schema files. It does not run a check or apply settings. An IT administrator must review the file before use.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                Write-EFMenuLine -Text '1. Windows settings starter - firewall, sign-in protection, and Windows Update examples' -NoColor:$effectiveNoColor -Width $width
                                Write-EFMenuLine -Text '2. Everyday checks - editable file, log text, event ID, and network connection examples' -NoColor:$effectiveNoColor -Width $width
                                Write-EFMenuLine -Text '   Everyday checks contain fictional Contoso targets and must be edited before they are run.' -Color Yellow -NoColor:$effectiveNoColor -Width $width -Indent 2
                                $templateChoice = Read-EFMenuInput -Prompt 'Choose 1 or 2; press Enter to cancel'
                                $newTemplate = switch ($templateChoice) {
                                    '1' { 'Starter' }
                                    '2' { 'EverydayChecks' }
                                    default { $null }
                                }
                                if ($null -eq $newTemplate -and -not [string]::IsNullOrWhiteSpace($templateChoice)) {
                                    Write-EFMenuLine -Text '[INVALID] Choose 1 or 2.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                }
                                $newName = if ($null -ne $newTemplate) {
                                    Read-EFMenuInput -Prompt 'Checklist name, for example Contoso.Workstation; press Enter to cancel'
                                } else { $null }
                                if ($null -ne $newTemplate -and -not [string]::IsNullOrWhiteSpace($newName)) {
                                    $defaultPath = Join-Path (Join-Path $resolvedReportDirectory 'Checklists') ("{0}.json" -f $newName.Trim())
                                    $newPath = Read-EFMenuInput -Prompt "Output path [$defaultPath]"
                                    if ([string]::IsNullOrWhiteSpace($newPath)) { $newPath = $defaultPath }
                                    $created = New-EFBaseline -Name $newName.Trim() -Template $newTemplate -Path $newPath.Trim() `
                                        -Description "Editable $newTemplate checklist for $($newName.Trim()). Review before use."
                                    Write-EFMenuLine -Text ("[CREATED] {0}" -f $created.Path) -Color Green -NoColor:$effectiveNoColor -Width $width
                                    if ($newTemplate -eq 'EverydayChecks') {
                                        Write-EFMenuLine -Text 'Replace every Contoso path, text, event source and ID, host, and port before use.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                    }
                                    Write-EFMenuLine -Text 'The file was not selected or run. Review it, validate it, then load it with option 2.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                    & $addHistory 'Create checklist' 'Completed' $created.Path
                                }
                                elseif ([string]::IsNullOrWhiteSpace($templateChoice) -or $null -ne $newTemplate) {
                                    Write-EFMenuLine -Text '[CANCELLED] No file was created.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                }
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ChecklistLoop }
                            }
                            { $_ -in @('B', 'BACK', 'Q') } { break ChecklistLoop }
                            default { Write-EFMenuLine -Text '[INVALID] Choose 1-5 or B.' -Color Yellow -NoColor:$effectiveNoColor -Width $width }
                        }
                    }
                    if (-not $running) { break MainLoop }
                    break
                }

                '^(A|ADVANCED|TOOLS)$' {
                    :ToolsLoop while ($running) {
                        Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'Tools for IT scripts and troubleshooting' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'These choices explain technical details. They do not change Windows.' -Color Green -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '1. Show readiness and missing Windows features' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '2. Show PowerShell command examples' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text '3. Show the latest script result code' -NoColor:$effectiveNoColor -Width $width
                        Write-EFMenuLine -Text 'B. Back to the main menu' -NoColor:$effectiveNoColor -Width $width
                        $toolChoice = Read-EFMenuInput -Prompt 'Choose a technical tool'
                        if ($null -eq $toolChoice) { $exitReason = 'InputClosed'; $running = $false; break ToolsLoop }
                        switch ($toolChoice.Trim().ToUpperInvariant()) {
                            '1' {
                                $actionCount++
                                $readiness = Get-EFEndpointReadiness -Baseline $activeBaseline
                                Write-EFMenuReadiness -Readiness $readiness -NoColor:$effectiveNoColor -Width $width
                                & $addHistory 'Readiness details' 'Viewed' $readiness.Status
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ToolsLoop }
                            }
                            '2' {
                                $actionCount++
                                Write-EFMenuLine -Text 'Read-only check: Get-EFEndpointSummary -NoProgress' -NoColor:$effectiveNoColor -Width $width
                                Write-EFMenuLine -Text 'Read-only plan: Get-EFRemediationPlan -NoProgress' -NoColor:$effectiveNoColor -Width $width
                                Write-EFMenuLine -Text 'No-change preview: Invoke-EFEndpointRemediation -ControlId <approved IDs> -WhatIf' -NoColor:$effectiveNoColor -Width $width
                                Write-EFMenuLine -Text 'Human report: Get-EFEndpointSummary -NoProgress | Export-EFEndpointReport -Path .\check.html' -NoColor:$effectiveNoColor -Width $width
                                Write-EFMenuLine -Text 'Several computers: Get-EFFleetSummary -ComputerName PC1,PC2' -NoColor:$effectiveNoColor -Width $width
                                Write-EFMenuLine -Text 'Compare JSON reports: Compare-EFEndpointSummary .\before.json .\after.json' -NoColor:$effectiveNoColor -Width $width
                                & $addHistory 'PowerShell examples' 'Viewed' 'Command examples displayed.'
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ToolsLoop }
                            }
                            '3' {
                                $actionCount++
                                if ($null -eq $lastSummary) {
                                    Write-EFMenuLine -Text '[NOT READY] Run a computer check first.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                                }
                                else {
                                    Write-EFMenuLine -Text ("For scripts: result code {0}. 0 means okay; 1 needs attention; 2 has an urgent or mismatched setting; 3 means information could not be checked." -f $lastSummary.ExitCode) -NoColor:$effectiveNoColor -Width $width
                                }
                                if (-not (& $pause)) { $exitReason = 'InputClosed'; $running = $false; break ToolsLoop }
                            }
                            { $_ -in @('B', 'BACK', 'Q') } { break ToolsLoop }
                            default { Write-EFMenuLine -Text '[INVALID] Choose 1-3 or B.' -Color Yellow -NoColor:$effectiveNoColor -Width $width }
                        }
                    }
                    if (-not $running) { break MainLoop }
                    break
                }

                '^(H|HELP|\?)$' {
                    $currentAction = 'Help'
                    $actionCount++
                    Write-EFMenuHelp -NoColor:$effectiveNoColor -Width $width
                    & $addHistory 'Help' 'Viewed' 'Plain-language glossary displayed.'
                    if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
                    break
                }

                '^(Q|QUIT|EXIT)$' {
                    $exitReason = 'Quit'
                    $running = $false
                    break
                }

                default {
                    Write-EFMenuLine -Text '[INVALID] Choose 1-6, A, H, or Q.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                }
            }
        }
        catch [System.Management.Automation.PipelineStoppedException] { throw }
        catch {
            $menuErrors.Add([pscustomobject]@{
                PSTypeName = 'EndpointForge.MenuError'
                AtUtc      = [DateTime]::UtcNow
                Action     = $currentAction
                Message    = $_.Exception.Message
                ErrorId    = $_.FullyQualifiedErrorId
            })
            & $addHistory $currentAction 'Failed' $_.Exception.Message
            Write-EFMenuLine -Text ("[COULD NOT COMPLETE] {0}" -f $_.Exception.Message) -Color Red -NoColor:$effectiveNoColor -Width $width
            Write-EFMenuLine -Text 'Windows was not assumed changed. Review the message, then choose another action or try again.' -NoColor:$effectiveNoColor -Width $width
            if (-not (& $pause)) { $exitReason = 'InputClosed'; break MainLoop }
        }
    }

    if ($PassThru) {
        [pscustomobject]@{
            PSTypeName       = 'EndpointForge.MenuSession'
            SchemaVersion    = '1.1'
            ComputerName     = $computerName
            StartedAtUtc     = $startedAtUtc
            CompletedAtUtc   = [DateTime]::UtcNow
            ExitReason       = $exitReason
            IsRemoteSession  = $isRemoteSession
            IsAdministrator  = $isAdministrator
            ChecklistName    = [string]$resolvedBaseline.Name
            ChecklistVersion = [string]$resolvedBaseline.Version
            BaselineName     = [string]$resolvedBaseline.Name
            BaselineVersion  = [string]$resolvedBaseline.Version
            BaselinePath     = [string](Get-EFPropertyValue $resolvedBaseline 'SourcePath' '')
            ReportDirectory  = $resolvedReportDirectory
            ActionCount      = $actionCount
            ErrorCount       = $menuErrors.Count
            LastExportPath   = $lastExportPath
            Readiness        = $readiness
            LastSummary      = $lastSummary
            PreviousSummary  = $previousSummary
            LastComparison   = $lastComparison
            LastPlan         = $lastPlan
            LastPreview      = $lastPreview
            LastRemediation  = $lastRemediation
            LastFleet        = $lastFleet
            History          = @($history)
            Errors           = @($menuErrors)
        }
    }
}
