# EndpointForge 1.x compatibility

This document defines how EndpointForge compatibility is claimed for a stable 1.x
release. It deliberately separates behavior that exists in the source from behavior that
has been exercised on a representative Windows computer.

## What the compatibility labels mean

| Label | Meaning |
|---|---|
| Implemented | The source contains the capability and automated tests cover its contract. This is not proof that every Windows edition or management-agent version behaves the same way. |
| CI verified | The quality gate, Pester suite, and safe runtime smoke passed in the named PowerShell host on a GitHub-hosted Windows Server runner. This is build evidence, not Windows client or managed-agent certification. |
| Runtime-smoke verified | `build\Test-WindowsRuntime.ps1` passed on a recorded Windows build and PowerShell version. This exercises real local providers, but it is still one computer and one configuration. |
| Target-certified | The release candidate passed the applicable acceptance cases on the exact operating-system, architecture, execution context, and management state named in the release evidence. |
| Not certified | The project does not make a production-support claim for that combination. A graceful `NotApplicable`, `CouldNotCheck`, or blocked result is acceptable; a false passing result is not. |

A platform belongs in the 1.0 support statement only after its target-certification row is
complete. Documentation, Gallery tags, and release notes must not turn an intended target
into a tested claim.

## Current implementation boundary

The module manifest requires Windows PowerShell 5.1 and declares compatibility with the
Desktop and Core PowerShell editions. The source is Windows-only: endpoint commands stop
when the host is not Windows.

The repository currently provides:

- CI matrices for Windows PowerShell 5.1 and the PowerShell 7 version installed on pinned
  `windows-2022` and `windows-2025` runner labels; each run records the resolved image and
  PowerShell version;
- source parsing, manifest validation, PSScriptAnalyzer, and Pester checks;
- a local Windows runtime smoke script for inventory, health, the built-in checklist,
  a remediation `-WhatIf` guard, WMI namespace and IP-range checks, and management-agent
  health and action previews;
- `build\Invoke-ManagedEndpointCertification.ps1` and a manually dispatched self-hosted
  lab workflow for the `Unmanaged`, `Intune`, `ConfigurationManager`, and `CoManaged`
  rings; the workflow creates sanitized evidence but does not count as certification
  until it runs on the exact recorded lab target;
- staged-package import and SHA-256 inventory verification.

These are valuable release controls, but they do not by themselves certify a named
Windows version, an Intune tenant, a Configuration Manager site, or a co-managed device.

## 1.0 target-certification matrix

Record exact versions, dates, evidence links, and the tester in the release record. A
blank or failed required row blocks the 1.0 release.

| Target | Required contexts and cases | 1.0 status |
|---|---|---|
| Primary Windows client, x64 | Windows PowerShell 5.1 and the declared PowerShell 7 version; standard user, Administrator, and `SYSTEM`; read-only summary, all applicable built-in items, report export, `-WhatIf`, one approved reversible remediation, clean install, update, and uninstall | Pending lab evidence |
| Intune-managed Windows client, x64 | Microsoft Intune Management Extension absent, healthy, stopped, disabled, and unreadable where reproducible; local health check; action preview; approved start/restart; management traffic observed through normal administration tools | Pending lab evidence |
| Configuration Manager-managed Windows client, x64 | Client absent, healthy, stopped, disabled, damaged interface, access denied, and timeout where reproducible; action preview; approved service action; machine-policy request and evaluation; asynchronous result verified in normal administration tools | Pending lab evidence |
| Co-managed Windows client, x64 | Both local agents present; independent health results; one approved action for each product; no cross-product assumptions | Pending lab evidence |
| Every additional Windows client release claimed | The primary-client cases on the exact edition and supported build | Not certified until recorded |
| Every Windows Server release claimed | Local and remote read-only cases, role-relevant provider availability, report export, and explicitly approved remediation cases | Not certified until recorded |
| Windows on Arm | Full runtime suite plus application-inventory behavior with `Architecture: All` | Not certified |
| 32-bit PowerShell on 64-bit Windows | Read-only suite and documented provider limitations | Not a preferred production host; not certified unless recorded |

If a row remains pending at release time, remove that platform from the 1.0 support claim
instead of weakening the gate.

## PowerShell hosts

| Host | Compatibility position |
|---|---|
| Windows PowerShell 5.1, 64-bit | Required 1.0 host. Pin the exact Windows build used for release evidence. |
| PowerShell 7, 64-bit | Required 1.0 host. The release record must name the exact tested PowerShell 7 version; `pwsh` or `windows-latest` alone is not sufficient. |
| 32-bit Windows PowerShell or PowerShell 7 | Limited. Registry and provider views can differ. `LocalGroupMembership` is unavailable from a 32-bit process on 64-bit Windows because the LocalAccounts provider is unavailable there. |
| Non-Windows PowerShell | Unsupported. Endpoint assessment commands are expected to block rather than return a Windows health result. |

Use 64-bit PowerShell on 64-bit Windows. The application checklist can explicitly inspect
the x86 and x64 uninstall views from a 64-bit process. On Windows on Arm, the implemented
application rule requires `Architecture: All`; that rule is not a claim that the complete
module is certified on Arm.

