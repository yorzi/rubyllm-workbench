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
embedding coverage still need evidence. M5 has started with per-Run, opt-in
provider web search and saved citation artifacts; saved Agent definitions,
multi-step research, restart recovery, and cancellation remain unfinished.
M6–M8 are planned; see [TODO.md](TODO.md) for current scope and evidence.

## Local setup

The app targets Ruby 4.0.2, Rails 8.1.3.1, RubyLLM 2.0.0, SQLite, Tailwind,
Vite, Hotwire, and Solid Queue.

```sh
bundle install
bin/rails db:prepare
bin/dev
```

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
