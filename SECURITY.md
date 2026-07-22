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
network configuration, installed software, security posture, compliance failures, and
remediation evidence. JSONL logs contain computer and process context even though the
module avoids intentionally logging several high-risk fields. Baselines can disclose an
organization's security policy and desired registry or service configuration.

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

Use signed modules and signed baseline artifacts where organizational policy requires them.
Validate the staged SHA-256 inventory and the package source at distribution boundaries.
Deploy read-only evaluation first, preview approved controls with `-WhatIf`, and use a
representative pilot ring before remediation.
