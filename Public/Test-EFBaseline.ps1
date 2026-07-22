function Test-EFBaseline {
    <#
    .SYNOPSIS
    Checks whether an EndpointForge settings checklist file is valid.

    .DESCRIPTION
    A checklist is a list of things expected to be true, such as Windows settings,
    storage, applications, jobs, files, certificates, recent events, and approved network
    services; scripts call it a baseline. This command checks the file structure, item IDs,
    value types, supported-fix safety, and type-specific requirements. It does not run any
    item or contact a service. Validation confirms safe input shape, not organizational
    authorization. It returns True or False by default. PassThru returns detailed results.

    .PARAMETER Name
    The name of a built-in checklist.

    .PARAMETER Path
    The path to a custom checklist JSON file.

    .PARAMETER InputObject
    An in-memory checklist object, usually returned by Get-EFBaseline.

    .PARAMETER PassThru
    Returns an EndpointForge.BaselineValidation object instead of a Boolean.

    .EXAMPLE
    Test-EFBaseline -Path .\Contoso.Workstation.json

    .EXAMPLE
    Get-EFBaseline | Test-EFBaseline -PassThru

    .OUTPUTS
    System.Boolean
    EndpointForge.BaselineValidation when PassThru is specified.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    param(
        [Parameter(ParameterSetName = 'Name')]
        [ValidateNotNullOrEmpty()]
        [string]$Name = 'EnterpriseRecommended',

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')]
        [AllowNull()]
        [object]$InputObject,

        [switch]$PassThru
    )

    process {
        $errors = [Collections.Generic.List[string]]::new()
        $warnings = [Collections.Generic.List[string]]::new()
        $baseline = $null
        $inputLabel = switch ($PSCmdlet.ParameterSetName) {
            'Path' { $Path }
            'InputObject' { '<pipeline object>' }
            default { $Name }
        }

        try {
            $baseline = switch ($PSCmdlet.ParameterSetName) {
                'Path' { Get-EFBaseline -Path $Path }
                'InputObject' {
                    Assert-EFBaseline -Baseline $InputObject
                    $InputObject
                }
                default { Get-EFBaseline -Name $Name }
            }

            $rebootingControls = @($baseline.Controls | Where-Object {
                [bool](Get-EFPropertyValue -InputObject $_ -Name 'Remediable') -and
                [bool](Get-EFPropertyValue -InputObject $_ -Name 'RequiresReboot' -Default $false)
            })
            if ($rebootingControls.Count -gt 0) {
                $warnings.Add(
                    "$($rebootingControls.Count) remediable control(s) may require a restart. EndpointForge never restarts devices automatically."
                )
            }
            $networkControls = @($baseline.Controls | Where-Object { Test-EFControlUsesNetwork -Control $_ })
            if ($networkControls.Count -gt 0) {
                $networkTypes = @($networkControls.Type | Sort-Object -Unique) -join ', '
                $warnings.Add(
                    "$($networkControls.Count) network-active check(s) ($networkTypes) can contact named or configured services when this checklist is run. Those services or network monitoring tools may record the activity."
                )
            }
        }
        catch {
            $errors.Add($_.Exception.Message)
        }

        $isValid = $errors.Count -eq 0
        [object[]]$controls = @()
        if ($null -ne $baseline) {
            $controls = @($baseline.Controls)
        }
        $validation = [pscustomobject]@{
            PSTypeName       = 'EndpointForge.BaselineValidation'
            Input            = $inputLabel
            IsValid          = $isValid
            Name             = if ($null -ne $baseline) { [string]$baseline.Name } else { $null }
            Version          = if ($null -ne $baseline) { [string]$baseline.Version } else { $null }
            ControlCount     = $controls.Count
            RemediableCount  = @($controls | Where-Object Remediable).Count
            AuditOnlyCount   = @($controls | Where-Object { -not $_.Remediable }).Count
            ErrorCount       = $errors.Count
            WarningCount     = $warnings.Count
            Errors           = @($errors)
            Warnings         = @($warnings)
            CheckedAtUtc     = [DateTime]::UtcNow
            Baseline         = $baseline
        }

        if ($PassThru) {
            $validation
        }
        else {
            [bool]$isValid
        }
    }
}
