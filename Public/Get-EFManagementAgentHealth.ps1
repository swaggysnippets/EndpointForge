function Get-EFManagementAgentHealth {
    <#
    .SYNOPSIS
    Checks the local Intune and Configuration Manager agent health without contacting management services.

    .DESCRIPTION
    Reads fixed, local evidence for the Microsoft Intune Management Extension and the
    Microsoft Configuration Manager client. It checks the agent service, its startup
    setting, a standard local log timestamp, and the local Configuration Manager interface.

    This command does not contact Intune, a Configuration Manager management point, or any
    other computer. It does not read log contents, tenant or site details, management-service
    device IDs, policies, applications, account names, or server addresses. Local evidence
    cannot prove cloud registration, compliance, or a successful check-in.

    The result includes the Windows computer name plus local operational metadata such as
    agent service state, version, standard log path, and last-write time. Consequently,
    SensitiveDataIncluded is true. Protect exported health results according to your
    organization's handling requirements.

    The Intune Management Extension is installed only when an applicable Intune workload
    needs it. Not finding the extension does not by itself prove that the computer is not
    enrolled in Intune.

    .PARAMETER Agent
    Chooses Intune, ConfigurationManager, or All. CCM, SCCM, and ConfigMgr are accepted as
    familiar names for ConfigurationManager.

    .PARAMETER TimeoutSeconds
    Maximum time allowed for the local Configuration Manager interface check. This does not
    allow a network request.

    .EXAMPLE
    Get-EFManagementAgentHealth

    .EXAMPLE
    Get-EFManagementAgentHealth -Agent ConfigurationManager

    .OUTPUTS
    EndpointForge.ManagementAgentHealth. LocalStatus is LooksReady only when all required
    local evidence was collected and passed. NeedsAttention represents a known local issue
    or partially collected evidence. CouldNotCheck represents unavailable trustworthy
    evidence. SensitiveDataIncluded is true because the result contains computer-identifying
    and local operational metadata.

    .LINK
    Invoke-EFManagementAgentAction
    #>
    [CmdletBinding()]
    [OutputType('EndpointForge.ManagementAgentHealth')]
    param(
        [ValidateSet('All', 'Intune', 'ConfigurationManager', 'CCM', 'SCCM', 'ConfigMgr')]
        [string]$Agent = 'All',

        [ValidateRange(1, 30)]
        [int]$TimeoutSeconds = 10
    )

    $null = Test-EFWindows -Throw
    $agents = if ($Agent -eq 'All') { @('Intune', 'ConfigurationManager') } elseif ($Agent -eq 'Intune') { @('Intune') } else { @('ConfigurationManager') }
    $computerName = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { [Environment]::MachineName } else { $env:COMPUTERNAME }

    foreach ($agentName in $agents) {
        $definition = Get-EFManagementAgentDefinition -Agent $agentName
        $state = Get-EFManagementAgentState -Definition $definition -TimeoutSeconds $TimeoutSeconds
        $checks = [Collections.Generic.List[object]]::new()
        $findings = [Collections.Generic.List[string]]::new()
        $issueCount = 0

        $agentDetectionUnavailable = -not [bool]$state.Installed -and
            -not [bool]$state.ServiceQuerySucceeded -and
            -not [bool]$state.ServiceRegistryReadable

        if ($agentDetectionUnavailable) {
            $localStatus = 'CouldNotCheck'
            $dataStatus = 'Failed'
            $issueCount++
            $findings.Add('Windows did not provide trustworthy evidence showing whether the local management agent is installed.')
            $checks.Add([pscustomobject]@{
                Name        = 'Agent installed'
                Result      = 'CouldNotCheck'
                Explanation = 'Windows did not provide trustworthy service or registry evidence for this agent.'
            })
            $summary = "EndpointForge could not determine whether the $($definition.DisplayName) is installed."
            $nextStep = 'Open PowerShell with the permissions approved by your organization, or review the agent through Windows Services. Do not assume the agent is installed or absent.'
        }
        elseif (-not [bool]$state.Installed) {
            $localStatus = 'NotDetected'
            $dataStatus = 'Complete'
            $checks.Add([pscustomobject]@{
                Name        = 'Agent installed'
                Result      = 'NotDetected'
                Explanation = "The $($definition.DisplayName) was not found."
            })
            if ($agentName -eq 'Intune') {
                $summary = 'The Microsoft Intune Management Extension was not found. This alone does not prove the computer is not enrolled in Intune.'
                $nextStep = 'If your organization expects Win32 apps, PowerShell scripts, remediations, or other extension workloads, confirm assignment and device status in Intune. Otherwise, no action may be needed.'
            }
            else {
                $summary = 'The Microsoft Configuration Manager client was not found on this computer.'
                $nextStep = 'If your organization expects this computer to use Configuration Manager, confirm the approved client deployment process. Otherwise, no action may be needed.'
            }
        }
        elseif (-not [bool]$state.ServiceQuerySucceeded) {
            $localStatus = 'CouldNotCheck'
            $dataStatus = 'Failed'
            $issueCount++
            $findings.Add('Windows did not provide a trustworthy state for the local management agent service.')
            $checks.Add([pscustomobject]@{
                Name        = 'Agent service'
                Result      = 'CouldNotCheck'
                Explanation = 'Windows did not provide a trustworthy service state.'
            })
            $summary = 'EndpointForge found local agent evidence but could not read a trustworthy service state.'
            $nextStep = 'Open PowerShell with the permissions approved by your organization, or review the agent through Windows Services. Do not assume the agent is healthy or broken.'
        }
        else {
            $serviceRunning = [string]$state.ServiceStatus -eq 'Running'
            $startupEvidenceAvailable = [bool]$state.ServiceRegistryReadable -and
                -not [string]::IsNullOrWhiteSpace([string]$state.StartupType)
            $startupUnexpected = $startupEvidenceAvailable -and [string]$state.StartupType -ne 'Automatic'
            $interfaceProblem = $agentName -eq 'ConfigurationManager' -and [string]$state.LocalInterfaceStatus -eq 'Unavailable'
            $interfaceUnknown = $agentName -eq 'ConfigurationManager' -and
                [string]$state.LocalInterfaceStatus -notin @('Available', 'Unavailable')

            $checks.Add([pscustomobject]@{
                Name        = 'Agent service'
                Result      = if ($serviceRunning) { 'LooksReady' } else { 'NeedsAttention' }
                Explanation = if ($serviceRunning) { 'The local agent service is running.' } else { "The local agent service is $($state.ServiceStatus)." }
            })
            if (-not $serviceRunning) {
                $issueCount++
                $findings.Add("The local agent service is $($state.ServiceStatus), not Running.")
            }
            $checks.Add([pscustomobject]@{
                Name        = 'Service startup setting'
                Result      = if (-not $startupEvidenceAvailable) {
                    'CouldNotCheck'
                }
                elseif ($startupUnexpected) {
                    'NeedsAttention'
                }
                else {
                    'LooksReady'
                }
                Explanation = if (-not $startupEvidenceAvailable) {
                    'Windows did not provide a trustworthy startup setting for the local agent service.'
                }
                elseif ($startupUnexpected) {
                    "The local agent service startup setting is $($state.StartupType), not Automatic."
                }
                else {
                    'The local agent service startup setting is Automatic.'
                }
            })
            if (-not $startupEvidenceAvailable) {
                $issueCount++
                $findings.Add('The local agent service startup setting could not be checked.')
            }
            elseif ($startupUnexpected) {
                $issueCount++
                $findings.Add("The local agent service startup setting is $($state.StartupType), not Automatic.")
            }
            if ($agentName -eq 'ConfigurationManager') {
                $checks.Add([pscustomobject]@{
                    Name        = 'Local client interface'
                    Result      = if ($interfaceUnknown) { 'CouldNotCheck' } elseif ($interfaceProblem) { 'NeedsAttention' } else { 'LooksReady' }
                    Explanation = if ($interfaceUnknown) {
                        'EndpointForge could not finish the time-limited local Configuration Manager interface check.'
                    }
                    elseif ($interfaceProblem) {
                        'The fixed local Configuration Manager interface root\ccm was not available.'
                    }
                    else {
                        'The fixed local Configuration Manager interface root\ccm is available.'
                    }
                })
                if ($interfaceProblem) {
                    $issueCount++
                    $findings.Add('The local Configuration Manager client interface was not available.')
                }
                elseif ($interfaceUnknown) {
                    $issueCount++
                    $findings.Add('The local Configuration Manager client interface could not be checked.')
                }
            }

            if ($interfaceUnknown) {
                $localStatus = 'CouldNotCheck'
                $dataStatus = 'Partial'
                $summary = 'The Configuration Manager service state was read, but the local client interface could not be checked.'
                $nextStep = 'Review the local Configuration Manager client and WMI health before requesting policy.'
            }
            elseif (-not $serviceRunning -or -not $startupEvidenceAvailable -or $startupUnexpected -or $interfaceProblem) {
                $localStatus = 'NeedsAttention'
                $dataStatus = if ($startupEvidenceAvailable) { 'Complete' } else { 'Partial' }
                $summary = if (-not $startupEvidenceAvailable -and $serviceRunning -and -not $interfaceProblem) {
                    "The $($definition.DisplayName) is running, but EndpointForge could not verify every required local setting."
                }
                else {
                    "The $($definition.DisplayName) has a local issue that needs attention."
                }
                $nextStep = 'Preview a supported agent action, or review the local Windows service and agent logs through your approved support process.'
            }
            else {
                $localStatus = 'LooksReady'
                $dataStatus = 'Complete'
                $summary = "The $($definition.DisplayName) looks ready from local evidence. This does not prove a successful management-service check-in."
                $nextStep = 'No local service action is indicated. Confirm current device status in your organization management console when needed.'
            }
        }

        [pscustomobject][ordered]@{
            PSTypeName              = 'EndpointForge.ManagementAgentHealth'
            ComputerName            = $computerName
            Agent                   = $agentName
            DisplayName             = [string]$definition.DisplayName
            CheckedAtUtc            = [DateTime]::UtcNow
            Installed               = [bool]$state.Installed
            LocalStatus             = $localStatus
            DataStatus              = $dataStatus
            IsReady                 = $localStatus -eq 'LooksReady'
            ExitCode                = if ($localStatus -eq 'LooksReady') { 0 } elseif ($localStatus -eq 'CouldNotCheck') { 3 } else { 1 }
            Summary                 = $summary
            NextStep                = $nextStep
            ServiceName             = [string]$definition.ServiceName
            ServiceStatus           = [string]$state.ServiceStatus
            StartupType             = [string]$state.StartupType
            Version                 = $state.Version
            MainLogPath             = [string]$definition.MainLogPath
            MainLogPresent          = [bool]$state.MainLogPresent
            LastLocalActivityUtc    = $state.LastLocalActivityUtc
            LocalInterfaceAvailable = $state.LocalInterfaceAvailable
            IssueCount              = $issueCount
            Checks                  = @($checks)
            Findings                = @($findings)
            AvailableActions        = @($definition.AvailableActions)
            NetworkActivityPerformed = $false
            SensitiveDataIncluded   = $true
        }
    }
}
