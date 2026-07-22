function Select-EFMenuControlId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Steps,

        [switch]$NoColor,

        [ValidateRange(20, 240)]
        [int]$Width = 80
    )

    $candidates = @($Steps | Where-Object Action -eq 'Automatic')
    if ($candidates.Count -eq 0) {
        return
    }

    Write-EFMenuLine -Text '' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Select supported fixes to preview' -Color Cyan -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Selecting an item does not change Windows. A no-change preview runs next.' -Color Green -NoColor:$NoColor -Width $Width
    for ($index = 0; $index -lt $candidates.Count; $index++) {
        $candidate = $candidates[$index]
        Write-EFMenuLine -Text ("{0}. {1}{2}" -f ($index + 1), $candidate.Title, `
            $(if ($candidate.RequiresReboot) { ' [restart may be required]' } else { '' })) `
            -NoColor:$NoColor -Width $Width -Indent 2
        if (-not [string]::IsNullOrWhiteSpace([string](Get-EFPropertyValue $candidate 'WhatWouldChange' ''))) {
            Write-EFMenuLine -Text ([string]$candidate.WhatWouldChange) -NoColor:$NoColor -Width $Width -Indent 5
        }
    }

    while ($true) {
        $selection = Read-EFMenuInput -Prompt 'Enter numbers separated by commas, A for all, or B to cancel without changes'
        if ($null -eq $selection -or $selection.Trim() -match '^(?i:b|back|q|quit)$') {
            return
        }
        if ($selection.Trim() -match '^(?i:a|all)$') {
            return @($candidates.ControlId)
        }

        $selectedIndices = [Collections.Generic.List[int]]::new()
        $isValid = $true
        foreach ($token in @($selection -split '[,\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            $parsed = 0
            if (-not [int]::TryParse($token, [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt $candidates.Count) {
                $isValid = $false
                break
            }
            if (-not $selectedIndices.Contains($parsed - 1)) {
                $selectedIndices.Add($parsed - 1)
            }
        }
        if ($isValid -and $selectedIndices.Count -gt 0) {
            return @($selectedIndices | ForEach-Object { [string]$candidates[$_].ControlId })
        }
        Write-EFMenuLine -Text '[INVALID] Choose the listed numbers, A, or B.' -Color Yellow -NoColor:$NoColor -Width $Width
    }
}
