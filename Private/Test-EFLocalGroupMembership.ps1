function Test-EFLocalGroupMembership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$GroupName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MemberName,

        [ValidateRange(10, 60)]
        [int]$TimeoutSeconds = 15
    )

    $checkScript = {
        param($InputData)

        if ($null -eq (Get-Command -Name Get-LocalGroup -ErrorAction SilentlyContinue)) {
            return [pscustomobject]@{
                ProviderAvailable = $false
                GroupFound        = $null
                IsMember          = $null
            }
        }

        $groupName = [string]$InputData.GroupName
        $memberName = [string]$InputData.MemberName
        $groupUsesSid = $groupName -match '^S-1-(?:\d+-)+\d+$'
        $groupParameters = if ($groupUsesSid) {
            @{ SID = [Security.Principal.SecurityIdentifier]::new($groupName); ErrorAction = 'Stop' }
        }
        else {
            @{ Name = $groupName; ErrorAction = 'Stop' }
        }
        try {
            $group = Get-LocalGroup @groupParameters
        }
        catch {
            if ($_.FullyQualifiedErrorId -match '^GroupNotFound(?:,|$)' -or
                $_.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.GroupNotFoundException') {
                return [pscustomobject]@{
                    ProviderAvailable = $true
                    GroupFound        = $false
                    IsMember          = $false
                }
            }
            throw
        }
        $memberSid = if ($memberName -match '^S-1-(?:\d+-)+\d+$') {
            [Security.Principal.SecurityIdentifier]::new($memberName)
        }
        else {
            $computerName = [string]$InputData.ComputerName
            $accountName = if ($memberName -match '^\.\\(.+)$') {
                if ([string]::IsNullOrWhiteSpace($computerName)) { $Matches[1] } else { "$computerName\$($Matches[1])" }
            }
            elseif ($memberName -notmatch '[\\@]' -and -not [string]::IsNullOrWhiteSpace($computerName)) {
                "$computerName\$memberName"
            }
            else { $memberName }
            ([Security.Principal.NTAccount]::new($accountName)).Translate(
                [Security.Principal.SecurityIdentifier]
            )
        }

        $nativeSource = @'
using System;
using System.Runtime.InteropServices;
public static class EndpointForgeLocalGroupNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct LOCALGROUP_MEMBERS_INFO_0 { public IntPtr Sid; }

    [DllImport("Netapi32.dll", CharSet = CharSet.Unicode)]
    public static extern int NetLocalGroupGetMembers(
        string serverName,
        string localGroupName,
        int level,
        out IntPtr buffer,
        int preferredMaximumLength,
        out int entriesRead,
        out int totalEntries,
        ref IntPtr resumeHandle);

    [DllImport("Netapi32.dll")]
    public static extern int NetApiBufferFree(IntPtr buffer);
}
'@
        $null = Add-Type -TypeDefinition $nativeSource -Language CSharp -ErrorAction Stop
        $resumeHandle = [IntPtr]::Zero
        $isMember = $false
        $membersRead = 0
        $maximumMembers = 4096
        $preferredMaximumLength = 65536
        do {
            $buffer = [IntPtr]::Zero
            $entriesRead = 0
            $totalEntries = 0
            $previousResumeHandle = $resumeHandle
            try {
                $status = [EndpointForgeLocalGroupNative]::NetLocalGroupGetMembers(
                    $null,
                    [string]$group.Name,
                    0,
                    [ref]$buffer,
                    $preferredMaximumLength,
                    [ref]$entriesRead,
                    [ref]$totalEntries,
                    [ref]$resumeHandle
                )
                if ($status -notin @(0, 234)) {
                    throw "Windows returned local-group status $status."
                }
                if ($totalEntries -gt $maximumMembers -or $membersRead + $entriesRead -gt $maximumMembers) {
                    throw "The requested local group exceeds the $maximumMembers-member safety limit."
                }
                if ($status -eq 234 -and
                    ($entriesRead -le 0 -or $resumeHandle -eq $previousResumeHandle)) {
                    throw 'Windows did not make progress while reading the requested local group.'
                }
                if ($entriesRead -gt 0 -and $buffer -eq [IntPtr]::Zero) {
                    throw 'Windows returned an incomplete local-group result.'
                }
                $entrySize = [Runtime.InteropServices.Marshal]::SizeOf(
                    [type][EndpointForgeLocalGroupNative+LOCALGROUP_MEMBERS_INFO_0]
                )
                for ($index = 0; $index -lt $entriesRead; $index++) {
                    $entryAddress = [IntPtr]::Add($buffer, $index * $entrySize)
                    $memberInfo = [Runtime.InteropServices.Marshal]::PtrToStructure(
                        $entryAddress,
                        [type][EndpointForgeLocalGroupNative+LOCALGROUP_MEMBERS_INFO_0]
                    )
                    $returnedSid = [Security.Principal.SecurityIdentifier]::new($memberInfo.Sid)
                    if ([string]::Equals($returnedSid.Value, $memberSid.Value, [StringComparison]::OrdinalIgnoreCase)) {
                        $isMember = $true
                        break
                    }
                }
                $membersRead += $entriesRead
            }
            finally {
                if ($buffer -ne [IntPtr]::Zero) {
                    $null = [EndpointForgeLocalGroupNative]::NetApiBufferFree($buffer)
                }
            }
            if ($isMember) { break }
        } while ($status -eq 234)

        [pscustomobject]@{
            ProviderAvailable = $true
            GroupFound        = $true
            IsMember          = $isMember
        }
    }

    Invoke-EFIsolatedCheck -ScriptBlock $checkScript -InputData @{
        GroupName    = $GroupName
        MemberName   = $MemberName
        ComputerName = $env:COMPUTERNAME
    } -TimeoutMilliseconds ($TimeoutSeconds * 1000) -StartupAllowanceMilliseconds 3000 `
        -Activity 'The local-group membership check'
}
