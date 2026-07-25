# Contributing

Contributions should preserve EndpointForge's automation contracts: Windows PowerShell 5.1 compatibility, structured output, user-friendly presentation, idempotent evaluation, no automatic restarts, no remote code download, and `SupportsShouldProcess` for state changes.

## Development

1. Create a focused branch.
2. Add comment-based help and tests for public behavior.
3. Run `build\Test-Module.ps1 -RequireScriptAnalyzer` and
   `build\Invoke-PesterTests.ps1` in Windows PowerShell 5.1 and PowerShell 7.
4. Run `build\Test-WindowsRuntime.ps1` on a representative Windows endpoint.
5. Run `build\Build-Module.ps1 -SkipTests`, followed by
   `build\Test-StagedModule.ps1`, and inspect the exact staged module.
6. Do not edit files beneath `artifacts` by hand; rebuild to regenerate the package and its
   SHA-256 inventory.
7. Update `CHANGELOG.md` for user-visible changes.
8. Read new menu and help text as if the user has never heard the terms baseline,
   compliance, remediation, DSC, or `WhatIf`; define technical names before using them.

Public commands use approved PowerShell verbs and the `EF` noun prefix. Private helpers stay in `Private`; exported commands stay in `Public`. Do not add required runtime dependencies without documenting the operational and supply-chain impact.

## Baseline controls

New report-only control types require:

- a deterministic, read-only evaluator and clear distinction between a known mismatch and
  a value that could not be checked;
- strict validation of exact targets, bounded work, and tests for invalid, inaccessible,
  changing, and unexpectedly large input;
- user-friendly `WhyItMatters`, `HowChecked`, `ManualAction`, `SafetyNotes`, and
  privacy wording in the example checklist;
- no automatic remediation, restart request, or suggestion that EndpointForge repaired
  the reported condition; and
- result objects that expose only the evidence needed for the answer. Do not return log
  lines, Windows event messages or payloads, credentials, or application data.

File readers must reject network, relative, wildcard, provider, alternate-data-stream, and
link or reparse-point paths. Keep reads bounded and detect a file that changes during the
read. Event readers must bound the time window, event ID count, and returned count. Network
checks must use exact destinations, a bounded timeout, no retries by default, and no
application payload. Their help, menu, example, validation output, and security guidance
must state that the connection attempt can be observed and recorded.

Application discovery must read explicit uninstall registry views and must not query
`Win32_Product` or trigger Windows Installer consistency checks. Keep application checks
bounded, validate compatible scope and architecture combinations, and return an unavailable
answer when requested version evidence cannot be compared reliably. Scheduled-task results
must omit actions and arguments, handle never-run sentinels explicitly, and compare ages in
UTC. Certificate readers must open stores read-only, compare validity in UTC, and omit
subjects, names, raw certificate data, and private-key details. Process checks must omit
IDs, paths, owners, command lines, modules, and process contents. Local-group checks must
resolve only the requested account, inspect direct members as raw SIDs, cap enumeration,
avoid resolving unrelated names, and never expand nested membership.

CIM namespace checks must remain structured and local-only. Accept `root` or one exact
validated child path, query the module-qualified `CimCmdlets\Get-CimInstance` command
against `__Namespace` inside a hard time limit, and return only a Boolean evidence value
without WMI objects or provider data. Do not accept a
computer name, session, credential, free-form WQL, returned provider object, method call,
command line, native arguments, scriptblock, expression, or PowerShell script text from a
checklist. A missing namespace is a known mismatch; access denial, provider failure,
ambiguous evidence, or timeout is unavailable. Keep the per-checklist item count bounded.

IP-range checks must remain structured, local-only, and report-only. Accept a bounded array
of unique canonical IPv4 or IPv6 CIDR networks and, optionally, one exact local connection
name. Reject match-all `/0`, host bits, legacy or shorthand IPv4, scoped or mapped IPv6,
wildcards, masks, start-end forms, control characters, and unrelated item properties. Read
active connection state through a bounded isolated worker; do not use DNS, sockets, gateway
probes, routes, module discovery, or a network service. Cap both interface and address
enumeration. Return only a validated Boolean/status tuple and never local addresses,
configured ranges, adapter objects, hardware addresses, gateways, DNS settings, or routes in
evaluation results. Preserve the difference between a complete non-match and unavailable,
ambiguous, over-limit, or timed-out evidence. Treat Boolean membership as a potential local
network-placement disclosure, and test IPv4/IPv6 boundaries, canonicalization, duplicate
normalization, byte order, cache keys, serialization, and privacy behavior.

Do not add a generic command-output item that executes baseline-supplied text. Checklists
can run as Administrator or `SYSTEM`, and a child process or timeout is not a sandbox. Any
future extensibility design must reference administrator-controlled, reviewed descriptors
with typed parameters; the checklist itself must remain data rather than executable code.

