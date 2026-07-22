function Show-EFMenu {
    <#
    .SYNOPSIS
    Opens the guided EndpointForge console menu.

    .DESCRIPTION
    Provides a keyboard-friendly interactive menu over EndpointForge's object-based
    commands. The menu guides operators through assessment, detailed findings,
    remediation planning, safe WhatIf previews, scoped remediation, baseline selection
    and creation, and report export.

    Assessment and planning are read-only. Applying remediation requires an elevated
    session, selection of specific automatic controls, a fresh WhatIf preview, and an
    exact APPLY acknowledgement. EndpointForge never restarts the device automatically.

    The menu writes presentation text to the host and is silent on the success stream by
    default. Use PassThru to receive one session object when the menu closes. For
    unattended automation, call the underlying Get, Test, Export, and Invoke commands
    directly instead of using this interactive command.

    .PARAMETER Baseline
    The initial built-in baseline name, custom JSON path, or validated baseline object.

    .PARAMETER ReportDirectory
    The directory used by the Export session report action. It is created only when an
    export is requested. The default is EndpointForge Reports under Documents.

    .PARAMETER IncludeSoftware
    Includes installed software in assessments started from the menu.

    .PARAMETER MinimumFreeSpacePercent
    Sets the system-drive warning threshold for menu assessments.

    .PARAMETER MaximumUptimeDays
    Sets the uptime warning threshold for menu assessments.

    .PARAMETER NoColor
    Disables menu and dashboard colors. Color is also disabled when NO_COLOR is set or
    console output is redirected.

    .PARAMETER NoProgress
    Suppresses progress displays from assessment, planning, preview, and remediation.

    .PARAMETER NoPause
    Skips Press Enter pauses after actions. It never skips menu input, control selection,
    or the APPLY safety acknowledgement.

    .PARAMETER PassThru
    Returns one EndpointForge.MenuSession object after the menu closes.

    .EXAMPLE
    Show-EFMenu

    .EXAMPLE
    Show-EFMenu -Baseline .\Contoso.Workstation.json -IncludeSoftware

    .EXAMPLE
    $session = Show-EFMenu -NoColor -NoProgress -PassThru

    .OUTPUTS
    None by default. EndpointForge.MenuSession when PassThru is specified.

    .LINK
    Get-EFEndpointSummary

    .LINK
    Get-EFRemediationPlan

    .LINK
    Invoke-EFEndpointRemediation
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
    $width = Get-EFConsoleWidth
    $effectiveNoColor = [bool]$NoColor -or -not [string]::IsNullOrEmpty($env:NO_COLOR)
    try {
        $effectiveNoColor = $effectiveNoColor -or [Console]::IsOutputRedirected
    }
    catch {
        Write-Verbose 'Console redirection state is unavailable; using NoColor and NO_COLOR preferences.'
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
        throw [System.ArgumentException]::new("The initial baseline is invalid: $($_.Exception.Message)", $_.Exception)
    }
    $activeBaseline = $Baseline

    $history = [Collections.Generic.List[object]]::new()
    $menuErrors = [Collections.Generic.List[object]]::new()
    $lastSummary = $null
    $lastPlan = $null
    $lastPreview = $null
    $lastRemediation = $null
    $lastExportPath = $null
    $actionCount = 0
    $exitReason = 'Quit'
    $isAdministrator = Test-EFAdministrator
    $isRemoteSession = $false
    try {
        $senderInfo = Get-Variable -Name PSSenderInfo -ValueOnly -ErrorAction SilentlyContinue
        $isRemoteSession = $null -ne $senderInfo
    }
    catch {
        $isRemoteSession = $false
    }

    $addHistory = {
        param([string]$Action, [string]$Status, [string]$Message)
        $null = $history.Add([pscustomobject]@{
            PSTypeName = 'EndpointForge.MenuHistoryEntry'
            AtUtc      = [DateTime]::UtcNow
            Action     = $Action
            Status     = $Status
            Message    = $Message
        })
    }

    $running = $true
    :MenuLoop while ($running) {
        $isAdministrator = Test-EFAdministrator
        $lastAssessmentText = if ($null -eq $lastSummary) {
            'Not run'
        }
        else {
            "{0} at {1:u}" -f $lastSummary.OverallStatus, ([DateTime]$lastSummary.CompletedAtUtc)
        }

        Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'EndpointForge' -Color Cyan -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'Enterprise Windows endpoint automation' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ('=' * [math]::Min(72, $width)) -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ("Target: {0} ({1})" -f $computerName, $(if ($isRemoteSession) { 'remote session' } else { 'local endpoint' })) `
            -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ("Access: {0}" -f $(if ($isAdministrator) { 'Administrator' } else { 'Standard user - assessment and preview available' })) `
            -Color $(if ($isAdministrator) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }) `
            -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ("Baseline: {0} {1}" -f $resolvedBaseline.Name, $resolvedBaseline.Version) -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text ("Last assessment: {0}" -f $lastAssessmentText) -NoColor:$effectiveNoColor -Width $width
        if ($isRemoteSession) {
            Write-EFMenuLine -Text '[REMOTE] Actions affect the endpoint named above, not your local workstation.' `
                -Color Yellow -NoColor:$effectiveNoColor -Width $width
        }

        Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '1. Run or refresh assessment                 [read only]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '2. Review detailed findings                  [read only]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '3. Build remediation plan                    [read only]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '4. Preview selected automatic fixes          [no changes]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '5. Apply selected automatic fixes            [changes endpoint]' -Color Yellow -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '6. Export current session report             [writes JSON]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '7. Select a different baseline               [clears cached results]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text '8. Create a new baseline                     [writes JSON + schema]' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'H. Help and safety guide' -NoColor:$effectiveNoColor -Width $width
        Write-EFMenuLine -Text 'Q. Quit' -NoColor:$effectiveNoColor -Width $width

        $choice = Read-EFMenuInput -Prompt 'Choose an option'
        if ($null -eq $choice) {
            $exitReason = 'InputClosed'
            break MenuLoop
        }
        $normalizedChoice = $choice.Trim().ToUpperInvariant()
        $shouldPause = $true
        $currentAction = $normalizedChoice

        try {
            switch -Regex ($normalizedChoice) {
                '^(1|A|ASSESS|ASSESSMENT|REFRESH)$' {
                    $currentAction = 'Assessment'
                    $actionCount++
                    Write-EFMenuLine -Text 'Collecting endpoint evidence...' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    $summaryParameters = @{
                        Baseline                = $activeBaseline
                        IncludeSoftware         = [bool]$IncludeSoftware
                        MinimumFreeSpacePercent = $MinimumFreeSpacePercent
                        MaximumUptimeDays       = $MaximumUptimeDays
                        NoProgress              = [bool]$NoProgress
                    }
                    $lastSummary = Get-EFEndpointSummary @summaryParameters
                    $null = Show-EFEndpointSummary -InputObject $lastSummary -NoColor:$effectiveNoColor
                    & $addHistory 'Assessment' 'Completed' $lastSummary.OverallStatus
                    break
                }
                '^(2|D|DETAIL|DETAILS|FINDINGS)$' {
                    $currentAction = 'Detailed findings'
                    $actionCount++
                    if ($null -eq $lastSummary) {
                        Write-EFMenuLine -Text 'No cached assessment exists; collecting one now...' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                        $summaryParameters = @{
                            Baseline                = $activeBaseline
                            IncludeSoftware         = [bool]$IncludeSoftware
                            MinimumFreeSpacePercent = $MinimumFreeSpacePercent
                            MaximumUptimeDays       = $MaximumUptimeDays
                            NoProgress              = [bool]$NoProgress
                        }
                        $lastSummary = Get-EFEndpointSummary @summaryParameters
                    }
                    $null = Show-EFEndpointSummary -InputObject $lastSummary -Detailed -NoColor:$effectiveNoColor
                    & $addHistory 'Detailed findings' 'Completed' "$($lastSummary.IssueCount) issue(s), $($lastSummary.UnknownCount) unknown"
                    break
                }
                '^(3|P|PLAN)$' {
                    $currentAction = 'Remediation plan'
                    $actionCount++
                    Write-EFMenuLine -Text 'Evaluating the active baseline...' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    $lastPlan = Get-EFRemediationPlan -Baseline $activeBaseline -NoProgress:$NoProgress
                    Write-EFMenuPlan -Plan $lastPlan -NoColor:$effectiveNoColor -Width $width
                    & $addHistory 'Remediation plan' 'Completed' $lastPlan.Summary
                    break
                }
                '^(4|V|PREVIEW)$' {
                    $currentAction = 'Remediation preview'
                    $actionCount++
                    $lastPlan = Get-EFRemediationPlan -Baseline $activeBaseline -NoProgress:$NoProgress
                    Write-EFMenuPlan -Plan $lastPlan -NoColor:$effectiveNoColor -Width $width
                    if ([int]$lastPlan.AutomaticCount -eq 0) {
                        Write-EFMenuLine -Text '[OK] There are no automatic changes to preview.' -Color Green -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Remediation preview' 'NotRequired' 'No automatic changes were available.'
                        break
                    }
                    $selectedControlIds = @(Select-EFMenuControlId -Steps $lastPlan.Steps -NoColor:$effectiveNoColor -Width $width)
                    if ($selectedControlIds.Count -eq 0) {
                        Write-EFMenuLine -Text '[CANCELLED] No controls were selected.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Remediation preview' 'Cancelled' 'No controls were selected.'
                        break
                    }
                    $previewParameters = @{
                        Baseline   = $activeBaseline
                        ControlId  = $selectedControlIds
                        NoProgress = [bool]$NoProgress
                        WhatIf     = $true
                        Confirm    = $false
                    }
                    $lastPreview = Invoke-EFEndpointRemediation @previewParameters
                    Write-EFMenuRemediationReport -Report $lastPreview -NoColor:$effectiveNoColor -Width $width
                    & $addHistory 'Remediation preview' 'Completed' "$($selectedControlIds.Count) control(s) previewed."
                    break
                }
                '^(5|F|FIX|APPLY)$' {
                    $currentAction = 'Apply remediation'
                    $actionCount++
                    $lastPlan = Get-EFRemediationPlan -Baseline $activeBaseline -NoProgress:$NoProgress
                    Write-EFMenuPlan -Plan $lastPlan -NoColor:$effectiveNoColor -Width $width
                    if ([int]$lastPlan.AutomaticCount -eq 0) {
                        Write-EFMenuLine -Text '[OK] There are no automatic changes to apply.' -Color Green -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Apply remediation' 'NotRequired' 'No automatic changes were available.'
                        break
                    }
                    if (-not (Test-EFAdministrator)) {
                        Write-EFMenuLine -Text '[BLOCKED] Applying changes requires an elevated PowerShell session. Assessment, planning, and WhatIf preview remain available.' `
                            -Color Red -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Apply remediation' 'Blocked' 'Administrator access is required.'
                        break
                    }
                    $selectedControlIds = @(Select-EFMenuControlId -Steps $lastPlan.Steps -NoColor:$effectiveNoColor -Width $width)
                    if ($selectedControlIds.Count -eq 0) {
                        Write-EFMenuLine -Text '[CANCELLED] No controls were selected.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Apply remediation' 'Cancelled' 'No controls were selected.'
                        break
                    }

                    Write-EFMenuLine -Text 'Running the required WhatIf preview first...' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    $previewParameters = @{
                        Baseline   = $activeBaseline
                        ControlId  = $selectedControlIds
                        NoProgress = [bool]$NoProgress
                        WhatIf     = $true
                        Confirm    = $false
                    }
                    $lastPreview = Invoke-EFEndpointRemediation @previewParameters
                    Write-EFMenuRemediationReport -Report $lastPreview -NoColor:$effectiveNoColor -Width $width
                    if ([int]$lastPreview.FailureCount -gt 0) {
                        Write-EFMenuLine -Text '[BLOCKED] The preview reported failures. Resolve them before applying changes.' `
                            -Color Red -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Apply remediation' 'Blocked' 'The required preview reported failures.'
                        break
                    }

                    $selectedSteps = @($lastPlan.Steps | Where-Object { $_.ControlId -in $selectedControlIds })
                    $selectedRebootCount = @($selectedSteps | Where-Object RequiresReboot).Count
                    Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'CHANGE CONFIRMATION' -Color Red -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text ("Target: {0}" -f $computerName) -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text ("Baseline: {0} {1}" -f $resolvedBaseline.Name, $resolvedBaseline.Version) -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text ("Selected automatic controls: {0}" -f ($selectedControlIds -join ', ')) -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text ("Restart-impacting controls: {0}. EndpointForge will not restart the device." -f $selectedRebootCount) `
                        -Color Yellow -NoColor:$effectiveNoColor -Width $width
                    $acknowledgement = Read-EFMenuInput -Prompt 'Type APPLY to make these changes; anything else cancels'
                    if ($null -eq $acknowledgement -or $acknowledgement.Trim() -cne 'APPLY') {
                        Write-EFMenuLine -Text '[CANCELLED] Endpoint state was not changed.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Apply remediation' 'Cancelled' 'The APPLY acknowledgement was not entered.'
                        break
                    }

                    $applyParameters = @{
                        Baseline   = $activeBaseline
                        ControlId  = $selectedControlIds
                        NoProgress = [bool]$NoProgress
                        Confirm    = $false
                    }
                    $lastRemediation = Invoke-EFEndpointRemediation @applyParameters
                    Write-EFMenuRemediationReport -Report $lastRemediation -NoColor:$effectiveNoColor -Width $width
                    & $addHistory 'Apply remediation' 'Completed' $lastRemediation.Summary

                    Write-EFMenuLine -Text 'Verifying endpoint state with a fresh assessment...' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    $summaryParameters = @{
                        Baseline                = $activeBaseline
                        IncludeSoftware         = [bool]$IncludeSoftware
                        MinimumFreeSpacePercent = $MinimumFreeSpacePercent
                        MaximumUptimeDays       = $MaximumUptimeDays
                        NoProgress              = [bool]$NoProgress
                    }
                    $lastSummary = Get-EFEndpointSummary @summaryParameters
                    $lastPlan = $null
                    $null = Show-EFEndpointSummary -InputObject $lastSummary -NoColor:$effectiveNoColor
                    break
                }
                '^(6|E|EXPORT)$' {
                    $currentAction = 'Export session report'
                    $actionCount++
                    if ($null -eq $lastSummary -and $null -eq $lastPlan -and $null -eq $lastPreview -and $null -eq $lastRemediation) {
                        Write-EFMenuLine -Text '[NOT READY] Run an assessment, plan, or preview before exporting.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Export session report' 'NotReady' 'There were no cached results to export.'
                        break
                    }
                    $reportBundle = [pscustomobject][ordered]@{
                        PSTypeName       = 'EndpointForge.MenuReport'
                        SchemaVersion    = '1.0'
                        ExportedAtUtc    = [DateTime]::UtcNow
                        ComputerName     = $computerName
                        BaselineName     = [string]$resolvedBaseline.Name
                        BaselineVersion  = [string]$resolvedBaseline.Version
                        Summary          = $lastSummary
                        Plan             = $lastPlan
                        Preview          = $lastPreview
                        Remediation      = $lastRemediation
                        SessionHistory   = @($history)
                    }
                    $timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmssfff')
                    $fileName = "EndpointForge-$computerName-$timestamp.json"
                    $exportPath = Join-Path $resolvedReportDirectory $fileName
                    $createdFile = $reportBundle | Export-EFEndpointReport -Path $exportPath -PassThru
                    $lastExportPath = $createdFile.FullName
                    Write-EFMenuLine -Text ("[EXPORTED] {0}" -f $lastExportPath) -Color Green -NoColor:$effectiveNoColor -Width $width
                    & $addHistory 'Export session report' 'Completed' $lastExportPath
                    break
                }
                '^(7|B|BASELINE|SELECT)$' {
                    $currentAction = 'Select baseline'
                    $actionCount++
                    Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'Available built-in baselines' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    foreach ($availableBaseline in @(Get-EFBaseline -ListAvailable)) {
                        Write-EFMenuLine -Text ("- {0} {1}: {2}" -f $availableBaseline.Name, $availableBaseline.Version, $availableBaseline.Description) `
                            -NoColor:$effectiveNoColor -Width $width -Indent 2
                    }
                    $baselineSelection = Read-EFMenuInput -Prompt 'Enter a built-in name or custom JSON path; press Enter to cancel'
                    if ($null -eq $baselineSelection -or [string]::IsNullOrWhiteSpace($baselineSelection)) {
                        Write-EFMenuLine -Text '[CANCELLED] The active baseline was not changed.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Select baseline' 'Cancelled' 'No baseline was entered.'
                        break
                    }
                    $candidateBaseline = Resolve-EFBaseline -Baseline $baselineSelection.Trim()
                    $activeBaseline = $baselineSelection.Trim()
                    $resolvedBaseline = $candidateBaseline
                    $lastSummary = $null
                    $lastPlan = $null
                    $lastPreview = $null
                    $lastRemediation = $null
                    Write-EFMenuLine -Text ("[SELECTED] {0} {1}. Cached assessment and remediation results were cleared." -f `
                        $resolvedBaseline.Name, $resolvedBaseline.Version) -Color Green -NoColor:$effectiveNoColor -Width $width
                    & $addHistory 'Select baseline' 'Completed' "$($resolvedBaseline.Name) $($resolvedBaseline.Version)"
                    break
                }
                '^(8|N|NEW|CREATE)$' {
                    $currentAction = 'Create baseline'
                    $actionCount++
                    Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'Create a baseline' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    $newName = Read-EFMenuInput -Prompt 'Baseline name (for example Contoso.Workstation); press Enter to cancel'
                    if ($null -eq $newName -or [string]::IsNullOrWhiteSpace($newName)) {
                        Write-EFMenuLine -Text '[CANCELLED] No baseline was created.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                        & $addHistory 'Create baseline' 'Cancelled' 'No name was entered.'
                        break
                    }
                    $newDescription = Read-EFMenuInput -Prompt 'Description (optional)'
                    $newVersion = Read-EFMenuInput -Prompt 'Version [1.0.0]'
                    if ([string]::IsNullOrWhiteSpace($newVersion)) { $newVersion = '1.0.0' }
                    Write-EFMenuLine -Text 'Template: 1 Starter, 2 EnterpriseRecommended, 3 AuditOnly' -NoColor:$effectiveNoColor -Width $width
                    $templateChoice = Read-EFMenuInput -Prompt 'Template [1]'
                    $newTemplate = switch (([string]$templateChoice).Trim().ToUpperInvariant()) {
                        '' { 'Starter' }
                        '1' { 'Starter' }
                        'STARTER' { 'Starter' }
                        '2' { 'EnterpriseRecommended' }
                        'ENTERPRISERECOMMENDED' { 'EnterpriseRecommended' }
                        '3' { 'AuditOnly' }
                        'AUDITONLY' { 'AuditOnly' }
                        default { throw [System.ArgumentException]::new("Unknown template '$templateChoice'. Choose 1, 2, or 3.") }
                    }
                    $defaultBaselinePath = Join-Path (Join-Path $resolvedReportDirectory 'Baselines') ("{0}.json" -f $newName.Trim())
                    $newPath = Read-EFMenuInput -Prompt "Output path [$defaultBaselinePath]"
                    if ([string]::IsNullOrWhiteSpace($newPath)) { $newPath = $defaultBaselinePath }
                    $newBaselineParameters = @{
                        Name        = $newName.Trim()
                        Version     = $newVersion.Trim()
                        Template    = $newTemplate
                        Path        = $newPath.Trim()
                    }
                    if (-not [string]::IsNullOrWhiteSpace($newDescription)) {
                        $newBaselineParameters.Description = $newDescription.Trim()
                    }
                    $createdBaseline = New-EFBaseline @newBaselineParameters
                    $activeBaseline = $createdBaseline.Path
                    $resolvedBaseline = Resolve-EFBaseline -Baseline $activeBaseline
                    $lastSummary = $null
                    $lastPlan = $null
                    $lastPreview = $null
                    $lastRemediation = $null
                    Write-EFMenuLine -Text ("[CREATED] {0}" -f $createdBaseline.Path) -Color Green -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text ("Schema: {0}" -f $createdBaseline.SchemaPath) -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'The new baseline is now active. Review it before planning or applying changes.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                    & $addHistory 'Create baseline' 'Completed' $createdBaseline.Path
                    break
                }
                '^(H|HELP|\?)$' {
                    $currentAction = 'Help'
                    $actionCount++
                    Write-EFMenuLine -Text '' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'Safety guide' -Color Cyan -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text '1-3 only read endpoint state. Option 4 uses PowerShell WhatIf and cannot change state.' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'Option 5 applies only the controls you select. It requires Administrator access, always runs a fresh preview, and requires you to type APPLY exactly.' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'EndpointForge never restarts the endpoint. A result may tell you that a restart should be scheduled through your normal change process.' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'Options 6 and 8 write files. Selecting or creating a baseline clears cached results so they cannot be mistaken for results from the new baseline.' -NoColor:$effectiveNoColor -Width $width
                    Write-EFMenuLine -Text 'For automation, leave the menu and use Get-EFEndpointSummary, Get-EFRemediationPlan, Export-EFEndpointReport, and Invoke-EFEndpointRemediation directly.' -NoColor:$effectiveNoColor -Width $width
                    & $addHistory 'Help' 'Viewed' 'Safety guide displayed.'
                    break
                }
                '^(Q|QUIT|EXIT)$' {
                    $exitReason = 'Quit'
                    $running = $false
                    $shouldPause = $false
                    break
                }
                default {
                    Write-EFMenuLine -Text '[INVALID] Choose 1-8, H, or Q.' -Color Yellow -NoColor:$effectiveNoColor -Width $width
                    $shouldPause = $false
                }
            }
        }
        catch [System.Management.Automation.PipelineStoppedException] {
            throw
        }
        catch {
            $errorRecord = [pscustomobject]@{
                PSTypeName = 'EndpointForge.MenuError'
                AtUtc      = [DateTime]::UtcNow
                Action     = $currentAction
                Message    = $_.Exception.Message
                ErrorId    = $_.FullyQualifiedErrorId
            }
            $null = $menuErrors.Add($errorRecord)
            & $addHistory $currentAction 'Failed' $_.Exception.Message
            Write-EFMenuLine -Text ("[ERROR] {0}" -f $_.Exception.Message) -Color Red -NoColor:$effectiveNoColor -Width $width
            Write-EFMenuLine -Text 'The menu is still active. Correct the issue or choose another action.' -NoColor:$effectiveNoColor -Width $width
        }

        if ($shouldPause -and -not $NoPause -and $running) {
            $pauseInput = Read-EFMenuInput -Prompt 'Press Enter to return to the menu'
            if ($null -eq $pauseInput) {
                $exitReason = 'InputClosed'
                break MenuLoop
            }
        }
    }

    if ($PassThru) {
        [pscustomobject]@{
            PSTypeName       = 'EndpointForge.MenuSession'
            ComputerName     = $computerName
            StartedAtUtc     = $startedAtUtc
            CompletedAtUtc   = [DateTime]::UtcNow
            ExitReason       = $exitReason
            IsRemoteSession  = $isRemoteSession
            IsAdministrator  = $isAdministrator
            BaselineName     = [string]$resolvedBaseline.Name
            BaselineVersion  = [string]$resolvedBaseline.Version
            BaselinePath     = [string](Get-EFPropertyValue -InputObject $resolvedBaseline -Name 'SourcePath')
            ReportDirectory  = $resolvedReportDirectory
            ActionCount      = $actionCount
            ErrorCount       = $menuErrors.Count
            LastExportPath   = $lastExportPath
            LastSummary      = $lastSummary
            LastPlan         = $lastPlan
            LastPreview      = $lastPreview
            LastRemediation  = $lastRemediation
            History          = @($history)
            Errors           = @($menuErrors)
        }
    }
}
