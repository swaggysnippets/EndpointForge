function Write-EFMenuHelp {
    [CmdletBinding()]
    param(
        [switch]$NoColor,

        [ValidateRange(20, 240)]
        [int]$Width = 80
    )

    Write-EFMenuLine -Text '' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Help - everyday words used by EndpointForge' -Color Cyan -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text ('-' * [math]::Min(72, $Width)) -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Checklist: a list of Windows settings and the values you expect. Choosing one does not apply it. PowerShell scripts call it a baseline.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Computer checkup: reads health and settings, then explains the result. It never changes Windows.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Preview: shows the exact supported changes EndpointForge would try. A preview never changes Windows. PowerShell calls this WhatIf.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'EndpointForge can fix: a supported setting that can be changed only after selection, preview, Administrator permission, and typing APPLY exactly.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'You need to review: EndpointForge can explain the item but will not change it automatically.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Could not check: Windows did not provide a definite answer. This does not mean the setting failed or was fixed.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Administrator: a PowerShell window opened with Run as administrator. Normal checks work without it, but protected details and approved fixes may need it.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Before-and-after receipt: records observed values around an approved change. EndpointForge does not promise automatic rollback because policy or later Windows changes may control the setting.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Reports: HTML is easiest for people; JSON is for scripts. Both may contain private device and security information.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'EndpointForge never restarts a computer, installs itself elsewhere, enables remote access, turns on BitLocker, or changes firmware or TPM settings.' -Color Yellow -NoColor:$NoColor -Width $Width
}
