# Contributing

RubyLLM Workbench is a local-first reference app. Contributions should keep the
documented capability boundary and verification evidence aligned with the code.

## Local setup

Install Ruby `4.0.2` and Node.js `24.21.0`, then run:

```sh
nvm install
nvm use
bin/setup --skip-server
```

`bin/setup` may print a non-fatal notice if `libvips` is missing. Install it
manually only if you need Active Storage image variants; see the platform
commands in the [README](README.md#local-setup). The app can still boot without
this optional native library.

Do not commit provider credentials, generated databases, uploaded files, or
machine-specific configuration.

## Before opening a pull request

Run the relevant tests and checks for the change. CI runs the Rails tests, system tests,
Zeitwerk check, RuboCop, security scans, production asset build and Docker image build.
The matching local commands are:

```sh
bin/rails db:test:prepare test
bin/rails test:system
bin/rails zeitwerk:check
bin/rubocop --cache false
bin/bundler-audit
bin/brakeman --no-pager
npm ci
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
docker build --tag rubyllm-workbench:local .
```

Describe behavior changes, migrations, security implications, and the checks
you actually ran. Keep provider calls opt-in and identify any check that needs
provider credentials or external services.

Open an issue for a bug or a focused proposal, then submit a pull request with
the relevant tests and documentation updates. Do not include secret values or
private user data in issues, logs, screenshots, or test fixtures.
