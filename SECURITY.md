# Security policy

## Supported versions

Security fixes are provided for the latest stable 1.x version published to the PowerShell
Gallery. During the 0.9 preview and contract-candidate period, fixes are provided in the next available
preview package. Older stable or preview packages are not maintained concurrently unless a
private advisory identifies a transition period that is necessary for safe migration.
Upgrade to the latest applicable release before reporting a problem that may already be
resolved. Breaking public-contract changes are reserved for a new major version; a security
fix can deprecate unsafe behavior sooner when retaining it would expose users.

## Report a vulnerability privately

Use GitHub private vulnerability reporting for this repository: open the repository's
**Security** (or **Security and quality**) area and select **Report a vulnerability** on the
Advisories page. This creates a private report visible only to the reporter and authorized
repository maintainers.
GitHub documents the process in
[Privately reporting a security vulnerability](https://docs.github.com/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability).

If GitHub private vulnerability reporting is unavailable, email
[loganbamborough@gmail.com](mailto:loganbamborough@gmail.com) with the subject
`EndpointForge security report`. Reports sent to this address are handled privately, but the
address itself is intentionally published in this public policy. Do not include vulnerability
details, endpoint data, or other sensitive evidence in a public issue.

Include the following in the private report when applicable:

- affected EndpointForge version and package source;
- PowerShell version, Windows edition, and execution context;
- a minimal reproduction, security impact, and any proposed mitigation;
- whether remediation, management-agent actions, baseline parsing, report export, or
  privileged execution is involved.

Remove credentials, API keys, device names, usernames, tenant identifiers, IP addresses,
and exported inventory unless a specific value is essential to reproduce the vulnerability.
Never attach a production report without the data owner's approval. Maintainers will use
the private advisory to validate and coordinate a fix and disclosure; do not publish exploit
details before that coordination is complete.

General bugs and feature requests may use the public issue tracker after logs and examples
have been sanitized. Public issues are not an appropriate vulnerability-reporting channel.

## Sensitive output and access control

EndpointForge reports can contain host identity, hardware and operating-system details,
network configuration, installed software, security findings, checklist mismatches, and
evidence of changes. JSONL logs contain computer and process context even though the module
avoids intentionally logging several high-risk fields. Custom checklists (called baselines
in PowerShell commands) can disclose an organization's security policy, desired registry or
service configuration, application and scheduled-job names, local file paths, literal log
search text, event sources and IDs, certificate thumbprints, account or group names, and
approved update, DNS, TCP, or web destinations.

HTML reports are self-contained: they use embedded styling, encode report values for HTML,
and do not load scripts, fonts, images, or other content from the internet. Self-contained
does **not** mean anonymous, encrypted, or safe to publish. HTML and JSON reports can hold
the same sensitive device and security information. Review the report contents before
sharing them, and do not open an untrusted report with elevated privileges.

CSV exports neutralize text cells and headings that begin with spreadsheet formula
characters. `-AllowUnsafeCsvFormulaValues` disables that protection only for an explicitly
trusted non-spreadsheet consumer. Never use that switch on data that may be opened in Excel
or another spreadsheet application.

A change receipt can include the value found before a change, the expected value, the value
seen afterward, and recovery guidance. This is useful evidence, but it can also reveal
security configuration. Protect before-and-after receipts just like assessment reports.

Management-agent health results deliberately omit log contents and management identifiers,
but they can still reveal that Intune or Configuration Manager components are installed,
their local version and service state, and when a standard log was last written. Agent-action
receipts record the computer, agent, action, local before and after status, and whether a
request was accepted. Treat these objects as support data and protect exported copies.

Treat reports, logs, baselines, and hash inventories according to the data classification of
the managed environment. Store them only in approved locations, encrypt them in transit and
at rest where required, apply an appropriate retention period, and restrict access to the
operators and services that need it. For centrally managed execution, the report and log
directories should normally be writable only by the management-agent identity, `SYSTEM`,
and authorized administrators. Verify inherited permissions with `Get-Acl`; do not assume a
new or shared directory has suitable access control.

EndpointForge JSONL logging uses bounded single-line UTF-8 appends and rejects paths through
links or reparse points. The log is not cryptographically signed, chained, or otherwise
tamper-evident. Treat it as operational troubleshooting data, not an independent forensic
audit trail, and collect it into an approved protected logging system when audit integrity
is required.

An elevated process must not import EndpointForge or load a baseline from a directory that
an untrusted user can modify. Enterprise deployment systems should install the module and
baseline in an administrator-controlled location and protect both against unauthorized
writes. A per-user module installation is suitable for that user's read-only interactive
work, but it should not become a shared privileged execution source.

Custom checklist files are limited to 1 MiB and decoded as strict UTF-8. EndpointForge
hashes and parses the same locked byte buffer. `Get-EFBaseline -ExpectedSha256` records the
approved hash and integrity method on the returned object. An actual supported fix from a
custom checklist is blocked unless that verified object is passed to
`Invoke-EFEndpointRemediation`; unverified custom files remain usable for validation,
read-only checks, and `-WhatIf` previews. Hash verification does not replace source
control, protected directory permissions, code review, or change approval.

## Trust boundary

EndpointForge baselines are privileged configuration input. Review, validate, and
source-control custom baseline files before deploying them. The module does not execute
script text from a baseline, but a remediable baseline can change registry values, service
state, firewall profiles, Defender real-time protection, and Windows optional features.
Raw command lines, native executable arguments, PowerShell expressions, scriptblocks, WQL,
and remoting targets are intentionally not accepted as checklist item content. The separate
management-agent action command uses only module-defined service names and fixed
Configuration Manager methods; it does not accept those values from a checklist or caller.
A checklist can run under Administrator or `SYSTEM`; accepting executable text would turn
privileged configuration into arbitrary code.

The `BitLocker`, `SecureBoot`, `Tpm`, `FileExists`, `FileContainsText`, `WindowsEvent`,
`TcpPort`, `PendingRestart`, `DiskSpace`, `WindowsUpdateAvailable`,
`InstalledApplication`, `ScheduledTaskHealth`, `DefenderSignatureHealth`, `FileFreshness`,
`CertificateExpiry`, `DnsResolution`, `HttpEndpointHealth`, `ProcessRunning`,
`LocalGroupMembership`, `CimNamespaceExists`, and `IpAddressInRange` types are report-only
and cannot request automatic remediation.
Report-only does not mean free of observable or sensitive activity:

- File checks name one exact local path. Relative paths, network shares, mapped network
  drives, wildcards, alternate data streams, and paths through links are rejected. File
  checks can still reveal whether a sensitive file exists. `FileContainsText` reads up to
  the requested number of trailing lines, so use the smallest useful `TailLines` value.
- Text-log results contain only whether the literal text was found. Matching lines and
  other file contents are not included. The check stops if the file changes during the
  read or the selected tail exceeds the decoded-character limit; an uncertain read is not
  reported as a match.
- Event results contain a Boolean answer and a bounded count summary. Event messages and
  event data are not included. Access to protected logs, especially the Security log, can
  require an Administrator process. Event IDs must be reviewed together with their exact
  log and provider because the same number can have different meanings.
- Pending-restart checks never restart Windows. Disk-space checks never delete, move,
  compress, or clean files. Defender-signature checks never refresh definitions or change
  antivirus settings.
- Installed-application checks read explicit 32-bit, 64-bit, and current-user uninstall
  registry views. They do not query `Win32_Product`, trigger Windows Installer consistency
  checks, install, repair, update, or remove software. A checklist can contain at most 32
  application checks. Windows Arm requires the unfiltered `All` architecture view.
  Scheduled-task results omit task actions and arguments. Process results omit IDs, paths,
  owners, command lines, modules, and process contents.
- Certificate stores are opened read-only, and validity is compared in UTC. Results omit
  certificate subjects, DNS names, raw certificate data, and private-key details.
  Local-group checks resolve only the requested account name to a SID and inspect direct
  group members as raw SIDs. They inspect at most 4,096 direct members, do not expand nested
  groups, and do not resolve or return unrelated member names. Supplying a SID avoids
  account-name resolution.
- A TCP item makes one real outbound connection attempt to the exact `HostName` and
  `Port`, then closes it without sending application data. The destination, firewall,
  endpoint security product, and network monitoring tools may record the attempt. A
  successful connection proves only basic TCP reachability, not protocol, identity,
  encryption, authentication, or application health.
- A DNS item performs one time-limited Windows name-resolution operation for one absolute,
  multi-label name and omits returned addresses from results. An HTTP item sends an
  approved `HEAD` or `GET` request with normal certificate validation. It uses the
  configured proxy without proxy credentials, sends no explicit origin credentials or
  custom headers, does not include response headers in results, and does not read the
  response body. Redirects are disabled by default. If explicitly enabled, EndpointForge
  follows at most five redirects and only when every address retains the same scheme,
  host, and port and has no credentials, query, fragment, or wildcard. Name-resolution
  infrastructure, web services, proxies, endpoint security products, and network monitoring
  tools may record the activity.
- A Windows Update item can start Windows update components, refresh local scan metadata,
  and contact the computer's configured Windows Update or WSUS service. It does not
  download or install updates, accept licenses, change update settings, or restart Windows.
  By default, it counts assigned, non-hidden, uninstalled software updates and excludes
  optional updates and drivers. Results contain only a bounded waiting count, not titles,
  knowledge-base identifiers, or update metadata. Incomplete scans and scans with warnings
  are unavailable answers, not passing results.
- A local-group item can contact an organizational identity provider while resolving the
  one requested account name. It therefore requires the same explicit network
  acknowledgement as TCP, DNS, HTTP, and update checks. Use a direct SID when name
  resolution is unnecessary. On 64-bit Windows, run it from 64-bit PowerShell because the
  LocalAccounts provider is not available in a 32-bit PowerShell process there.
- A CIM namespace item uses a module-qualified local query against WMI's `__Namespace`
  system class. It accepts only `root` or an exact validated child path, never a remote
  computer, credentials, free-form query, command, or script. It performs at most 16
  segment checks inside one hard time limit. Its evidence value is Boolean, and no WMI
  objects or provider data are returned. Missing paths are **Does not match**; access
  denial, provider failure, malformed evidence, and timeout are
  unavailable answers. At most 32 namespace items are allowed per checklist.
- An IP-range item enumerates active local network connections through the .NET
  `NetworkInterface` API inside a hard time limit and performs CIDR membership math locally.
  It does not open a socket, resolve a name, contact a gateway or service, or require
  `-AllowNetworkChecks`. Inputs are limited to 1 through 32 unique canonical IPv4 or IPv6
  CIDRs plus an optional exact connection name; `/0`, host bits, legacy IPv4 forms, scoped
  or mapped IPv6, wildcards, masks, and start-end forms are rejected. Enumeration is capped
  at 128 interfaces and 256 unicast addresses, and a checklist can contain at most 16 such
  items. Generated evidence contains only Boolean state and generic prose; it does not copy
  detected local addresses or `ApprovedRanges` values and omits adapter objects, hardware
  addresses, gateways, DNS settings, and routes. The checklist, `Get-EFBaseline`, and
  author-provided titles or explanation fields still contain whatever the author wrote.
  Even Boolean range membership can reveal a network-placement fact, so protect checklist
  sources and results accordingly.

Treat an untrusted checklist as capable of probing installed applications, scheduled jobs,
local file state, certificate presence, protected event logs, local WMI namespace paths,
local network placement, account relationships, and network or update-service reachability.
Review all names, paths, event queries, accounts, thumbprints, namespaces, approved ranges,
connection names, hosts, ports, web addresses, and update-scan options before running it,
even in a standard-user process. Validation limits input shape and scope; it does not decide
whether a target or network action is appropriate for the organization.

Stable EndpointForge 1.x packages require trusted, timestamped Authenticode signatures on
every staged PowerShell file and verification of the expected publisher certificate.
Validate those signatures, the staged SHA-256 inventory, release provenance, and the
package source at distribution boundaries. A checksum without an authenticated publisher
identity is not a signature.
Deploy read-only evaluation first, preview approved controls with `-WhatIf`, and use a
representative pilot ring before remediation.

## Intune and Configuration Manager support

`Get-EFManagementAgentHealth` reads only fixed local evidence for the Microsoft Intune
Management Extension and Microsoft Configuration Manager client. It does not contact a
management service or another computer. It reads the fixed agent service and startup state,
standard main-log presence and last-write time, and the fixed local Configuration Manager
client interface when applicable. It does not read log contents, policies, application or
script data, tenant or site identifiers, device identifiers, account names, credentials, or
server addresses.

A `LooksReady` result means only that the selected local evidence looked ready. It does not
prove cloud enrollment, current compliance, management-point health, or a recent successful
check-in. The Intune Management Extension is installed only when assigned work needs it, so
its absence alone is not proof that the computer is not enrolled in Intune.

`Invoke-EFManagementAgentAction` can request only these module-defined combinations:

- start or restart the Intune Management Extension service;
- start or restart the Configuration Manager client service;
- request Configuration Manager machine policy through the fixed local `SMS_Client`
  interface; or
- evaluate already-downloaded Configuration Manager machine policy through that fixed
  local interface.

Each action can contact the computer's configured management service or begin assigned
applications, scripts, policy, updates, and other work. A service restart can interrupt work
already in progress. An applied action declares `SupportsShouldProcess` with high
confirmation impact and requires Administrator permission, explicit
`-AllowManagementTraffic`, and a bounded timeout. Run `-WhatIf` first; it makes no service
change and initiates no management traffic. The menu adds exact `NETWORK` and `APPLY`
acknowledgements before it suppresses the redundant PowerShell prompt.

A service action can verify only the immediate local service state. An accepted
`RequestMachinePolicy` or `EvaluateMachinePolicy` call means the local Configuration Manager
client accepted the request; the subsequent work is asynchronous. It is not proof that the
client contacted its service, downloaded or evaluated policy, or finished any assigned
task. Confirm final state through the organization's approved management console and
support process. A timeout after an action starts can leave the result uncertain.

The command does not accept an arbitrary command, service name, WMI/CIM method, method
argument, Configuration Manager schedule ID, computer name, session, credential, or fleet
target. It does not reset policy, clear a cache, delete management data, repair or reinstall
an agent, reassign a site, re-enroll a device, or weaken a management or security control.
Those operations require product-specific diagnosis, recovery planning, and the
organization's approved tools.

The implemented boundaries align with Microsoft's documentation for the
[Intune Management Extension](https://learn.microsoft.com/en-us/intune/device-management/tools/management-extension-windows),
Configuration Manager [`SMS_Client` class](https://learn.microsoft.com/en-us/intune/configmgr/develop/reference/core/clients/client-classes/sms_client-client-wmi-class),
[`RequestMachinePolicy`](https://learn.microsoft.com/en-us/intune/configmgr/develop/reference/core/clients/client-classes/requestmachinepolicy-method-in-class-sms_client),
[`EvaluateMachinePolicy`](https://learn.microsoft.com/en-us/intune/configmgr/develop/reference/core/clients/client-classes/evaluatemachinepolicy-method-in-class-sms_client),
and [client health checks](https://learn.microsoft.com/en-us/intune/configmgr/core/clients/manage/client-health-checks).

## Fleet checks and PowerShell remoting

`Get-EFFleetSummary` is read-only. It connects with PowerShell remoting and asks an existing
EndpointForge installation on each target to collect a computer checkup. It does not install
EndpointForge, enable remoting, change TrustedHosts, weaken authentication, or run fixes.
Each target must already have a contract-compatible EndpointForge 0.8.0 or later, permit
PowerShell remoting, and allow the selected account to connect.

`TcpPort`, `DnsResolution`, `HttpEndpointHealth`, `WindowsUpdateAvailable`, and
`LocalGroupMembership` are the five network-active types. Local and fleet commands reject
a checklist containing any of them unless `-AllowNetworkChecks` is supplied. That switch
is an explicit acknowledgement, not a network authorization system: operators must
independently confirm every destination, identity lookup, purpose, scan option, and source
computer. Each target performs its own network activity, so a fleet run can multiply
observable requests across the target list.

`IpAddressInRange` is not network-active. It reads local connection state and performs only
local address math, so adding it does not grant or imply approval for any outbound request.

That remote connection crosses several trust boundaries: the operator's computer, the
remoting service and network path, the module already installed on the target, and the place
where results are saved. Configure remoting through your organization's normal management
process. Prefer domain authentication or properly validated HTTPS endpoints as appropriate
for the environment. Do not bypass certificate checks, broadly trust unknown hosts, or grant
administrator access merely to make a fleet check succeed.

Use a dedicated account with only the permissions required to collect the intended data.
EndpointForge uses a supplied `PSCredential` for the connection and does not put that
credential in the fleet result, but PowerShell remoting and any surrounding automation still
need their own credential protection, logging, and delegation review. A failed connection is
reported for review; EndpointForge does not try to repair remote access automatically.

## Changes, recovery, and rollback

EndpointForge does not provide automatic rollback. A fix can touch Windows features,
services, firewall profiles, Defender settings, or registry values, and organization policy
may change the same setting again. A single automatic reversal would not be safe or reliable
for every control.

Before approving changes, save the checkup, inspect the `-WhatIf` preview, confirm that the
organization's backup and recovery process covers the affected setting, and test in a pilot
ring. Afterward, keep the change receipt and verify the computer again. Recovery guidance in
a receipt is explanatory; it does not execute a rollback. If a change is only partly
successful, stop and review the reported before and after values, Windows policy sources,
and the organization's documented recovery procedure before making further changes.

Management-agent actions also have no automatic rollback. Restarting a service cannot undo
management work that already began, and an accepted asynchronous policy request cannot be
recalled by EndpointForge. Do not repeatedly restart, reset, reinstall, or clear agent data
to force an immediate result. Review the receipt and use the product owner's approved
diagnostic and recovery process.
