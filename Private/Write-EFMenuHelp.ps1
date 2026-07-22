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
    Write-EFMenuLine -Text 'Checklist: a list of things you expect to be true, such as enough disk space, a current update or security state, an application or job working, a file being recent, or an approved service responding. Choosing one does not run it. PowerShell scripts call it a baseline.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Computer checkup: reads health and checklist information, then explains the result. It never changes Windows.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Text log check: looks for exact ordinary words near the end of one local file. It never includes matching lines in the report.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Windows event ID: a number recorded when something happens. Its meaning depends on the event log and usually the event source.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'TCP connection check: briefly asks whether one named host accepts a connection on one numbered port. It sends no application data, but the destination may record the attempt. A connection does not prove the app is healthy.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Network-active check: contacts an approved TCP destination, DNS service, web address, this computer configured update service, or an identity provider while resolving the one requested account. EndpointForge explains the activity and requires NETWORK approval before it runs.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Preview: shows the exact supported changes EndpointForge would try. A preview never changes Windows. PowerShell calls this WhatIf.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'EndpointForge can fix: a supported setting that can be changed only after selection, preview, Administrator permission, and typing APPLY exactly.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'You need to review: EndpointForge can explain the item but will not change it automatically.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Could not check: Windows did not provide a definite answer. This does not mean the setting failed or was fixed.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Administrator: a PowerShell window opened with Run as administrator. Normal checks work without it, but protected details and approved fixes may need it.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Before-and-after receipt: records observed values around an approved change. EndpointForge does not promise automatic rollback because policy or later Windows changes may control the setting.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Reports: HTML is easiest for people; JSON is for scripts. Both may contain private device and security information.' -NoColor:$NoColor -Width $Width
    Write-EFMenuLine -Text 'Report-only checks never create or delete files, edit logs, clear events, install updates or applications, start scheduled jobs or programs, renew certificates, change group membership, restart a computer, turn on BitLocker, or change firmware or TPM settings.' -Color Yellow -NoColor:$NoColor -Width $Width
}
