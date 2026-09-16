# RubyLLM Workbench implementation map

## Scope

This implementation covers the M0, M1 and current M2 slice:

`Project -> Experiment -> structured comparison -> persisted Run/Attempt/Artifact -> inspector`

Later milestones (tools, approvals, knowledge, agents, media, batch/evals and
operational polish) stay deferred until this loop is extended deliberately.

## Product shape

- **User:** one local Ruby/Rails developer; no accounts, teams, billing or
  multi-tenancy in V0.
- **Project:** durable context boundary with a name, slug and description.
- **Chat:** a project-owned conversation whose message history can be reloaded.
- **Run:** one user-meaningful chat execution with a stable detail URL and
  explicit lifecycle state.
- **Attempt:** one provider/model call inside a Run. Retries must create a new
  Attempt rather than rewriting a failed one.
- **Experiment:** a project-owned, versioned prompt and constrained structured
  output definition that can be executed repeatedly.
- **Experiment execution:** one frozen definition snapshot grouping one Run per
  selected model; reruns create a new execution and preserve prior evidence.
- **Artifact:** a bounded JSON result attached to the successful structured Run;
  the raw chat/Run/Attempt history remains inspectable alongside it.

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
6. Global Run history: searchable/filterable local execution ledger linking each
   result back to its Project and stable Run inspector.
7. Experiment workspace: create/edit a versioned definition, choose configured
   interactive structured-output models, rerun a frozen execution, and inspect
   grouped Runs and JSON Artifacts.

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
- `Ai::SchemaDefinition` owns the bounded schema contract; `Ai::SchemaValidator`
  validates returned JSON without evaluating code or arbitrary schema keywords.
- `Ai::ExperimentExecutor` freezes definitions and creates one queued child Run
  per target; `Ai::StructuredExecutor` owns schema configuration, validation,
  Artifact persistence and failure classification.

## Integrations and constraints

- Rails 8.1.3.1, RubyLLM 2.0.0.rc3 target, SQLite, Active Storage local disk,
  Hotwire/Turbo/Stimulus, Tailwind and Vite following the loaded Rails MVP
  conventions.
- Provider credentials are read from environment/Rails credentials only; they
  are never rendered, persisted as plaintext or copied into logs.
- Provider capability differences are runtime-visible. Unsupported actions are
  disabled/explained rather than simulated.
- No direct provider SDK/HTTP calls, arbitrary shell execution, auth, billing,
  PostgreSQL, pgvector, Redis, batch endpoints or remote deployment in this
  slice. Registry models marked `:batch` are excluded from interactive M2 runs.

## UX direction

Light-first, dense but calm developer tooling: a left project rail, main work
canvas and first-class right inspector. Use tables, badges, split-pane layouts,
code/JSON viewers and concise status chips. Keep advanced options collapsed and
keyboard-friendly.

## Pre-flight record

- Milestone: M0 + M1 + M2 current slice.
- Scope: local chat plus structured experiment comparison; M3-M8 explicitly
  deferred.
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

## M1 gate evidence — 2026-09-16

- OpenRouter is configured through the existing environment/credentials
  boundary; no provider secret is stored in an application record.
- The real `openrouter/free` route completed Run #6 through the application
  executor: the Run and Attempt succeeded, the response was persisted, usage
  was normalized, and the zero-cost result was labelled as estimated rather
  than reported.
- The default sandbox could not resolve `openrouter.ai`; that diagnostic Run
  remains a local environment failure, not a provider failure. The live check
  was then repeated once with network access explicitly allowed.
- No RubyLLM/OpenRouter gap was found in the M1 path. The free router's first
  output took about 12 seconds, which is an observed provider/runtime signal,
  not a persistence defect.

## M2 implementation map — current slice

The first M2 slice is a complete structured-comparison workflow:

- **Experiment:** project-owned, versioned reusable prompt definition with a
  constrained JSON Schema document and runnable/archive lifecycle.
- **Execution:** one frozen Experiment execution groups one child Run per
  selected model. Each child keeps its own Chat, Attempt, metrics and stable
  Run URL; no failed child is rewritten into a later success.
- **Structured output:** call RubyLLM's public `with_schema` API, parse and
  validate the response in an application adapter, and persist a JSON
  Artifact plus validation status.
- **Comparison UI:** create/edit-free execution from the saved definition,
  choose two or more configured structured-output models, and inspect the
  grouped results.
- **Boundary:** no arbitrary Ruby/schema class evaluation, no provider SDK or
  direct HTTP call, no universal quality score, and no M3 tools/approvals.

M2 acceptance for this slice is: a saved experiment can be run against two or
more configured models with a frozen definition; transport/provider failures
and schema-validation failures remain distinguishable; and rerunning the same
definition creates new evidence without mutating the saved definition.

## M2 gate evidence — 2026-09-16

- Execution #1 deliberately preserved a mixed outcome: Run #7 succeeded with a
  valid JSON Artifact while Run #8 recorded an OpenRouter service-unavailable
  `provider_error`. The parent execution failed without rewriting either child.
- Rerun Execution #2 kept experiment revision 1 unchanged and completed both
  targets: Run #9 `openrouter/free` and Run #10
  `liquid/lfm-2.5-2.6b:free` each succeeded with a valid JSON Artifact.
- The local browser check verified the comparison page, explicit Run again
  action, successful Run inspector, provider-failure diagnostic, and a 390px
  viewport with no horizontal overflow. The temporary narrow viewport and tab
  were closed/reset after verification.
