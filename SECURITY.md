# Security policy

RubyLLM Workbench is a local-first, single-user developer workbench. It has no
account system or tenant isolation. A deployment reachable by other people
needs an authenticated and trusted network boundary; the sample Docker command
binds only to loopback.

## Reporting a vulnerability

If GitHub private vulnerability reporting is enabled for this repository, use
the repository's **Security** tab to report the issue privately. If that option
is unavailable, open a minimal issue asking the maintainers for a private
reporting channel. Do not include exploit details, credentials, or private data
in a public issue.

There is no published supported-version or response-time commitment yet. When
reporting, include the affected commit or release, relevant environment details,
reproduction steps, and the impact, while keeping secrets and user data out of
the report.
