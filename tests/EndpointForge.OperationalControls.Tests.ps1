BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ManifestPath = Join-Path $script:ProjectRoot 'EndpointForge.psd1'
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force
}

AfterAll {
    Remove-Module EndpointForge -Force -ErrorAction SilentlyContinue
}

Describe 'Everyday checklist validation' {
    BeforeAll {
        $script:EverydayBaseline = Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'examples\EverydayChecks.json') `
            -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    It 'validates all four report-only everyday item types' {
        InModuleScope EndpointForge -Parameters @{ Candidate = $script:EverydayBaseline } {
            { Assert-EFBaseline -Baseline $Candidate } | Should -Not -Throw
            @($Candidate.Controls.Type) | Should -Contain 'FileExists'
            @($Candidate.Controls.Type) | Should -Contain 'FileContainsText'
            @($Candidate.Controls.Type) | Should -Contain 'WindowsEvent'
            @($Candidate.Controls.Type) | Should -Contain 'TcpPort'
            @($Candidate.Controls | Where-Object Remediable).Count | Should -Be 0
        }
    }

    It 'warns that TCP items make observable connections without running them' {
        $result = Test-EFBaseline -InputObject $script:EverydayBaseline -PassThru

        $result.IsValid | Should -BeTrue
        $result.WarningCount | Should -Be 1
        $result.Warnings[0] | Should -Match 'TCP connection'
    }

    It 'creates an edit-before-use everyday template' {
        $path = Join-Path $TestDrive 'Contoso.Operations.json'

        $result = New-EFBaseline -Name 'Contoso.Operations' -Template EverydayChecks -Path $path

        $result.Template | Should -Be 'EverydayChecks'
        $result.ControlCount | Should -Be 4
        $result.NextSteps[0] | Should -Match 'Replace every sample'
        (Test-EFBaseline -Path $path) | Should -BeTrue
    }

    It 'rejects automatic fixes and restart claims for everyday items' {
        $automatic = $script:EverydayBaseline | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $automatic.Controls[0].Remediable = $true
        $restart = $script:EverydayBaseline | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $restart.Controls[0].RequiresReboot = $true

        InModuleScope EndpointForge -Parameters @{ Automatic = $automatic; Restart = $restart } {
            { Assert-EFBaseline -Baseline $Automatic } | Should -Throw '*audit-only*'
            { Assert-EFBaseline -Baseline $Restart } | Should -Throw '*cannot require a restart*'
        }
    }

    It 'rejects unsafe file paths' -ForEach @(
        @{ UnsafePath = '..\agent.log' }
        @{ UnsafePath = '\\server\share\agent.log' }
        @{ UnsafePath = 'C:\Logs\*.log' }
        @{ UnsafePath = 'C:\Logs\agent.log:secret' }
        @{ UnsafePath = 'HKLM:\Software\Contoso' }
    ) {
        $candidate = $script:EverydayBaseline | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $candidate.Controls[0].Path = $UnsafePath

        InModuleScope EndpointForge -Parameters @{ Candidate = $candidate } {
            { Assert-EFBaseline -Baseline $Candidate } | Should -Throw '*unsafe file Path*'
        }
    }

    It 'rejects unbounded or ambiguous log, event, and host fields' {
        $badTail = $script:EverydayBaseline | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $badTail.Controls[1].TailLines = 10001
        $badEvent = $script:EverydayBaseline | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $badEvent.Controls[2].EventIds = @(1000, 1000)
        $badHost = $script:EverydayBaseline | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $badHost.Controls[3].HostName = 'https://app.contoso.example/path'

        InModuleScope EndpointForge -Parameters @{ BadTail = $badTail; BadEvent = $badEvent; BadHost = $badHost } {
            { Assert-EFBaseline -Baseline $BadTail } | Should -Throw '*TailLines*'
            { Assert-EFBaseline -Baseline $BadEvent } | Should -Throw '*duplicate*'
            { Assert-EFBaseline -Baseline $BadHost } | Should -Throw '*HostName*'
        }
    }

    It 'rejects non-string values for everyday text fields instead of coercing them' -ForEach @(
        @{ ControlIndex = 0; PropertyName = 'Path'; BadValue = @('C:\Logs\one.log', 'C:\Logs\two.log') }
        @{ ControlIndex = 1; PropertyName = 'Text'; BadValue = @('fatal', 'error') }
        @{ ControlIndex = 2; PropertyName = 'LogName'; BadValue = 123 }
        @{ ControlIndex = 2; PropertyName = 'ProviderName'; BadValue = @('One', 'Two') }
        @{ ControlIndex = 3; PropertyName = 'HostName'; BadValue = 127001 }
    ) {
        $candidate = $script:EverydayBaseline | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $candidate.Controls[$ControlIndex].$PropertyName = $BadValue

        InModuleScope EndpointForge -Parameters @{ Candidate = $candidate; PropertyName = $PropertyName } {
            { Assert-EFBaseline -Baseline $Candidate } | Should -Throw "*$PropertyName must be a JSON string*"
        }
    }

    It 'rejects a drive letter backed by a UNC PowerShell drive root' {
        InModuleScope EndpointForge {
            Mock Get-PSDrive {
                [pscustomobject]@{ Name = 'Q'; Root = '\\server\share'; DisplayRoot = '' }
            }

            { Resolve-EFLocalFilePath -Path 'Q:\agent.log' } | Should -Throw '*network-mapped drives*'
        }
    }
}

Describe 'File checklist items' {
    BeforeAll {
        $script:ExistingFile = Join-Path $TestDrive 'agent.ready'
        $script:LogFile = Join-Path $TestDrive 'agent.log'
        Set-Content -LiteralPath $script:ExistingFile -Value 'ready' -Encoding UTF8
        Set-Content -LiteralPath $script:LogFile -Value @(
            'first line only',
            'normal activity',
            'SERVICE [READY].* token-should-never-be-exported'
        ) -Encoding UTF8
    }

    It 'reports whether one exact file exists without reading its contents' {
        InModuleScope EndpointForge -Parameters @{ ExistingFile = $script:ExistingFile } {
            $control = [pscustomobject]@{
                Id = 'FILE-EXISTS'; Title = 'Required file'; Type = 'FileExists'; Severity = 'High'
                Path = $ExistingFile; DesiredValue = $true; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'Compliant'
            $result.ActualValue | Should -BeTrue
        }
    }

    It 'returns a definite false when the exact file is absent' {
        $missingFile = Join-Path $TestDrive 'missing.ready'
        InModuleScope EndpointForge -Parameters @{ MissingFile = $missingFile } {
            $control = [pscustomobject]@{
                Id = 'FILE-MISSING'; Title = 'Required file'; Type = 'FileExists'; Severity = 'High'
                Path = $MissingFile; DesiredValue = $true; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'NonCompliant'
            $result.ActualValue | Should -BeFalse
        }
    }

    It 'performs a bounded literal case-insensitive text search without leaking matching content' {
        InModuleScope EndpointForge -Parameters @{ LogFile = $script:LogFile } {
            $control = [pscustomobject]@{
                Id = 'LOG-TEXT'; Title = 'Ready text'; Type = 'FileContainsText'; Severity = 'Medium'
                Path = $LogFile; Text = '[ready].*'; TailLines = 2; CaseSensitive = $false
                Encoding = 'Utf8'; DesiredValue = $true; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'Compliant'
            $result.ActualValue | Should -BeTrue
            $result.Message | Should -Not -Match 'token-should-never-be-exported'
            $result.Message | Should -Not -Match '\[ready\]\.\*'
        }
    }

    It 'does not search before the requested tail window' {
        InModuleScope EndpointForge -Parameters @{ LogFile = $script:LogFile } {
            $control = [pscustomobject]@{
                Id = 'LOG-TAIL'; Title = 'First text'; Type = 'FileContainsText'; Severity = 'Low'
                Path = $LogFile; Text = 'first line only'; TailLines = 2; CaseSensitive = $false
                Encoding = 'Utf8'; DesiredValue = $true; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'NonCompliant'
            $result.ActualValue | Should -BeFalse
        }
    }

    It 'returns Error instead of a false green when the text file is missing' {
        $missingLog = Join-Path $TestDrive 'missing.log'
        InModuleScope EndpointForge -Parameters @{ MissingLog = $missingLog } {
            $control = [pscustomobject]@{
                Id = 'LOG-MISSING'; Title = 'No error text'; Type = 'FileContainsText'; Severity = 'High'
                Path = $MissingLog; Text = 'fatal'; DesiredValue = $false; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'Error'
            $result.ActualValue | Should -BeNullOrEmpty
        }
    }

    It 'enforces the decoded-character limit before an early text match can pass' {
        $oversizedTail = Join-Path $TestDrive 'oversized-tail.log'
        Set-Content -LiteralPath $oversizedTail -Value ('MATCH' + ('x' * 100)) -Encoding UTF8

        InModuleScope EndpointForge -Parameters @{ OversizedTail = $oversizedTail } {
            {
                Read-EFBoundedTextTail -Path $OversizedTail -TailLines 1 -Encoding Utf8 `
                    -MaximumDecodedCharacters 64
            } | Should -Throw '*decoded-character limit*'
        }
    }

    It 'stops at a byte bound instead of materializing one oversized log line' {
        $hugeLine = Join-Path $TestDrive 'huge-line.log'
        Set-Content -LiteralPath $hugeLine -Value ('x' * 4096) -Encoding UTF8

        InModuleScope EndpointForge -Parameters @{ HugeLine = $hugeLine } {
            {
                Read-EFBoundedTextTail -Path $HugeLine -TailLines 1 -Encoding Utf8 `
                    -MaximumDecodedCharacters 64
            } | Should -Throw '*safe read limit*'
        }
    }

    It 'materializes only the requested number of lines from a many-line log' {
        $manyLines = Join-Path $TestDrive 'many-short-lines.log'
        Set-Content -LiteralPath $manyLines -Value (1..25000 | ForEach-Object { "line-$_" }) -Encoding UTF8

        InModuleScope EndpointForge -Parameters @{ ManyLines = $manyLines } {
            $tail = Read-EFBoundedTextTail -Path $ManyLines -TailLines 2000 -Encoding Utf8

            @($tail.Lines).Count | Should -Be 2000
            $tail.Lines[0] | Should -Be 'line-23001'
            $tail.Lines[-1] | Should -Be 'line-25000'
        }
    }

    It 'returns Error rather than a false green when the log cannot be opened' {
        InModuleScope EndpointForge -Parameters @{ LogFile = $script:LogFile } {
            Mock Read-EFBoundedTextTail { throw [System.UnauthorizedAccessException]::new('Access denied.') }
            $control = [pscustomobject]@{
                Id = 'LOG-DENIED'; Title = 'No error text'; Type = 'FileContainsText'; Severity = 'High'
                Path = $LogFile; Text = 'fatal'; DesiredValue = $false; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'Error'
            $result.ActualValue | Should -BeNullOrEmpty
            $result.Message | Should -Match 'Access denied'
        }
    }

    It 'returns Error rather than a false green when the log changes during the read' {
        InModuleScope EndpointForge -Parameters @{ LogFile = $script:LogFile } {
            $script:GetItemCall = 0
            Mock Resolve-EFLocalFilePath { $Path }
            Mock Read-EFBoundedTextTail { [pscustomobject]@{ Lines = @('normal activity') } }
            Mock Get-Item {
                $script:GetItemCall++
                [pscustomobject]@{
                    PSIsContainer = $false
                    Attributes = [IO.FileAttributes]::Normal
                    Length = if ($script:GetItemCall -eq 1) { 100 } else { 101 }
                    LastWriteTimeUtc = [datetime]'2026-07-21T12:00:00Z'
                }
            }
            $control = [pscustomobject]@{
                Id = 'LOG-CHANGED'; Title = 'No error text'; Type = 'FileContainsText'; Severity = 'High'
                Path = $LogFile; Text = 'fatal'; DesiredValue = $false; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'Error'
            $result.ActualValue | Should -BeNullOrEmpty
            $result.Message | Should -Match 'changed while EndpointForge was reading it'
        }
    }
}

Describe 'Windows event checklist items' {
    It 'uses an indexed bounded event query and never returns event content' {
        InModuleScope EndpointForge {
            $script:CapturedEventFilter = $null
            Mock Get-WinEvent { [pscustomobject]@{ LogName = 'Application' } } -ParameterFilter { $null -ne $ListLog }
            Mock Get-WinEvent {
                $script:CapturedEventFilter = $FilterHashtable
                [pscustomobject]@{ Id = 1000; Message = 'private event payload' }
            } -ParameterFilter { $null -ne $FilterHashtable }
            $control = [pscustomobject]@{
                Id = 'EVENT-SUCCESS'; Title = 'Success event'; Type = 'WindowsEvent'; Severity = 'High'
                LogName = 'Application'; ProviderName = 'Contoso App'; EventIds = @(1000, 1001)
                LookbackMinutes = 60; MinimumCount = 1; DesiredValue = $true; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'Compliant'
            $result.ActualValue | Should -BeTrue
            $script:CapturedEventFilter.LogName | Should -Be 'Application'
            $script:CapturedEventFilter.ProviderName | Should -Be 'Contoso App'
            @($script:CapturedEventFilter.Id) | Should -Be @(1000, 1001)
            $script:CapturedEventFilter.StartTime | Should -BeOfType ([DateTime])
            $result.Message | Should -Not -Match 'private event payload'
        }
    }

    It 'returns a definite false when the event query completes with no matches' {
        InModuleScope EndpointForge {
            Mock Get-WinEvent { [pscustomobject]@{ LogName = 'System' } } -ParameterFilter { $null -ne $ListLog }
            Mock Get-WinEvent { @() } -ParameterFilter { $null -ne $FilterHashtable }
            $control = [pscustomobject]@{
                Id = 'EVENT-MISSING'; Title = 'Recent event'; Type = 'WindowsEvent'; Severity = 'Medium'
                LogName = 'System'; EventIds = @(42); DesiredValue = $true; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'NonCompliant'
            $result.ActualValue | Should -BeFalse
        }
    }

    It 'returns Error when the intended event log cannot be read' {
        InModuleScope EndpointForge {
            Mock Get-WinEvent { throw 'Access denied to the requested event log.' } -ParameterFilter { $null -ne $ListLog }
            $control = [pscustomobject]@{
                Id = 'EVENT-DENIED'; Title = 'Protected event'; Type = 'WindowsEvent'; Severity = 'High'
                LogName = 'Security'; EventIds = @(4624); DesiredValue = $true; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'Error'
            $result.Message | Should -Match 'Access denied'
        }
    }

    It 'returns Error instead of a false green when event commands are unavailable' {
        InModuleScope EndpointForge {
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-WinEvent' }
            $control = [pscustomobject]@{
                Id = 'EVENT-UNAVAILABLE'; Title = 'Recent event'; Type = 'WindowsEvent'; Severity = 'High'
                LogName = 'System'; EventIds = @(42); DesiredValue = $false; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'Error'
            $result.Message | Should -Match 'commands are unavailable'
        }
    }

    It 'returns Error when the intended event log is disabled' {
        InModuleScope EndpointForge {
            Mock Get-WinEvent { [pscustomobject]@{ LogName = 'System'; IsEnabled = $false } } `
                -ParameterFilter { $null -ne $ListLog }
            Mock Get-WinEvent { @() } -ParameterFilter { $null -ne $FilterHashtable }
            $control = [pscustomobject]@{
                Id = 'EVENT-DISABLED'; Title = 'Recent event'; Type = 'WindowsEvent'; Severity = 'High'
                LogName = 'System'; EventIds = @(42); DesiredValue = $false; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'Error'
            $result.Message | Should -Match 'event log.*disabled'
            Should -Invoke Get-WinEvent -Times 0 -Exactly -ParameterFilter { $null -ne $FilterHashtable }
        }
    }
}

Describe 'TCP port checklist items' {
    It 'maps a successful TCP connection to a Boolean checklist result' {
        InModuleScope EndpointForge {
            Mock Test-EFTcpPort {
                [pscustomobject]@{ Connected = $true; FailureReason = 'None'; IsEvaluationError = $false }
            }
            $control = [pscustomobject]@{
                Id = 'TCP-OPEN'; Title = 'App connection'; Type = 'TcpPort'; Severity = 'High'
                HostName = 'app.contoso.example'; Port = 443; TimeoutMilliseconds = 3000
                DesiredValue = $true; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'Compliant'
            $result.ActualValue | Should -BeTrue
            $result.Message | Should -Match 'without sending application data'
        }
    }

    It 'treats a refused connection as a definite false' {
        InModuleScope EndpointForge {
            Mock Test-EFTcpPort {
                [pscustomobject]@{ Connected = $false; FailureReason = 'ConnectionRefused'; IsEvaluationError = $false }
            }
            $control = [pscustomobject]@{
                Id = 'TCP-CLOSED'; Title = 'App connection'; Type = 'TcpPort'; Severity = 'High'
                HostName = 'app.contoso.example'; Port = 443; DesiredValue = $true; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'NonCompliant'
            $result.ActualValue | Should -BeFalse
        }
    }

    It 'returns Error when DNS did not identify the intended host' {
        InModuleScope EndpointForge {
            Mock Test-EFTcpPort {
                [pscustomobject]@{ Connected = $false; FailureReason = 'NameResolutionFailed'; IsEvaluationError = $false }
            }
            $control = [pscustomobject]@{
                Id = 'TCP-DNS'; Title = 'App connection'; Type = 'TcpPort'; Severity = 'High'
                HostName = 'missing.contoso.example'; Port = 443; DesiredValue = $false; Remediable = $false
            }

            $result = Get-EFControlState -Control $control

            $result.Status | Should -Be 'Error'
            $result.ActualValue | Should -BeNullOrEmpty
        }
    }

    It 'opens and closes one real loopback connection without using the external network' {
        InModuleScope EndpointForge {
            $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
            try {
                $listener.Start()
                $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port

                $probe = Test-EFTcpPort -HostName '127.0.0.1' -Port $port -TimeoutMilliseconds 1000

                $probe.Connected | Should -BeTrue
                $probe.FailureReason | Should -Be 'None'
            }
            finally {
                $listener.Stop()
            }
        }
    }
}

Describe 'Everyday control readiness and fleet safety' {
    It 'describes all four checks in everyday words and offers no automatic fixes' {
        $readiness = Get-EFEndpointReadiness -Baseline $script:EverydayBaseline

        $readiness.NetworkCheckCount | Should -Be 1
        @($readiness.ControlCapabilities).Count | Should -Be 4
        @($readiness.ControlCapabilities | Where-Object FixStatus -ne 'NotOffered').Count | Should -Be 0
        ($readiness.ControlCapabilities | Where-Object Type -eq 'TcpPort').HowChecked | Should -Match 'one time-limited TCP connection'
        ($readiness.ControlCapabilities | Where-Object Type -eq 'WindowsEvent').HowChecked | Should -Match 'Event messages.*never returned'
    }

    It 'blocks fleet fan-out until network checks are explicitly allowed' {
        InModuleScope EndpointForge -Parameters @{ Baseline = $script:EverydayBaseline } {
            Mock Invoke-Command { @() }
            $targetComputer = 'PC-101'

            { Get-EFFleetSummary -ComputerName $targetComputer -Baseline $Baseline } | Should -Throw '*AllowNetworkChecks*'
            Should -Invoke Invoke-Command -Times 0 -Exactly
        }
    }

    It 'allows an explicitly approved fleet network check to reach remoting' {
        InModuleScope EndpointForge -Parameters @{ Baseline = $script:EverydayBaseline } {
            Mock Invoke-Command { @() }
            $targetComputer = 'PC-101'

            $result = Get-EFFleetSummary -ComputerName $targetComputer -Baseline $Baseline -AllowNetworkChecks

            Should -Invoke Invoke-Command -Times 1 -Exactly
            $result.NetworkCheckCount | Should -Be 1
            $result.NetworkChecksAllowed | Should -BeTrue
        }
    }
}

Describe 'Everyday checks in the guided menu' {
    It 'shows the four capabilities and makes the example template edit-before-use' {
        $script:EverydayMenuInputs = [Collections.Generic.Queue[string]]::new()
        foreach ($inputValue in @('6', '5', '', 'B', 'Q')) {
            $script:EverydayMenuInputs.Enqueue($inputValue)
        }
        $script:EverydayMenuLines = [Collections.Generic.List[string]]::new()
        Mock Read-Host -ModuleName EndpointForge {
            if ($script:EverydayMenuInputs.Count -eq 0) { return 'Q' }
            return $script:EverydayMenuInputs.Dequeue()
        }
        Mock Write-Host -ModuleName EndpointForge { $script:EverydayMenuLines.Add([string]$Object) }

        Show-EFMenu -NoPause -NoColor
        $text = $script:EverydayMenuLines -join "`n"

        $text | Should -Match 'required files'
        $text | Should -Match 'text near the end of a log'
        $text | Should -Match 'Windows event IDs'
        $text | Should -Match 'network connection examples'
        $text | Should -Match 'fictional Contoso targets'
        $text | Should -Match 'edited before they are run'
    }

    It 'shows the TCP notice again after selecting another checklist with the same name and version' {
        $firstChecklist = $script:EverydayBaseline | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $secondChecklist = $script:EverydayBaseline | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        ($firstChecklist.Controls | Where-Object Type -eq 'TcpPort').HostName = 'first.contoso.example'
        ($secondChecklist.Controls | Where-Object Type -eq 'TcpPort').HostName = 'second.contoso.example'
        $firstPath = Join-Path $TestDrive 'First.Everyday.json'
        $secondPath = Join-Path $TestDrive 'Second.Everyday.json'
        [IO.File]::WriteAllText($firstPath, ($firstChecklist | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($secondPath, ($secondChecklist | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))

        $script:EverydayMenuInputs = [Collections.Generic.Queue[string]]::new()
        foreach ($inputValue in @('1', '6', '2', $secondPath, 'B', '1', 'Q')) {
            $script:EverydayMenuInputs.Enqueue($inputValue)
        }
        $script:EverydayMenuLines = [Collections.Generic.List[string]]::new()
        Mock Read-Host -ModuleName EndpointForge { $script:EverydayMenuInputs.Dequeue() }
        Mock Write-Host -ModuleName EndpointForge { $script:EverydayMenuLines.Add([string]$Object) }
        Mock Get-EFEndpointSummary -ModuleName EndpointForge {
            [pscustomobject]@{
                PSTypeName = 'EndpointForge.EndpointSummary'; ComputerName = 'MENU-PC'; OverallStatus = 'Healthy';
                CompletedAtUtc = [DateTime]::UtcNow; IssueCount = 0; UnknownCount = 0
            }
        }
        Mock Show-EFEndpointSummary -ModuleName EndpointForge {}

        Show-EFMenu -Baseline $firstPath -NoProgress -NoPause -NoColor

        @($script:EverydayMenuLines | Where-Object { $_ -match '\[NETWORK NOTE\]' }).Count | Should -Be 2
    }
}
