# Security policy

## Supported versions

Security fixes are provided for the latest version published to the PowerShell Gallery.
Preview versions are intended for evaluation rings and receive fixes on a best-effort basis;
upgrade to the latest release before reporting a problem that may already be resolved.

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
- whether remediation, baseline parsing, report export, or privileged execution is involved.

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
service configuration, local file paths, literal log search text, event sources and IDs, and
approved network destinations.

HTML reports are self-contained: they use embedded styling, encode report values for HTML,
and do not load scripts, fonts, images, or other content from the internet. Self-contained
does **not** mean anonymous, encrypted, or safe to publish. HTML and JSON reports can hold
the same sensitive device and security information. Review the report contents before
sharing them, and do not open an untrusted report with elevated privileges.

A change receipt can include the value found before a change, the expected value, the value
seen afterward, and recovery guidance. This is useful evidence, but it can also reveal
security configuration. Protect before-and-after receipts just like assessment reports.

Treat reports, logs, baselines, and hash inventories according to the data classification of
the managed environment. Store them only in approved locations, encrypt them in transit and
at rest where required, apply an appropriate retention period, and restrict access to the
operators and services that need it. For centrally managed execution, the report and log
directories should normally be writable only by the management-agent identity, `SYSTEM`,
and authorized administrators. Verify inherited permissions with `Get-Acl`; do not assume a
new or shared directory has suitable access control.

An elevated process must not import EndpointForge or load a baseline from a directory that
an untrusted user can modify. Enterprise deployment systems should install the module and
baseline in an administrator-controlled location and protect both against unauthorized
writes. A per-user module installation is suitable for that user's read-only interactive
work, but it should not become a shared privileged execution source.

## Trust boundary

EndpointForge baselines are privileged configuration input. Review, validate, and
source-control custom baseline files before deploying them. The module does not execute
script text from a baseline, but a remediable baseline can change registry values, service
state, firewall profiles, Defender real-time protection, and Windows optional features.

The `FileExists`, `FileContainsText`, `WindowsEvent`, and `TcpPort` types are report-only
and cannot request automatic remediation. Report-only does not mean free of observable or
sensitive activity:

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
- A TCP item makes one real outbound connection attempt to the exact `HostName` and
  `Port`, then closes it without sending application data. The destination, firewall,
  endpoint security product, and network monitoring tools may record the attempt. A
  successful connection proves only basic TCP reachability, not protocol, identity,
  encryption, authentication, or application health.

Treat an untrusted checklist as capable of probing local file state, protected event logs,
and network reachability. Review all paths, event queries, hosts, and ports before running
it, even in a standard-user process. Validation limits input shape and scope; it does not
decide whether a target is appropriate for the organization.

Use signed modules and signed baseline artifacts where organizational policy requires them.
Validate the staged SHA-256 inventory and the package source at distribution boundaries.
Deploy read-only evaluation first, preview approved controls with `-WhatIf`, and use a
representative pilot ring before remediation.

## Fleet checks and PowerShell remoting

`Get-EFFleetSummary` is read-only. It connects with PowerShell remoting and asks an existing
EndpointForge installation on each target to collect a computer checkup. It does not install
EndpointForge, enable remoting, change TrustedHosts, weaken authentication, or run fixes.
Each target must already have EndpointForge 0.5.0 or later, permit PowerShell remoting, and
allow the selected account to connect.

If a fleet checklist contains `TcpPort` items, `Get-EFFleetSummary` rejects the run unless
`-AllowNetworkChecks` is supplied. That switch is an explicit acknowledgement, not a
network authorization system: operators must independently confirm that every destination
and every source computer is approved. Each target makes its own connection attempt for
each TCP item, so a fleet run can multiply observable attempts across the target list.

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
