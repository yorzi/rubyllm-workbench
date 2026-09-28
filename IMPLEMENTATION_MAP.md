# RubyLLM Workbench implementation map

## Scope

This implementation covers M0–M4 slices, three M5 slices, and first local
slices of M6 media, M7 evaluation comparisons and M8 Run reproduction export:

`Project -> Chat/Tool Lab/Knowledge/Agent definition -> persisted execution and evidence records -> inspectors`

The M4 slice currently covers local text collections, deterministic chunks,
checksums, provider embeddings in a SQLite vector adapter, explainable
lexical/semantic/hybrid retrieval, compatible-provider rerank, file upload/local
extraction and provenance artifacts, with explicit degradation. M5.1 adds
opt-in provider web search and citation artifacts to a Chat Run. M5.2 adds
Project-scoped revisioned Agent definitions and a dedicated Agent Run worker
restored from immutable Run snapshots, protected by an expiring generation-fenced
lease and local tool-contract drift check. Focused tests cover the durable
snapshot, outbox, recovery, lease, citation and timeline boundaries, plus
two-step job success, approved/denied continuation through the delivery outbox,
recovery from an expired lease with an interrupted blank response, and a late
Agent response that cannot overturn cancellation. A forked Solid Queue worker
crash/restart drill also verified that replay after `save_run_note` committed its
Artifact reused that Artifact. Stale delivery generations are rejected. M5.3
stores each successful Agent's final assistant answer as a Run-owned report
Artifact, linked to its source Message, final Attempt, frozen Agent revision and
citation Artifacts. Report creation shares the Run success transaction, and the
inspector links the report back to its citations; provider-free tests cover
success, cancellation and idempotency. M5.4 expires pending approvals, stores a
denial result to close local calls and uses RubyLLM's provider-specific approval
response for remote calls, then cancels unfinished tool invocations with Run
cancellation; a waiting approval does not leave a Chat-level
cancel request, and terminal-state reconciliation cannot restore stale approval
controls; provider-free browser review of synthetic report, citation, pending and
denied approval, cancellation, and narrow layout is complete. Live
Agent/provider presentation remains unverified. M6 adds
asynchronous speech, image, video and transcription, capability-based model catalogs,
Active Storage media/text Artifacts, media cost categories, provider lifecycle events,
disabled Chat entry actions when the catalog has no matching capability, and stale-Run
recovery that fails rather than automatically replaying provider work.
Video runs use RubyLLM's blocking poller inside the queue worker; RubyLLM 2.0.0 has
no public API to restore a VideoJob from its provider ID, and normalized video
cost/usage is unavailable. The observed video submission ID is stored as `submitted`
Run timeline evidence and redacted from reproduction exports; this does not resume
polling. Speech, image, video and transcription have fake-provider integration
evidence, including enqueue rejection and stale queued recovery; image and video
also test a late successful response after stale recovery. No live provider
acceptance is claimed. Media failure writes now share the Run lock with cancellation.
Generated speech, image and video bytes
are uploaded before the successful Run/Artifact transaction; unattached Blobs are
purged if the transaction fails or cancellation wins. Incoming transcription audio
is uploaded before the Run is created. A recurring job purges unattached Blobs
older than 24 hours, covering process death between upload and attachment.
Whitespace-only transcripts are normalized to empty text while retaining
`empty_transcript: true`. Tests cover downloadable media bytes, storage upload
failure, orphan cleanup, failures after cancellation, late provider completion
after stale recovery for image/video, and rejected enqueues and stale queued Runs
for speech/image/video/transcription.
M7 groups 2–5 model-specific `EvaluationExecution` records under one immutable
`EvaluationComparison`, which freezes one dataset revision and Experiment snapshot;
every model/case pair retains its ordinary Run/Attempt, and the page derives
per-model plus per-case summaries with links to raw Runs. The comparison entry
uses individual jobs. M7 also includes an opt-in RubyLLM Batch path for models advertising both structured output and batch;
the refresh path maps documented submission-order messages to frozen case
positions, checks queue admission before reporting refresh as queued, and leaves
state unchanged when the refresh job is rejected. Submission state transitions fence stale recovery and permit
  late local-store reconciliation. Fake-provider tests cover readiness, ordered
  Store matching and late reconciliation, positional refresh with a cancelled case,
  and per-case JSON Artifact/Attempt/token mapping. Optional bounded case tags
  stay in immutable revision/Run context, appear in evaluation views and are
  excluded from provider prompts. Optional bounded rubric criteria are frozen
  into each case result and local Run evaluation context; completed cases accept
  append-only per-criterion human ratings with descriptive per-case counts and no
  combined score. Rubric-specific checks have not run in this pass. Live provider acceptance
  remains open. An operator can close an unresolved submission
  locally after acknowledging that the provider request cannot be cancelled from
