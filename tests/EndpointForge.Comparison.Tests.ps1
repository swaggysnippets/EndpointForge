BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ModulePath = Join-Path $script:ProjectRoot 'EndpointForge.psm1'
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Import-Module $script:ModulePath -Force

    function Get-EFTestSummary {
        param(
            [string]$MachineName = 'TEST-PC',
            [string]$ChecklistName = 'EnterpriseRecommended',
            [string]$ChecklistVersion = '1.0.0',
            [object[]]$HealthChecks = @(),
            [object[]]$ChecklistResults = @(),
            [double]$Score = 80,
            [double]$Coverage = 100,
            [string]$DataStatus = 'Complete'
        )
        [pscustomobject]@{
            PSTypeName       = 'EndpointForge.EndpointSummary'
            ComputerName     = $MachineName
            CompletedAtUtc   = [DateTime]::UtcNow
            Score            = $Score
            CoveragePercent  = $Coverage
            DataStatus       = $DataStatus
            Health           = [pscustomobject]@{ Checks = @($HealthChecks) }
            Compliance       = [pscustomobject]@{
                BaselineName = $ChecklistName
                BaselineVersion = $ChecklistVersion
                Results = @($ChecklistResults)
            }
        }
    }

    function Get-EFTestHealthCheck {
        param([string]$Id, [string]$Status, [object]$Value = $null)
        [pscustomobject]@{ Id = $Id; Status = $Status; ActualValue = $Value; Threshold = $true; Message = "$Id is $Status." }
    }

    function Get-EFTestChecklistResult {
        param([string]$Id, [string]$Status, [object]$Value = $null)
        [pscustomobject]@{
            ControlId = $Id; Title = "Check $Id"; Status = $Status; ActualValue = $Value;
            DesiredValue = $true; Message = "$Id is $Status."
        }
    }
}

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-EFTestSummary -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-EFTestHealthCheck -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-EFTestChecklistResult -ErrorAction SilentlyContinue
}

