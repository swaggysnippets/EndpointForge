function Write-EFLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Debug', 'Information', 'Warning', 'Error')]
        [string]$Level = 'Information',

        [AllowNull()]
        [object]$Data,

        [string]$CorrelationId
    )

    $levels = @{
        Debug       = 0
        Information = 1
        Warning     = 2
        Error       = 3
    }

    if ($levels[$Level] -lt $levels[$script:EFConfiguration.LogLevel]) {
        return
    }

    Write-Verbose -Message ("[{0}] {1}" -f $Level, $Message)

    if ([string]::IsNullOrWhiteSpace([string]$script:EFConfiguration.LogPath)) {
        return
    }

    try {
        $expandedLogPath = [Environment]::ExpandEnvironmentVariables([string]$script:EFConfiguration.LogPath)
        $logPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($expandedLogPath)
        $parent = Split-Path -Parent $logPath
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
            $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
        }
        $pathItem = if (Test-Path -LiteralPath $logPath) {
            Get-Item -LiteralPath $logPath -Force -ErrorAction Stop
        }
        else {
            Get-Item -LiteralPath $parent -Force -ErrorAction Stop
        }
        while ($null -ne $pathItem) {
            if (($pathItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw [System.Security.SecurityException]::new(
                    "The configured log path passes through a link or reparse point: '$logPath'."
                )
            }
            if ($pathItem -is [IO.FileInfo]) {
                $pathItem = $pathItem.Directory
            }
            else {
                $pathItem = $pathItem.Parent
            }
        }

        $entry = [ordered]@{
            timestampUtc = [DateTime]::UtcNow.ToString('o')
            level        = $Level
            message      = $Message
            computerName = $env:COMPUTERNAME
            processId    = $PID
            correlationId = $CorrelationId
            data         = $Data
        }

        $line = ($entry | ConvertTo-Json -Depth 8 -Compress) + [Environment]::NewLine
        $lineBytes = [Text.UTF8Encoding]::new($false).GetBytes($line)
        $written = $false
        $lastWriteError = $null
        foreach ($attempt in 1..3) {
            $stream = $null
            try {
                $stream = [IO.FileStream]::new(
                    $logPath,
                    [IO.FileMode]::Append,
                    [IO.FileAccess]::Write,
                    [IO.FileShare]::Read
                )
                $stream.Write($lineBytes, 0, $lineBytes.Length)
                $stream.Flush($true)
                $written = $true
                break
            }
            catch {
                $lastWriteError = $_.Exception
                if ($attempt -lt 3) {
                    [Threading.Thread]::Sleep(50 * $attempt)
                }
            }
            finally {
                if ($null -ne $stream) { $stream.Dispose() }
            }
        }
        if (-not $written) {
            throw $lastWriteError
        }
    }
    catch {
        Write-Warning "EndpointForge could not write to its configured log: $($_.Exception.Message)"
    }
}
