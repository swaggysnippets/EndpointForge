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
