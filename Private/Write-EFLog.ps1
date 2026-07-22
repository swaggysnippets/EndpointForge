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
        $logPath = [Environment]::ExpandEnvironmentVariables([string]$script:EFConfiguration.LogPath)
        $parent = Split-Path -Parent $logPath
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
            $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
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

        $line = $entry | ConvertTo-Json -Depth 8 -Compress
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "EndpointForge could not write to its configured log: $($_.Exception.Message)"
    }
}
