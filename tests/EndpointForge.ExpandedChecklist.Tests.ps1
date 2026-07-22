BeforeAll {
    $script:ExpandedProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ExpandedManifestPath = Join-Path $script:ExpandedProjectRoot 'EndpointForge.psd1'
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Import-Module $script:ExpandedManifestPath -Force

    $script:ExpandedChecklist = Get-Content -LiteralPath (
        Join-Path $script:ExpandedProjectRoot 'examples\EverydayChecks.json'
    ) -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:ExpandedTypes = @(
        'PendingRestart', 'DiskSpace', 'WindowsUpdateAvailable', 'InstalledApplication',
        'ScheduledTaskHealth', 'DefenderSignatureHealth', 'FileFreshness', 'CertificateExpiry',
        'DnsResolution', 'HttpEndpointHealth', 'ProcessRunning', 'LocalGroupMembership'
    )
    $script:CopyTestValue = {
        param([Parameter(Mandatory)][object]$Value)
        $Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    }
    $script:GetExpandedControl = {
        param([Parameter(Mandatory)][string]$Type)
        $source = $script:ExpandedChecklist.Controls | Where-Object Type -eq $Type | Select-Object -First 1
        & $script:CopyTestValue $source
    }
    $script:NewExpandedBaseline = {
        param(
            [Parameter(Mandatory)][object[]]$Controls,
            [string]$Name = 'Expanded.Test'
        )
        [pscustomobject]@{
            Name        = $Name
            Version     = '1.0.0'
            Description = 'Deterministic expanded checklist test.'
            Controls    = @($Controls)
        }
    }
}

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'Expanded checklist contracts' {
    It 'runs bounded checks in a real isolated PowerShell worker without using the network' {
        InModuleScope EndpointForge {
            $workerResult = Invoke-EFIsolatedCheck -ScriptBlock {
                param($InputData)
                [pscustomobject]@{ Echo = [string]$InputData.Value }
            } -InputData @{ Value = 'worker-ok' } -TimeoutMilliseconds 3000 `
                -StartupAllowanceMilliseconds 3000 -Activity 'The isolated worker smoke test'

            $workerResult.Echo | Should -Be 'worker-ok'
        }
    }

    It 'validates every new report-only type with user-facing explanations' {
        $validation = Test-EFBaseline -InputObject $script:ExpandedChecklist -PassThru

        $validation.IsValid | Should -BeTrue
        $validation.ControlCount | Should -Be 16
        foreach ($type in $script:ExpandedTypes) {
            $control = $script:ExpandedChecklist.Controls | Where-Object Type -eq $type
            @($control).Count | Should -Be 1 -Because "$type should have one maintained example"
            $control.DesiredValue | Should -BeOfType ([bool])
            $control.Remediable | Should -BeFalse
            $control.RequiresReboot | Should -BeFalse
            $control.WhyItMatters | Should -Not -BeNullOrEmpty
            $control.HowChecked | Should -Not -BeNullOrEmpty
            $control.WhatWouldChange | Should -Match '^Nothing|Nothing is installed|Nothing on this computer'
            $control.ManualAction | Should -Not -BeNullOrEmpty
            $control.SafetyNotes | Should -Not -BeNullOrEmpty
            $control.RecoveryGuidance | Should -Not -BeNullOrEmpty
        }
    }

    It 'rejects remediation, restart claims, and non-Boolean desired values for every new type' {
        foreach ($type in $script:ExpandedTypes) {
            $remediable = & $script:GetExpandedControl $type
            $remediable.Remediable = $true
            $restart = & $script:GetExpandedControl $type
            $restart.RequiresReboot = $true
            $badDesired = & $script:GetExpandedControl $type
            $badDesired.DesiredValue = 'true'

            (Test-EFBaseline -InputObject (& $script:NewExpandedBaseline @($remediable)) -PassThru).IsValid |
                Should -BeFalse -Because "$type is report-only"
            (Test-EFBaseline -InputObject (& $script:NewExpandedBaseline @($restart)) -PassThru).IsValid |
                Should -BeFalse -Because "$type cannot claim that EndpointForge requires a restart"
            (Test-EFBaseline -InputObject (& $script:NewExpandedBaseline @($badDesired)) -PassThru).IsValid |
                Should -BeFalse -Because "$type requires a JSON Boolean DesiredValue"
        }
    }

    It 'rejects ambiguous, unsafe, and unbounded new-type fields' {
        $invalidControls = [Collections.Generic.List[object]]::new()

        $disk = & $script:GetExpandedControl 'DiskSpace'
        $disk.PSObject.Properties.Remove('MinimumFreePercent')
        $invalidControls.Add($disk)

        $application = & $script:GetExpandedControl 'InstalledApplication'
        $application | Add-Member -NotePropertyName ExactVersion -NotePropertyValue '1.0.0' -Force
        $invalidControls.Add($application)

        $task = & $script:GetExpandedControl 'ScheduledTaskHealth'
        $task.TaskName = 'Folder\Task*'
        $invalidControls.Add($task)

        $freshness = & $script:GetExpandedControl 'FileFreshness'
        $freshness.Path = '\\server\share\status.txt'
        $invalidControls.Add($freshness)

        $certificate = & $script:GetExpandedControl 'CertificateExpiry'
        $certificate.Thumbprint = 'NOT-A-THUMBPRINT'
        $invalidControls.Add($certificate)

        $dns = & $script:GetExpandedControl 'DnsResolution'
        $dns.HostName = '127.0.0.1'
        $invalidControls.Add($dns)

        $http = & $script:GetExpandedControl 'HttpEndpointHealth'
        $http.Uri = 'https://user:secret@app.contoso.example/health?token=secret'
        $invalidControls.Add($http)

        $process = & $script:GetExpandedControl 'ProcessRunning'
        $process.ProcessName = 'C:\Contoso\Agent.exe'
        $invalidControls.Add($process)

        $membership = & $script:GetExpandedControl 'LocalGroupMembership'
        $membership.MemberName = 'CONTOSO\*'
        $invalidControls.Add($membership)

        foreach ($control in $invalidControls) {
            $validation = Test-EFBaseline -InputObject (
                & $script:NewExpandedBaseline @($control) ("Invalid.{0}" -f $control.Type)
            ) -PassThru
            $validation.IsValid | Should -BeFalse -Because "$($control.Type) should reject the unsafe test value"
            $validation.ErrorCount | Should -BeGreaterThan 0
        }
    }

    It 'rejects unsafe edge cases for paths, filters, timeouts, destinations, and process names' {
        $invalidCases = [Collections.Generic.List[object]]::new()

        foreach ($unsafeTaskPath in @('\Contoso\..\Maintenance\', '\Contoso\\Maintenance\')) {
            $task = & $script:GetExpandedControl 'ScheduledTaskHealth'
            $task.TaskPath = $unsafeTaskPath
            $invalidCases.Add([pscustomobject]@{
                Label = "scheduled task path '$unsafeTaskPath'"
                Control = $task
            })
        }

        foreach ($scopeAndArchitecture in @(
            @{ Scope = 'Machine'; Architecture = 'User' },
            @{ Scope = 'CurrentUser'; Architecture = 'x64' }
        )) {
            $application = & $script:GetExpandedControl 'InstalledApplication'
            $application.Scope = $scopeAndArchitecture.Scope
            $application.Architecture = $scopeAndArchitecture.Architecture
            $invalidCases.Add([pscustomobject]@{
                Label = "installed application $($scopeAndArchitecture.Scope)/$($scopeAndArchitecture.Architecture) filter"
                Control = $application
            })
        }

        $membership = & $script:GetExpandedControl 'LocalGroupMembership'
        $membership | Add-Member -NotePropertyName TimeoutSeconds -NotePropertyValue 61 -Force
        $invalidCases.Add([pscustomobject]@{
            Label = 'local-group timeout above 60 seconds'
            Control = $membership
        })

        foreach ($unsafeDnsName in @('server', '127.0.0.1')) {
            $dns = & $script:GetExpandedControl 'DnsResolution'
            $dns.HostName = $unsafeDnsName
            $invalidCases.Add([pscustomobject]@{
                Label = "DNS name '$unsafeDnsName'"
                Control = $dns
            })
        }

        foreach ($unsafeUri in @(
            'https://app.contoso.example/health?token=secret',
            ('https://app.contoso.example/' + ('a' * 2050))
        )) {
            $http = & $script:GetExpandedControl 'HttpEndpointHealth'
            $http.Uri = $unsafeUri
            $invalidCases.Add([pscustomobject]@{
                Label = if ($unsafeUri.Length -gt 2048) { 'HTTP address above 2,048 characters' } else { 'HTTP address with query string' }
                Control = $http
            })
        }

        $process = & $script:GetExpandedControl 'ProcessRunning'
        $process.ProcessName = '.exe'
        $invalidCases.Add([pscustomobject]@{
            Label = "empty executable base name '.exe'"
            Control = $process
        })

        foreach ($invalidCase in $invalidCases) {
            $validation = Test-EFBaseline -InputObject (
                & $script:NewExpandedBaseline @($invalidCase.Control) 'Invalid.EdgeCase'
            ) -PassThru

            $validation.IsValid | Should -BeFalse -Because $invalidCase.Label
            $validation.ErrorCount | Should -BeGreaterThan 0 -Because $invalidCase.Label
        }
    }

    It 'allows only one Windows Update scan item in a checklist' {
        $first = & $script:GetExpandedControl 'WindowsUpdateAvailable'
        $second = & $script:GetExpandedControl 'WindowsUpdateAvailable'
        $second.Id = 'WINDOWS-UPDATES-SECOND'
        $candidate = & $script:NewExpandedBaseline @($first, $second) 'Duplicate.Update.Scan'

        $validation = Test-EFBaseline -InputObject $candidate -PassThru

        $validation.IsValid | Should -BeFalse
        $validation.Errors[0] | Should -Match 'only one WindowsUpdateAvailable'
    }
}

Describe 'Local health and application checklist behavior' {
    It 'maps pending restart evidence to compliant, noncompliant, and error results' {
        $control = & $script:GetExpandedControl 'PendingRestart'
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            $script:PendingMode = 'Clear'
            Mock Get-EFPendingReboot {
                switch ($script:PendingMode) {
                    'Clear' { [pscustomobject]@{ IsRebootPending = $false; DetectionCount = 0; ErrorCount = 0 } }
                    'Waiting' { [pscustomobject]@{ IsRebootPending = $true; DetectionCount = 2; ErrorCount = 0; Reasons = @('PRIVATE-REASON') } }
                    'PartialWaiting' { [pscustomobject]@{ IsRebootPending = $true; DetectionCount = 1; ErrorCount = 1; Errors = @('PRIVATE-ERROR') } }
                    default { [pscustomobject]@{ IsRebootPending = $false; DetectionCount = 0; ErrorCount = 1; Errors = @('PRIVATE-ERROR') } }
                }
            }

            (Get-EFControlState -Control $Control).Status | Should -Be 'Compliant'
            $script:PendingMode = 'Waiting'
            $waiting = Get-EFControlState -Control $Control
            $waiting.Status | Should -Be 'NonCompliant'
            $waiting.Message | Should -Not -Match 'PRIVATE-REASON'
            $script:PendingMode = 'PartialWaiting'
            $partialWaiting = Get-EFControlState -Control $Control
            $partialWaiting.Status | Should -Be 'NonCompliant' -Because 'one positive restart indicator is conclusive even when another indicator is unavailable'
            $partialWaiting.Message | Should -Not -Match 'PRIVATE-ERROR'
            $script:PendingMode = 'Error'
            $errorResult = Get-EFControlState -Control $Control
            $errorResult.Status | Should -Be 'Error'
            $errorResult.Message | Should -Not -Match 'PRIVATE-ERROR'
        }
    }

    It 'checks both disk thresholds and never treats collection failure as enough free space' {
        $control = & $script:GetExpandedControl 'DiskSpace'
        $control | Add-Member -NotePropertyName MinimumFreeGB -NotePropertyValue 10 -Force
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            $script:DiskMode = 'Enough'
            Mock Get-CimInstance {
                if ($script:DiskMode -eq 'Error') { throw 'Access denied to private disk details.' }
                [pscustomobject]@{
                    Size      = 100GB
                    FreeSpace = switch ($script:DiskMode) {
                        'Enough' { 20GB }
                        'Boundary' { 14.96GB }
                        default { 5GB }
                    }
                }
            } -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' }

            $enough = Get-EFControlState -Control $Control
            $enough.Status | Should -Be 'Compliant'
            $enough.ActualValue | Should -BeTrue
            $script:DiskMode = 'Low'
            (Get-EFControlState -Control $Control).Status | Should -Be 'NonCompliant'
            $script:DiskMode = 'Boundary'
            $roundedBoundary = Get-EFControlState -Control $Control
            $roundedBoundary.Status | Should -Be 'NonCompliant' -Because 'display rounding must never create a passing threshold'
            $roundedBoundary.Message | Should -Match '15%'
            $script:DiskMode = 'Error'
            $errorResult = Get-EFControlState -Control $Control
            $errorResult.Status | Should -Be 'Error'
            $errorResult.ActualValue | Should -BeNullOrEmpty
        }
    }

    It 'checks an exact installed application and omits unrelated inventory details' {
        $control = & $script:GetExpandedControl 'InstalledApplication'
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            $script:ApplicationMode = 'Current'
            Mock Get-EFInstalledApplicationEvidence {
                if ($script:ApplicationMode -eq 'Error') {
                    return [pscustomobject]@{ Entries = @(); ErrorCount = 1; Errors = @('PRIVATE-REGISTRY-ERROR') }
                }
                $version = if ($script:ApplicationMode -eq 'Current') { '2.1.0' } else { '0.9.0' }
                $secondEntry = if ($script:ApplicationMode -eq 'Ambiguous') {
                    [pscustomobject]@{
                        Name = 'Contoso Endpoint Agent'; Version = '2026 Enterprise'; Publisher = 'Contoso'
                        ProductCode = '{CONTOSO-SECOND}'; Architecture = 'x64'
                    }
                }
                else {
                    [pscustomobject]@{
                        Name = 'Private Unrelated Application'; Version = '99.0'; Publisher = 'Private Publisher'
                        ProductCode = '{PRIVATE}'; Architecture = 'x64'
                    }
                }
                [pscustomobject]@{
                    ErrorCount = 0
                    Entries = @(
                        [pscustomobject]@{
                            Name = 'Contoso Endpoint Agent'; Version = $version; Publisher = 'Contoso'
                            ProductCode = '{CONTOSO}'; Architecture = 'x64'; UninstallString = 'SECRET-UNINSTALL-TOKEN'
                        },
                        $secondEntry
                    )
                }
            }

            $current = Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }
            $current.Status | Should -Be 'Compliant'
            (ConvertTo-Json $current -Depth 10) | Should -Not -Match 'SECRET-UNINSTALL-TOKEN|Private Unrelated Application|Private Publisher'
            $script:ApplicationMode = 'Old'
            (Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }).Status |
                Should -Be 'NonCompliant'
            $script:ApplicationMode = 'Ambiguous'
            (Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }).Status |
                Should -Be 'Error'
            $script:ApplicationMode = 'Error'
            $errorResult = Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }
            $errorResult.Status | Should -Be 'Error'
            $errorResult.Message | Should -Not -Match 'PRIVATE-REGISTRY-ERROR'
        }
    }

    It 'checks scheduled job state, result, and age without returning actions or arguments' {
        $control = & $script:GetExpandedControl 'ScheduledTaskHealth'
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            $script:TaskMode = 'Healthy'
            Mock Get-Command { [pscustomobject]@{ Name = $Name } } -ParameterFilter {
                $Name -in @('Get-ScheduledTask', 'Get-ScheduledTaskInfo')
            }
            Mock Get-ScheduledTask {
                if ($script:TaskMode -eq 'Missing') {
                    $missingTaskError = [System.Management.Automation.ErrorRecord]::new(
                        [System.Management.Automation.ItemNotFoundException]::new('Provider-specific task query text.'),
                        'CmdletizationQuery_NotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $null
                    )
                    throw $missingTaskError
                }
                New-CimInstance -ClassName MSFT_ScheduledTask `
                    -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClientOnly -Property @{
                        TaskName = 'Endpoint Agent Maintenance'
                        TaskPath = '\Contoso\'
                        State = if ($script:TaskMode -eq 'Disabled') { 'Disabled' } else { 'Ready' }
                        Actions = 'SECRET-TASK-ACTION SECRET-TASK-ARGUMENT'
                    }
            }
            Mock Get-ScheduledTaskInfo {
                if ($script:TaskMode -eq 'Error') { throw 'Access denied to SECRET-TASK-ACTION.' }
                [pscustomobject]@{
                    LastRunTime   = switch ($script:TaskMode) {
                        'Old' { [DateTime]::Now.AddDays(-3) }
                        'Boundary' { [DateTime]::Now.AddMinutes(-$Control.MaximumAgeMinutes - 0.01) }
                        default { [DateTime]::Now.AddMinutes(-5) }
                    }
                    LastTaskResult = if ($script:TaskMode -eq 'Failed') { 1 } else { 0 }
                }
            }

            $healthy = Get-EFControlState -Control $Control
            $healthy.Status | Should -Be 'Compliant'
            (ConvertTo-Json $healthy -Depth 10) | Should -Not -Match 'SECRET-TASK-ACTION|SECRET-TASK-ARGUMENT'
            $script:TaskMode = 'Failed'
            (Get-EFControlState -Control $Control).Status | Should -Be 'NonCompliant'
            $script:TaskMode = 'Boundary'
            (Get-EFControlState -Control $Control).Status | Should -Be 'NonCompliant' -Because 'display rounding must not make an old job look recent'
            $script:TaskMode = 'Missing'
            (Get-EFControlState -Control $Control).Status | Should -Be 'NonCompliant'
            $script:TaskMode = 'Error'
            $errorResult = Get-EFControlState -Control $Control
            $errorResult.Status | Should -Be 'Error'
            $errorResult.Message | Should -Not -Match 'SECRET-TASK-ACTION'
        }
    }

    It 'checks Defender definition age, handles passive mode, and caches one status read' {
        $control = & $script:GetExpandedControl 'DefenderSignatureHealth'
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            $script:DefenderMode = 'Recent'
            Mock Get-Command { [pscustomobject]@{ Name = $Name } } -ParameterFilter { $Name -eq 'Get-MpComputerStatus' }
            Mock Get-MpComputerStatus {
                if ($script:DefenderMode -eq 'Error') { throw 'Private Defender provider failure.' }
                [pscustomobject]@{
                    AntivirusEnabled      = $true
                    AMRunningMode         = if ($script:DefenderMode -eq 'Passive') { 'Passive Mode' } elseif ($script:DefenderMode -eq 'EdrBlock') { 'EDR Block Mode' } else { 'Normal' }
                    AntivirusSignatureAge = if ($script:DefenderMode -eq 'Old') { 20 } elseif ($script:DefenderMode -eq 'NullAge') { $null } else { 2 }
                    AntivirusSignatureVersion = 'PRIVATE-SIGNATURE-VERSION'
                }
            }

            $context = @{ Cache = @{}; AllowNetworkChecks = $false }
            $recent = Get-EFControlState -Control $Control -EvaluationContext $context
            $recent.Status | Should -Be 'Compliant'
            (ConvertTo-Json $recent -Depth 10) | Should -Not -Match 'PRIVATE-SIGNATURE-VERSION'
            $null = Get-EFControlState -Control $Control -EvaluationContext $context
            Should -Invoke Get-MpComputerStatus -Times 1 -Exactly
            $script:DefenderMode = 'Old'
            (Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }).Status |
                Should -Be 'NonCompliant'
            $script:DefenderMode = 'Passive'
            (Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }).Status |
                Should -Be 'NotApplicable'
            $script:DefenderMode = 'EdrBlock'
            (Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }).Status |
                Should -Be 'NotApplicable'
            $script:DefenderMode = 'NullAge'
            (Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }).Status |
                Should -Be 'Error'
            $script:DefenderMode = 'Error'
            $defenderError = Get-EFControlState -Control $Control -EvaluationContext @{ Cache = @{}; AllowNetworkChecks = $false }
            $defenderError.Status | Should -Be 'Error'
            $defenderError.Message | Should -Not -Match 'Private Defender provider failure'
        }
    }
}