this state. M8 now saves append-only upstream candidate
report Artifacts and downloads Markdown issue drafts with a redacted Run snapshot.
Chat Runs freeze the prior RubyLLM message context, reject context drift before the
first request, serialize one active Run per Chat, and export messages bounded to
that Run. Focused regression coverage for this addition is pending.
`docs/CAPABILITIES.md` maps registry/application gates to the
surfaces and current evidence limits, including historical pre-2.0.0 dogfood.
Representative Run review remains open. Provider file
references, real OCR/page-level provenance, live provider-backed Agent behavior,
broader evaluation and operational polish remain incomplete or deferred.

Evaluation summaries separately report known provider responses/failures, schema
validity, app-observed individual Attempt latency, token coverage and reported or
estimated cost by currency. Unknown and cancelled outcomes remain visible; p95 is
shown only with at least 20 latency samples, and provider Batch wait/refresh time
is excluded. Completed evaluation outputs also accept append-only human review
records with a self-reported reviewer label, verdict and optional rationale. These
records are displayed beside the corresponding case result and leave exact-JSON
outcomes and provider metrics unchanged. Cases may freeze up to eight rubric
criteria, with one append-only human rating per criterion and per-case descriptive
counts. Ratings are not a semantic evaluator or consensus score, and no combined
quality score is calculated. The optional automated rubric judge freezes a
provider/model target plus prompt and schema versions, and stores generated
ratings in a distinct EvaluationCaseJudgment linked to its own Run/Attempt and
cost. It receives only case input, generated output and rubric; expected output,
tags and attachment names/content/IDs are excluded. Queue rejection is visibly
resumable before a Run starts; recovery re-enqueues only unstarted judgments and
marks stale started requests `submission_unknown` without replay, fencing late
responses. It does not change exact-JSON results, human reviews or generation
metrics, and is not a calibrated quality score. Focused provider-free judge and
page-disclosure checks passed: 24 runs, 259 assertions; no provider call was
made. Human rubric checks passed: 18 runs, 237 assertions. Judge dogfood and
quality/cost calibration remain open.
Project-scoped case attachments are revision-owned, bounded to 5 files per case,
10 MB per file and 50 MB per revision, and allowed only for text, JSON, CSV, PDF,
JPEG and PNG. New revisions copy retained files by case key; removing a file
affects only the new revision, and Project deletion purges old Blobs. Attachment
uploads are checked before revision creation using the declared MIME, with the
filename extension selecting a check only for missing or generic MIME, plus
basic PDF/image signatures, JSON parsing, CSV syntax and UTF-8/control-byte
checks for text. This is not full document decoding or malware scanning. Attachment and
local metadata are excluded from individual and Batch prompts; focused
provider-free coverage for the earlier attachment boundary passed: 8 runs, 87
assertions, but the new byte validator has no test evidence yet. There is no lifetime
dataset/project storage budget, so repeated new uploads can grow retained storage.
Reviewer labels are not authenticated identities.
Execution metrics do not score model quality.

