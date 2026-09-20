# RubyLLM Workbench

RubyLLM Workbench is a local-first Rails reference application for building and
inspecting AI workflows with RubyLLM. It brings model selection, project-scoped
chats, structured experiments, approved tools, local knowledge retrieval, and
durable execution records into one application.

This is a single-user developer workbench. It is not a hosted service and does
not provide accounts, teams, billing, or multi-tenant isolation.

Start with:

- [Current system guide](docs/SYSTEM_GUIDE.md)
- [Architecture and runtime diagrams](docs/ARCHITECTURE.md)
- [Local setup and evidence boundaries](docs/OPERATIONS.md)
- [Implementation map](IMPLEMENTATION_MAP.md)
- [Roadmap](TODO.md)
- [Documentation index](docs/README.md)
- [Contribution guide](CONTRIBUTING.md)
- [Security reporting](SECURITY.md)

The repository is self-contained. Code, migrations, existing tests, and the
current implementation documents are the source of truth for behavior. The
roadmap describes planned work; `IMPLEMENTED`, `PARTIAL`, and `PLANNED` labels
are kept distinct from verification evidence.

## Current implementation

The implemented application includes Projects, a RubyLLM model explorer,
persisted Chats and Messages, streaming execution, structured Experiments,
allowlisted tools with durable approval, Run/Attempt/ToolInvocation records,
searchable Run history, and a local lifecycle timeline. Its Project-scoped
Knowledge workspace supports text and file sources, checksummed chunks,
provider embeddings, lexical/semantic/hybrid evidence search, optional reranking,
and extraction provenance.

Provider compatibility remains partial. In particular, parallel tool-call
compatibility, OCR dogfooding, page-level provenance, and broader cross-provider
embedding coverage still need evidence. M5 now includes per-Run provider search
and citations plus saved, revisioned Agent definitions and dedicated queued
Agent Runs with approval and cancellation paths. The new Agent execution path
has an expiring database execution lease that fences transcript, usage, and
current local tool writes by owner token/generation. Approval continuations
identify the decided tool call, saved local tool contracts are checked before
resuming, and the built-in note Artifact is idempotent by tool-call id. Focused
automated tests now cover frozen snapshots, outbox dispatch and retries,
recovery scans, lease-generation fencing, cancellation terminal state, and
step/citation timeline records. Full Agent execution, worker restart recovery,
and provider dogfooding still need verification. M5 remains partial. Initial
and resumed Agent work is durably recorded in the
primary database, then dispatched to Solid Queue with retry and stale-lease
recovery. Queue insertion and delivery acknowledgement are at-least-once across
separate databases, so duplicate jobs are possible and fenced by the Run lease.
The recurring Solid Queue scheduler must run for pending deliveries and crash
recovery to drain. M6–M8 remain planned behind the M5 execution and recovery
gates. See [TODO.md](TODO.md) for current scope and evidence.

## Local setup

The app targets Ruby 4.0.2, Rails 8.1.3.1, RubyLLM 2.0.0, SQLite, Tailwind,
Vite, Hotwire, Solid Queue, and Node.js 24.21.0 for frontend assets.

```sh
nvm install
nvm use
bundle install
npm ci
bin/rails db:prepare
bin/dev
```

The `bin/setup` script checks the pinned Node.js version, installs Ruby and npm
dependencies, and prepares the database.

For a one-off local server, bind it to loopback explicitly:

```sh
bin/rails server -b 127.0.0.1 -p 3100
```

The Model Explorer and project pages can be opened without provider keys.
Running a chat requires the selected provider to be configured through the
environment or Rails credentials. Never commit or print plaintext credentials.

## Verification

```sh
bin/rails test
bin/rails zeitwerk:check
bin/rubocop --cache false
bin/rails assets:precompile
```

Paid-provider checks are opt-in. The application keeps provider configuration
visible and reports unavailable providers instead of attempting a hidden
fallback.