Describe 'EndpointForge endpoint comparison' {
    It 'classifies definite improvements, new issues, unavailable results, and unchanged items' {
        $before = Get-EFTestSummary -Score 60 -Coverage 100 -HealthChecks @(
            (Get-EFTestHealthCheck DiskFreeSpace Healthy 40)
            (Get-EFTestHealthCheck Uptime Unhealthy 50)
        ) -ChecklistResults @(
            (Get-EFTestChecklistResult FIREWALL NonCompliant $false)
            (Get-EFTestChecklistResult UAC Compliant $true)
        )
        $after = Get-EFTestSummary -Score 70 -Coverage 75 -DataStatus Partial -HealthChecks @(
            (Get-EFTestHealthCheck DiskFreeSpace Healthy 45)
            (Get-EFTestHealthCheck Uptime Healthy 1)
        ) -ChecklistResults @(
            (Get-EFTestChecklistResult FIREWALL Error $null)
            (Get-EFTestChecklistResult UAC NonCompliant $false)
        )

        $comparison = Compare-EFEndpointSummary -Before $before -After $after

        $comparison.PSObject.TypeNames | Should -Contain 'EndpointForge.EndpointComparison'
        $comparison.ImprovedCount | Should -Be 1
        $comparison.NewIssueCount | Should -Be 1
        $comparison.CouldNotCheckCount | Should -Be 1
        $comparison.UnchangedCount | Should -Be 1
        $comparison.ScoreChange | Should -Be 10
        $comparison.CoverageChange | Should -Be -25
        ($comparison.Changes | Where-Object Id -eq 'Uptime').Category | Should -Be 'Improved'
        ($comparison.Changes | Where-Object Id -eq 'FIREWALL').Category | Should -Be 'CouldNotCheck'
        ($comparison.Changes | Where-Object Id -eq 'UAC').Category | Should -Be 'NewIssue'
    }

    It 'never calls missing later evidence improved' {
        $before = Get-EFTestSummary -ChecklistResults @(
            (Get-EFTestChecklistResult FIREWALL NonCompliant $false)
        )
        $after = Get-EFTestSummary -Coverage 50 -DataStatus Partial -ChecklistResults @()

        $comparison = Compare-EFEndpointSummary $before $after
        $change = $comparison.Changes | Where-Object Id -eq 'FIREWALL'

        $comparison.ImprovedCount | Should -Be 0
        $comparison.CouldNotCheckCount | Should -Be 1
        $change.Category | Should -Be 'CouldNotCheck'
        $change.Explanation | Should -Match 'not been treated as fixed'
    }

    It 'accepts endpoint summaries, menu wrappers, and exported JSON paths' {
        $before = Get-EFTestSummary -HealthChecks @((Get-EFTestHealthCheck Uptime Unhealthy 40))
        $after = Get-EFTestSummary -HealthChecks @((Get-EFTestHealthCheck Uptime Healthy 2))
        $menuReport = [pscustomobject]@{ PSTypeName = 'EndpointForge.MenuReport'; Summary = $before }
        $menuSession = [pscustomobject]@{ PSTypeName = 'EndpointForge.MenuSession'; LastSummary = $after }
        $path = Join-Path $TestDrive 'menu-session.json'
        [IO.File]::WriteAllText($path, ($menuSession | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

        (Compare-EFEndpointSummary $menuReport $menuSession).ImprovedCount | Should -Be 1
        (Compare-EFEndpointSummary $menuReport $path).ImprovedCount | Should -Be 1
    }

    It 'rejects different computers unless explicitly allowed' {
        $before = Get-EFTestSummary -MachineName 'PC-ONE'
        $after = Get-EFTestSummary -MachineName 'PC-TWO'

        { Compare-EFEndpointSummary $before $after } | Should -Throw '*different computers*'
        $comparison = Compare-EFEndpointSummary $before $after -AllowDifferentComputer
        $comparison.DifferentComputer | Should -BeTrue
        $comparison.IsLikeForLike | Should -BeFalse
        $comparison.NextStep | Should -Match 'side-by-side'
    }

    It 'flags a different checklist name or version' {
        $before = Get-EFTestSummary -ChecklistName 'Recommended' -ChecklistVersion '1.0.0'
        $after = Get-EFTestSummary -ChecklistName 'Recommended' -ChecklistVersion '2.0.0'

        $comparison = Compare-EFEndpointSummary $before $after

        $comparison.ChecklistChanged | Should -BeTrue
        $comparison.IsLikeForLike | Should -BeFalse
        $comparison.Summary | Should -Match 'checklist changed'
    }

    It 'renders a plain-language comparison without changing the comparison object' {
        $before = Get-EFTestSummary -HealthChecks @((Get-EFTestHealthCheck Uptime Unhealthy 40))
        $after = Get-EFTestSummary -HealthChecks @((Get-EFTestHealthCheck Uptime Healthy 2))
        $comparison = Compare-EFEndpointSummary $before $after
        $env:ENDPOINTFORGE_COMPARISON_CAPTURE = Join-Path $TestDrive 'comparison-host.txt'

        InModuleScope EndpointForge -Parameters @{ Comparison = $comparison } {
            Mock Write-Host { Add-Content -LiteralPath $env:ENDPOINTFORGE_COMPARISON_CAPTURE -Value ([string]$Object) }
            Write-EFMenuComparison -Comparison $Comparison -NoColor
        }

        $text = @(Get-Content -LiteralPath $env:ENDPOINTFORGE_COMPARISON_CAPTURE) -join "`n"
        $text | Should -Match 'What changed since the earlier check'
        $text | Should -Match '\[IMPROVED\]'
        $text | Should -Match 'What to do next'
        $text | Should -Not -Match '\b(remediation|noncompliant|WhatIf|baseline)\b'
        $comparison.ImprovedCount | Should -Be 1
        Remove-Item Env:\ENDPOINTFORGE_COMPARISON_CAPTURE -ErrorAction SilentlyContinue
    }

    It 'rejects invalid report input with an actionable message' {
        $badPath = Join-Path $TestDrive 'bad.json'
        [IO.File]::WriteAllText($badPath, '{not-json', [Text.UTF8Encoding]::new($false))
        $valid = Get-EFTestSummary

        { Compare-EFEndpointSummary $badPath $valid } | Should -Throw '*not valid JSON*'
        { Compare-EFEndpointSummary ([pscustomobject]@{ Name = 'not a report' }) $valid } |
            Should -Throw '*not an EndpointForge computer check*'
    }
}
