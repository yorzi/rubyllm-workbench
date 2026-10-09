# RubyLLM Workbench contributor instructions

Read [docs/AI_USAGE_GUIDE.md](docs/AI_USAGE_GUIDE.md) for AI configuration and
testing policy. Read [docs/CAPABILITIES.md](docs/CAPABILITIES.md) for verified
behavior and [docs/UPSTREAM_ISSUES.md](docs/UPSTREAM_ISSUES.md) for gem findings.
Use source, lockfile and executed checks to resolve factual discrepancies.

## Development and AI tests

- Use the locked RubyLLM/Rails versions and existing Rails Minitest suite.
  Reuse `app/services/ai`, `test/` and `bin/dogfood`; avoid a second test framework.
- Run focused offline tests first. Ordinary `bin/rails test` must not call
  external AI APIs; WebMock permits loopback for local test services.
- Real calls require user authorization within a stated scope and explicit
  opt-in. Authorization persists; do not ask again for already authorized work.
  Environment flags alone are not authorization. Paid calls need separate approval.
- Prefer `bin/dogfood --include test_<scenario>` for bounded free acceptance. It sets
  `RUN_LIVE_AI=1`, `AI_TEST_PROFILE=free` and `LIVE_DOGFOOD=1` in a serial process.
  Select concrete, currently verified `:free` model IDs and explicit providers.
- Do not configure silent model/provider fallback, paid plugins or hosted tools
  in free tests. Speech has a separate catalog/short-input guard; chat routing
  controls do not establish a speech price ceiling.
- Use RubyLLM's native provider in application paths. Raw REST is a diagnostic
  comparison, never a replacement that hides an adapter failure.
- Test integration, records and protocol shapes. Do not make answer, retrieval
  or voice quality a requirement for this acceptance exercise.
- Codex/Claude Code are development agents; do not turn subscription login
  credentials into an application inference provider.

## Secrets and services

- Read keys from a securely prepared environment or installation-local Rails
  credentials. Never put secret values in command arguments, inline exports,
  fixtures, logs, screenshots, diffs or reports. Never print decrypted credentials.
- `bin/dev` loads `.env`; standalone Rails/dogfood/diagnostic commands do not.
- Bind task-owned services to `127.0.0.1` or `::1`, record their process IDs and
  stop all servers, watchers, workers and tunnels before reporting completion.
  Leave an owner-managed service alone unless authorized to stop it.

## Evidence and delivery

- Follow verify → reproduce → isolate → fix → test → report. Separate application
  defects, provider errors/quotas and potential RubyLLM/Rails regressions.
- Record gem candidates in `docs/UPSTREAM_ISSUES.md` with versions, minimal public
  API reproduction, evidence, verification gaps and contribution next steps.
  A single provider failure does not establish a gem bug.
- Keep one capability matrix in `docs/CAPABILITIES.md`; unknown costs remain
  unknown. Update affected operations, changelog and roadmap with behavior changes.
- Report checks actually executed, live model/date/request count, remaining
  manual acceptance and cost provenance. Distinguish local from hosted CI evidence.
- Stay on the current branch unless a branch is requested. Do not push, publish,
  deploy, send messages or submit upstream issues/PRs without user authorization.