## Permission and identity behavior

| Execution context | Supported use |
|---|---|
| Standard user | Guided menu, readiness, ordinary read-only checks, report viewing, comparison, validation, and `-WhatIf`. Windows can withhold protected evidence, which must be reported as incomplete rather than healthy. |
| Administrator | Protected reads and explicitly approved local remediation. Administrator permission does not override Group Policy, mobile-device management, Defender tamper protection, or another security product. |
| `SYSTEM` | Intended for centrally managed deployment after the exact package and baseline are protected and pilot-tested. `CurrentUser` then means `SYSTEM`, not the person at the keyboard. |
| PowerShell remoting | `Get-EFFleetSummary` only. Targets must already allow the organization's approved remoting method, have a compatible EndpointForge version installed, and permit the connecting identity. |

EndpointForge does not elevate itself, enable remoting, change TrustedHosts, install itself
remotely, retain a credential in its returned fleet object, or run fleet remediation.

## Windows feature dependencies

Windows edition, hardware, security-product ownership, policy, and permissions determine
whether some checks are applicable. The stable behavior is an honest unavailable or
not-applicable result, not a manufactured answer.

| Capability | Important dependency |
|---|---|
| Defender settings and definition age | Microsoft Defender cmdlets and trustworthy Defender ownership/status |
| BitLocker | BitLocker cmdlets and an applicable volume |
| Secure Boot | Supported UEFI firmware and access to the Windows Secure Boot provider |
| TPM | TPM cmdlets and applicable hardware |
| Windows optional features | DISM optional-feature cmdlets and an applicable feature name |
| Windows Update availability | Windows Update interfaces and access to the configured Windows Update or WSUS service |
| Local group membership | Microsoft.PowerShell.LocalAccounts in a compatible 64-bit process |
| Scheduled task health | ScheduledTasks module and access to the named task |
| Windows event checks | Access to the exact named log and provider; protected logs can require Administrator permission |
| WMI/CIM namespace presence | Local WMI provider and access to the exact validated namespace path |
| Management-agent health | The fixed Intune Management Extension or Configuration Manager local components; no cloud or site health is inferred |

Run `Get-EFEndpointReadiness` before assessment when provider availability matters.

## Intune and Configuration Manager boundary

`Get-EFManagementAgentHealth` reads fixed local evidence. A `LooksReady` answer means only
that the evidence collected locally passed the implemented checks. It does not certify:

- Intune enrollment or compliance;
- Configuration Manager assignment, site, or management-point health;
- a recent successful check-in;
- successful policy, application, script, or update processing.

The Intune Management Extension is installed only when assigned work needs it, so its
absence alone is not proof that a computer is not Intune-enrolled.

`Invoke-EFManagementAgentAction` supports only the fixed actions documented by the
command. An accepted policy request is asynchronous and is not evidence that downstream
work finished. Final state must be checked in the organization's normal management
console.

## Remote and network-active checks

Five checklist types can create observable outbound activity:
`TcpPort`, `DnsResolution`, `HttpEndpointHealth`, `WindowsUpdateAvailable`, and
`LocalGroupMembership` when an account name must be resolved. They are blocked until the
operator supplies `-AllowNetworkChecks`.

That switch records acknowledgement; it does not grant network authorization. In a fleet
run, every remote computer performs its own approved checks, so one command can multiply
the traffic.

`IpAddressInRange` is local-only and does not require that acknowledgement.

## 1.x support policy

- Security and compatibility fixes are issued for the latest stable 1.x release.
- A supported 1.x release continues to accept the 1.0 public command and checklist
  contracts described in `Public-Contract.md`.
- Operators should update to the latest stable 1.x before requesting a fix that may
  already be available. Older 1.x packages remain immutable in the PowerShell Gallery but
  are not separate long-term support branches.
- A deprecation is documented before removal and remains available for at least one
  subsequent minor release. Removal waits for the next major version unless retaining the
  behavior would create a material security or data-integrity risk.
- Preview and release-candidate versions are for evaluation rings and receive fixes on a
  best-effort basis.

## Evidence required with every support claim

For each certified matrix row, retain:

1. Windows edition, version, build, architecture, and servicing state.
2. PowerShell edition, version, process architecture, and execution identity.
3. EndpointForge version, commit, package hash, and signer thumbprint.
4. Intune Management Extension and Configuration Manager client versions when present.
5. Pester, runtime-smoke, staged-package, clean-install, and scenario results.
6. Sanitized failure evidence and a link to the approved test record.

The repository's managed-endpoint evidence helper can record the core environment and
agent scenarios:

```powershell
.\build\Invoke-ManagedEndpointCertification.ps1 `
    -Ring Intune `
    -ModulePath .\artifacts\EndpointForge\EndpointForge.psd1 `
    -OutputPath .\TestResults\managed-endpoint-intune.json
```

Its changing mode deliberately requires both `-AllowChangingActions` and the exact
`I_ACCEPT_MANAGED_ENDPOINT_CHANGES` acknowledgement. Use that mode only on an approved
disposable or pilot computer and after an independent change review.

Do not publish device identifiers, tenant or site identifiers, credentials, server
addresses, production reports, or other sensitive endpoint evidence with the release.
