function Export-EFEndpointReport {
    <#
    .SYNOPSIS
    Exports EndpointForge objects to HTML, JSON, CSV, or CLIXML.

    .DESCRIPTION
    Accepts pipeline input and writes a report. HTML creates a self-contained,
    plain-language report for people; it does not load scripts, fonts, or other content
    from the internet. Nested properties are preserved in JSON and CLIXML; CSV serializes
    nested values as compact JSON strings. Existing files require Force. The command
    supports WhatIf and Confirm.

    .PARAMETER InputObject
    One or more EndpointForge or PowerShell objects to export.

    .PARAMETER Path
    The destination path. A matching extension is appended when none is provided.

    .PARAMETER Format
    Html, Json, Csv, or Clixml. When omitted, the format is inferred from the destination
    extension and defaults to Json when the path has no extension.

    .PARAMETER Depth
    The maximum object depth used for JSON and CLIXML serialization.

    .PARAMETER AsArray
    Always writes a JSON array, including when the pipeline contains one object.

    .PARAMETER AllowUnsafeCsvFormulaValues
    Disables the default protection that prefixes spreadsheet formula characters in CSV
    text cells and column names. Use only when the CSV will never be opened by spreadsheet
    software and preserving the original leading characters is required. This switch is
    rejected for non-CSV reports.

    .PARAMETER Force
    Overwrites an existing report.

    .PARAMETER PassThru
    Returns the created FileInfo. The command is silent by default.

    .EXAMPLE
    Get-EFEndpointHealth | Export-EFEndpointReport -Path C:\ProgramData\EndpointForge\health.json

    .EXAMPLE
    Get-EFInstalledSoftware | Export-EFEndpointReport -Path .\software.csv -Format Csv -Force

    .EXAMPLE
    Get-EFEndpointSummary -NoProgress | Export-EFEndpointReport -Path .\computer-check.html

    .EXAMPLE
    $data | Export-EFEndpointReport -Path .\raw-data.csv -AllowUnsafeCsvFormulaValues

    Exports original leading formula characters for a trusted non-spreadsheet consumer.

    .OUTPUTS
    System.IO.FileInfo when PassThru is specified.

    .LINK
    Get-EFEndpointSummary
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [ValidateSet('Html', 'Json', 'Csv', 'Clixml')]
        [string]$Format,

        [ValidateRange(2, 100)]
        [int]$Depth = 12,

        [switch]$AsArray,

        [switch]$AllowUnsafeCsvFormulaValues,

        [switch]$Force,

        [switch]$PassThru
    )

    begin {
        $items = [Collections.Generic.List[object]]::new()
    }

    process {
        $items.Add($InputObject)
    }

    end {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $pathExtension = [IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
        $extensionFormat = switch ($pathExtension) {
            '.html' { 'Html' }
            '.htm' { 'Html' }
            '.json' { 'Json' }
            '.csv' { 'Csv' }
            '.clixml' { 'Clixml' }
            default { $null }
        }
        $effectiveFormat = if ($PSBoundParameters.ContainsKey('Format')) { $Format } elseif ($null -ne $extensionFormat) { $extensionFormat } else { 'Json' }

        if (-not [string]::IsNullOrWhiteSpace($pathExtension) -and $null -eq $extensionFormat) {
            throw [System.ArgumentException]::new(
                "Report extension '$pathExtension' is not supported. Use .html, .json, .csv, or .clixml."
            )
        }
        if ($null -ne $extensionFormat -and $PSBoundParameters.ContainsKey('Format') -and $extensionFormat -ne $Format) {
            throw [System.ArgumentException]::new(
                "Path extension '$pathExtension' does not match requested format '$Format'. Use a matching extension or omit Format."
            )
        }
        if ([string]::IsNullOrWhiteSpace($pathExtension)) {
            $extension = switch ($effectiveFormat) { 'Html' { '.html' } 'Json' { '.json' } 'Csv' { '.csv' } 'Clixml' { '.clixml' } }
            $resolvedPath += $extension
        }
        if ($AsArray -and $effectiveFormat -ne 'Json') {
            throw [System.ArgumentException]::new('AsArray is supported only for JSON reports.')
        }
        if ($AllowUnsafeCsvFormulaValues -and $effectiveFormat -ne 'Csv') {
            throw [System.ArgumentException]::new('AllowUnsafeCsvFormulaValues is supported only for CSV reports.')
        }
        $containsNull = $false
        foreach ($reportItem in $items) {
            if ($null -eq $reportItem) { $containsNull = $true; break }
        }
        if ($containsNull -and $effectiveFormat -ne 'Json') {
            throw [System.ArgumentException]::new('Null report input is supported only for JSON output.')
        }

        if ((Test-Path -LiteralPath $resolvedPath) -and -not $Force) {
            throw [System.IO.IOException]::new("Report '$resolvedPath' already exists. Use -Force to overwrite it.")
        }

        if (-not $PSCmdlet.ShouldProcess($resolvedPath, "Export $($items.Count) report object(s) as $effectiveFormat")) {
            return
        }

        $parent = Split-Path -Parent $resolvedPath
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
            $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop
        }

        $output = if ($items.Count -eq 1 -and -not $AsArray) { $items[0] } else { @($items) }
        $utf8WithoutBom = [Text.UTF8Encoding]::new($false)
        $temporaryPath = Join-Path $parent (
            ".{0}.{1}.tmp" -f [IO.Path]::GetFileName($resolvedPath), [guid]::NewGuid().ToString('N')
        )
        $backupPath = Join-Path $parent (
            ".{0}.{1}.bak" -f [IO.Path]::GetFileName($resolvedPath), [guid]::NewGuid().ToString('N')
        )
        try {
            switch ($effectiveFormat) {
                'Html' {
                    $html = ConvertTo-EFHtmlReport -InputObject $items.ToArray() -Title 'EndpointForge computer report'
                    [IO.File]::WriteAllText($temporaryPath, $html, $utf8WithoutBom)
                }
                'Json' {
                    if ($AsArray) {
                        $serializableItems = [Collections.Generic.List[object]]::new()
                        foreach ($item in $items) {
                            if ($null -eq $item) {
                                $serializableItems.Add($null)
                            }
                            else {
                                $serializableItems.Add((ConvertTo-EFSerializableValue -InputObject $item))
                            }
                        }
                        $json = ConvertTo-Json -InputObject $serializableItems.ToArray() -Depth $Depth
                    }
                    else {
                        $serializableOutput = ConvertTo-EFSerializableValue -InputObject $output
                        $json = if ($null -eq $output) { 'null' } else { ConvertTo-Json -InputObject $serializableOutput -Depth $Depth }
                    }
                    [IO.File]::WriteAllText($temporaryPath, $json, $utf8WithoutBom)
                }
                'Csv' {
                    $csv = @($items | ForEach-Object {
                        ConvertTo-EFFlatRecord -InputObject $_ -AllowUnsafeCsvFormulaValues:$AllowUnsafeCsvFormulaValues
                    }) |
                        ConvertTo-Csv -NoTypeInformation
                    [IO.File]::WriteAllLines($temporaryPath, [string[]]$csv, $utf8WithoutBom)
                }
                'Clixml' {
                    $output | Export-Clixml -LiteralPath $temporaryPath -Depth $Depth -Force -ErrorAction Stop
                }
            }

            if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
                # Windows PowerShell 5.1/.NET Framework rejects a null backup path
                # even though newer runtimes accept it. A same-directory backup keeps
                # replacement atomic across both supported PowerShell generations.
                [IO.File]::Replace($temporaryPath, $resolvedPath, $backupPath, $true)
            }
            else {
                [IO.File]::Move($temporaryPath, $resolvedPath)
            }
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
            }
        }

        Write-EFLog -Message "Report exported to '$resolvedPath'." -Data @{ format = $effectiveFormat; itemCount = $items.Count }
        if ($PassThru) {
            Get-Item -LiteralPath $resolvedPath
        }
    }
}
