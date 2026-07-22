function Get-EFControlCapability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Control,

        [Parameter(Mandatory)]
        [bool]$IsWindowsPlatform,

        [Parameter(Mandatory)]
        [bool]$IsAdministrator
    )

    $controlId = [string](Get-EFPropertyValue -InputObject $Control -Name 'Id')
    $title = [string](Get-EFPropertyValue -InputObject $Control -Name 'Title')
    $type = [string](Get-EFPropertyValue -InputObject $Control -Name 'Type')
    $isAutomaticFixDeclared = [bool](Get-EFPropertyValue -InputObject $Control -Name 'Remediable' -Default $false)

    $checkCommands = @()
    $fixCommands = @()
    $administratorRecommendedForCheck = $false
    $howChecked = $null
    $whatWouldChange = $null
    $isSupportedType = $true

    switch ($type) {
        'Registry' {
            $checkCommands = @('Get-ItemProperty')
            $fixCommands = @('New-Item', 'New-ItemProperty')
            $howChecked = 'Reads one Windows registry setting and compares its current value with the checklist value.'
            $whatWouldChange = 'Sets only the registry value named by this checklist item. It does not run downloaded code or edit unrelated settings.'
        }
        'Service' {
            $checkCommands = @('Get-Service')
            $fixCommands = @('Set-Service')
            $desiredStatus = [string](Get-EFPropertyValue -InputObject $Control -Name 'Status')
            if ($desiredStatus -eq 'Running') {
                $fixCommands += 'Start-Service'
            }
            elseif ($desiredStatus -eq 'Stopped') {
                $fixCommands += 'Stop-Service'
            }
            $howChecked = 'Reads the Windows service start setting and running state requested by this checklist item.'
            $whatWouldChange = 'Changes only the named Windows service setting or running state requested by the checklist.'
        }
        'FirewallProfile' {
            $checkCommands = @('Get-NetFirewallProfile')
            $fixCommands = @('Set-NetFirewallProfile')
            $howChecked = 'Reads whether the named Windows Firewall profile is turned on.'
            $whatWouldChange = 'Turns the named Windows Firewall profile on or off to match the checklist.'
        }
        'Defender' {
            $checkCommands = @('Get-MpComputerStatus')
            $fixCommands = @('Set-MpPreference')
            $howChecked = 'Reads the Microsoft Defender protection setting named by this checklist item.'
            $whatWouldChange = 'Changes only the supported Microsoft Defender real-time protection preference.'
        }
        'WindowsOptionalFeature' {
            $checkCommands = @('Get-WindowsOptionalFeature')
            $desiredFeatureState = [string](Get-EFPropertyValue -InputObject $Control -Name 'DesiredValue')
            if ($desiredFeatureState -eq 'Enabled') {
                $fixCommands = @('Enable-WindowsOptionalFeature')
            }
            else {
                $fixCommands = @('Disable-WindowsOptionalFeature')
            }
            $administratorRecommendedForCheck = $true
            $howChecked = 'Reads whether the named optional Windows feature is enabled or disabled.'
            $whatWouldChange = 'Enables or disables only the named optional Windows feature. EndpointForge never restarts the PC automatically.'
        }
        'PendingRestart' {
            $checkCommands = @('Get-EFPendingReboot')
            $howChecked = 'Reads Windows servicing, update, installer, file-rename, and computer-rename indicators to answer whether a restart is waiting.'
            $whatWouldChange = 'Nothing. EndpointForge never restarts the computer automatically.'
        }
        'DiskSpace' {
            $checkCommands = @('Get-CimInstance')
            $howChecked = 'Reads free space for one exact fixed local drive and compares it with the requested percentage, gigabytes, or both.'
            $whatWouldChange = 'Nothing. EndpointForge does not delete, move, compress, or clean up files.'
        }
        'WindowsUpdateAvailable' {
            $checkCommands = @()
            $howChecked = 'With explicit network approval, asks this computer''s configured Windows Update or WSUS service how many required software updates are waiting. Update titles and metadata are not included in results.'
            $whatWouldChange = 'Nothing is installed or configured. The scan can contact the update service and refresh Windows Update scan metadata, but EndpointForge never downloads updates, accepts licenses, installs updates, or restarts Windows.'
        }
        'InstalledApplication' {
            $checkCommands = @()
            $howChecked = 'Reads Windows uninstall records for one exact application name and optional publisher, product code, architecture, scope, or version. It never uses Win32_Product.'
            $whatWouldChange = 'Nothing. EndpointForge does not install, repair, update, or remove software.'
        }
        'ScheduledTaskHealth' {
            $checkCommands = @('Get-ScheduledTask', 'Get-ScheduledTaskInfo')
            $administratorRecommendedForCheck = $true
            $howChecked = 'Reads one exact scheduled job enabled state, last run time, and result code. Task actions and arguments are never returned.'
            $whatWouldChange = 'Nothing. EndpointForge does not start, stop, enable, disable, create, or edit scheduled jobs.'
        }
        'DefenderSignatureHealth' {
            $checkCommands = @('Get-MpComputerStatus')
            $howChecked = 'Reads the age of Microsoft Defender threat definitions and compares it with the requested maximum age.'
            $whatWouldChange = 'Nothing. EndpointForge reports the age but does not refresh Defender or change antivirus settings.'
        }
        'FileExists' {
            $checkCommands = @('Get-Item')
            $howChecked = 'Looks for one exact file on a local Windows drive. Environment variables such as %ProgramData% are expanded; folders, wildcards, relative paths, and network paths are not accepted.'
            $whatWouldChange = 'Nothing. EndpointForge reports whether the file exists but never creates, deletes, opens, or edits it.'
        }
        'FileContainsText' {
            $checkCommands = @('Get-Item')
            $howChecked = 'Reads a limited number of lines from the end of one local text file and looks for exact ordinary text. Matching lines and file contents are never returned in the result.'
            $whatWouldChange = 'Nothing. EndpointForge reads the text file but never edits, clears, rotates, or copies it.'
        }
        'FileFreshness' {
            $checkCommands = @('Get-Item')
            $howChecked = 'Reads the modified time of one exact local file and compares its age with the requested limit. File contents are not read.'
            $whatWouldChange = 'Nothing. EndpointForge does not open, create, edit, move, or delete the file.'
        }
        'WindowsEvent' {
            $checkCommands = @('Get-WinEvent')
            $eventLogName = [string](Get-EFPropertyValue -InputObject $Control -Name 'LogName')
            $administratorRecommendedForCheck = $eventLogName -eq 'Security'
            $howChecked = 'Counts matching event IDs in one Windows event log during a limited time window. Event messages and event data are never returned in the result.'
            $whatWouldChange = 'Nothing. EndpointForge reads the event log but never writes to it or clears it.'
        }
        'TcpPort' {
            $howChecked = 'Opens one time-limited TCP connection to the exact host and port, then closes it without sending application data. A successful connection does not prove that the application itself is healthy.'
            $whatWouldChange = 'Nothing on this computer. The destination or network monitoring tools may record the brief connection attempt.'
        }
        'DnsResolution' {
            $howChecked = 'With explicit network approval, asks Windows to resolve one absolute server name inside a time-limited worker. Windows can answer from its cache or hosts file, or contact DNS; returned addresses are not included in results.'
            $whatWouldChange = 'Nothing on this computer. DNS infrastructure and network monitoring tools may record a request.'
        }
        'HttpEndpointHealth' {
            $howChecked = 'With explicit network approval, sends a time-limited HEAD or GET check to one exact HTTP or HTTPS address and compares only its status code. A GET response body is not read.'
            $whatWouldChange = 'Nothing on this computer. The web service, configured proxy, and network monitoring tools may record the request; response headers are not included in results and the response body is not read.'
        }
        'CertificateExpiry' {
            $howChecked = 'Opens one Windows certificate store read-only, finds one exact thumbprint, and checks only its time window and remaining days. It does not verify trust, revocation, names, intended use, or a private key.'
            $whatWouldChange = 'Nothing. EndpointForge does not import, export, renew, remove, or access certificate private keys.'
        }
        'ProcessRunning' {
            $howChecked = 'Checks whether one exact program name is running. Process IDs and other details are not included in results; command lines, owners, and loaded modules are not read.'
            $whatWouldChange = 'Nothing. EndpointForge does not start, stop, suspend, or inspect the contents of a process.'
        }
        'LocalGroupMembership' {
            $checkCommands = @('Get-LocalGroup')
            $administratorRecommendedForCheck = $true
            $howChecked = 'With explicit network approval, reads one exact local group inside a time-limited worker, resolves only the requested account to a security identifier, and compares it with direct-member identifiers. Unrelated member identities are not resolved or included in results.'
            $whatWouldChange = 'Nothing. EndpointForge does not add or remove accounts or change local groups. Windows may contact an organizational identity provider while resolving the requested account.'
        }
        'BitLocker' {
            $checkCommands = @('Get-BitLockerVolume')
            $administratorRecommendedForCheck = $true
            $howChecked = 'Reads whether BitLocker protection is active on the requested drive.'
            $whatWouldChange = 'Nothing. EndpointForge reports BitLocker state but never starts encryption automatically.'
        }
        'SecureBoot' {
            $checkCommands = @('Confirm-SecureBootUEFI')
            $administratorRecommendedForCheck = $true
            $howChecked = 'Asks Windows whether Secure Boot is enabled on supported UEFI hardware.'
            $whatWouldChange = 'Nothing. EndpointForge reports Secure Boot state but never changes firmware settings.'
        }
        'Tpm' {
            $checkCommands = @('Get-Tpm')
            $administratorRecommendedForCheck = $true
            $howChecked = 'Asks Windows whether a Trusted Platform Module (TPM) is present and ready.'
            $whatWouldChange = 'Nothing. EndpointForge reports TPM state but never clears, initializes, or changes the TPM.'
        }
        default {
            $isSupportedType = $false
            $howChecked = "The checklist uses an unsupported check type named '$type'."
            $whatWouldChange = 'Nothing. Unsupported checklist items are blocked before a change can be attempted.'
        }
    }

    $missingCheckCommands = [Collections.Generic.List[string]]::new()
    $missingFixCommands = [Collections.Generic.List[string]]::new()
    if ($IsWindowsPlatform -and $isSupportedType) {
        foreach ($commandName in $checkCommands) {
            if ($null -eq (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
                $missingCheckCommands.Add($commandName)
            }
        }
        if ($isAutomaticFixDeclared) {
            foreach ($commandName in $fixCommands) {
                if ($null -eq (Get-Command -Name $commandName -ErrorAction SilentlyContinue)) {
                    $missingFixCommands.Add($commandName)
                }
            }
        }
    }

    $canCheck = $IsWindowsPlatform -and $isSupportedType -and $missingCheckCommands.Count -eq 0
    $automaticFixAvailable = $IsWindowsPlatform -and $isSupportedType -and $isAutomaticFixDeclared -and
        $fixCommands.Count -gt 0 -and $missingFixCommands.Count -eq 0
    $canFixNow = $automaticFixAvailable -and $IsAdministrator

    $checkStatus = if ($canCheck) { 'Available' } else { 'Unavailable' }
    $fixStatus = if (-not $isAutomaticFixDeclared) {
        'NotOffered'
    }
    elseif (-not $automaticFixAvailable) {
        'Unavailable'
    }
    elseif (-not $IsAdministrator) {
        'NeedsAdministrator'
    }
    else {
        'Available'
    }

    $plainLanguage = if (-not $IsWindowsPlatform) {
        'This check is unavailable because EndpointForge endpoint checks require Windows.'
    }
    elseif (-not $isSupportedType) {
        $howChecked
    }
    elseif ($missingCheckCommands.Count -gt 0) {
        "Windows does not provide the command needed for this check in the current session: $($missingCheckCommands -join ', ')."
    }
    elseif ($administratorRecommendedForCheck -and -not $IsAdministrator) {
        'The check is available, but Windows may hide some details from a standard-user PowerShell window.'
    }
    else {
        'The Windows feature needed for this check is available.'
    }

    $nextStep = if (-not $canCheck) {
        'Run the checklist on a supported Windows edition where the named feature is installed.'
    }
    elseif ($administratorRecommendedForCheck -and -not $IsAdministrator) {
        'You can check now. If the result is incomplete, reopen PowerShell using Run as administrator and check again.'
    }
    elseif ($fixStatus -eq 'NeedsAdministrator') {
        'Checking is available now. Reopen PowerShell using Run as administrator only if you later approve a fix.'
    }
    elseif ($fixStatus -eq 'Unavailable') {
        'Checking is available, but EndpointForge cannot offer an automatic fix in this Windows session.'
    }
    elseif ($fixStatus -eq 'NotOffered') {
        'This is a report-only check. EndpointForge will explain the result but will not change this setting.'
    }
    else {
        'This check and its guarded automatic fix are available. A fix still requires preview and approval.'
    }

    [pscustomobject]@{
        PSTypeName                       = 'EndpointForge.ControlCapability'
        ControlId                        = $controlId
        Title                            = $title
        Type                             = $type
        CanCheck                         = $canCheck
        CheckStatus                      = $checkStatus
        MissingCheckCommands             = @($missingCheckCommands)
        AdministratorRecommendedForCheck = $administratorRecommendedForCheck
        IsAutomaticFixDeclared           = $isAutomaticFixDeclared
        AutomaticFixAvailable            = $automaticFixAvailable
        CanFixNow                        = $canFixNow
        FixStatus                        = $fixStatus
        MissingFixCommands               = @($missingFixCommands)
        RequiresAdministratorForFix      = $isAutomaticFixDeclared
        HowChecked                       = $howChecked
        WhatWouldChange                  = $whatWouldChange
        PlainLanguage                    = $plainLanguage
        NextStep                         = $nextStep
    }
}
