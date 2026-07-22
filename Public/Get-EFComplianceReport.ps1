function Get-EFComplianceReport {
    <#
    .SYNOPSIS
    Checks this computer against a selected checklist without applying fixes.

    .DESCRIPTION
    Reads each selected item and compares it with the expected answer in a checklist.
    Items can cover Windows settings, an exact local file, literal text near the end of a
    log, recent Windows event IDs, or one TCP host and port. This command does not apply a
    fix or change Windows. A TcpPort item does make one real, observable connection
    attempt to the named destination, then closes it without sending application data.

    File-text results do not contain matching lines, and event results do not contain
    event messages or event data. In script output, a checklist is called a baseline and
    each checklist item is called a control. Those names are retained so existing
    PowerShell automation remains compatible.

    The report includes results, a score, guidance, and a predictable ExitCode for
    scripts: 0 when checked items match, 2 when an item does not match, or 3 when one or
    more items could not be checked.

    Use Test-EFEndpointCompliance when a simple Boolean answer is needed.

    .PARAMETER Baseline
    The checklist to use: a built-in name, a checklist JSON file, or an object returned
    by Get-EFBaseline. Review custom paths, event queries, hosts, and ports before running
    the checklist.

    .PARAMETER ControlId
    One or more checklist item IDs to check. Every item is checked by default.

    .PARAMETER NoProgress
    Suppresses the progress display for non-interactive automation hosts.

    .EXAMPLE
    Get-EFComplianceReport

    .EXAMPLE
    $report = Get-EFComplianceReport -Baseline .\contoso-baseline.json
    $report.Results | Where-Object Status -ne 'Compliant'

    .EXAMPLE
    Get-EFComplianceReport -Baseline .\Contoso.EverydayChecks.json -NoProgress

    Runs the four report-only everyday checks in the custom file. If it includes TcpPort,
    the named connection attempt can be recorded by the destination or network tools.

    .OUTPUTS
    EndpointForge.ComplianceReport
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object]$Baseline = 'EnterpriseRecommended',

        [string[]]$ControlId,

        [switch]$NoProgress
    )

    $null = Test-EFWindows -Throw
    $correlationId = [guid]::NewGuid().ToString()
    $resolvedBaseline = Resolve-EFBaseline -Baseline $Baseline
    $controls = @($resolvedBaseline.Controls)

    if ($PSBoundParameters.ContainsKey('ControlId') -and $null -ne $ControlId -and $ControlId.Length -gt 0) {
        $missingIds = @($ControlId | Where-Object { $_ -notin $controls.Id })
        if ($missingIds.Count -gt 0) {
            throw [System.ArgumentException]::new("Unknown control Id(s): $($missingIds -join ', ')")
        }
        $controls = @($controls | Where-Object { $_.Id -in @($ControlId) })
    }

    Write-EFLog -Message "Compliance evaluation started for baseline '$($resolvedBaseline.Name)'." `
        -CorrelationId $correlationId -Data @{ controlCount = $controls.Count }

    $controlIndex = 0
    $baselineCommandArgument = Get-EFBaselineCommandArgument -Baseline $resolvedBaseline
    $results = @(
        foreach ($control in $controls) {
            $controlIndex++
            if (-not $NoProgress) {
                Write-Progress -Id 1102 -Activity 'EndpointForge checklist check' `
                    -Status "Checking: $($control.Title)" `
                    -PercentComplete ([math]::Round(($controlIndex / $controls.Count) * 100))
            }
            $controlResult = Get-EFControlState -Control $control
            if ($controlResult.Status -eq 'NonCompliant' -and $controlResult.Remediable) {
                $controlResult.RecommendedAction = if ($null -ne $baselineCommandArgument) {
                    "Preview this supported fix before approval. For scripts: Invoke-EFEndpointRemediation $baselineCommandArgument -ControlId '$($controlResult.ControlId)' -WhatIf"
                }
                else {
                    'Create a fix plan from this same in-memory checklist, then preview the supported change before approval.'
                }
            }
            $controlResult
        }
    )
    if (-not $NoProgress) {
        Write-Progress -Id 1102 -Activity 'EndpointForge checklist check' -Completed
    }

    $compliantCount = @($results | Where-Object Status -eq 'Compliant').Count
    $nonCompliantCount = @($results | Where-Object Status -eq 'NonCompliant').Count
    $notApplicableCount = @($results | Where-Object Status -eq 'NotApplicable').Count
    $errorCount = @($results | Where-Object Status -eq 'Error').Count
    $knownCount = $compliantCount + $nonCompliantCount
    $attemptedCount = $knownCount + $errorCount
    $score = if ($knownCount -eq 0) { 100 } else { [math]::Round(($compliantCount / $knownCount) * 100, 1) }
    $coveragePercent = if ($attemptedCount -eq 0) { 100 } else { [math]::Round(($knownCount / $attemptedCount) * 100, 1) }
    $dataStatus = if ($errorCount -eq 0) { 'Complete' } elseif ($knownCount -eq 0) { 'Failed' } else { 'Partial' }
    $isCompliant = $nonCompliantCount -eq 0 -and $errorCount -eq 0
    $exitCode = if ($errorCount -gt 0) { 3 } elseif ($nonCompliantCount -gt 0) { 2 } else { 0 }
    $status = if ($nonCompliantCount -gt 0) { 'NonCompliant' } elseif ($errorCount -gt 0) { 'Incomplete' } else { 'Compliant' }
    $automaticFixCount = @($results | Where-Object { $_.Status -eq 'NonCompliant' -and $_.Remediable }).Count
    $summaryText = if ($isCompliant) {
        "$compliantCount applicable checklist item(s) have the expected result."
    }
    elseif ($errorCount -gt 0) {
        "The check is incomplete: $nonCompliantCount item(s) do not match and $errorCount could not be checked."
    }
    else {
        "$nonCompliantCount checklist item(s) need attention. $score% of the items that could be checked match."
    }
    $nextStep = if ($isCompliant) {
        'No supported fix is needed.'
    }
    elseif ($errorCount -gt 0) {
        'Review the items that could not be checked. Some protected information requires PowerShell to be opened with Run as Administrator (also called an elevated session).'
    }
    elseif ($automaticFixCount -gt 0) {
        'Create a fix plan to see what EndpointForge can safely preview and what needs a person to review.'
    }
    else {
        'Review the details and follow your organization''s approved manual guidance. EndpointForge does not change these report-only items.'
    }

    $report = [pscustomobject]@{
        PSTypeName          = 'EndpointForge.ComplianceReport'
        ComputerName        = $env:COMPUTERNAME
        BaselineName        = [string]$resolvedBaseline.Name
        BaselineVersion     = [string]$resolvedBaseline.Version
        ChecklistName       = [string]$resolvedBaseline.Name
        ChecklistVersion    = [string]$resolvedBaseline.Version
        ChecklistItemCount  = $controls.Count
        CorrelationId       = $correlationId
        EvaluatedAtUtc      = [DateTime]::UtcNow
        IsCompliant         = $isCompliant
        Status              = $status
        Score               = $score
        DataStatus          = $dataStatus
        CoveragePercent     = $coveragePercent
        ExitCode            = $exitCode
        Summary             = $summaryText
        NextStep            = $nextStep
        CompliantCount      = $compliantCount
        NonCompliantCount   = $nonCompliantCount
        NotApplicableCount  = $notApplicableCount
        ErrorCount          = $errorCount
        AutomaticFixCount   = $automaticFixCount
        Results             = $results
    }

    Write-EFLog -Message "Compliance evaluation completed for baseline '$($resolvedBaseline.Name)'." `
        -Level $(if ($isCompliant) { 'Information' } else { 'Warning' }) -CorrelationId $correlationId `
        -Data @{ score = $score; exitCode = $exitCode; nonCompliant = $nonCompliantCount; errors = $errorCount }

    return $report
}
