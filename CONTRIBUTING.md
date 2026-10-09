# Contributing

Thanks for helping. RubyLLM Workbench is a local-first reference application,
so the bar is clarity: code a Rails developer can read and copy, behavior
covered by tests, and documentation that matches what the code does.

## Scope

The v0.1 scope is frozen (see [ROADMAP.md](ROADMAP.md)). Bug fixes,
documentation, tests and evidence (live checks of existing features) are
always welcome. For a new feature, open an issue first so we can agree on
whether it fits a reference app.

## Local setup

Install Ruby `4.0.2` and Node.js `24.21.0`, then:

```sh
nvm install && nvm use
bin/setup --skip-server
bin/rails workbench:demo     # optional synthetic data, no provider keys needed
```

`bin/setup` prints a non-fatal notice if `libvips` is missing; install it only
if you need Active Storage image variants.

Never commit provider credentials, `config/credentials.yml.enc` or its key,
databases, uploads or machine-specific configuration.

## Before opening a pull request

Run the checks CI runs:

```sh
bin/vite build --mode=test
bin/rails db:test:prepare test
CI=1 bin/rails test:system
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
npm ci && npm audit
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
docker build --tag rubyllm-workbench:local .
```

Build test assets once (`bin/vite build --mode=test`) before parallel tests.
Ordinary tests must never call a provider; use the fakes and doubles already
in `test/`. If your change touches provider behavior, use the opt-in live
suite only with explicit authorization and your own key. `bin/dogfood`
defaults to bounded, verified-free OpenRouter routes without paid fallback;
paid routes require separate authorization. Follow
[docs/AI_USAGE_GUIDE.md](docs/AI_USAGE_GUIDE.md) and record the actual result in
[docs/CAPABILITIES.md](docs/CAPABILITIES.md). Unsupported or unavailable
routes may remain manual acceptance tasks.

## Expectations

- **Records stay honest.** Never overwrite a failed Attempt, rewrite a Run's
  input snapshot, or replay provider work that may already have been accepted.
- **Docs move with code.** Update the affected guide, diagram and changelog in
  the same commit. Test counts and live evidence belong only in
  `docs/CAPABILITIES.md`.
- **RubyLLM stays the boundary.** No direct provider SDK or HTTP calls. If you
  need a private RubyLLM API, add it to `Ai::RubyLlmInternals` with a contract
  test, and prefer an upstream fix.
- **Experimental features are labelled** in the UI and docs until they have
  live evidence.
- **Small, focused commits** with messages that say why.

In the pull request, describe behavior changes, migrations, security
implications and the checks you actually ran. Keep secrets and private data
out of issues, logs, screenshots and fixtures.

## Reporting security issues

Please do not open public issues for vulnerabilities; follow
[SECURITY.md](SECURITY.md).
