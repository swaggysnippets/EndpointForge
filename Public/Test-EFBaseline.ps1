function Test-EFBaseline {
    <#
    .SYNOPSIS
    Tests whether an EndpointForge baseline is valid.

    .DESCRIPTION
    Validates baseline structure, control identifiers, value types, remediation safety,
    and type-specific requirements without evaluating or changing the endpoint. Returns
    a Boolean by default. PassThru returns a detailed validation result.

    .PARAMETER Name
    The name of a built-in baseline.

    .PARAMETER Path
    The path to a custom baseline JSON file.

    .PARAMETER InputObject
    An in-memory baseline object, typically received from the pipeline.

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
