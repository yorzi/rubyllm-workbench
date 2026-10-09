# Releasing the reference app

Updated: 2026-10-09

The repository is public and has an MIT license and contribution/security
guides. Private vulnerability reporting is enabled and its report link is
visible on the public security page. This checklist prepares a reviewed
release; source publication and public demo deployment are separate steps.

## Prepare a candidate

1. Freeze the commit, lockfiles, Ruby and Node versions. Run the
   [operations checks](OPERATIONS.md#verification), record results in
   [CAPABILITIES.md](CAPABILITIES.md#verification-snapshot), and require hosted
   CI on the candidate commit, including Docker.
2. Install without environment files, credentials, databases, uploads, npm
   dependencies or a developer's asset manifest. Generate the synthetic tour
   and complete [SHOWCASE.md](SHOWCASE.md). Verify Linux with and without
   optional libvips and the runtime container.
3. Run intentional live acceptance on the pinned RubyLLM with the chosen
   provider and budget. Keep versions, dates and models; older 2.0 evidence
   does not certify 2.1.
4. Review the tracked tree and git history for secrets/private data. Current
   ignores do not erase history. Earlier commits contain encrypted Rails
   credentials; verify their keys were never committed and decide whether
   public history should retain them. Revoke any exposed credential before
   publication. Review exports/screenshots manually; use only synthetic demo
   content.
5. Plan a usable private security-report channel. GitHub private vulnerability
   reporting is available for public repositories; enable it immediately
   after changing visibility, then test it from an outside account before
   announcing the release. If unavailable, add a verified private contact to
   SECURITY.md before publication.

Normal pull-request CI must use fakes and no provider secrets. The container
excludes environment files, keys, encrypted credentials, local data and uploads.

For raw-history secret scanning, disable local Git text conversions and
external diff drivers so the scan reads committed blobs rather than decrypted
credential output:

```sh
gitleaks git --redact --log-opts='--all --no-textconv --no-ext-diff'
```

A clean scan is evidence of no detected patterns, not proof that every secret
is absent. Encrypted credentials in old commits are still part of history.
[Rails permits encrypted credentials in version control when the master key
is kept safe](https://guides.rubyonrails.org/security.html#custom-credentials).
Their presence alone does not establish a leak or require a history rewrite.
Keep the key private; if a key was exposed, rotate the affected secrets before
publication. Use Git's tracked-source archive for distribution rather than
zipping a working directory with ignored logs, caches and local data.

## Upgrade an existing installation

Stop web, workers and schedulers. Back up all SQLite databases consistently
and back up uploaded files; copying an active `.sqlite3` file can omit its WAL.
Keep the old application version with that backup. Run `bin/rails db:migrate`
with the new lockfile, check pending migrations, and open an old Chat and Run
before restarting workers.

The 2.1 migration adds framework usage-owner/server-tool fields, provider-file
and MCP tables, and message cache lifetime. Workbench also adds
`attempts.recorded_cost`. It does not connect an MCP server or create encryption
credentials. The generated framework migration is not a tested downgrade
procedure: restore a verified backup and previous lockfile if necessary.
New 2.1 usage-operation rows must not be loaded by an old schema.

## Publish with owner authorization

1. Publish the reviewed commit and verify remote checks.
2. Make the repository public, set description/topics, and check README links
   from a logged-out browser. Immediately enable private vulnerability
   reporting and verify its form from an outside account; update SECURITY.md
   with the verified channel before announcing the release.
3. Tag `v0.1.0`; release notes should link to the showcase route, capability
   evidence, upgrade procedure and experimental scope.
4. Verify the licence renders and an outside contributor can file an issue,
   reproduce the tour and run documented checks.

[CAPABILITIES.md](CAPABILITIES.md#verification-snapshot) records accepted
release checks, and [ROADMAP.md](../ROADMAP.md) defines public demo acceptance.
The implemented [read-only mode](DEMO.md) has a separate synthetic snapshot;
hosting/TLS/host checks and external verification remain public-demo tasks.

Build the release source from the accepted tag, without ignored workspace files:

```sh
git archive --format=tar --prefix=rubyllm-workbench-0.1.0/ v0.1.0 | gzip -n > rubyllm-workbench-0.1.0.tar.gz
shasum -a 256 rubyllm-workbench-0.1.0.tar.gz > SHA256SUMS
shasum -a 256 -c SHA256SUMS
```

Review archive paths and scan the extracted tracked source before uploading
the archive and `SHA256SUMS`. Downloads can verify the same checksum locally.

## Release notes

The complete [v0.1.0 release notes](releases/v0.1.0.md) cover installation,
accepted scope, manual follow-ups and the upgrade boundary.

RubyLLM Workbench v0.1.0 is a single-user Rails reference app for inspectable
AI workflows on Rails 8.1.4 and RubyLLM 2.1.0. Explore a synthetic tour without
keys, then read the source behind persisted streaming, approvals, durable
Agent delivery, retrieval evidence and revisioned evaluations. The Run
inspector preserves request history, finish reasons and cost provenance and
provides bounded redacted exports. Media and rubric judging remain
experimental. The full workbench needs trusted local access or authentication;
verified provider scope is listed with its date/version in the capability
matrix.
