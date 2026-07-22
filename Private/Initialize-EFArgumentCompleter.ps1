function Initialize-EFArgumentCompleter {
    [CmdletBinding()]
    param()

    if ($null -eq (Get-Command -Name Register-ArgumentCompleter -ErrorAction SilentlyContinue)) {
        return
    }

    $dataPath = Join-Path $script:ModuleRoot 'Data'
    $baselineCompleter = {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $null = $commandName, $parameterName, $commandAst, $fakeBoundParameters
        foreach ($file in Get-ChildItem -LiteralPath $dataPath -Filter '*.json' -File -ErrorAction SilentlyContinue) {
            if ($file.Name -eq 'Baseline.schema.json') { continue }
            $candidate = $file.BaseName
            if ($candidate -like "$wordToComplete*") {
                [Management.Automation.CompletionResult]::new(
                    $candidate,
                    $candidate,
                    [Management.Automation.CompletionResultType]::ParameterValue,
                    "EndpointForge built-in baseline: $candidate"
                )
            }
        }
    }.GetNewClosure()

    Register-ArgumentCompleter -CommandName @(
        'Get-EFBaseline', 'Get-EFComplianceReport', 'Get-EFEndpointSummary',
        'Get-EFRemediationPlan', 'Invoke-EFEndpointRemediation',
        'Show-EFEndpointSummary', 'Show-EFMenu', 'Test-EFEndpointCompliance'
    ) -ParameterName Baseline -ScriptBlock $baselineCompleter
    Register-ArgumentCompleter -CommandName Get-EFBaseline,Test-EFBaseline -ParameterName Name -ScriptBlock $baselineCompleter

    try {
        $baseline = Get-Content -LiteralPath (Join-Path $dataPath 'EnterpriseRecommended.json') -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
        $controlCompletionData = @($baseline.Controls | ForEach-Object {
            [pscustomobject]@{ Id = [string]$_.Id; Title = [string]$_.Title }
        })
        $controlCompleter = {
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            $null = $commandName, $parameterName, $commandAst, $fakeBoundParameters
            foreach ($control in $controlCompletionData) {
                if ($control.Id -like "$wordToComplete*") {
                    [Management.Automation.CompletionResult]::new(
                        $control.Id,
                        $control.Id,
                        [Management.Automation.CompletionResultType]::ParameterValue,
                        $control.Title
                    )
                }
            }
        }.GetNewClosure()
        Register-ArgumentCompleter -CommandName @(
            'Get-EFComplianceReport', 'Get-EFEndpointSummary', 'Get-EFRemediationPlan',
            'Invoke-EFEndpointRemediation', 'Show-EFEndpointSummary', 'Test-EFEndpointCompliance'
        ) -ParameterName ControlId -ScriptBlock $controlCompleter
    }
    catch {
        Write-Verbose "EndpointForge control-ID completion could not be initialized: $($_.Exception.Message)"
    }
}
