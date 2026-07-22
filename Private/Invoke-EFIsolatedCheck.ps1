function Invoke-EFIsolatedCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$InputData,

        [ValidateRange(100, 603000)]
        [int]$TimeoutMilliseconds,

        [ValidateRange(0, 10000)]
        [int]$StartupAllowanceMilliseconds = 0,

        [ValidateNotNullOrEmpty()]
        [string]$Activity = 'The isolated check'
    )

    $inputJson = $InputData | ConvertTo-Json -Compress -Depth 8
    $inputBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($inputJson))
    $checkBase64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptBlock.ToString()))
    $bootstrap = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
try {
    `$inputJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$inputBase64'))
    `$inputObject = `$inputJson | ConvertFrom-Json -ErrorAction Stop
    `$checkText = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$checkBase64'))
    `$check = [scriptblock]::Create(`$checkText)
    `$result = & `$check `$inputObject
    [Console]::Out.Write((`$result | ConvertTo-Json -Compress -Depth 8))
    exit 0
}
catch {
    [Console]::Error.Write(`$_.Exception.GetType().FullName)
    exit 1
}
"@

    $engineFileName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $powerShellPath = Join-Path $PSHOME $engineFileName
    if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) {
        throw [InvalidOperationException]::new(
            "$Activity requires '$engineFileName' in the active PowerShell engine folder, but it was not found."
        )
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $powerShellPath
    $readerScript = @'
[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
$workerText = [Console]::In.ReadToEnd()
if ($workerText.Length -gt 0 -and [int]$workerText[0] -eq 0xFEFF) { $workerText = $workerText.Substring(1) }
& ([scriptblock]::Create($workerText))
'@
    $encodedReader = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($readerScript))
    $startInfo.Arguments = "-NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedReader"
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $outputTask = $null
    $errorTask = $null
    $processStarted = $false
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) {
            throw [InvalidOperationException]::new("$Activity could not start its isolated worker process.")
        }
        $processStarted = $true
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $hardTimeout = [int64]$TimeoutMilliseconds + [int64]$StartupAllowanceMilliseconds
        $inputBytes = [Text.Encoding]::ASCII.GetBytes($bootstrap + [Environment]::NewLine)
        $inputTask = $process.StandardInput.BaseStream.WriteAsync($inputBytes, 0, $inputBytes.Length)
        if (-not $inputTask.Wait([int]$hardTimeout)) {
            try { $process.Kill() }
            catch {
                throw [TimeoutException]::new("$Activity exceeded its time limit and its isolated worker could not be stopped.")
            }
            if (-not $process.WaitForExit(5000)) {
                throw [TimeoutException]::new("$Activity exceeded its time limit and worker termination could not be confirmed.")
            }
            throw [TimeoutException]::new("$Activity did not finish within its time limit.")
        }
        $null = $inputTask.GetAwaiter().GetResult()
        $process.StandardInput.Close()
        $remainingMilliseconds = [math]::Max(1, $hardTimeout - $stopwatch.ElapsedMilliseconds)
        if (-not $process.WaitForExit([int]$remainingMilliseconds)) {
            try { $process.Kill() }
            catch {
                throw [TimeoutException]::new("$Activity exceeded its time limit and its isolated worker could not be stopped.")
            }
            if (-not $process.WaitForExit(5000)) {
                throw [TimeoutException]::new("$Activity exceeded its time limit and worker termination could not be confirmed.")
            }
            throw [TimeoutException]::new("$Activity did not finish within its time limit.")
        }

        $standardOutput = $outputTask.GetAwaiter().GetResult()
        $null = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw [InvalidOperationException]::new("$Activity could not complete in its isolated worker.")
        }
        if ([string]::IsNullOrWhiteSpace($standardOutput)) {
            throw [InvalidOperationException]::new("$Activity returned no trustworthy result.")
        }
        try {
            return $standardOutput | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw [InvalidOperationException]::new("$Activity returned an unreadable result.")
        }
    }
    finally {
        $stopwatch.Stop()
        if ($processStarted -and -not $process.HasExited) {
            try {
                $process.Kill()
                $null = $process.WaitForExit(5000)
            }
            catch { Write-Verbose "$Activity worker cleanup could not be confirmed." }
        }
        if ($null -ne $process) { $process.Dispose() }
    }
}