Current status: M0–M3 core, the M4 local-text foundation and the M4
embedding/retrieval/rerank/document slices are `IMPLEMENTED` for their verified
local paths with OpenRouter embedding/rerank dogfood; live M3 parallel provider
compatibility, provider file references, real OCR/page-level provenance and
cross-provider embedding compatibility are `PARTIAL` or deferred. M5.1's
provider-search path passes local automated tests; provider dogfood is pending.
M5.2 now has deterministic tests for frozen definitions, durable queue delivery,
stale-run and approval recovery, lease fencing, cancellation terminal state,
Agent step citation/timeline linkage, fake-Agent success plus approved/denied
continuation, deterministic recovery of an interrupted placeholder, and terminal
cancellation after a late Agent response. M5.3 report persistence, citation
linkage, retry idempotency, cross-Chat rejection, and cancellation are covered by
provider-free tests. Local Solid Queue worker crash/restart
and note Artifact replay passed; local-tool Agents additionally require an exact
RubyLLM chat-registry model entry declaring `function_calling` during definition
validation, before enqueue, and before each worker restoration. This registry
gate is not evidence of provider acceptance. A dispatcher regression also
covers an accepted
queue enqueue whose outbox acknowledgement is lost, expired-claim redelivery,
Run lease fencing while the first execution is active, one successful report
Artifact, and the stale duplicate `AgentRunJob` exiting before Agent reconstruction
after success. A threaded provider-free cancellation race confirmed no late
response persists. Live provider calls remain unverified. The dispatcher persists
delivery intents in the primary database and scans stale leases; scheduler
operation still depends on the recurring worker. The Runtime inspector now separates web
availability from job readiness, checking the recent Scheduler Agent-dispatch task,
Dispatcher, maintenance-queue Worker, and due Agent outbox count. Test mode and
other unmonitored queue adapters are not presented as healthy. This reports local
process/readiness evidence only. M5 remains `PARTIAL`. M6 remains
`PARTIAL`: speech, image, video and transcription have fake-provider local flow
coverage; durable video-job recovery remains blocked on a public RubyLLM restore
API, with normalized video cost/usage and live provider behavior open. M7 exact-JSON
and provider-batch code paths and M8 redacted Run export/candidate workflow are
`PARTIAL`; M7's provider Batch lifecycle and M8 candidate capture both have
deterministic fake coverage. M7 case-review submission, history and deletion
behavior also have provider-free integration coverage. Live provider acceptance,
judge calibration, representative reproduction review and deployment
readiness remain open.

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
- **AgentDefinition:** Project-owned, revisioned model/instructions/tool contract;
  a Run copies its JSON-safe definition and tool contracts so later edits do not
  affect frozen inputs. A changed registered tool contract stops resumption.
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
  a citation set attached to a cited provider response, source-extraction
  provenance, or generated audio stored by Active Storage; raw chat/Run/Attempt
  history remains inspectable alongside it.
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
10. Agent workspace: edit a versioned Project definition and queue a dedicated
    Chat/Run transcript; inspect steps, tools, approvals, citations and cancel state.

## Data and service boundaries

- RubyLLM version: `2.0.0`; provider interactions go through the stable 2.0 APIs
  (`with_schema`, `with_tool_options(calls:, concurrency:)`, `approve`/`deny`/
  `complete`, `RubyLLM.embed`, `RubyLLM.rerank`, `chunk.content`).
- Rails application records: `Project`, `AgentDefinition`, `Chat`, `Run`, `Attempt`, `Artifact`,
  `LifecycleEvent`, `KnowledgeCollection`, `KnowledgeItem`, `KnowledgeChunk`,
  `KnowledgeEmbedding` and
  the minimum message association needed to preserve durable history.
- RubyLLM remains responsible for provider abstraction and conversation
  semantics where its Rails persistence helpers fit.
- `Ai::ModelCatalog` queries RubyLLM model metadata and provider configuration.
- `Ai::RunExecutor` owns Run creation and final lifecycle transitions.
- `Ai::AgentRunExecutor` creates a dedicated Chat and freezes prompt plus
  AgentDefinition snapshot into one Agent Run.
- `AgentRunJob` rebuilds the RubyLLM Agent from that snapshot and advances it
  through `ActiveJob::Continuable`; an expiring lease fences transcript, usage
  and current local tool writes, while approval resumes identify the decided
  invocation and paused generation.
- `Ai::AttemptRecorder` normalizes provider/model, timing, usage, cost and
  errors without mutating historical attempts.
- `Ai::ChatExecutor` performs chat execution through RubyLLM only.
- `Ai::SpeechCatalog`, `Ai::SpeechRunExecutor` and `SpeechRunJob` filter for
  speech-capable models, freeze the assistant reply and provider/model in a Run,
  then store returned audio as an Active Storage Artifact. `SpeechRunRecoveryJob`
  fails work stuck in `running` for 30 minutes instead of replaying a provider call.
- `Ai::MediaCatalog`, `Ai::ImageRunExecutor` and `ImageRunJob` require the
  `image_generation` capability and store one generated raster image with provider,
  model, usage/cost, byte size and digest. `Ai::TranscriptionRunExecutor` accepts a
  bounded allowlist of audio uploads, stores the source as an audio Artifact and
  queues `TranscriptionRunJob` to persist transcript text and provenance. The shared
  `MediaRunRecoveryJob` fails stale work without replay. Image, video and
  transcription queue-to-Artifact paths have fake-provider local coverage;
  configured-provider acceptance remains open.
