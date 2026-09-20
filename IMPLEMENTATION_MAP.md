# RubyLLM Workbench implementation map

## Scope

This implementation covers the M0–M4 slices and the first M5 provider-search slice:

`Project -> Chat/Tool Lab/Knowledge -> persisted execution and evidence records -> inspectors`

The M4 slice currently covers local text collections, deterministic chunks,
checksums, provider embeddings in a SQLite vector adapter, explainable
lexical/semantic/hybrid retrieval, compatible-provider rerank, file upload/local
extraction and provenance artifacts, with explicit degradation. M5 currently
adds opt-in provider web search and citation artifacts to a Chat Run. Provider
file references, real OCR/page-level provenance, saved Agents, multi-step
recovery, media, batch/evals and operational polish remain incomplete or
deferred.

Current status: M0–M3 core, the M4 local-text foundation and the M4
embedding/retrieval/rerank/document slices are `IMPLEMENTED` for their verified
local paths with OpenRouter embedding/rerank dogfood; live M3 parallel provider
compatibility, provider file references, real OCR/page-level provenance and
cross-provider embedding compatibility are `PARTIAL` or deferred. M5.1's
provider-search path passes local automated tests; provider dogfood is pending.
The rest of M5 is incomplete and M6–M8 remain `PLANNED`.

## Human understanding layer

The repository's public documentation is self-contained. `docs/SYSTEM_GUIDE.md`
describes current capabilities and limits; `docs/ARCHITECTURE.md` shows verified
data and runtime paths; `docs/OPERATIONS.md` covers local operation; and
`docs/CHANGELOG.md` records thematic changes and their evidence. Code, migrations,
existing tests, and recorded runtime checks remain the sources for claims about
behavior. `TODO.md` is the current roadmap.

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
- **Artifact:** a bounded JSON result attached to the successful structured Run,
  a citation set attached to a cited provider response, or source-extraction
  provenance; raw chat/Run/Attempt history remains inspectable alongside it.
- **LifecycleEvent:** a Run-scoped, metadata-only event catalog entry with a fixed
  name, optional links to an Attempt/Artifact/ToolInvocation/Approval, occurrence
  time, duration and idempotency key. It indexes transitions; it is not a content
  store or distributed trace.
- **ToolDefinition:** a Project-owned enabled/disabled reference to a
  code-defined registry entry; browser input cannot upload executable code. Each
  registry entry also declares whether concurrent execution is safe.
- **ToolInvocation:** one normalized tool call attached to a Run, preserving
  secret-filtered arguments, result/error, timing and lifecycle.
- **Approval:** one persisted human decision for an approval-required tool call;
  RubyLLM's persisted tool-call approval is the conversation source of truth.
- **Rerank stage:** an optional second stage over retrieved evidence, offered
  only for models whose registry output modality is `rerank` and whose provider is
  configured. It reorders results and records a provider score and the pre-rank
  position; it never replaces retrieval scores or chunk evidence.
- **Tool execution policy:** a Project setting requests sequential or parallel
  execution. Each new Run freezes the requested mode, model capability result,
  effective mode, and any sequential fallback reason in its input snapshot.
- **KnowledgeCollection:** a Project-owned local text corpus boundary.
- **KnowledgeItem:** one normalized, checksummed text source with ingestion status
  and optional source reference.
- **KnowledgeChunk:** one deterministic searchable slice with position, character
  offsets and chunker metadata. It is evidence, not an LLM answer.
- **File source:** a KnowledgeItem backed by an Active Storage attachment. Its
  text is produced by a background extraction (local reader for text-like files,
  provider OCR for PDFs/images) and every extraction writes an `ocr_document`
  Artifact carrying extractor, provider/model, page count and both the blob and
  content checksums.
- **KnowledgeEmbedding:** one vector per chunk per embedding model, storing
  provider, dimensions, packed Float32 vector and content checksum. Retrieval
  compares vectors only inside one model id and skips stale checksums, so
  incompatible dimensions/models are never mixed.

## Core flows and pages

1. Project index: list projects and create a project without provider keys.
2. Project workspace: project switcher/sections, recent chats/runs and a clear
   path to the model explorer.
3. Model Explorer: RubyLLM-backed model catalog with search/provider/
   capability/configuration filters, capability badges and explicit
   configured/unconfigured state.
4. Chat: choose a model, optionally enable provider web search for one Run,
   submit a prompt, inspect search activity/citations, and reload durable history.
5. Run inspector: stable `/runs/:id` URL showing status, provider/model,
   timing, usage, cost provenance, attempts, output and safe diagnostic data.
6. Global Run history: searchable/filterable local execution ledger linking each
   result back to its Project and stable Run inspector.
7. Experiment workspace: create/edit a versioned definition, choose configured
   interactive structured-output models, rerun a frozen execution, and inspect
   grouped Runs and JSON Artifacts.
8. Run lifecycle timeline: inspect the ordered local event catalog alongside the
   Run's original records.
