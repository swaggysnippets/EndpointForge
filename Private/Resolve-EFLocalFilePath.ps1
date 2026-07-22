function Resolve-EFLocalFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$CheckExistingAncestors
    )

    if ($Path -match '[\x00-\x1F\x7F]') {
        throw [System.ArgumentException]::new('File paths must not contain control characters.')
    }
    if ($Path.Length -gt 1024) {
        throw [System.ArgumentException]::new('File paths cannot be longer than 1,024 characters.')
    }

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
    if ($expandedPath -match '%[A-Za-z_][A-Za-z0-9_]*%') {
        throw [System.ArgumentException]::new(
            "File path '$Path' contains an environment variable that is not defined on this computer."
        )
    }
    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($expandedPath)) {
        throw [System.ArgumentException]::new('File paths must name one exact file and cannot contain wildcard characters.')
    }
    if ($expandedPath -match '^(?:\\\\|//)' -or $expandedPath -notmatch '^[A-Za-z]:\\') {
        throw [System.ArgumentException]::new(
            'File paths must be absolute paths on a local Windows drive, such as C:\ProgramData\Contoso\agent.log. Network and relative paths are not allowed.'
        )
    }
    if ($expandedPath.Substring(2).Contains(':')) {
        throw [System.ArgumentException]::new('File paths cannot name alternate data streams or PowerShell providers.')
    }
    if ($expandedPath -match '(?:^|\\)\.{1,2}(?:\\|$)') {
        throw [System.ArgumentException]::new('File paths cannot contain dot or parent-directory segments.')
    }

    try {
        $fullPath = [IO.Path]::GetFullPath($expandedPath)
    }
    catch {
        throw [System.ArgumentException]::new("File path '$Path' is not a valid local Windows path.", $_.Exception)
    }

    $driveName = $fullPath.Substring(0, 1)
    $drive = Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction SilentlyContinue
    $driveDisplayRoot = if ($null -eq $drive) { '' } else {
        [string](Get-EFPropertyValue -InputObject $drive -Name 'DisplayRoot' -Default '')
    }
    $driveRoot = if ($null -eq $drive) { '' } else {
        [string](Get-EFPropertyValue -InputObject $drive -Name 'Root' -Default '')
    }
    if ($driveDisplayRoot -match '^(?:\\\\|//)' -or $driveRoot -match '^(?:\\\\|//)') {
        throw [System.ArgumentException]::new('File paths on network-mapped drives are not allowed.')
    }
    try {
        $driveInfo = [IO.DriveInfo]::new("${driveName}:\")
        if ($driveInfo.DriveType -eq [IO.DriveType]::Network) {
            throw [System.ArgumentException]::new('File paths on network-mapped drives are not allowed.')
        }
    }
    catch [System.ArgumentException] {
        throw
    }
    catch {
        Write-Verbose "Windows drive-type discovery was unavailable for '$driveName'. The PowerShell drive roots were still checked."
    }

    if ($CheckExistingAncestors) {
        $currentPath = [IO.Path]::GetPathRoot($fullPath)
        $relativePath = $fullPath.Substring($currentPath.Length)
        foreach ($segment in $relativePath.Split([char]'\')) {
            if ([string]::IsNullOrWhiteSpace($segment)) {
                continue
            }
            $currentPath = Join-Path $currentPath $segment
            if (-not (Test-Path -LiteralPath $currentPath -ErrorAction Stop)) {
                break
            }
            $currentItem = Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop
            if (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw [System.ArgumentException]::new(
                    "File path '$Path' passes through a link or reparse point. Use a direct local path instead."
                )
            }
        }
    }

    return $fullPath
}
