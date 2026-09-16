# TODO — M0/M1/M2 current slice complete, M3 next

## Foundation

- [x] Initialize the Rails 8.1.3.1 app with SQLite, Tailwind, Vite, Hotwire,
      and the local Solid Queue baseline.
- [x] Lock Ruby 4.0.2 and RubyLLM 2.0.0.rc3 in the project.
- [x] Add the project shell, navigation, responsive states, and empty states.
- [x] Add SQLite migrations/models for Project, Chat, Run, and Attempt with
      indexes and validated status transitions.
- [x] Add provider configuration status without exposing credentials.

## M1 workflow

- [x] Implement the RubyLLM-backed model catalog and
      capability/configuration filtering.
- [x] Implement durable project chats and model selection.
- [x] Implement streaming states and durable completion/failure persistence;
      paid-provider smoke testing remains opt-in.
- [x] Make Run/Attempt creation atomic and exercise the ChatExecutor streaming
      success/failure lifecycle with deterministic provider doubles.
- [x] Implement the Run/Attempt inspector with usage, cost provenance,
      latency, partial output, and safe error details.
- [x] Add a global Run history with status/provider/search filters and stable
      inspector links.
- [x] Add deterministic fake-provider tests and keep paid-provider tests
      opt-in.
- [x] Verify Rails boot, migrations, Zeitwerk, tests, assets, and key screens
      at desktop and narrow widths.
- [x] Record the current boundary: provider-specific behavior still needs
      real-key dogfooding before the next milestone.
- [x] Dogfood the complete M1 path with an explicitly configured provider and
      record any RubyLLM/provider gaps before starting M2.

## M1 gate record — 2026-09-16

- [x] OpenRouter configuration was verified without printing the credential.
- [x] Real `openrouter/free` execution completed Run #6 with persisted
      streamed output, Attempt metrics, and estimated zero cost.
- [x] No RubyLLM/OpenRouter gap was found; the default sandbox DNS failure and
      the free route's roughly 12-second TTFO are recorded in the
      implementation map.

## M2 — Experiments + Structured Output + Compare

- [x] Add versioned Project-owned Experiment definitions with a constrained
      JSON Schema input.
- [x] Add grouped Experiment executions with one independent Run/Attempt per
      selected model.
- [x] Add RubyLLM structured output execution, JSON validation, and durable
      JSON Artifacts.
- [x] Distinguish schema-validation failures from transport/provider failures.
- [x] Add comparison UI, rerun behavior, and request/service coverage.
- [x] Dogfood structured output and a two-model comparison through OpenRouter
      before starting M3.

## M2 gate record — 2026-09-16

- [x] Execution #1 retained one successful Artifact and one independent
      OpenRouter `provider_error` child Run.
- [x] Execution #2 reran the unchanged revision against two free OpenRouter
      targets; both Runs succeeded with valid JSON Artifacts.
- [x] Desktop and 390px browser checks passed; no horizontal overflow was
      observed and the original browser page was restored.

## Explicitly deferred

- [ ] M3 tools, approvals, and agents.
- [ ] M4 knowledge, RAG, rerank, and document/OCR flows.
- [ ] M5-M8 research, media, batch/evals, exports, deployment, and
      public-reference polish.
