# Security policy

RubyLLM Workbench is a local-first, single-user developer workbench. It has no
account system or tenant isolation. A deployment reachable by other people
needs an authenticated and trusted network boundary; the sample Docker command
binds only to loopback.

Evaluation attachment size and count checks run in the application after the
multipart request has been parsed. The declared MIME type selects a basic format
check; when it is missing or `application/octet-stream`, the filename extension
selects the check instead. The app checks PDF headers, JPEG/PNG signatures,
JSON parsing, CSV syntax, and UTF-8 text without binary control bytes. These
checks do not fully decode PDFs or images, scan for malware, or detect
polyglot files. If the app is exposed to a network, set total request-body and
multipart-part limits at the ingress as well.

## Reporting a vulnerability

If GitHub private vulnerability reporting is enabled for this repository, use
the repository's **Security** tab to report the issue privately. If that option
is unavailable, do not publish exploit details, credentials, or private data
in a public issue. Contact a project maintainer through an existing private
channel and wait for a private reporting path before sharing sensitive details.
If no private channel is available, hold the report until the maintainers
publish one.

There is no published supported-version or response-time commitment yet. When
reporting, include the affected commit or release, relevant environment details,
reproduction steps, and the impact, while keeping secrets and user data out of
the report.
