function Get-EFComplianceReport {
    <#
    .SYNOPSIS
    Gets a detailed compliance report for the local Windows endpoint.

    .DESCRIPTION
    Evaluates each selected baseline control without changing endpoint state. The rich
    report includes results, score, guidance, and a deterministic ExitCode: 0 compliant,
    2 noncompliant, or 3 when one or more controls could not be evaluated.

    Use Test-EFEndpointCompliance when a simple Boolean answer is needed.

    .PARAMETER Baseline
    A built-in baseline name, a JSON file path, or a baseline object returned by
    Get-EFBaseline.

    .PARAMETER ControlId
    One or more control identifiers to evaluate. All controls are evaluated by default.

    .PARAMETER NoProgress
    Suppresses the progress display for non-interactive automation hosts.

    .EXAMPLE
    Get-EFComplianceReport

    .EXAMPLE
    $report = Get-EFComplianceReport -Baseline .\contoso-baseline.json
    $report.Results | Where-Object Status -ne 'Compliant'

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
                Write-Progress -Id 1102 -Activity 'EndpointForge compliance' `
                    -Status "Evaluating $($control.Id): $($control.Title)" `
                    -PercentComplete ([math]::Round(($controlIndex / $controls.Count) * 100))
            }
            $controlResult = Get-EFControlState -Control $control
            if ($controlResult.Status -eq 'NonCompliant' -and $controlResult.Remediable) {
                $controlResult.RecommendedAction = if ($null -ne $baselineCommandArgument) {
                    "Preview automatic remediation: Invoke-EFEndpointRemediation $baselineCommandArgument -ControlId '$($controlResult.ControlId)' -WhatIf"
                }
                else {
                    'Pass this same in-memory baseline to Get-EFRemediationPlan, then review Invoke-EFEndpointRemediation -WhatIf.'
                }
            }
            $controlResult
        }
    )
    if (-not $NoProgress) {
        Write-Progress -Id 1102 -Activity 'EndpointForge compliance' -Completed
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
    $summaryText = if ($isCompliant) {
        "$compliantCount applicable control(s) are compliant."
    }
    elseif ($errorCount -gt 0) {
        "Evaluation is incomplete: $nonCompliantCount noncompliant control(s) and $errorCount error(s)."
    }
    else {
        "$nonCompliantCount control(s) require attention; compliance score is $score%."
    }
    $nextStep = if ($isCompliant) {
        'No remediation is required.'
    }
    elseif ($errorCount -gt 0) {
        'Review Results.RecommendedAction. Privileged security checks may require an elevated PowerShell session.'
    }
    else {
        'Run Get-EFRemediationPlan to separate automatic and manual actions.'
    }

    $report = [pscustomobject]@{
        PSTypeName          = 'EndpointForge.ComplianceReport'
        ComputerName        = $env:COMPUTERNAME
        BaselineName        = [string]$resolvedBaseline.Name
        BaselineVersion     = [string]$resolvedBaseline.Version
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
        Results             = $results
    }

    Write-EFLog -Message "Compliance evaluation completed for baseline '$($resolvedBaseline.Name)'." `
        -Level $(if ($isCompliant) { 'Information' } else { 'Warning' }) -CorrelationId $correlationId `
        -Data @{ score = $score; exitCode = $exitCode; nonCompliant = $nonCompliantCount; errors = $errorCount }

    return $report
}
