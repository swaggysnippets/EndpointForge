function Compare-EFEndpointSummary {
    <#
    .SYNOPSIS
    Shows what changed between two EndpointForge computer checks.

    .DESCRIPTION
    Compares an earlier check with a later check without reading or changing either
    computer. Inputs can be EndpointForge endpoint summaries, menu reports, menu
    sessions, or paths to exported JSON reports.

    An item is counted as improved only when an earlier problem has a definite passing
    result in the later check. Missing or unreadable later information is reported as
    CouldNotCheck and is never described as fixed.

    .PARAMETER Before
    The earlier computer check, menu report, menu session, or exported JSON report path.

    .PARAMETER After
    The later computer check, menu report, menu session, or exported JSON report path.

    .PARAMETER AllowDifferentComputer
    Allows a side-by-side comparison of results from different computers. Without this
    switch, different computer names are rejected to prevent a misleading progress report.

    .EXAMPLE
    Compare-EFEndpointSummary -Before .\before.json -After .\after.json

    .EXAMPLE
    Compare-EFEndpointSummary $earlierSummary $latestSummary

    .OUTPUTS
    EndpointForge.EndpointComparison
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Previous', 'Reference')]
        [object]$Before,

        [Parameter(Mandatory, Position = 1)]
        [Alias('Latest', 'Difference')]
        [object]$After,

        [switch]$AllowDifferentComputer
    )

    $beforeSummary = Resolve-EFEndpointSummaryInput -InputObject $Before -Label 'Before'
    $afterSummary = Resolve-EFEndpointSummaryInput -InputObject $After -Label 'After'

    $beforeComputer = [string](Get-EFPropertyValue -InputObject $beforeSummary -Name 'ComputerName')
    $afterComputer = [string](Get-EFPropertyValue -InputObject $afterSummary -Name 'ComputerName')
    $differentComputer = -not [string]::Equals($beforeComputer.Trim(), $afterComputer.Trim(), [StringComparison]::OrdinalIgnoreCase)
    if ($differentComputer -and -not $AllowDifferentComputer) {
        throw [System.ArgumentException]::new(
            "The checks came from different computers ('$beforeComputer' and '$afterComputer'). Use -AllowDifferentComputer only for an intentional side-by-side comparison."
        )
    }

    $beforeHealth = Get-EFPropertyValue -InputObject $beforeSummary -Name 'Health'
    $afterHealth = Get-EFPropertyValue -InputObject $afterSummary -Name 'Health'
    $beforeChecklist = Get-EFPropertyValue -InputObject $beforeSummary -Name 'Compliance'
    $afterChecklist = Get-EFPropertyValue -InputObject $afterSummary -Name 'Compliance'

    $readText = {
        param([object]$Object, [string]$Name, [string]$FallbackName, [object]$FallbackObject)
        $value = [string](Get-EFPropertyValue -InputObject $Object -Name $Name)
        if ([string]::IsNullOrWhiteSpace($value) -and $null -ne $FallbackObject) {
            $value = [string](Get-EFPropertyValue -InputObject $FallbackObject -Name $FallbackName)
        }
        return $value
    }
    $beforeChecklistName = & $readText $beforeChecklist 'BaselineName' 'BaselineName' $beforeSummary
    $afterChecklistName = & $readText $afterChecklist 'BaselineName' 'BaselineName' $afterSummary
    $beforeChecklistVersion = & $readText $beforeChecklist 'BaselineVersion' 'BaselineVersion' $beforeSummary
    $afterChecklistVersion = & $readText $afterChecklist 'BaselineVersion' 'BaselineVersion' $afterSummary
    $checklistChanged = -not [string]::Equals($beforeChecklistName, $afterChecklistName, [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals($beforeChecklistVersion, $afterChecklistVersion, [StringComparison]::Ordinal)

    $getHealthTitle = {
        param([string]$Id)
        switch -Wildcard ($Id) {
            'DiskFreeSpace' { return 'System drive free space' }
            'Uptime' { return 'Time since the last Windows restart' }
            'PendingReboot' { return 'Windows restart status' }
            'Firewall*' { return (($Id -replace '^Firewall', '') + ' firewall') }
            'DefenderRealTimeProtection' { return 'Microsoft Defender real-time protection' }
            'BitLockerProtection' { return 'BitLocker protection' }
            'InventoryCollection' { return 'Computer information collection' }
            default { return $Id }
        }
    }
    $getState = {
        param([string]$Source, [string]$Status)
        if ([string]::IsNullOrWhiteSpace($Status) -or $Status -in @('Unknown', 'Error', 'Incomplete', 'Missing')) { return 'Unknown' }
        if ($Source -eq 'Health') {
            if ($Status -eq 'Healthy') { return 'Good' }
            if ($Status -eq 'NotApplicable') { return 'NotApplicable' }
            return 'NeedsAttention'
        }
        if ($Status -eq 'Compliant') { return 'Good' }
        if ($Status -eq 'NonCompliant') { return 'NeedsAttention' }
        if ($Status -eq 'NotApplicable') { return 'NotApplicable' }
        return 'Unknown'
    }
    $makeEvidence = {
        param([string]$Source, [object]$Item)
        $idProperty = if ($Source -eq 'Health') { 'Id' } else { 'ControlId' }
        $id = [string](Get-EFPropertyValue -InputObject $Item -Name $idProperty)
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw [System.IO.InvalidDataException]::new("A $Source comparison item does not have an identifier.")
        }
        $status = [string](Get-EFPropertyValue -InputObject $Item -Name 'Status')
        $title = if ($Source -eq 'Health') { & $getHealthTitle $id } else { [string](Get-EFPropertyValue -InputObject $Item -Name 'Title' -Default $id) }
        [pscustomobject]@{
            Key           = "${Source}::$id"
            Source        = $Source
            Id            = $id
            Title         = $title
            Status        = $status
            State         = & $getState $Source $status
            Value         = Get-EFPropertyValue -InputObject $Item -Name 'ActualValue'
            ExpectedValue = if ($Source -eq 'Health') {
                Get-EFPropertyValue -InputObject $Item -Name 'Threshold'
            } else {
                Get-EFPropertyValue -InputObject $Item -Name 'DesiredValue'
            }
            Message       = [string](Get-EFPropertyValue -InputObject $Item -Name 'Message')
        }
    }

    $beforeItems = @()
    $afterItems = @()
    $beforeItems += @((Get-EFPropertyValue -InputObject $beforeHealth -Name 'Checks') | ForEach-Object { & $makeEvidence 'Health' $_ })
    $beforeItems += @((Get-EFPropertyValue -InputObject $beforeChecklist -Name 'Results') | ForEach-Object { & $makeEvidence 'Checklist' $_ })
    $afterItems += @((Get-EFPropertyValue -InputObject $afterHealth -Name 'Checks') | ForEach-Object { & $makeEvidence 'Health' $_ })
    $afterItems += @((Get-EFPropertyValue -InputObject $afterChecklist -Name 'Results') | ForEach-Object { & $makeEvidence 'Checklist' $_ })

    $beforeByKey = @{}
    $afterByKey = @{}
    foreach ($item in $beforeItems) { if (-not $beforeByKey.ContainsKey($item.Key)) { $beforeByKey[$item.Key] = $item } }
    foreach ($item in $afterItems) { if (-not $afterByKey.ContainsKey($item.Key)) { $afterByKey[$item.Key] = $item } }
    $allKeys = @($beforeByKey.Keys + $afterByKey.Keys | Sort-Object -Unique)

    $changes = @(
        foreach ($key in $allKeys) {
            $hasBefore = $beforeByKey.ContainsKey($key)
            $hasAfter = $afterByKey.ContainsKey($key)
            $beforeItem = if ($hasBefore) { $beforeByKey[$key] } else { $null }
            $afterItem = if ($hasAfter) { $afterByKey[$key] } else { $null }
            $item = if ($hasAfter) { $afterItem } else { $beforeItem }
            $beforeState = if ($hasBefore) { $beforeItem.State } else { 'Missing' }
            $afterState = if ($hasAfter) { $afterItem.State } else { 'Missing' }

            $category = 'Changed'
            $explanation = ''
            if ($item.Source -eq 'Checklist' -and $checklistChanged) {
                $category = 'ChecklistChanged'
                $explanation = 'The checklist name or version changed. This item is shown for context but is not counted as improved or newly worse.'
            }
            elseif (-not $hasAfter) {
                $category = 'CouldNotCheck'
                $explanation = 'The later check did not contain this information. Its earlier result has not been treated as fixed.'
            }
            elseif ($afterState -eq 'Unknown') {
                $category = 'CouldNotCheck'
                $explanation = 'EndpointForge could not get a definite result in the later check. This item has not been treated as fixed.'
            }
            elseif (-not $hasBefore) {
                if ($afterState -eq 'NeedsAttention') {
                    $category = 'NewIssue'
                    $explanation = 'The earlier check did not include this item; the later check found that it needs attention.'
                }
                else {
                    $category = 'NowAvailable'
                    $explanation = 'This information was not in the earlier check and is available now.'
                }
            }
            elseif ($beforeState -eq 'Unknown') {
                if ($afterState -eq 'NeedsAttention') {
                    $category = 'NewIssue'
                    $explanation = 'The earlier check could not determine this result; the later check found that it needs attention.'
                }
                else {
                    $category = 'NowAvailable'
                    $explanation = 'The earlier check could not determine this result. The later check can read it now.'
                }
            }
            elseif ($beforeState -eq 'NeedsAttention' -and $afterState -eq 'Good') {
                $category = 'Improved'
                $explanation = 'This item needed attention earlier and has a definite passing result now.'
            }
            elseif ($beforeState -in @('Good', 'NotApplicable') -and $afterState -eq 'NeedsAttention') {
                $category = 'NewIssue'
                $explanation = 'This item did not need attention earlier and does now.'
            }
            elseif ($beforeState -eq $afterState) {
                $category = 'Unchanged'
                $explanation = if ($afterState -eq 'NeedsAttention') { 'This item still needs attention.' } else { 'This result stayed the same.' }
            }
            elseif ($afterState -eq 'NotApplicable') {
                $category = 'Changed'
                $explanation = 'The later check says this item is not used on this computer. It has not been treated as fixed.'
            }
            else {
                $category = 'Changed'
                $explanation = 'The result changed, but the change is not enough to call this item improved or newly worse.'
            }

            [pscustomobject]@{
                PSTypeName          = 'EndpointForge.EndpointComparisonChange'
                Source              = $item.Source
                Id                  = $item.Id
                Title               = $item.Title
                Category            = $category
                BeforeStatus        = if ($hasBefore) { $beforeItem.Status } else { 'Not present' }
                AfterStatus         = if ($hasAfter) { $afterItem.Status } else { 'Not present' }
                BeforeValue         = if ($hasBefore) { $beforeItem.Value } else { $null }
                AfterValue          = if ($hasAfter) { $afterItem.Value } else { $null }
                ExpectedValue       = if ($hasAfter) { $afterItem.ExpectedValue } else { $beforeItem.ExpectedValue }
                BeforeMessage       = if ($hasBefore) { $beforeItem.Message } else { '' }
                AfterMessage        = if ($hasAfter) { $afterItem.Message } else { '' }
                Explanation         = $explanation
            }
        }
    )

    $improvedCount = @($changes | Where-Object Category -eq 'Improved').Count
    $newIssueCount = @($changes | Where-Object Category -eq 'NewIssue').Count
    $couldNotCheckCount = @($changes | Where-Object Category -eq 'CouldNotCheck').Count
    $unchangedCount = @($changes | Where-Object Category -eq 'Unchanged').Count
    $nowAvailableCount = @($changes | Where-Object Category -eq 'NowAvailable').Count
    $otherChangedCount = @($changes | Where-Object Category -in @('Changed', 'ChecklistChanged')).Count

    $getNumber = {
        param([object]$Object, [string]$Name)
        $value = Get-EFPropertyValue -InputObject $Object -Name $Name
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return $null }
        return [math]::Round([double]$value, 1)
    }
    $beforeScore = & $getNumber $beforeSummary 'Score'
    $afterScore = & $getNumber $afterSummary 'Score'
    $beforeCoverage = & $getNumber $beforeSummary 'CoveragePercent'
    $afterCoverage = & $getNumber $afterSummary 'CoveragePercent'
    $scoreChange = if ($null -ne $beforeScore -and $null -ne $afterScore) { [math]::Round($afterScore - $beforeScore, 1) } else { $null }
    $coverageChange = if ($null -ne $beforeCoverage -and $null -ne $afterCoverage) { [math]::Round($afterCoverage - $beforeCoverage, 1) } else { $null }

    $summaryText = "$improvedCount improved; $newIssueCount new item(s) need attention; $couldNotCheckCount could not be checked; $unchangedCount stayed the same."
    if ($checklistChanged) {
        $summaryText += ' The checklist changed, so this is not a like-for-like progress check.'
    }
    if ($differentComputer) {
        $summaryText += ' The checks came from different computers.'
    }
    $nextStep = if ($differentComputer) {
        'Use this only as a side-by-side view. Compare two checks from the same computer to measure progress.'
    }
    elseif ($checklistChanged) {
        'For a reliable progress check, compare results made with the same checklist name and version.'
    }
    elseif ($couldNotCheckCount -gt 0) {
        'Review the items that could not be checked and try again with Administrator permission if Windows requires it.'
    }
    elseif ($newIssueCount -gt 0) {
        'Review the new items that need attention before approving any changes.'
    }
    elseif ($improvedCount -gt 0) {
        'Review the improved items and save this comparison with your support records if needed.'
    }
    else {
        'No newly improved or newly worse items were found.'
    }

    [pscustomobject]@{
        PSTypeName               = 'EndpointForge.EndpointComparison'
        ComparedAtUtc            = [DateTime]::UtcNow
        BeforeComputerName       = $beforeComputer
        AfterComputerName        = $afterComputer
        DifferentComputer        = $differentComputer
        BeforeCompletedAtUtc     = Get-EFPropertyValue -InputObject $beforeSummary -Name 'CompletedAtUtc'
        AfterCompletedAtUtc      = Get-EFPropertyValue -InputObject $afterSummary -Name 'CompletedAtUtc'
        BeforeChecklistName      = $beforeChecklistName
        BeforeChecklistVersion   = $beforeChecklistVersion
        AfterChecklistName       = $afterChecklistName
        AfterChecklistVersion    = $afterChecklistVersion
        ChecklistChanged         = $checklistChanged
        IsLikeForLike            = -not $differentComputer -and -not $checklistChanged
        BeforeScore              = $beforeScore
        AfterScore               = $afterScore
        ScoreChange              = $scoreChange
        BeforeCoveragePercent    = $beforeCoverage
        AfterCoveragePercent     = $afterCoverage
        CoverageChange           = $coverageChange
        ImprovedCount            = $improvedCount
        NewCount                 = $newIssueCount
        NewIssueCount            = $newIssueCount
        CouldNotCheckCount       = $couldNotCheckCount
        UnchangedCount           = $unchangedCount
        NowAvailableCount        = $nowAvailableCount
        OtherChangedCount        = $otherChangedCount
        AfterCollectionIncomplete = ([string](Get-EFPropertyValue -InputObject $afterSummary -Name 'DataStatus') -ne 'Complete') -or $couldNotCheckCount -gt 0
        Changes                  = @($changes)
        Summary                  = $summaryText
        NextStep                 = $nextStep
    }
}