Describe 'File, certificate, process, and access checklist behavior' {
    It 'checks file freshness without reading or returning file contents' {
        $path = Join-Path $TestDrive 'freshness.status'
        Set-Content -LiteralPath $path -Value 'SECRET-FILE-CONTENT' -Encoding UTF8
        (Get-Item -LiteralPath $path).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-5)
        $control = & $script:GetExpandedControl 'FileFreshness'
        $control.Path = $path

        InModuleScope EndpointForge -Parameters @{ Control = $control; Path = $path } {
            $fresh = Get-EFControlState -Control $Control
            $fresh.Status | Should -Be 'Compliant'
            (ConvertTo-Json $fresh -Depth 10) | Should -Not -Match 'SECRET-FILE-CONTENT'

            (Get-Item -LiteralPath $Path).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-2)
            (Get-EFControlState -Control $Control).Status | Should -Be 'NonCompliant'

            (Get-Item -LiteralPath $Path).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-$Control.MaximumAgeMinutes - 0.01)
            (Get-EFControlState -Control $Control).Status | Should -Be 'NonCompliant' -Because 'display rounding must not make a stale file look recent'

            (Get-Item -LiteralPath $Path).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(10)
            (Get-EFControlState -Control $Control).Status | Should -Be 'Error'
        }
    }

    It 'treats a missing exact certificate as false without exposing the thumbprint' {
        $control = & $script:GetExpandedControl 'CertificateExpiry'
        $control.StoreLocation = 'LocalMachine'
        $control.StoreName = 'Root'
        $control.Thumbprint = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'

        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            $missing = Get-EFControlState -Control $Control
            $missing.Status | Should -Be 'NonCompliant'
            $missing.ActualValue | Should -BeFalse
            (ConvertTo-Json $missing -Depth 10) | Should -Not -Match 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'

            $Control.DesiredValue = $false
            (Get-EFControlState -Control $Control).Status | Should -Be 'Compliant'
        }
    }

    It 'checks only the requested process name and returns no process details' {
        $currentProcess = [Diagnostics.Process]::GetCurrentProcess()
        try { $currentName = $currentProcess.ProcessName; $currentId = $currentProcess.Id }
        finally { $currentProcess.Dispose() }
        $control = & $script:GetExpandedControl 'ProcessRunning'
        $control.ProcessName = $currentName

        InModuleScope EndpointForge -Parameters @{ Control = $control; CurrentId = $currentId } {
            $running = Get-EFControlState -Control $Control
            $running.Status | Should -Be 'Compliant'
            $running.ActualValue | Should -BeTrue
            $running.PSObject.Properties.Name | Should -Not -Contain 'ProcessId'
            (ConvertTo-Json $running -Depth 10) | Should -Not -Match ('"{0}"' -f $CurrentId)

            $Control.ProcessName = 'EndpointForgeProcessThatDoesNotExist987654321'
            (Get-EFControlState -Control $Control).Status | Should -Be 'NonCompliant'
        }
    }

    It 'checks one direct local-group membership without returning unrelated members' {
        $control = & $script:GetExpandedControl 'LocalGroupMembership'
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            $script:MembershipMode = 'Present'
            Mock Test-EFLocalGroupMembership {
                if ($script:MembershipMode -eq 'Error') { throw 'Access denied while reading PRIVATE-OTHER-MEMBER.' }
                [pscustomobject]@{
                    ProviderAvailable = $true
                    GroupFound = $script:MembershipMode -ne 'MissingGroup'
                    IsMember = $script:MembershipMode -eq 'Present'
                    OtherMembers = 'PRIVATE-OTHER-MEMBER'
                }
            }

            $context = @{ AllowNetworkChecks = $true; Cache = @{} }
            $present = Get-EFControlState -Control $Control -EvaluationContext $context
            $present.Status | Should -Be 'Compliant'
            (ConvertTo-Json $present -Depth 10) | Should -Not -Match 'PRIVATE-GROUP-DESCRIPTION|PRIVATE-OTHER-MEMBER|S-1-5-21-PRIVATE'
            $script:MembershipMode = 'Missing'
            (Get-EFControlState -Control $Control -EvaluationContext $context).Status | Should -Be 'NonCompliant'
            $script:MembershipMode = 'MissingGroup'
            $missingGroup = Get-EFControlState -Control $Control -EvaluationContext $context
            $missingGroup.Status | Should -Be 'NonCompliant'
            $missingGroup.Message | Should -Not -Match 'PRIVATE-MISSING-GROUP-DETAIL'
            $script:MembershipMode = 'Error'
            $errorResult = Get-EFControlState -Control $Control -EvaluationContext $context
            $errorResult.Status | Should -Be 'Error'
            $errorResult.Message | Should -Not -Match 'PRIVATE-OTHER-MEMBER'
        }
    }
}

