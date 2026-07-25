function Read-EFBaselineFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [AllowNull()]
        [string]$ExpectedSha256,

        [switch]$RequireDirectPath,

        [ValidateRange(1, 104857600)]
        [int]$MaximumSizeBytes = 1048576
    )

    $fileItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($fileItem.PSIsContainer) {
        throw [System.IO.FileNotFoundException]::new("Baseline file '$Path' was not found.")
    }

    if ($RequireDirectPath) {
        $currentItem = $fileItem
        while ($null -ne $currentItem) {
            if (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw [System.Security.SecurityException]::new(
                    "Baseline '$Path' passes through a link or reparse point. Use a direct local path for elevated or hash-verified use."
                )
            }

            if ($currentItem -is [IO.FileInfo]) {
                $currentItem = $currentItem.Directory
            }
            else {
                $currentItem = $currentItem.Parent
            }
        }
    }

    $stream = $null
    try {
        # FileShare.Read prevents the opened file from being replaced or modified while
        # the one buffer used for both hashing and JSON parsing is captured.
        $stream = [IO.FileStream]::new(
            $fileItem.FullName,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read
        )
        if ($stream.Length -gt $MaximumSizeBytes) {
            throw [System.IO.InvalidDataException]::new(
                "Baseline '$Path' is $($stream.Length) bytes. The maximum supported baseline size is $MaximumSizeBytes bytes."
            )
        }

        $length = [int]$stream.Length
        $bytes = [byte[]]::new($length)
        $offset = 0
        while ($offset -lt $length) {
            $readCount = $stream.Read($bytes, $offset, $length - $offset)
            if ($readCount -eq 0) {
                throw [System.IO.EndOfStreamException]::new(
                    "Baseline '$Path' ended before its declared length could be read."
                )
            }
            $offset += $readCount
        }
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $actualSha256 = ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        $normalizedExpectedSha256 = $ExpectedSha256.Trim()
        if ($normalizedExpectedSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            throw [System.ArgumentException]::new('ExpectedSha256 must contain exactly 64 hexadecimal characters.')
        }
        if (-not [string]::Equals(
            $actualSha256,
            $normalizedExpectedSha256,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw [System.IO.InvalidDataException]::new(
                "Baseline '$Path' failed SHA-256 verification. Expected $($normalizedExpectedSha256.ToUpperInvariant()), but read $actualSha256."
            )
        }
    }

    $textOffset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $textOffset = 3
    }
    try {
        $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
        $text = $strictUtf8.GetString($bytes, $textOffset, $bytes.Length - $textOffset)
    }
    catch [Text.DecoderFallbackException] {
        throw [System.IO.InvalidDataException]::new(
            "Baseline '$Path' is not valid UTF-8 text.",
            $_.Exception
        )
    }

    return [pscustomobject]@{
        Text        = $text
        Sha256      = $actualSha256
        LengthBytes = $bytes.Length
    }
}
