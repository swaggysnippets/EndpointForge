function Invoke-EFEndpointRemediation {
    <#
    .SYNOPSIS
    Remediates supported noncompliant controls on the local Windows endpoint.

    .DESCRIPTION
    Evaluates controls, changes only those marked Remediable, and evaluates them again.
    The cmdlet supports WhatIf and Confirm, requires an elevated session when changes are
    needed, and returns a result for every selected control. It never enables BitLocker,
    Secure Boot, or a TPM automatically.

    .PARAMETER Baseline
    A built-in baseline name, a JSON file path, or a validated baseline object.

    .PARAMETER ControlId
    Limits remediation to specific control identifiers.

    .PARAMETER StopOnError
    Stops after the first remediation error. By default, remaining controls continue.

    .PARAMETER NoProgress
    Suppresses the progress display for non-interactive automation hosts.

    .EXAMPLE
    Invoke-EFEndpointRemediation -WhatIf

    .EXAMPLE
    Invoke-EFEndpointRemediation -ControlId EF-FW-DOMAIN,EF-UAC-ENABLED -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object]$Baseline = 'EnterpriseRecommended',

        [string[]]$ControlId,

        [switch]$StopOnError,

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

    $beforeResults = @{}
    $evaluationIndex = 0
    foreach ($control in $controls) {
        $evaluationIndex++
        if (-not $NoProgress) {
            Write-Progress -Id 1103 -Activity 'EndpointForge remediation' `
                -Status "Checking $($control.Id): $($control.Title)" `
                -PercentComplete ([math]::Round(($evaluationIndex / $controls.Count) * 30))
        }
        $beforeResults[[string]$control.Id] = Get-EFControlState -Control $control
    }

    $changeCandidates = @($controls | Where-Object {
        $beforeResults[[string]$_.Id].Status -eq 'NonCompliant' -and [bool]$_.Remediable
    })
    if ($changeCandidates.Count -gt 0 -and -not $WhatIfPreference -and -not (Test-EFAdministrator)) {
        if (-not $NoProgress) {
            Write-Progress -Id 1103 -Activity 'EndpointForge remediation' -Completed
        }
        throw [System.UnauthorizedAccessException]::new(
            'Endpoint remediation requires an elevated PowerShell session. Re-run as Administrator, or use -WhatIf to preview changes.'
        )
    }

    Write-EFLog -Message "Remediation started for baseline '$($resolvedBaseline.Name)'." `
        -CorrelationId $correlationId -Data @{ selected = $controls.Count; candidates = $changeCandidates.Count; whatIf = [bool]$WhatIfPreference }

    $rebootRequired = $false
    $stopRequested = $false
    $remediationIndex = 0
    $results = @(
        foreach ($control in $controls) {
            $remediationIndex++
            if (-not $NoProgress) {
                Write-Progress -Id 1103 -Activity 'EndpointForge remediation' `
                    -Status "Processing $($control.Id): $($control.Title)" `
                    -PercentComplete (30 + [math]::Round(($remediationIndex / $controls.Count) * 70))
            }
            $before = $beforeResults[[string]$control.Id]
            $outcome = $null
            $after = $before
            $message = $before.Message

            if ($before.Status -eq 'Compliant') {
                $outcome = 'NotRequired'
            }
            elseif ($before.Status -eq 'NotApplicable') {
                $outcome = 'NotApplicable'
            }
            elseif ($before.Status -eq 'Error') {
                $outcome = 'EvaluationFailed'
            }
            elseif (-not [bool]$control.Remediable) {
                $outcome = 'NotRemediable'
            }
            else {
                $target = "$env:COMPUTERNAME/$($control.Id)"
                if ($PSCmdlet.ShouldProcess($target, "Remediate $($control.Title)")) {
                    try {
                        $change = Invoke-EFControlRemediation -Control $control
                        $rebootRequired = $rebootRequired -or [bool]$change.RebootRequired
                        $after = Get-EFControlState -Control $control
                        if ($after.Status -eq 'Compliant') {
                            $outcome = 'Changed'
                            $message = 'The control was remediated and verified.'
                        }
                        else {
                            $outcome = 'VerificationFailed'
                            $message = "The change completed, but verification returned '$($after.Status)': $($after.Message)"
                        }
                    }
                    catch {
                        $outcome = 'Failed'
                        $message = $_.Exception.Message
                        Write-EFLog -Level Error -Message "Remediation failed for control '$($control.Id)'." `
                            -CorrelationId $correlationId -Data @{ error = $message }
                        if ($StopOnError) {
                            $stopRequested = $true
                        }
                    }
                }
                else {
                    $outcome = if ($WhatIfPreference) { 'WhatIf' } else { 'Skipped' }
                    $message = if ($WhatIfPreference) { 'The change was previewed; endpoint state was not modified.' } else { 'The change was declined.' }
                }
            }

            $recommendedAction = switch ($outcome) {
                'NotRequired' { 'No action required.' }
                'NotApplicable' { 'No action is required on this endpoint.' }
                'Changed' { 'No further action is required unless RebootRequired is true.' }
                'WhatIf' { 'Apply this control from an elevated session using the same Baseline and ControlId parameters when approved.' }
                'Skipped' { 'Run Invoke-EFEndpointRemediation again with the same Baseline and ControlId when the change is approved.' }
                'NotRemediable' { 'Remediate this control through your approved enterprise policy or management platform.' }
                'EvaluationFailed' { $before.RecommendedAction }
                default { 'Review the failure details, correct the underlying issue, and try again.' }
            }

            $resultItem = [pscustomobject]@{
                PSTypeName   = 'EndpointForge.RemediationResult'
                ControlId    = [string]$control.Id
                Title        = [string]$control.Title
                Severity     = [string]$control.Severity
                BeforeStatus = [string]$before.Status
                Outcome      = $outcome
                AfterStatus  = [string]$after.Status
                Message      = $message
                RecommendedAction = $recommendedAction
            }
            $resultItem
            if ($stopRequested) {
                break
            }
        }
    )
    if (-not $NoProgress) {
        Write-Progress -Id 1103 -Activity 'EndpointForge remediation' -Completed
    }

    $failureCount = @($results | Where-Object Outcome -in @('Failed', 'EvaluationFailed', 'VerificationFailed')).Count
    $remainingCount = @($results | Where-Object AfterStatus -eq 'NonCompliant').Count
    $changedCount = @($results | Where-Object Outcome -eq 'Changed').Count
    $previewCount = @($results | Where-Object Outcome -eq 'WhatIf').Count
    $unprocessedCount = $controls.Count - $results.Count
    $exitCode = if ($failureCount -gt 0) { 3 } elseif ($remainingCount -gt 0) { 2 } else { 0 }
    $summaryText = if ($previewCount -gt 0) {
        "$previewCount change(s) were previewed; endpoint state was not modified."
    }
    elseif ($failureCount -gt 0) {
        "$changedCount change(s) succeeded and $failureCount action(s) failed."
    }
    elseif ($remainingCount -gt 0) {
        "$changedCount change(s) succeeded; $remainingCount noncompliant control(s) remain."
    }
    else {
        "Remediation completed successfully with $changedCount verified change(s)."
    }
    $nextStep = if ($rebootRequired) {
        'Schedule a restart through your approved change process; EndpointForge does not restart devices automatically.'
    }
    elseif ($exitCode -ne 0) {
        'Review Results.RecommendedAction for unresolved controls.'
    }
    else {
        'Run Get-EFComplianceReport to confirm the complete baseline state.'
    }

    $report = [pscustomobject]@{
        PSTypeName        = 'EndpointForge.RemediationReport'
        ComputerName      = $env:COMPUTERNAME
        BaselineName      = [string]$resolvedBaseline.Name
        BaselineVersion   = [string]$resolvedBaseline.Version
        CorrelationId     = $correlationId
        CompletedAtUtc    = [DateTime]::UtcNow
        IsSuccessful      = $exitCode -eq 0
        ExitCode          = $exitCode
        Summary           = $summaryText
        NextStep          = $nextStep
        ChangedCount      = $changedCount
        CandidateCount    = $changeCandidates.Count
        PreviewCount      = $previewCount
        RemainingCount    = $remainingCount
        FailureCount      = $failureCount
        UnprocessedCount  = $unprocessedCount
        RebootRequired    = $rebootRequired
        Results           = $results
    }

    Write-EFLog -Message "Remediation completed for baseline '$($resolvedBaseline.Name)'." `
        -Level $(if ($exitCode -eq 0) { 'Information' } else { 'Warning' }) -CorrelationId $correlationId `
        -Data @{ changed = $changedCount; remaining = $remainingCount; failures = $failureCount; exitCode = $exitCode }

    return $report
}
