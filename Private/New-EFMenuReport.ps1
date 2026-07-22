function New-EFMenuReport {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'This private constructor only creates an in-memory report object.'
    )]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [object]$Checklist,

        [AllowNull()][object]$Readiness,
        [AllowNull()][object]$Summary,
        [AllowNull()][object]$PreviousSummary,
        [AllowNull()][object]$Comparison,
        [AllowNull()][object]$Plan,
        [AllowNull()][object]$Preview,
        [AllowNull()][object]$Remediation,
        [AllowNull()][object]$Fleet,
        [object[]]$History = @()
    )

    $findings = if ($null -ne $Summary) { @(Get-EFPropertyValue $Summary 'Findings' @()) } else { @() }
    $steps = if ($null -ne $Plan) { @(Get-EFPropertyValue $Plan 'Steps' @()) } else { @() }
    $results = if ($null -ne $Remediation) {
        @(Get-EFPropertyValue $Remediation 'Results' @())
    }
    elseif ($null -ne $Preview) {
        @(Get-EFPropertyValue $Preview 'Results' @())
    }
    else { @() }
    $changes = if ($null -ne $Comparison) { @(Get-EFPropertyValue $Comparison 'Changes' @()) } else { @() }
    $fleetResults = if ($null -ne $Fleet) { @(Get-EFPropertyValue $Fleet 'Results' @()) } else { @() }
    $failures = if ($null -ne $Fleet) { @(Get-EFPropertyValue $Fleet 'Failures' @()) } else { @() }

    [pscustomobject][ordered]@{
        PSTypeName          = 'EndpointForge.MenuReport'
        SchemaVersion       = '1.1'
        ExportedAtUtc       = [DateTime]::UtcNow
        ComputerName        = $ComputerName
        ChecklistName       = [string](Get-EFPropertyValue $Checklist 'Name' '')
        ChecklistVersion    = [string](Get-EFPropertyValue $Checklist 'Version' '')
        BaselineName        = [string](Get-EFPropertyValue $Checklist 'Name' '')
        BaselineVersion     = [string](Get-EFPropertyValue $Checklist 'Version' '')
        OverallStatus       = if ($null -ne $Summary) { Get-EFPropertyValue $Summary 'OverallStatus' } else { $null }
        HealthStatus        = if ($null -ne $Summary) { Get-EFPropertyValue $Summary 'HealthStatus' } else { $null }
        ComplianceStatus    = if ($null -ne $Summary) { Get-EFPropertyValue $Summary 'ComplianceStatus' } else { $null }
        DataStatus          = if ($null -ne $Summary) { Get-EFPropertyValue $Summary 'DataStatus' } else { $null }
        Score               = if ($null -ne $Summary) { Get-EFPropertyValue $Summary 'Score' } else { $null }
        CoveragePercent     = if ($null -ne $Summary) { Get-EFPropertyValue $Summary 'CoveragePercent' } else { $null }
        IssueCount          = if ($null -ne $Summary) { Get-EFPropertyValue $Summary 'IssueCount' } else { $null }
        UnknownCount        = if ($null -ne $Summary) { Get-EFPropertyValue $Summary 'UnknownCount' } else { $null }
        SummaryText         = if ($null -ne $Summary) { [string](Get-EFPropertyValue $Summary 'NextStep' '') } else { 'No computer check has been run in this session.' }
        NextStep            = if ($null -ne $Summary) { [string](Get-EFPropertyValue $Summary 'NextStep' '') } else { 'Run a computer check before making decisions.' }
        Findings            = $findings
        Steps               = $steps
        Results             = $results
        Changes             = $changes
        FleetResults        = $fleetResults
        Failures            = $failures
        Readiness           = $Readiness
        Summary             = $Summary
        LastSummary         = $Summary
        PreviousSummary     = $PreviousSummary
        Comparison          = $Comparison
        Plan                = $Plan
        Preview             = $Preview
        Remediation         = $Remediation
        Fleet               = $Fleet
        SessionHistory      = @($History)
    }
}
