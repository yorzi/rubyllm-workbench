# Security policy

## Deployment boundary

RubyLLM Workbench is a local-first, single-user developer workbench. It has no
account system or tenant isolation. The development servers and the sample
Docker command bind only to loopback. A deployment reachable by anyone else
needs authentication, TLS and host checks in front of it.

Things to know before exposing it:

- Provider keys are read from the environment or local Rails credentials and
  are never shown in the UI. Anyone who can reach the app can spend them.
- Provider-hosted tools (such as web search) run on the provider, and approving
  a remote tool call lets the provider execute it.
- Evaluation attachment size and count checks run after the multipart request
  is parsed. The declared MIME type (or, when missing, the filename extension)
  selects a basic format check: PDF header, JPEG/PNG signature, JSON parsing,
  CSV syntax, or UTF-8 text without binary control bytes. These checks do not
  fully decode files, scan for malware or detect polyglots. Set request-body
  and multipart-part limits at your ingress too.
- Run exports and upstream issue drafts are redacted on a best-effort basis.
  Review them before sharing.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: open the repository's
**Security** tab and choose **Report a vulnerability**. Do not open a public
issue, and do not include credentials or other people's data in the report.

Include the affected commit or release, your environment, reproduction steps
and the impact. This is a volunteer-maintained project without a formal
response-time commitment; reports are acknowledged as soon as practical, and
fixes are released on `main` with a note in the changelog.

## Supported versions

Only the latest commit on `main` (and the latest tagged release, once one
exists) receives security fixes.