- `Ai::EvaluationExecutor` snapshots an immutable dataset revision and structured
  Experiment for either one model or a bounded multi-model `EvaluationComparison`;
  each model gets independent per-case Structured Runs. `EvaluationCaseJob`
  compares JSON values exactly; stale recovery fails uncertain provider work and
  only unstarted cases can be resumed. Queue admission is checked: rejected
  individual cases remain queued with a visible, sanitized error and can be
  retried; a rejected provider-batch submission closes its still-queued local
  cases as failed before provider work can begin.
- `EvaluationBatchSubmissionJob`, `RubyLLM::Batch` and `EvaluationBatchRefreshJob`
  stage those same per-case chats for one configured structured/batch-capable
  provider model, save the provider batch reference and map ordered results back
  into the existing Runs. A stale submission with no recoverable reference is
  marked uncertain and is never replayed; deterministic fake-batch tests cover
  readiness, Store reconciliation, positional refresh and per-case evidence.
- `Ai::EvaluationCaseOutcome` and `Ai::EvaluationMetrics` distinguish received,
  failed, cancelled, unknown and not-attempted requests; schema validity uses
  only known structured responses. Token totals include coverage counts, costs
  preserve reported/estimated provenance and currency, and p95 latency requires
  20 individual samples. Batch duration is not treated as request latency.
- `Ai::RunReproductionExporter` builds an explicit per-Run JSON bundle from
  allowlisted fields, redacts sensitive values, URL userinfo and local paths, omits binary
  Artifact content, and enforces schema-v2 text, structure, record and byte budgets with
  explicit omission counts. Export budget regressions cover collections, depth, text/value limits, escaped-byte
  overflow, recent messages, Artifact scanning and oversized Markdown;
  exports still require human review before sharing.
- `Ai::UpstreamCandidateRecorder` stores a sanitized triage report as a new Run
  Artifact with provider/model/version evidence; `Ai::UpstreamIssueDraft` downloads
  Markdown containing that candidate and its redacted reproduction snapshot, with a
  final rendered-draft size cap and a compact fallback for oversized drafts.
  Provider-free tests cover candidate validation, evidence, sanitization, export
  exclusion and draft download. Candidate review and external submission remain
  manual.
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
  the matching resumable Chat or Agent worker.
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

The current inspector records application lifecycle events for Run, Agent step,
Attempt, ToolInvocation, Approval and Artifact transitions. The M4 Knowledge workspace is
a separate synchronous product flow and does not create a Run/Attempt for a local
collection search. This is a local event catalog, not provider-native tracing, a
complete distributed event stream, a cost dashboard or a historical backfill system.

## Integrations and constraints

- Rails 8.1.4, RubyLLM 2.0.0, SQLite, Active Storage local disk,
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
  rerank and document-source slices; M5.1 provider search is locally tested,
  M5.2 Agent durability boundaries have deterministic test coverage, M6
  speech/image/video/transcription have fake-provider local flow coverage, and
  M7's provider-batch path has deterministic fake-batch coverage; live provider
  evidence remains open for M5-M7.
- Scope: local chat with optional per-Run provider web search, structured experiment comparison, code-defined tools,
  durable approval continuation, and Project-scoped text evidence retrieval with
  provider embeddings, lexical/semantic/hybrid modes, a compatible-provider
  rerank stage, file sources with extraction provenance, and saved Agent Runs.
  Provider file references, real OCR dogfood, provider-backed Agent execution,
  durable M6 video-job recovery, M7 judge provider dogfood and calibration,
  broader M8 upstream-gap reporting, real provider acceptance and release
  readiness remain open.
- Runtime verified: Ruby 4.0.2 and Rails 8.1.4.
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
  response; provider-native tracing, historical backfill and M5
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

## Run event export — 2026-09-27

`GET /runs/:id/events` downloads sanitized lifecycle JSON via
`Ai::RunReproductionExporter#events`. It captures the highest event ID, selects
the latest 100 records by timestamp/ID, returns them chronologically, includes
related record IDs, and reports omissions. It shares the 512 KiB reproduction
budget and falls back to an identifiable compact export on byte overflow.
The response is an attachment with `Cache-Control: private, no-store`.
No provider request, historical backfill or external telemetry delivery occurs.