9. Knowledge workspace: create a local collection, paste bounded text, ingest
   deterministic chunks, embed ready chunks with a configured embedding model,
   and search ready chunks in lexical/semantic/hybrid mode with score
   components, matched terms, source and offsets.

## Data and service boundaries

- RubyLLM version: `2.0.0`; provider interactions go through the stable 2.0 APIs
  (`with_schema`, `with_tool_options(calls:, concurrency:)`, `approve`/`deny`/
  `complete`, `RubyLLM.embed`, `RubyLLM.rerank`, `chunk.content`).
- Rails application records: `Project`, `Chat`, `Run`, `Attempt`, `Artifact`,
  `LifecycleEvent`, `KnowledgeCollection`, `KnowledgeItem`, `KnowledgeChunk`,
  `KnowledgeEmbedding` and
  the minimum message association needed to preserve durable history.
- RubyLLM remains responsible for provider abstraction and conversation
  semantics where its Rails persistence helpers fit.
- `Ai::ModelCatalog` queries RubyLLM model metadata and provider configuration.
- `Ai::RunExecutor` owns Run creation and final lifecycle transitions.
- `Ai::AttemptRecorder` normalizes provider/model, timing, usage, cost and
  errors without mutating historical attempts.
- `Ai::ChatExecutor` performs chat execution through RubyLLM only.
- `Ai::CitationSetRecorder` writes normalized RubyLLM citations as a Run/Attempt
  Artifact; provider tool steps remain on the persisted RubyLLM Message.
- `Ai::CostNormalizer` labels reported, estimated or unknown cost.
- `Ai::SchemaDefinition` owns the bounded schema contract; `Ai::SchemaValidator`
  validates returned JSON without evaluating code or arbitrary schema keywords.
- `Ai::ExperimentExecutor` freezes definitions and creates one queued child Run
  per target; `Ai::StructuredExecutor` owns schema configuration, validation,
  Artifact persistence and failure classification.
- `Ai::ToolRegistry` is the allowlisted code-defined tool boundary;
  `Ai::ChatTooling` applies the frozen tool snapshot and RubyLLM tool options.
- `Ai::ToolExecutionPolicy` decides whether a requested parallel mode is
  effective. It requires the model's `parallel_tool_calls` capability and all
  enabled tools to declare `parallel_safe?`; otherwise it records a safe
  sequential fallback.
- `Ai::ToolInvocationRecorder` maps RubyLLM tool calls to inspectable
  application records; `Ai::ApprovalService` records a decision and enqueues
  the resumable Chat completion.
- `Ai::LifecycleEventRecorder` subscribes to application lifecycle
  notifications, filters payloads to safe metadata, persists `LifecycleEvent`
  rows and deduplicates repeated notifications by `event_key`.
- `Ai::RubyLlmInstrumentation` subscribes to RubyLLM's `*.ruby_llm`
  notifications and maps a whitelisted subset onto `ai.provider.*` events with
  `source = ruby_llm`; because the notification payload's chat is RubyLLM's own
  object, `Ai::ExecutionContext` publishes the Run/Attempt being executed and the
  adapter correlates on that rather than on payload internals.
- `Ai::Knowledge::Chunker` normalizes text into deterministic character windows;
  `Ai::Knowledge::Ingestor` replaces a source's chunks transactionally and keeps
  checksum/status/error metadata; `Ai::Knowledge::VectorStore` provides the vector
  adapter interface with the bounded `sqlite_application_cosine` adapter;
  `Ai::Knowledge::EmbeddingCatalog` gates models on capability and provider
  configuration; `Ai::Knowledge::Embedder` stores one vector per ready chunk per
  model with per-chunk fallback and partial/failed state;
  `Ai::Knowledge::Retriever` performs bounded exact-token lexical scoring, cosine
  ranking over stored vectors and a hybrid blend, returning score, cosine,
  lexical score and matched terms as inspectable evidence;
  `Ai::Knowledge::Search` resolves the requested mode, embeds the query when
  needed and records an explicit degradation reason when semantic or hybrid
  retrieval is unavailable; `Ai::Knowledge::RerankCatalog` gates the optional
  second stage on a compatible, configured provider and `Ai::Knowledge::Reranker`
  reorders evidence while preserving the original scores and pre-rank positions.

The current M3 inspector records application lifecycle events for Run, Attempt,
ToolInvocation, Approval and Artifact transitions. The M4 Knowledge workspace is
a separate synchronous product flow and does not create a Run/Attempt for a local
collection search. This is a local event catalog, not provider-native tracing, a
complete distributed event stream, a cost dashboard or a historical backfill system.

## Integrations and constraints

- Rails 8.1.3.1, RubyLLM 2.0.0, SQLite, Active Storage local disk,
  Hotwire/Turbo/Stimulus, Tailwind and Vite following the loaded Rails MVP
  conventions.
- Provider credentials are read from environment/Rails credentials only; they
  are never rendered, persisted as plaintext or copied into logs.
- Provider capability differences are runtime-visible. Registry-declared
  capabilities gate supported actions; provider-tool support is opt-in and can
  still fail for a specific model/protocol, with the error retained on its Run.
