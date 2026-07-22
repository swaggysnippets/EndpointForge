function ConvertTo-EFHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$InputObject,

        [ValidateNotNullOrEmpty()]
        [string]$Title = 'EndpointForge report'
    )

    $encode = {
        param([AllowNull()][object]$Value)

        if ($null -eq $Value) { return '' }
        $text = if ($Value -is [DateTime]) {
            $Value.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss UTC', [Globalization.CultureInfo]::InvariantCulture)
        }
        elseif ($Value -is [bool]) {
            if ($Value) { 'Yes' } else { 'No' }
        }
        elseif ($Value -is [string] -or $Value.GetType().IsPrimitive -or $Value -is [decimal]) {
            [string]$Value
        }
        else {
            ConvertTo-Json -InputObject (ConvertTo-EFSerializableValue -InputObject $Value) -Depth 12 -Compress
        }
        [Net.WebUtility]::HtmlEncode($text)
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
            'Ready' { 'Ready' }
            'Limited' { 'Ready with limits' }
            'Blocked' { 'Not available here' }
            'Improved' { 'Improved' }
            'NewIssue' { 'Needs attention now' }
            'CouldNotCheck' { 'Could not check' }
            'Unchanged' { 'Stayed the same' }
            'NowAvailable' { 'Information available now' }
            'ChecklistChanged' { 'Checklist changed' }
            'Changed' { 'Changed and checked' }
            'PartiallyChanged' { 'A value changed, but the fix did not complete' }
            'VerificationFailed' { 'Changed, but the expected result was not confirmed' }
            'EvaluationFailed' { 'Could not check before changing' }
            'WhatIf' { 'Preview only - not changed' }
            'NotRequired' { 'Already matches' }
            'NotRemediable' { 'Needs manual review' }
            'Skipped' { 'Not approved - not changed' }
            'Automatic' { 'EndpointForge can fix' }
            'Manual' { 'You need to review' }
            'NoAction' { 'No change needed' }
            default { [string]$Value }
        }
    }

    $friendlyLabel = {
        param([string]$Name)

        switch ($Name) {
            'OverallStatus' { 'Overall result' }
            'HealthStatus' { 'Computer health' }
            'ComplianceStatus' { 'Checklist result' }
            'DataStatus' { 'Check completeness' }
            'Score' { 'Overall score' }
            'CoveragePercent' { 'Information checked' }
            'IssueCount' { 'Items needing attention' }
            'UnknownCount' { 'Items not fully checked' }
            'TargetCount' { 'Computers requested' }
            'SucceededCount' { 'Computers checked' }
            'FailedCount' { 'Computers not checked' }
            'HealthyCount' { 'Computers that look good' }
            'WarningCount' { 'Computers needing attention' }
            'CriticalCount' { 'Computers needing urgent attention' }
            'IncompleteCount' { 'Computers not fully checked' }
            'AutomaticCount' { 'Fixes EndpointForge can make' }
            'ManualCount' { 'Items for you to review' }
            'BlockedCount' { 'Items that could not be checked' }
            'ChangedCount' { 'Settings changed' }
            'FailureCount' { 'Changes not completed' }
            'Status' { 'Readiness' }
            'AssessmentReady' { 'Can run a check' }
            'FixReady' { 'Can apply supported fixes now' }
            'ControlCount' { 'Checklist items' }
            'ImprovedCount' { 'Items improved' }
            'NewIssueCount' { 'New items needing attention' }
            'CouldNotCheckCount' { 'Items not checked later' }
            'UnchangedCount' { 'Items unchanged' }
            'BeforeScore' { 'Earlier score' }
            'AfterScore' { 'Latest score' }
            'ScoreChange' { 'Score change' }
            'BaselineName' { 'Checklist' }
            'BaselineVersion' { 'Checklist version' }
            'ComputerName' { 'Computer' }
            'BeforeComputerName' { 'Earlier check computer' }
            'AfterComputerName' { 'Latest check computer' }
            'BeforeChecklistName' { 'Earlier checklist' }
            'AfterChecklistName' { 'Latest checklist' }
            'CompletedAtUtc' { 'Check finished' }
            'CreatedAtUtc' { 'Created' }
            'IsRebootPending' { 'Restart waiting' }
            'RebootRequired' { 'Restart may be needed' }
            'CurrentValue' { 'Found now' }
            'DesiredValue' { 'Expected' }
            'BeforeValue' { 'Before' }
            'AfterValue' { 'After' }
            'ControlId' { 'Item ID' }
            'CurrentStatus' { 'Check result' }
            'Action' { 'Who can fix it' }
            'Outcome' { 'Result' }
            default { ($Name -creplace '([a-z0-9])([A-Z])', '$1 $2') }
        }
    }

    $statusClass = {
        param([AllowNull()][object]$Value)

        switch ([string]$Value) {
            { $_ -in @('Healthy', 'Compliant', 'Complete', 'Successful', 'Succeeded', 'Ready') } { 'good'; break }
            { $_ -in @('Changed', 'NotRequired') } { 'good'; break }
            { $_ -in @('Warning', 'Partial', 'Incomplete', 'Manual', 'Limited', 'WhatIf', 'Skipped') } { 'warn'; break }
            { $_ -in @('Critical', 'NonCompliant', 'Failed', 'Error', 'Blocked', 'PartiallyChanged', 'VerificationFailed', 'EvaluationFailed') } { 'bad'; break }
            default { 'neutral' }
        }
    }

    $get = {
        param([AllowNull()][object]$Object, [string]$Name)

        if ($null -eq $Object) { return $null }
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property) { return $null }
        $property.Value
    }

    $builder = [Text.StringBuilder]::new()
    $null = $builder.AppendLine('<!doctype html>')
    $null = $builder.AppendLine('<html lang="en"><head><meta charset="utf-8">')
    $null = $builder.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    $null = $builder.AppendLine("<title>$(& $encode $Title)</title>")
    $null = $builder.AppendLine('<style>')
    $null = $builder.AppendLine(':root{color-scheme:light;--ink:#182230;--muted:#5e6b7a;--line:#d9e1ea;--panel:#fff;--bg:#f3f6fa;--brand:#185abd;--good:#147a42;--warn:#9a5b00;--bad:#b42318}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 "Segoe UI",Arial,sans-serif}.wrap{max-width:1120px;margin:auto;padding:32px 20px 64px}header{background:linear-gradient(135deg,#123b6d,#185abd);color:#fff;border-radius:16px;padding:26px 30px;box-shadow:0 8px 24px #183b6d26}h1{margin:0 0 6px;font-size:29px}h2{font-size:21px;margin:0 0 14px}h3{font-size:17px;margin:22px 0 10px}.subtle{color:var(--muted)}header .subtle{color:#e4eefc}.panel{background:var(--panel);border:1px solid var(--line);border-radius:14px;margin-top:18px;padding:22px;box-shadow:0 3px 12px #21364d0d}.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(155px,1fr));gap:10px;margin:14px 0}.card{border:1px solid var(--line);border-left:5px solid #7890a8;border-radius:9px;padding:12px;background:#fbfcfe}.card.good{border-left-color:var(--good)}.card.warn{border-left-color:var(--warn)}.card.bad{border-left-color:var(--bad)}.label{color:var(--muted);font-size:12px;font-weight:600;text-transform:uppercase;letter-spacing:.03em}.value{font-size:17px;font-weight:650;margin-top:3px;overflow-wrap:anywhere}.notice{border-left:4px solid var(--brand);background:#edf5ff;padding:12px 14px;border-radius:6px;margin:14px 0}.table-wrap{overflow-x:auto;border:1px solid var(--line);border-radius:9px}table{width:100%;border-collapse:collapse;background:#fff}th,td{text-align:left;vertical-align:top;padding:10px 11px;border-bottom:1px solid var(--line);overflow-wrap:anywhere}th{background:#edf2f8;font-size:12px;text-transform:uppercase;letter-spacing:.03em}tr:last-child td{border-bottom:0}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f6f8fb;border:1px solid var(--line);padding:13px;border-radius:8px;font:12px/1.45 Consolas,monospace}.footer{margin-top:24px;color:var(--muted);font-size:12px}@media print{body{background:#fff}.wrap{max-width:none;padding:0}.panel,header{box-shadow:none;break-inside:avoid}}')
    $null = $builder.AppendLine('</style></head><body><main class="wrap">')
    $null = $builder.AppendLine(('<header><h1>{0}</h1><div class="subtle">A plain-language record created by EndpointForge on {1}.</div></header>' -f
        (& $encode $Title), (& $encode ([DateTime]::UtcNow))))
    $null = $builder.AppendLine('<div class="notice"><strong>Keep this report private.</strong> It can contain computer names, device details, and security findings.</div>')

    $cardProperties = @(
        'Status', 'AssessmentReady', 'FixReady', 'ControlCount',
        'OverallStatus', 'HealthStatus', 'ComplianceStatus', 'DataStatus', 'Score', 'CoveragePercent',
        'IssueCount', 'UnknownCount', 'TargetCount', 'SucceededCount', 'FailedCount', 'HealthyCount',
        'WarningCount', 'CriticalCount', 'IncompleteCount', 'AutomaticCount', 'ManualCount',
        'BlockedCount', 'ChangedCount', 'FailureCount', 'IsRebootPending', 'RebootRequired',
        'BeforeScore', 'AfterScore', 'ScoreChange', 'ImprovedCount', 'NewIssueCount',
        'CouldNotCheckCount', 'UnchangedCount'
    )
    $identityProperties = @(
        'ComputerName', 'BeforeComputerName', 'AfterComputerName', 'BaselineName', 'BaselineVersion',
        'BeforeChecklistName', 'AfterChecklistName', 'CreatedAtUtc', 'CompletedAtUtc'
    )
    $collectionProperties = [ordered]@{
        Findings = @('Title', 'Severity', 'Status', 'Message', 'SuggestedAction')
        Steps    = @('Title', 'Severity', 'CurrentStatus', 'Action', 'CurrentValue', 'DesiredValue', 'WhatWouldChange', 'RecommendedAction')
        Results  = @('ComputerName', 'OverallStatus', 'Score', 'IssueCount', 'Title', 'ControlId', 'BeforeStatus', 'Outcome', 'AfterStatus', 'BeforeValue', 'AfterValue', 'Message', 'RecoveryGuidance')
        FleetResults = @('ComputerName', 'OverallStatus', 'Score', 'IssueCount', 'UnknownCount', 'NextStep')
        Failures = @('ComputerName', 'Message')
        Changes  = @('Title', 'Category', 'BeforeStatus', 'AfterStatus', 'BeforeValue', 'AfterValue', 'Explanation')
        Checks   = @('Name', 'Status', 'PlainLanguage', 'NextStep')
    }

    $reportNumber = 0
    foreach ($item in @($InputObject)) {
        $reportNumber++
        $typeName = if ($null -ne $item -and $item.PSObject.TypeNames.Count -gt 0) {
            [string]$item.PSObject.TypeNames[0]
        }
        else { 'PowerShell object' }
        $heading = if ($InputObject.Count -gt 1) { "Report item $reportNumber" } else { 'Results' }
        $computerName = & $get $item 'ComputerName'
        if (-not [string]::IsNullOrWhiteSpace([string]$computerName)) { $heading += " - $computerName" }

        $null = $builder.AppendLine("<section class=""panel""><h2>$(& $encode $heading)</h2>")
        $summary = & $get $item 'SummaryText'
        if ([string]::IsNullOrWhiteSpace([string]$summary)) {
            $summaryCandidate = & $get $item 'Summary'
            if ($summaryCandidate -is [string] -or $summaryCandidate -is [ValueType]) {
                $summary = $summaryCandidate
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$summary)) {
            $null = $builder.AppendLine("<p>$(& $encode $summary)</p>")
        }

        $identityRows = [Collections.Generic.List[string]]::new()
        foreach ($name in $identityProperties) {
            $value = & $get $item $name
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                $identityRows.Add("<tr><th>$(& $encode (& $friendlyLabel $name))</th><td>$(& $encode $value)</td></tr>")
            }
        }
        if ($identityRows.Count -gt 0) {
            $null = $builder.AppendLine('<div class="table-wrap"><table><tbody>')
            foreach ($row in $identityRows) { $null = $builder.AppendLine($row) }
            $null = $builder.AppendLine('</tbody></table></div>')
        }

        $cards = [Collections.Generic.List[string]]::new()
        foreach ($name in $cardProperties) {
            $value = & $get $item $name
            if ($null -eq $value) { continue }
            $displayValue = if ($name -in @('Status', 'OverallStatus', 'HealthStatus', 'ComplianceStatus', 'DataStatus')) {
                & $friendlyStatus $value
            }
            elseif ($name -eq 'CoveragePercent') { "$value%" }
            else { $value }
            $class = & $statusClass $value
            $cards.Add("<div class=""card $class""><div class=""label"">$(& $encode (& $friendlyLabel $name))</div><div class=""value"">$(& $encode $displayValue)</div></div>")
        }
        if ($cards.Count -gt 0) {
            $null = $builder.AppendLine('<div class="cards">')
            foreach ($card in $cards) { $null = $builder.AppendLine($card) }
            $null = $builder.AppendLine('</div>')
        }

        $renderedCollectionCount = 0
        foreach ($collectionName in $collectionProperties.Keys) {
            $collection = @(& $get $item $collectionName)
            if ($collection.Count -eq 0 -or ($collection.Count -eq 1 -and $null -eq $collection[0])) { continue }
            $columns = @($collectionProperties[$collectionName] | Where-Object {
                $columnName = $_
                @($collection | Where-Object { $null -ne $_ -and $null -ne $_.PSObject.Properties[$columnName] }).Count -gt 0
            })
            if ($columns.Count -eq 0) { continue }
            $renderedCollectionCount++

            $null = $builder.AppendLine("<h3>$(& $encode (& $friendlyLabel $collectionName))</h3><div class=""table-wrap""><table><thead><tr>")
            foreach ($column in $columns) {
                $null = $builder.AppendLine("<th>$(& $encode (& $friendlyLabel $column))</th>")
            }
            $null = $builder.AppendLine('</tr></thead><tbody>')
            foreach ($entry in $collection) {
                $null = $builder.AppendLine('<tr>')
                foreach ($column in $columns) {
                    $value = & $get $entry $column
                    if ($column -in @('Status', 'OverallStatus', 'CurrentStatus', 'Action', 'BeforeStatus', 'AfterStatus', 'Outcome', 'Category')) {
                        $value = & $friendlyStatus $value
                    }
                    $null = $builder.AppendLine("<td>$(& $encode $value)</td>")
                }
                $null = $builder.AppendLine('</tr>')
            }
            $null = $builder.AppendLine('</tbody></table></div>')
        }

        $nextStep = & $get $item 'NextStep'
        if (-not [string]::IsNullOrWhiteSpace([string]$nextStep)) {
            $null = $builder.AppendLine("<div class=""notice""><strong>Suggested next step:</strong> $(& $encode $nextStep)</div>")
        }

        if ($null -eq $item) {
            $null = $builder.AppendLine('<p>No report data was supplied.</p>')
        }
        elseif ($cards.Count -eq 0 -and $identityRows.Count -eq 0 -and $renderedCollectionCount -eq 0 -and [string]::IsNullOrWhiteSpace([string]$summary)) {
            $json = ConvertTo-Json -InputObject (ConvertTo-EFSerializableValue -InputObject $item) -Depth 12
            $null = $builder.AppendLine("<h3>Details</h3><pre>$(& $encode $json)</pre>")
        }
        $null = $builder.AppendLine("<div class=""footer"">Technical object type: $(& $encode $typeName)</div></section>")
    }

    $null = $builder.AppendLine('<p class="footer">EndpointForge reports what it could observe at the time of the check. Organization policies and later Windows changes can affect the current state.</p>')
    $null = $builder.AppendLine('</main></body></html>')
    $builder.ToString()
}