Describe 'Network-active checklist consent, privacy, and caching' {
    BeforeAll {
        $script:NetworkControls = @(
            & $script:GetExpandedControl 'TcpPort'
            & $script:GetExpandedControl 'WindowsUpdateAvailable'
            & $script:GetExpandedControl 'DnsResolution'
            & $script:GetExpandedControl 'HttpEndpointHealth'
            & $script:GetExpandedControl 'LocalGroupMembership'
        )
        $script:NetworkBaseline = & $script:NewExpandedBaseline $script:NetworkControls 'Network.Consent.Test'
    }

    It 'blocks every local network-active item before any probe starts' {
        InModuleScope EndpointForge -Parameters @{ Baseline = $script:NetworkBaseline } {
            Mock Test-EFWindows { $true }
            Mock Test-EFTcpPort { throw 'TCP probe must not run.' }
            Mock Get-EFWindowsUpdateAvailability { throw 'Update scan must not run.' }
            Mock Test-EFDnsResolution { throw 'DNS probe must not run.' }
            Mock Test-EFHttpEndpoint { throw 'HTTP probe must not run.' }
            Mock Test-EFLocalGroupMembership { throw 'Group lookup must not run.' }

            { Get-EFComplianceReport -Baseline $Baseline -NoProgress } | Should -Throw '*AllowNetworkChecks*'
            Should -Invoke Test-EFTcpPort -Times 0 -Exactly
            Should -Invoke Get-EFWindowsUpdateAvailability -Times 0 -Exactly
            Should -Invoke Test-EFDnsResolution -Times 0 -Exactly
            Should -Invoke Test-EFHttpEndpoint -Times 0 -Exactly
            Should -Invoke Test-EFLocalGroupMembership -Times 0 -Exactly
        }
    }

    It 'runs approved probes and returns no update titles, addresses, headers, or content' {
        InModuleScope EndpointForge -Parameters @{ Baseline = $script:NetworkBaseline } {
            Mock Test-EFWindows { $true }
            Mock Test-EFTcpPort {
                [pscustomobject]@{ Connected = $true; FailureReason = 'None'; IsEvaluationError = $false }
            }
            Mock Get-EFWindowsUpdateAvailability {
                [pscustomobject]@{
                    UpdateCount = 0; ResultCode = 2; WarningCount = 0
                    Titles = @('PRIVATE-UPDATE-TITLE'); KnowledgeBaseIds = @('PRIVATE-KB')
                }
            }
            Mock Test-EFDnsResolution {
                [pscustomobject]@{
                    Resolved = $true; FailureReason = 'None'; IsEvaluationError = $false
                    Addresses = @('192.0.2.99')
                }
            }
            Mock Test-EFHttpEndpoint {
                [pscustomobject]@{
                    Responded = $true; StatusCode = 200; FailureReason = 'None'; IsEvaluationError = $false
                    Headers = @{ Authorization = 'PRIVATE-AUTHORIZATION' }; Content = 'PRIVATE-HTTP-CONTENT'
                }
            }
            Mock Test-EFLocalGroupMembership {
                [pscustomobject]@{ ProviderAvailable = $true; GroupFound = $true; IsMember = $true }
            }

            $report = Get-EFComplianceReport -Baseline $Baseline -AllowNetworkChecks -NoProgress
            $report.IsCompliant | Should -BeTrue
            $report.CompliantCount | Should -Be 5
            $serialized = ConvertTo-Json $report -Depth 20
            $serialized | Should -Not -Match 'PRIVATE-UPDATE-TITLE|PRIVATE-KB|192\.0\.2\.99|PRIVATE-AUTHORIZATION|PRIVATE-HTTP-CONTENT'
            Should -Invoke Test-EFTcpPort -Times 1 -Exactly
            Should -Invoke Get-EFWindowsUpdateAvailability -Times 1 -Exactly
            Should -Invoke Test-EFDnsResolution -Times 1 -Exactly
            Should -Invoke Test-EFHttpEndpoint -Times 1 -Exactly
            Should -Invoke Test-EFLocalGroupMembership -Times 1 -Exactly
        }
    }

    It 'maps DNS and HTTP negative and failed probes without false-green errors' {
        $dnsControl = & $script:GetExpandedControl 'DnsResolution'
        $httpControl = & $script:GetExpandedControl 'HttpEndpointHealth'
        InModuleScope EndpointForge -Parameters @{ DnsControl = $dnsControl; HttpControl = $httpControl } {
            $context = @{ AllowNetworkChecks = $true; Cache = @{} }
            $script:DnsMode = 'Missing'
            Mock Test-EFDnsResolution {
                if ($script:DnsMode -eq 'Error') {
                    return [pscustomobject]@{ Resolved = $false; FailureReason = 'Timeout'; IsEvaluationError = $true }
                }
                [pscustomobject]@{ Resolved = $false; FailureReason = 'NameNotFound'; IsEvaluationError = $false }
            }
            $script:HttpMode = 'Unexpected'
            Mock Test-EFHttpEndpoint {
                if ($script:HttpMode -eq 'Error') {
                    return [pscustomobject]@{ Responded = $false; StatusCode = $null; FailureReason = 'TlsFailure'; IsEvaluationError = $true }
                }
                if ($script:HttpMode -eq 'Timeout') {
                    return [pscustomobject]@{ Responded = $false; StatusCode = $null; FailureReason = 'Timeout'; IsEvaluationError = $false }
                }
                [pscustomobject]@{ Responded = $true; StatusCode = 503; FailureReason = 'None'; IsEvaluationError = $false }
            }

            (Get-EFControlState -Control $DnsControl -EvaluationContext $context).Status | Should -Be 'NonCompliant'
            $script:DnsMode = 'Error'
            (Get-EFControlState -Control $DnsControl -EvaluationContext $context).Status | Should -Be 'Error'
            (Get-EFControlState -Control $HttpControl -EvaluationContext $context).Status | Should -Be 'NonCompliant'
            $script:HttpMode = 'Timeout'
            $timedOut = Get-EFControlState -Control $HttpControl -EvaluationContext $context
            $timedOut.Status | Should -Be 'NonCompliant'
            $timedOut.Message | Should -Match 'did not return an HTTP response'
            $timedOut.Message | Should -Not -Match 'status 0'
            $script:HttpMode = 'Error'
            (Get-EFControlState -Control $HttpControl -EvaluationContext $context).Status | Should -Be 'Error'
        }
    }

    It 'caches one Windows Update result inside an evaluation and starts fresh for a new evaluation' {
        $control = & $script:GetExpandedControl 'WindowsUpdateAvailable'
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            Mock Get-EFWindowsUpdateAvailability {
                [pscustomobject]@{ UpdateCount = 0; ResultCode = 2; WarningCount = 0 }
            }

            $firstContext = @{ AllowNetworkChecks = $true; Cache = @{} }
            (Get-EFControlState -Control $Control -EvaluationContext $firstContext).Status | Should -Be 'Compliant'
            (Get-EFControlState -Control $Control -EvaluationContext $firstContext).Status | Should -Be 'Compliant'
            Should -Invoke Get-EFWindowsUpdateAvailability -Times 1 -Exactly

            $secondContext = @{ AllowNetworkChecks = $true; Cache = @{} }
            (Get-EFControlState -Control $Control -EvaluationContext $secondContext).Status | Should -Be 'Compliant'
            Should -Invoke Get-EFWindowsUpdateAvailability -Times 2 -Exactly
        }
    }

    It 'returns Error for an incomplete Windows Update scan and never exposes provider details' {
        $control = & $script:GetExpandedControl 'WindowsUpdateAvailable'
        InModuleScope EndpointForge -Parameters @{ Control = $control } {
            Mock Get-EFWindowsUpdateAvailability { throw 'PRIVATE-UPDATE-PROVIDER-DETAIL' }

            $result = Get-EFControlState -Control $Control -EvaluationContext @{
                AllowNetworkChecks = $true
                Cache = @{}
            }

            $result.Status | Should -Be 'Error'
            $result.ActualValue | Should -BeNullOrEmpty
            $result.Message | Should -Not -Match 'PRIVATE-UPDATE-PROVIDER-DETAIL'
            # Provider errors remain actionable, but update metadata must never be added to the result.
            $result.PSObject.Properties.Name | Should -Not -Contain 'Updates'
            $result.PSObject.Properties.Name | Should -Not -Contain 'Titles'
        }
    }
}
