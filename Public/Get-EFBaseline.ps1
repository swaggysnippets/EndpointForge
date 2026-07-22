function Get-EFBaseline {
    <#
    .SYNOPSIS
    Loads a built-in or file-based Windows computer checklist.

    .DESCRIPTION
    A checklist is a list of things expected to be true, such as Windows settings,
    required files, recent events, or an available network service. PowerShell commands
    call it a baseline for compatibility. This command only loads and validates the JSON
    file. It does not read a target file or event log, attempt a network connection, check
    a setting, or change a computer. ListAvailable shows the checklists included with the
    module.

    .PARAMETER Name
    The built-in checklist name. EnterpriseRecommended is the default.

    .PARAMETER Path
    The path to a custom checklist JSON file. Review custom files before use because they
    choose which local paths, event logs, hosts, and ports later checks can inspect.

    .PARAMETER ListAvailable
    Lists information about every checklist included with the installed module.

    .EXAMPLE
    Get-EFBaseline -Name EnterpriseRecommended

    .EXAMPLE
    Get-EFBaseline -Path .\contoso-baseline.json

    .EXAMPLE
    Get-EFBaseline -ListAvailable

    .EXAMPLE
    Get-EFBaseline -Path .\checklists\Contoso.EverydayChecks.json

    Loads and validates an everyday-checklist file without running any of its checks.

    .OUTPUTS
    EndpointForge.Baseline or EndpointForge.BaselineInfo.

    .LINK
    New-EFBaseline

    .LINK
    Test-EFBaseline
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    param(
        [Parameter(ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [string]$Name = 'EnterpriseRecommended',

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'List')]
        [switch]$ListAvailable
    )

    if ($ListAvailable) {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:ModuleRoot 'Data') -Filter '*.json' -File) {
            if ($file.Name -eq 'Baseline.schema.json') {
                continue
            }
            try {
                $item = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                Assert-EFBaseline -Baseline $item
                [pscustomobject]@{
                    PSTypeName   = 'EndpointForge.BaselineInfo'
                    Name         = [string]$item.Name
                    Version      = [string]$item.Version
                    Description  = [string]$item.Description
                    ControlCount = @($item.Controls).Count
                    Path         = $file.FullName
                }
            }
            catch {
                Write-Warning "Skipping invalid built-in baseline '$($file.Name)': $($_.Exception.Message)"
            }
        }
        return
    }

    if ($PSCmdlet.ParameterSetName -eq 'Name') {
        if ($Name -notmatch '^[A-Za-z0-9._-]+$') {
            throw [System.ArgumentException]::new("Baseline name '$Name' contains invalid characters.")
        }
        $resolvedPath = Join-Path (Join-Path $script:ModuleRoot 'Data') "$Name.json"
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw [System.IO.FileNotFoundException]::new("Built-in baseline '$Name' was not found.")
        }
    }
    else {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw [System.IO.FileNotFoundException]::new("Baseline file '$resolvedPath' was not found.")
        }
    }

    try {
        $baseline = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw [System.IO.InvalidDataException]::new("Baseline '$resolvedPath' is not valid JSON: $($_.Exception.Message)")
    }

    Assert-EFBaseline -Baseline $baseline
    $baseline.PSObject.TypeNames.Insert(0, 'EndpointForge.Baseline')
    $baseline | Add-Member -NotePropertyName SourcePath -NotePropertyValue $resolvedPath -Force
    $baseline | Add-Member -NotePropertyName ControlCount -NotePropertyValue @($baseline.Controls).Count -Force
    $baseline | Add-Member -NotePropertyName RemediableCount -NotePropertyValue @($baseline.Controls | Where-Object Remediable).Count -Force
    return $baseline
}
