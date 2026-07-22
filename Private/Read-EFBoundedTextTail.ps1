function Read-EFBoundedTextTail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateRange(1, 10000)]
        [int]$TailLines,

        [Parameter(Mandatory)]
        [ValidateSet('Utf8', 'Unicode', 'BigEndianUnicode', 'Ascii')]
        [string]$Encoding,

        [ValidateRange(1, 8388608)]
        [int]$MaximumDecodedCharacters = 8388608
    )

    $textEncoding = switch ($Encoding) {
        'Utf8' {
            [Text.UTF8Encoding]::new($false, $true)
        }
        'Unicode' {
            [Text.UnicodeEncoding]::new($false, $true, $true)
        }
        'BigEndianUnicode' {
            [Text.UnicodeEncoding]::new($true, $true, $true)
        }
        'Ascii' {
            [Text.Encoding]::GetEncoding(
                'us-ascii',
                [Text.EncoderFallback]::ExceptionFallback,
                [Text.DecoderFallback]::ExceptionFallback
            )
        }
    }
    $bytesPerCharacter = switch ($Encoding) {
        'Utf8' { 4 }
        'Ascii' { 1 }
        default { 2 }
    }
    $newlineAllowance = [int64]$TailLines * $(if ($Encoding -in @('Unicode', 'BigEndianUnicode')) { 4 } else { 2 })
    $maximumBytes = ([int64]$MaximumDecodedCharacters + 1) * $bytesPerCharacter + $newlineAllowance + 4

    $fileStream = [IO.FileStream]::new(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite
    )
    try {
        $fileLength = [int64]$fileStream.Length
        if ($fileLength -eq 0) {
            return [pscustomobject]@{
                Lines      = @()
                BytesRead  = 0
                WasLimited = $false
            }
        }

        $bytesToRead = [int][math]::Min($fileLength, $maximumBytes)
        $startOffset = $fileLength - $bytesToRead
        if ($Encoding -in @('Unicode', 'BigEndianUnicode') -and $startOffset % 2 -ne 0) {
            $startOffset--
            $bytesToRead++
        }

        $buffer = [byte[]]::new($bytesToRead)
        $null = $fileStream.Seek($startOffset, [IO.SeekOrigin]::Begin)
        $totalRead = 0
        while ($totalRead -lt $bytesToRead) {
            $read = $fileStream.Read($buffer, $totalRead, $bytesToRead - $totalRead)
            if ($read -eq 0) {
                break
            }
            $totalRead += $read
        }
        if ($totalRead -ne $bytesToRead) {
            throw [System.IO.IOException]::new('The text file changed or ended before the bounded tail read completed.')
        }

        $wasLimited = $startOffset -gt 0
        if ($wasLimited) {
            $delimiterEnd = -1
            if ($Encoding -in @('Utf8', 'Ascii')) {
                for ($index = 0; $index -lt $buffer.Length; $index++) {
                    if ($buffer[$index] -eq 10) {
                        $delimiterEnd = $index + 1
                        break
                    }
                    if ($buffer[$index] -eq 13) {
                        $delimiterEnd = if ($index + 1 -lt $buffer.Length -and $buffer[$index + 1] -eq 10) {
                            $index + 2
                        } else {
                            $index + 1
                        }
                        break
                    }
                }
            }
            else {
                for ($index = 0; $index + 1 -lt $buffer.Length; $index += 2) {
                    $codePoint = if ($Encoding -eq 'Unicode') {
                        [int]$buffer[$index] -bor ([int]$buffer[$index + 1] -shl 8)
                    }
                    else {
                        ([int]$buffer[$index] -shl 8) -bor [int]$buffer[$index + 1]
                    }
                    if ($codePoint -eq 10) {
                        $delimiterEnd = $index + 2
                        break
                    }
                    if ($codePoint -eq 13) {
                        $nextCodePoint = -1
                        if ($index + 3 -lt $buffer.Length) {
                            $nextCodePoint = if ($Encoding -eq 'Unicode') {
                                [int]$buffer[$index + 2] -bor ([int]$buffer[$index + 3] -shl 8)
                            }
                            else {
                                ([int]$buffer[$index + 2] -shl 8) -bor [int]$buffer[$index + 3]
                            }
                        }
                        $delimiterEnd = if ($nextCodePoint -eq 10) { $index + 4 } else { $index + 2 }
                        break
                    }
                }
            }

            if ($delimiterEnd -lt 0 -or $delimiterEnd -ge $buffer.Length) {
                throw [System.IO.InvalidDataException]::new(
                    'The selected log tail exceeds the safe read limit. Reduce TailLines and run the check again.'
                )
            }
            $trimmedBuffer = [byte[]]::new($buffer.Length - $delimiterEnd)
            [Array]::Copy($buffer, $delimiterEnd, $trimmedBuffer, 0, $trimmedBuffer.Length)
            $buffer = $trimmedBuffer
        }

        try {
            $decodedText = $textEncoding.GetString($buffer)
        }
        catch [Text.DecoderFallbackException] {
            throw [System.IO.InvalidDataException]::new(
                "The text file is not valid $Encoding text. Choose the correct Encoding and run the check again.",
                $_.Exception
            )
        }

        $selectedLines = @()
        if ($decodedText.Length -gt 0) {
            # Ignore one terminal line delimiter, matching Get-Content -Tail semantics.
            # Locate the requested tail by scanning backward so a file containing
            # millions of tiny lines never materializes millions of strings.
            $effectiveEnd = $decodedText.Length
            if ($decodedText[$effectiveEnd - 1] -eq "`n") {
                $effectiveEnd--
                if ($effectiveEnd -gt 0 -and $decodedText[$effectiveEnd - 1] -eq "`r") {
                    $effectiveEnd--
                }
            }
            elseif ($decodedText[$effectiveEnd - 1] -eq "`r") {
                $effectiveEnd--
            }

            $selectedStart = 0
            $logicalLineCount = 1
            for ($index = $effectiveEnd - 1; $index -ge 0; $index--) {
                if ($decodedText[$index] -eq "`n") {
                    $delimiterEnd = $index + 1
                    if ($index -gt 0 -and $decodedText[$index - 1] -eq "`r") {
                        $index--
                    }
                    $logicalLineCount++
                    if ($logicalLineCount -gt $TailLines) {
                        $selectedStart = $delimiterEnd
                        break
                    }
                }
                elseif ($decodedText[$index] -eq "`r") {
                    $logicalLineCount++
                    if ($logicalLineCount -gt $TailLines) {
                        $selectedStart = $index + 1
                        break
                    }
                }
            }

            if ($wasLimited -and $logicalLineCount -lt $TailLines) {
                throw [System.IO.InvalidDataException]::new(
                    'The selected log tail exceeds the safe read limit. Reduce TailLines and run the check again.'
                )
            }

            $selectedText = $decodedText.Substring($selectedStart, $effectiveEnd - $selectedStart)
            $lineList = [Collections.Generic.List[string]]::new()
            $lineStart = 0
            $decodedCharacterCount = 0
            for ($index = 0; $index -lt $selectedText.Length; $index++) {
                if ($selectedText[$index] -ne "`r" -and $selectedText[$index] -ne "`n") {
                    continue
                }

                $lineLength = $index - $lineStart
                $decodedCharacterCount += $lineLength
                if ($decodedCharacterCount -gt $MaximumDecodedCharacters) {
                    throw [System.IO.InvalidDataException]::new(
                        'The selected log tail exceeds the decoded-character limit. Reduce TailLines and run the check again.'
                    )
                }
                $lineList.Add($selectedText.Substring($lineStart, $lineLength))
                if ($selectedText[$index] -eq "`r" -and
                    $index + 1 -lt $selectedText.Length -and $selectedText[$index + 1] -eq "`n") {
                    $index++
                }
                $lineStart = $index + 1
            }

            $lastLineLength = $selectedText.Length - $lineStart
            $decodedCharacterCount += $lastLineLength
            if ($decodedCharacterCount -gt $MaximumDecodedCharacters) {
                throw [System.IO.InvalidDataException]::new(
                    'The selected log tail exceeds the decoded-character limit. Reduce TailLines and run the check again.'
                )
            }
            $lineList.Add($selectedText.Substring($lineStart, $lastLineLength))
            $selectedLines = @($lineList)
        }

        [pscustomobject]@{
            Lines      = @($selectedLines)
            BytesRead  = $totalRead
            WasLimited = $wasLimited
        }
    }
    finally {
        $fileStream.Dispose()
    }
}
