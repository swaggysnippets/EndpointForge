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

    .OUTPUTS
    System.IO.FileInfo when PassThru is specified.

    .LINK
    Get-EFEndpointSummary
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
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
        switch ($effectiveFormat) {
            'Html' {
                $html = ConvertTo-EFHtmlReport -InputObject $items.ToArray() -Title 'EndpointForge computer report'
                [IO.File]::WriteAllText($resolvedPath, $html, $utf8WithoutBom)
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
                [IO.File]::WriteAllText($resolvedPath, $json, $utf8WithoutBom)
            }
            'Csv' {
                $csv = @($items | ForEach-Object { ConvertTo-EFFlatRecord -InputObject $_ }) |
                    ConvertTo-Csv -NoTypeInformation
                [IO.File]::WriteAllLines($resolvedPath, [string[]]$csv, $utf8WithoutBom)
            }
            'Clixml' {
                $output | Export-Clixml -LiteralPath $resolvedPath -Depth $Depth -Force:$Force -ErrorAction Stop
            }
        }

        Write-EFLog -Message "Report exported to '$resolvedPath'." -Data @{ format = $effectiveFormat; itemCount = $items.Count }
        if ($PassThru) {
            Get-Item -LiteralPath $resolvedPath
        }
    }
}