- M4 retrieval is intentionally SQLite-bounded. Semantic mode requires a
  configured provider embedding model and stored vectors; otherwise `Search`
  degrades to lexical evidence and records the reason. The sqlite-vector adapter
  is a spike: exact cosine only, external binary not shipped with the app, and
  not yet benchmarked, so it is not the default. No fake
  embedding vectors, universal semantic score, remote URL fetch or provider file
  reference lifecycle is created by this slice. File upload, local extraction and
  provenance records are implemented; real OCR/page-level evidence remains bounded.
- No direct provider SDK/HTTP calls, arbitrary shell execution, auth, billing,
  PostgreSQL, pgvector, Redis, batch endpoints or remote deployment in this
  slice. Registry models marked `:batch` are excluded from interactive M2 runs.

## UX direction

Light-first, dense but calm developer tooling: a left project rail, main work
canvas and first-class right inspector. Use tables, badges, split-pane layouts,
code/JSON viewers and concise status chips. Keep advanced options collapsed and
keyboard-friendly.

## Pre-flight record

- Milestone: M0 + M1 + M2 + M3 plus the M4 local-text, embedding/retrieval,
  rerank and document-source slices; M5.1 provider search is locally verified,
  with provider dogfood pending.
- Scope: local chat with optional per-Run provider web search, structured experiment comparison, code-defined tools,
  durable approval continuation, and Project-scoped text evidence retrieval with
  provider embeddings, lexical/semantic/hybrid modes, a compatible-provider
  rerank stage, and file sources with extraction provenance. Provider file
  references, real OCR dogfood and the remaining M5–M8 work stay deferred.
- Runtime verified: Ruby 4.0.2 and Rails 8.1.3.1.
- Dependency target: RubyLLM 2.0.0 stable. Provider calls use the public 2.0 API;
  future upgrades should be checked against the official migration guide.
- RubyLLM instrumentation is consumed through an adapter
  (`Ai::RubyLlmInstrumentation`) rather than by reading payload internals.
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
  direct HTTP call, no universal quality score, and no M5 agents/server tools.

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

## M3 implementation map — current slice

- **Registry:** Project-scoped ToolDefinition records mirror two allowlisted
  RubyLLM tools: read-only `project_snapshot` and approval-gated
  `save_run_note`.
- **Run boundary:** new chat Runs snapshot enabled tool keys, schemas, approval
  policy and the requested/effective tool execution options; later toggles do
  not rewrite an existing Run.
- **Execution policy:** Tool Lab defaults to sequential mode. Parallel mode is
  opt-in and becomes `calls: :many, concurrency: :threads` only when RubyLLM's
  model metadata supports `parallel_tool_calls` and every enabled registry
  tool is marked parallel-safe. A missing capability or side-effecting tool is
  recorded as a sequential fallback rather than silently forcing concurrency.
- **Inspection:** RubyLLM's persisted tool calls are normalized into
  ToolInvocation records with sanitized arguments, result/error, timing and
  links to the internal Approval record.
- **Multiple calls:** each RubyLLM ToolCall receives its own ToolInvocation and
  idempotent request/completion lifecycle keys. Recorder persistence is mutex
  protected because RubyLLM's thread mode invokes tool callbacks concurrently.
- **Continuation:** an undecided approval moves the Run to
  `waiting_for_approval`; the approve/deny endpoint writes both application
  and RubyLLM decisions, then resumes the same persisted conversation with
  `complete` instead of adding a duplicate user prompt.
- **Failure boundary:** a local tool exception is represented as a tool-result
  error message plus failed invocation/Run diagnostics, leaving the chat
  history structurally answerable for the next prompt.
- **Lifecycle catalog:** `Run`, `Attempt` and `Artifact` transitions plus
  tool/approval notifications are normalized into `LifecycleEvent` rows. Event
  payloads intentionally exclude prompt, arguments, results and Artifact
  content; related records remain the source of those details.
- **OpenRouter dogfood:** Run #11 completed a real `project_snapshot` call;
  Run #13 exercised `save_run_note` from `waiting_for_approval` through
  approval, continuation, and a report Artifact. The latter retained one user
  message and two assistant messages, with no duplicate prompt from the queue
  continuation.
- **Still unverified:** no live provider has yet been accepted for a parallel
  response; provider-native tracing, event export/backfill and M5
  provider-hosted tools/agents are not part of this slice.

## Lifecycle event catalog — current slice

The application emits a fixed local catalog through `ActiveSupport::Notifications`:

- `ai.run.created`, `started`, `resumed`, `waiting_for_approval`, `succeeded`, `failed`;
- `ai.attempt.started`, `streaming`, `succeeded`, `failed`;
- `ai.tool.requested`, `completed`;
- `ai.approval.requested`, `decided`;
- `ai.artifact.created`.

`LifecycleEvent` rows are scoped to a Run and ordered by `occurred_at` plus `id`.
Repeated application notifications with the same `event_key` are ignored. Runs
created before the migration do not receive synthetic historical events.