`TcpPort`, `DnsResolution`, `HttpEndpointHealth`, `WindowsUpdateAvailable`, and
`LocalGroupMembership` are the five network-active types. Local and fleet entry points must
block them without explicit `-AllowNetworkChecks` acknowledgement. DNS checks must accept
only absolute multi-label names and omit returned addresses. HTTP checks must retain normal
certificate validation, send no explicit origin or proxy credentials or custom headers,
avoid reading the response body or including response headers in results, and disable
redirects by default. When enabled, redirects must be capped at five and restricted to safe
same-origin addresses. Windows Update checks must use the configured update service,
enforce cancellation and a hard timeout, return only a bounded count, and never download,
install, accept licenses, change update settings, or restart Windows. Local-group checks
must explain that resolving the requested account name can contact an identity provider and
that a direct SID avoids name resolution.
`IpAddressInRange` is explicitly local-only and must not be added to the network-active list;
it must never contact another system while determining address membership.

Preserve the difference between a known mismatch and an unavailable answer. An ordinary
TCP or HTTP refusal or timeout and a normally completed unresolved-name check are known
mismatches. Provider failures, permission failures, incomplete update results, scan
warnings, ambiguous identity resolution, untrustworthy evidence, and hard worker timeouts
are unavailable answers, never passing results.

New remediating control types require:

- a read-only evaluator;
- an idempotent remediator;
- a post-change verification path;
- explicit `-WhatIf` coverage;
- a tested before-and-after receipt and recovery guidance;
- automatic rollback only when it is provably safe across local policy and management
  ownership, otherwise an explicit explanation that rollback is not automatic.

Remote or fleet features must remain read-only unless a separate, explicitly scoped design
is approved. They must not install EndpointForge, enable WinRM, change TrustedHosts, or
retain credentials as a convenience side effect. A fleet run containing network checks
must require explicit operator acknowledgement such as `-AllowNetworkChecks`, explain that
every target becomes a connection source, and test the blocked-by-default behavior.

## Management-agent support

Intune and Configuration Manager support must remain separate from checklist content and
use only module-defined, local targets. Health collection must make no management request,
read no log contents, and omit policies, application data, account names, tenant or site
identifiers, device IDs, credentials, and server addresses. It may report only the fixed
service and startup state, bounded standard-log metadata, and fixed local Configuration
Manager interface evidence needed for the answer. `LooksReady` must never claim a successful
check-in, and absence of the Intune Management Extension must never be presented as proof
that the computer is not enrolled in Intune.

New or changed agent actions require all of the following:

- an explicit agent-and-action allowlist with no caller-supplied service, method, method
  argument, schedule ID, script, command, session, credential, or remote target;
- `SupportsShouldProcess` with high confirmation impact, reliable `-WhatIf` behavior,
  Administrator permission, explicit `-AllowManagementTraffic`, and a hard timeout;
- clear warning that service changes can interrupt work and every action can contact the
  configured service or begin assigned applications, scripts, policy, updates, or other
  work;
- a typed receipt that separates request acceptance, immediate local verification,
  possible change, and unavailable or uncertain final state; and
- tests proving that preview, missing traffic acknowledgement, insufficient permission,
  incompatible action combinations, malformed worker output, and timeout cannot silently
  report a completed synchronization.

Configuration Manager policy calls must use only the reviewed local `SMS_Client` methods
with module-owned fixed arguments. Request acceptance is asynchronous and must not be
reported as proof that policy download, evaluation, check-in, or assigned work completed.
Do not add generic WMI/CIM invocation, schedule triggers, reset, cache deletion, agent
repair or reinstall, site reassignment, management-data removal, re-enrollment, or remote
and fleet repair. Product recovery operations need a separate design, explicit threat
model, and approved recovery semantics.

## Release checklist

- Confirm the manifest version, author, description, license, repository metadata, release
  notes, and `CHANGELOG.md` describe the intended release and contain no placeholders.
- Confirm GitHub private vulnerability reporting is enabled and that `SECURITY.md` reflects
  the available private channels using only contact information approved for publication.
- Require successful Windows PowerShell 5.1 and PowerShell 7 CI jobs, including
  PSScriptAnalyzer and Pester.
- Build from the reviewed source and require `Test-StagedModule.ps1` to report
  `HashesVerified = True`; review the packaged `README.md`, `SECURITY.md`, and
  `CONTRIBUTING.md`, the JSON schema, and every shipped checklist example.
- Require `Test-PublishReadiness.ps1` to report `IsReady = True`. Stable 1.x releases must
  run `Protect-StagedModule.ps1` with the approved certificate and timestamp service, then
  run readiness with both `-RequireSignature` and the expected signer thumbprint.
- Protect the `powershell-gallery` GitHub environment, restrict who can approve a release,
  and store `PSGALLERY_API_KEY` only as an environment secret. Never include the key in a
  command transcript, issue, log, commit, or artifact.
- Create a tag exactly matching `v<manifest version>` only after the commit is final and
  required checks pass. Dispatch the protected release workflow; it creates a draft,
  publishes and verifies the Gallery package, then makes the GitHub release public.
- After publication, install the exact version from PSGallery in a clean session and run a
  read-only smoke assessment. Gallery package versions are immutable; fixes require a new
  version.
