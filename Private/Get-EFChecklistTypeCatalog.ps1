function Get-EFChecklistTypeCatalog {
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ Category = 'Windows settings and security'; Type = 'Registry'; Question = 'Does this Windows setting have the expected value?'; Activity = 'Supported fix when explicitly configured' }
        [pscustomobject]@{ Category = 'Windows settings and security'; Type = 'Service'; Question = 'Is this Windows service configured and running as expected?'; Activity = 'Supported fix when explicitly configured' }
        [pscustomobject]@{ Category = 'Windows settings and security'; Type = 'FirewallProfile'; Question = 'Is Windows Firewall turned on for this network type?'; Activity = 'Supported fix when explicitly configured' }
        [pscustomobject]@{ Category = 'Windows settings and security'; Type = 'Defender'; Question = 'Does this Microsoft Defender protection setting match what is expected?'; Activity = 'Supported fix when explicitly configured' }
        [pscustomobject]@{ Category = 'Windows settings and security'; Type = 'WindowsOptionalFeature'; Question = 'Is this Windows feature turned on or off as expected?'; Activity = 'Supported fix when explicitly configured' }
        [pscustomobject]@{ Category = 'Windows settings and security'; Type = 'BitLocker'; Question = 'Is this drive protected by BitLocker?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Windows settings and security'; Type = 'SecureBoot'; Question = 'Is Secure Boot turned on?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Windows settings and security'; Type = 'Tpm'; Question = 'Is the computer security chip present and ready?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Everyday computer health'; Type = 'PendingRestart'; Question = 'Does this computer need to restart?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Everyday computer health'; Type = 'DiskSpace'; Question = 'Does this drive have enough free space?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Everyday computer health'; Type = 'WindowsUpdateAvailable'; Question = 'Is the number of waiting Windows updates within the allowed limit?'; Activity = 'Report only; contacts the configured update service' }
        [pscustomobject]@{ Category = 'Everyday computer health'; Type = 'DefenderSignatureHealth'; Question = 'Are Microsoft Defender threat definitions recent?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Applications and jobs'; Type = 'InstalledApplication'; Question = 'Does Windows list this application at the expected version?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Applications and jobs'; Type = 'ScheduledTaskHealth'; Question = 'Did this scheduled job run successfully and recently?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Applications and jobs'; Type = 'ProcessRunning'; Question = 'Is this program currently running?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Files, logs, and certificates'; Type = 'FileExists'; Question = 'Does this exact local file exist?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Files, logs, and certificates'; Type = 'FileContainsText'; Question = 'Is the expected text near the end of this log file?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Files, logs, and certificates'; Type = 'FileFreshness'; Question = 'Has this file been updated recently?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Files, logs, and certificates'; Type = 'WindowsEvent'; Question = 'Were enough matching Windows events recorded recently?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Files, logs, and certificates'; Type = 'CertificateExpiry'; Question = 'Will this certificate remain valid long enough?'; Activity = 'Report only' }
        [pscustomobject]@{ Category = 'Connections and access'; Type = 'TcpPort'; Question = 'Can this computer connect to this server and port?'; Activity = 'Report only; contacts the named destination' }
        [pscustomobject]@{ Category = 'Connections and access'; Type = 'DnsResolution'; Question = 'Can this computer find this server name?'; Activity = 'Report only; uses Windows name resolution' }
        [pscustomobject]@{ Category = 'Connections and access'; Type = 'HttpEndpointHealth'; Question = 'Is this website or web service responding as expected?'; Activity = 'Report only; contacts the named web address' }
        [pscustomobject]@{ Category = 'Connections and access'; Type = 'LocalGroupMembership'; Question = 'Is this approved account directly in this local group?'; Activity = 'Report only; account-name lookup can contact an identity provider' }
    )
}
