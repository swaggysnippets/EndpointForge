function Invoke-EFEndpointRemediation {
    <#
    .SYNOPSIS
    Previews or applies selected supported Windows setting fixes.

    .DESCRIPTION
    Reads selected checklist items, changes only the narrow types marked as supported
    fixes, and checks them again. PowerShell scripts call this remediation. Use WhatIf for
    a no-change preview. Applying requires PowerShell opened with Run as Administrator.

    The result records before, expected, and after values plus recovery guidance. That
    receipt is not an automatic rollback guarantee. This command never restarts Windows,
    enables BitLocker, changes Secure Boot or firmware, or changes a TPM.

    .PARAMETER Baseline
    The checklist to use: a built-in name, JSON file, or validated checklist object.

    .PARAMETER ControlId
    Limits the preview or fix to specific checklist item IDs.

    .PARAMETER AllowNetworkChecks
    Allows network-active report-only items to be evaluated alongside selected supported
    fixes after their destinations and purposes have been reviewed. It does not make those
    report-only items remediable.

    .PARAMETER StopOnError
    Stops after the first selected fix cannot complete. By default, remaining items continue.

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

        [switch]$AllowNetworkChecks,

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

    $networkControls = @($controls | Where-Object { Test-EFControlUsesNetwork -Control $_ })
    if ($networkControls.Count -gt 0 -and -not $AllowNetworkChecks) {
        throw [System.InvalidOperationException]::new(
            'The selected items include network-active checks. Review them, then add -AllowNetworkChecks to evaluate them.'
        )
    }

    $beforeResults = @{}
    $evaluationContext = @{ AllowNetworkChecks = [bool]$AllowNetworkChecks; Cache = @{} }
    $evaluationIndex = 0
    foreach ($control in $controls) {
        $evaluationIndex++
        if (-not $NoProgress) {
            Write-Progress -Id 1103 -Activity 'EndpointForge supported fixes' `
                -Status "Checking $($control.Id): $($control.Title)" `
                -PercentComplete ([math]::Round(($evaluationIndex / $controls.Count) * 30))
        }
        $beforeResults[[string]$control.Id] = Get-EFControlState -Control $control -EvaluationContext $evaluationContext
    }

    $changeCandidates = @($controls | Where-Object {
        $beforeResults[[string]$_.Id].Status -eq 'NonCompliant' -and [bool]$_.Remediable
    })
    if ($changeCandidates.Count -gt 0 -and -not $WhatIfPreference -and -not (Test-EFAdministrator)) {
        if (-not $NoProgress) {
            Write-Progress -Id 1103 -Activity 'EndpointForge supported fixes' -Completed
        }
        throw [System.UnauthorizedAccessException]::new(
            'Applying supported fixes requires PowerShell opened with Run as Administrator. Use -WhatIf for a preview that cannot change Windows.'
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
                Write-Progress -Id 1103 -Activity 'EndpointForge supported fixes' `
                    -Status "Processing $($control.Id): $($control.Title)" `
                    -PercentComplete (30 + [math]::Round(($remediationIndex / $controls.Count) * 70))
            }
            $before = $beforeResults[[string]$control.Id]
            $outcome = $null
            $after = $before
            $message = $before.Message
            $changeAttempted = $false
            $afterReadAttempted = $false
            $afterReadSucceeded = $false

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
                if ($PSCmdlet.ShouldProcess($target, "Apply supported fix: $($control.Title)")) {
                    $changeAttempted = $true
                    try {
                        $change = Invoke-EFControlRemediation -Control $control
                        $rebootRequired = $rebootRequired -or [bool]$change.RebootRequired
                        $afterReadAttempted = $true
                        $after = Get-EFControlState -Control $control -EvaluationContext $evaluationContext
                        $afterReadSucceeded = $null -ne $after -and [string]$after.Status -ne 'Error'
                        if ($after.Status -eq 'Compliant') {
                            $outcome = 'Changed'
                            $message = 'The setting changed successfully and the new value was checked.'
                        }
                        else {
                            $outcome = 'VerificationFailed'
                            $message = "The change completed, but verification returned '$($after.Status)': $($after.Message)"
                        }
                    }
                    catch {
                        $outcome = 'Failed'
                        $remediationError = $_.Exception.Message
                        $message = $remediationError
                        $afterReadAttempted = $true
                        try {
                            $after = Get-EFControlState -Control $control -EvaluationContext $evaluationContext
                            $afterReadSucceeded = $null -ne $after -and [string]$after.Status -ne 'Error'
                        }
                        catch {
                            $after = [pscustomobject]@{
                                Status      = 'Error'
                                ActualValue = $null
                                Message     = $_.Exception.Message
                            }
                            $afterReadSucceeded = $false
                        }
                        Write-EFLog -Level Error -Message "Remediation failed for control '$($control.Id)'." `
                            -CorrelationId $correlationId -Data @{ error = $remediationError; afterReadSucceeded = $afterReadSucceeded }
                        if ($StopOnError) {
                            $stopRequested = $true
                        }
                    }
                }
                else {
                    $outcome = if ($WhatIfPreference) { 'WhatIf' } else { 'Skipped' }
                    $message = if ($WhatIfPreference) { 'Preview only: this shows what would change. Windows was not modified.' } else { 'The change was not approved, so Windows was not modified.' }
                }
            }

            $beforeValue = Get-EFPropertyValue -InputObject $before -Name 'ActualValue'
            $desiredValue = Get-EFPropertyValue -InputObject $before -Name 'DesiredValue' -Default (
                Get-EFPropertyValue -InputObject $control -Name 'DesiredValue'
            )
            $afterValue = Get-EFPropertyValue -InputObject $after -Name 'ActualValue' -Default $beforeValue
            $observedValueChanged = $false
            if ($afterReadSucceeded) {
                $beforeComparable = ConvertTo-Json -InputObject (ConvertTo-EFSerializableValue -InputObject $beforeValue) -Depth 12 -Compress
                $afterComparable = ConvertTo-Json -InputObject (ConvertTo-EFSerializableValue -InputObject $afterValue) -Depth 12 -Compress
                $observedValueChanged = $beforeComparable -cne $afterComparable
            }
            if ($outcome -eq 'Failed' -and $observedValueChanged) {
                $outcome = 'PartiallyChanged'
                $message = "$message A follow-up read found that at least one value changed, but the requested fix did not complete cleanly."
            }
            elseif ($outcome -eq 'Failed' -and -not $afterReadSucceeded) {
                $message = "$message EndpointForge could not confirm the resulting value, so a partial change must not be ruled out."
            }
            $changeWasApplied = $outcome -eq 'Changed' -or $observedValueChanged

            $recommendedAction = switch ($outcome) {
                'NotRequired' { 'No action required.' }
                'NotApplicable' { 'No action is required on this endpoint.' }
                'Changed' { 'Keep this receipt. If a restart is shown as required, schedule it through your approved process.' }
                'PartiallyChanged' { 'Review the before and after values now. Use the recovery guidance and your approved Windows management process before trying again.' }
                'VerificationFailed' { 'A change was attempted but the expected result was not confirmed. Review the observed after value and recovery guidance before trying again.' }
                'WhatIf' { 'Review the preview. If it is approved, an administrator can apply this same selected item.' }
                'Skipped' { 'Nothing changed. Run the fix again only after the change is approved.' }
                'NotRemediable' { 'Follow the manual guidance approved by your organization. EndpointForge will not change this item.' }
                'EvaluationFailed' { $before.RecommendedAction }
                default { 'Review the failure details and current Windows state before trying again; a partial change may have occurred.' }
            }

            $whatChanged = switch ($outcome) {
                'Changed' { "Changed from '$(ConvertTo-EFMenuValue $beforeValue)' to '$(ConvertTo-EFMenuValue $afterValue)'." }
                'PartiallyChanged' { "A change from '$(ConvertTo-EFMenuValue $beforeValue)' to '$(ConvertTo-EFMenuValue $afterValue)' was observed, but the requested fix reported an error." }
                'VerificationFailed' {
                    if ($observedValueChanged) {
                        "A change from '$(ConvertTo-EFMenuValue $beforeValue)' to '$(ConvertTo-EFMenuValue $afterValue)' was observed, but it did not produce the expected result."
                    }
                    else {
                        'A change was attempted, but the expected result was not confirmed.'
                    }
                }
                'WhatIf' { "Preview only: would change '$(ConvertTo-EFMenuValue $beforeValue)' to '$(ConvertTo-EFMenuValue $desiredValue)'." }
                'Failed' {
                    if ($changeAttempted -and -not $afterReadSucceeded) {
                        'A change was attempted, but EndpointForge could not read a reliable after value.'
                    }
                    else {
                        'No changed value was observed, but the requested fix reported an error.'
                    }
                }
                default { 'No setting change was recorded for this item.' }
            }
            $recoveryGuidance = [string](Get-EFPropertyValue -InputObject $control -Name 'RecoveryGuidance' -Default (
                'EndpointForge does not automatically roll back changes. Use the before value in this receipt and your approved Windows management process if recovery is needed.'
            ))

            $resultItem = [pscustomobject]@{
                PSTypeName   = 'EndpointForge.RemediationResult'
                ReceiptVersion = '1.0'
                ControlId    = [string]$control.Id
                Title        = [string]$control.Title
                Severity     = [string]$control.Severity
                BeforeStatus = [string]$before.Status
                BeforeValue  = $beforeValue
                DesiredValue = $desiredValue
                Outcome      = $outcome
                AfterStatus  = [string](Get-EFPropertyValue -InputObject $after -Name 'Status' -Default 'Error')
                AfterValue   = $afterValue
                ChangeWasApplied = $changeWasApplied
                ChangeMayHaveOccurred = $changeAttempted
                AfterReadWasAttempted = $afterReadAttempted
                AfterStateWasObserved = $afterReadSucceeded
                WhatChanged  = $whatChanged
                WhatWouldChange = [string](Get-EFPropertyValue -InputObject $control -Name 'WhatWouldChange' -Default '')
                SafetyNotes  = [string](Get-EFPropertyValue -InputObject $control -Name 'SafetyNotes' -Default '')
                RecoveryGuidance = $recoveryGuidance
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
        Write-Progress -Id 1103 -Activity 'EndpointForge supported fixes' -Completed
    }

    $failureCount = @($results | Where-Object Outcome -in @('Failed', 'PartiallyChanged', 'EvaluationFailed', 'VerificationFailed')).Count
    $remainingCount = @($results | Where-Object AfterStatus -eq 'NonCompliant').Count
    $changedCount = @($results | Where-Object Outcome -eq 'Changed').Count
    $observedChangeCount = @($results | Where-Object ChangeWasApplied).Count
    $partialChangeCount = @($results | Where-Object {
        $_.Outcome -in @('PartiallyChanged', 'VerificationFailed') -and [bool]$_.ChangeWasApplied
    }).Count
    $previewCount = @($results | Where-Object Outcome -eq 'WhatIf').Count
    $unprocessedCount = $controls.Count - $results.Count
    $exitCode = if ($failureCount -gt 0) { 3 } elseif ($remainingCount -gt 0) { 2 } else { 0 }
    $summaryText = if ($previewCount -gt 0) {
        "$previewCount supported change(s) were previewed. Windows was not modified."
    }
    elseif ($failureCount -gt 0) {
        "$changedCount change(s) completed; $failureCount had an error. $partialChangeCount error result(s) showed a changed after-value."
    }
    elseif ($remainingCount -gt 0) {
        "$changedCount change(s) succeeded; $remainingCount checklist item(s) still need attention."
    }
    else {
        "$changedCount approved change(s) completed and were checked."
    }
    $nextStep = if ($exitCode -ne 0) {
        if ($rebootRequired) {
            'Review every error, before-and-after value, and recovery note now; no failed item should be assumed fixed. A completed change also requires a restart through your approved process, but review the errors before restarting.'
        }
        else {
            'Review each result and its recovery guidance. No failed item should be assumed fixed.'
        }
    }
    elseif ($rebootRequired) {
        'Schedule a restart through your approved change process; EndpointForge does not restart devices automatically.'
    }
    else {
        'Run another computer checkup to confirm the full checklist, and keep this before-and-after receipt.'
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
        ObservedChangeCount = $observedChangeCount
        PartialChangeCount = $partialChangeCount
        CandidateCount    = $changeCandidates.Count
        PreviewCount      = $previewCount
        RemainingCount    = $remainingCount
        FailureCount      = $failureCount
        UnprocessedCount  = $unprocessedCount
        RebootRequired    = $rebootRequired
        CanAutomaticallyRollback = $false
        RollbackExplanation = 'EndpointForge records before and after values but does not automatically roll back changes. Windows policy, device management, or later changes may control the setting.'
        Results           = $results
    }

    Write-EFLog -Message "Remediation completed for baseline '$($resolvedBaseline.Name)'." `
        -Level $(if ($exitCode -eq 0) { 'Information' } else { 'Warning' }) -CorrelationId $correlationId `
        -Data @{ changed = $changedCount; remaining = $remainingCount; failures = $failureCount; exitCode = $exitCode }

    return $report
}
