# RubyLLM Workbench implementation map

## Scope

This first implementation covers M0 and M1 only:

`Project -> Model Explorer -> Chat -> streamed response -> persisted Run/Attempt -> token/cost inspector`

Later milestones (Experiments, structured output, tools, approvals, knowledge,
agents, media, batch/evals and operational polish) stay deferred until this
loop is usable and has been dogfooded.

## Product shape

- **User:** one local Ruby/Rails developer; no accounts, teams, billing or
  multi-tenancy in V0.
- **Project:** durable context boundary with a name, slug and description.
- **Chat:** a project-owned conversation whose message history can be reloaded.
- **Run:** one user-meaningful chat execution with a stable detail URL and
  explicit lifecycle state.
- **Attempt:** one provider/model call inside a Run. Retries must create a new
  Attempt rather than rewriting a failed one.
- **Artifact:** deferred for this slice unless the RubyLLM persistence contract
  requires a bounded text output record; the chat response remains durable
  through the conversation and Run records.

## Core flows and pages

1. Project index: list projects and create a project without provider keys.
2. Project workspace: project switcher/sections, recent chats/runs and a clear
   path to the model explorer.
3. Model Explorer: RubyLLM-backed model catalog with search/provider/
   capability/configuration filters, capability badges and explicit
   configured/unconfigured state.
4. Chat: choose a model, submit a prompt, see idle/submitting/streaming/
   finalizing/succeeded/failed states, and reload durable history.
5. Run inspector: stable `/runs/:id` URL showing status, provider/model,
   timing, usage, cost provenance, attempts, output and safe diagnostic data.

## Data and service boundaries

- Rails application records: `Project`, `Chat`, `Run`, `Attempt` and the
  minimum message association needed to preserve durable history.
- RubyLLM remains responsible for provider abstraction and conversation
  semantics where its Rails persistence helpers fit.
- `Ai::ModelCatalog` queries RubyLLM model metadata and provider configuration.
- `Ai::RunExecutor` owns Run creation and final lifecycle transitions.
- `Ai::AttemptRecorder` normalizes provider/model, timing, usage, cost and
  errors without mutating historical attempts.
- `Ai::ChatExecutor` performs chat execution through RubyLLM only.
- `Ai::CostNormalizer` labels reported, estimated or unknown cost.

## Integrations and constraints

- Rails 8.1.3.1, RubyLLM 2.0.0.rc3 target, SQLite, Active Storage local disk,
  Hotwire/Turbo/Stimulus, Tailwind and Vite following the loaded Rails MVP
  conventions.
- Provider credentials are read from environment/Rails credentials only; they
  are never rendered, persisted as plaintext or copied into logs.
- Provider capability differences are runtime-visible. Unsupported actions are
  disabled/explained rather than simulated.
- No direct provider SDK/HTTP calls, arbitrary shell execution, auth, billing,
  PostgreSQL, pgvector, Redis or remote deployment in this slice.

## UX direction

Light-first, dense but calm developer tooling: a left project rail, main work
canvas and first-class right inspector. Use tables, badges, split-pane layouts,
code/JSON viewers and concise status chips. Keep advanced options collapsed and
keyboard-friendly.

## Pre-flight record

- Milestone: M0 + M1.
- Scope: first complete local workflow only; M2-M8 explicitly deferred.
- Runtime verified: Ruby 4.0.2 and Rails 8.1.3.1.
- Baseline difference: RubyLLM 2.0.0.rc3 is not installed globally; RubyLLM
  1.16.0 is currently available. The Gemfile must target 2.0.0.rc3 and the
  installed API/source must be checked before implementation.
- Provider boundary: every provider operation goes through RubyLLM; no escape
  hatch is planned.
- Storage: SQLite remains sufficient; no external database/service is needed.
- Async policy: keep short interactive chat synchronous if it supports durable
  finalization; use Active Job only if the actual streaming/API behavior makes
  that necessary.
- Verification: unit/service tests, request/system coverage for project/chat/
  inspector, `zeitwerk:check`, asset build and manual desktop/narrow-screen
  acceptance.

