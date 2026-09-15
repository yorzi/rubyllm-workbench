# RubyLLM Workbench

RubyLLM Workbench is a local-first Rails reference app for inspecting model
capabilities, running project-scoped chats, and reviewing durable AI Runs and
Attempts. It follows the source specifications linked into this workspace:

- Canonical entrypoint: [ai/00_ENTRYPOINT.md](rubyllm-workbench/ai/00_ENTRYPOINT.md)
- Implementation map: [IMPLEMENTATION_MAP.md](IMPLEMENTATION_MAP.md)
- Current work list: [TODO.md](TODO.md)

## Current slice

The implemented gate is M0/M1: Projects, Model Explorer, model selection,
persisted Chats and Messages, RubyLLM-backed streaming execution, durable
Run/Attempt records, and a token/cost/latency inspector. Agents, tools,
approvals, RAG, media, batch evaluation, billing, and deployment remain
deferred until this slice is dogfooded.

## Local setup

The app targets Ruby 4.0.2, Rails 8.1.3.1, RubyLLM 2.0.0.rc3, SQLite, Tailwind,
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

The Model Explorer and project/chat pages are usable without provider keys.
Running a chat requires the selected provider to be configured through the
environment or Rails credentials. Never commit or print plaintext credentials.

## Verification

```sh
bin/rails test
bin/rails zeitwerk:check
bin/rubocop --cache false
bin/rails assets:precompile
```

Paid-provider checks are intentionally opt-in. The application keeps provider
configuration state visible and turns an unavailable provider into a diagnostic
state instead of attempting a hidden fallback.
