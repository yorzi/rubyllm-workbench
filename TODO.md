# TODO — M0–M4 verified slices; M5 local recovery covered; M6 media, M7 evaluation, M8 export slices partial

> 2026-09-27: per-Run event JSON export and M8 export-budget regressions are
> locally verified. Full suite: 333 runs / 2,892 assertions, no failures/errors,
> two live-provider skips; browser suite: 2 runs / 9 assertions. Provider-native
> tracing, historical backfill and live-provider acceptance remain open.

> 2026-09-26 update: Rails upgraded to 8.1.4; RubyLLM 2.0.0 remains the latest
> stable release verified via RubyGems. Fixed missing CSV dependency, reversed
> reproduction messages, and isolated a guard for malformed RubyLLM Batch indices.
> Full local suite: 322 runs / 2,818 assertions, zero failures/errors, two live
> provider skips. Browser suite: 2 runs / 9 assertions. Live provider acceptance
> remains pending. See [upgrade review](docs/UPGRADE_REVIEW_2026-09-26.md).

> Current correction (2026-09-21): RubyLLM is pinned to stable 2.0.0. M5.1's
> opt-in provider web-search slice has local automated coverage; provider dogfood
> remains pending. M5.2 has saved Agent definitions and a durable Agent Run
> worker with immutable snapshots, continuable steps, approval, citations and
> cancellation. Deterministic tests now cover snapshots, outbox dispatch/retry,
> recovery scans, lease fencing, terminal cancellation and citation/timeline
> records, a two-step fake-Agent `AgentRunJob` continuation through success,
> approved/denied continuations with stale delivery generation rejection, and
> late-response cancellation that preserves the terminal Run state. Real local
> Solid Queue worker interruption/restart, `save_run_note` crash-window replay,
> and provider-free in-flight cancellation now pass; live provider behavior remains open.
> M5.3 now persists the final Agent answer as a Run-owned report Artifact tied to
> the frozen Agent revision and citation Artifacts.
> M5.4 now expires pending approvals, records RubyLLM denial results so the Chat
> can continue, and cancels unfinished tool invocations when a Run is cancelled;
> this also handles cancellation while the approval is persisted but the Run has
> not yet changed to `waiting_for_approval`; terminal reconciliation cannot
> restore the invocation. M6 uploads generated media before
> committing successful Run/Artifact state and normalizes blank transcripts;
> tests cover upload failure, queue rejection, timeout recovery and late responses.
> M7 Batch tests found and fixed exact ordered-chat-set reconciliation against the
> local SQLite store.
> M5.7 freezes the queued Chat message context, rejects context drift before the
> first provider request, checks queue admission, and bounds exported messages to
> one Run. Focused provider-free regression coverage now passes (14 runs, 135
> assertions); no provider call was made.
> M7 summaries now keep provider outcomes, schema validity, app-observed
> individual latency, token coverage, and reported/estimated cost distinct;
> cancelled, unknown, and not-attempted work does not inflate response/schema rates.
> Immutable evaluation cases now support bounded optional tags, retained in old
> revision/Run snapshots and shown in dataset/comparison views; tags are excluded
> from provider prompts. Bounded optional rubric criteria, append-only human
> criterion ratings and per-case descriptive counts are implemented; focused
> rubric checks passed (18 runs, 237 assertions). Revision-owned per-case file
> attachments now have bounded upload/download/removal behavior (up to 5 files
> per case and 50 files per dataset revision), preserve old revisions and are
> excluded from provider inputs. Raw uploads are now prechecked against their
> declared formats before a new revision is written; CSV/JSON parsing, binary-text
> rejection and stream-position restoration have automated coverage since 2026-09-26. Focused attachment checks
> passed (8 runs, 87 assertions). The 50 MB bound is per revision; there is no
> lifetime dataset/project storage budget, so repeated uploads can grow retained
> storage. An optional automated rubric judge now uses a separate Run/Attempt and
> cost record; only case input, generated output and rubric are sent to that
> provider, while expected output, tags and attachments are excluded. Queue
> rejection, recovery and late-response fencing passed focused tests (24 runs,
> 259 assertions), with no live provider call. Provider dogfood and judge
> calibration remain open.
> The Runtime panel separates a responding web process from background-job readiness;
> with Solid Queue it checks recent Scheduler/Dispatcher/maintenance-Worker heartbeats,
> the recurring Agent-dispatch task and due Agent outbox deliveries.
> Open-source setup, security and local-only Docker guidance are documented;
> public redistribution still needs an owner-selected license.
> Post-flight checks on 2026-09-21: provider-free Rails suite passed (294 runs,
> 2,524 assertions, 0 failures/errors, 2 opt-in live-provider skips); system tests
> passed (2 runs, 9 assertions); full RuboCop (256 files), Zeitwerk, Bundler Audit,
> Brakeman (0 warnings), and a local production Docker/Vite build using Node 24.21.0
> passed. npm audit reported 0 vulnerabilities. Hosted CI and live provider behavior
> remain unverified.
> Latest local post-flight after the rubric judge and signed-query redaction:
> serial provider-free Rails suite passed (309 runs, 2,715 assertions, 0 failures,
> 0 errors, 2 opt-in live-provider skips); RuboCop checked 264 files without
> offenses, Zeitwerk eager loading passed, and Brakeman reported 0 warnings and
> 0 errors. Parallel Rails test startup is blocked by sandbox restrictions on
> DRb Unix sockets; the serial run completed all tests.
> After M5.7 context/export coverage, the serial provider-free Rails suite passed
> (315 runs, 2,758 assertions, 0 failures/errors, 2 opt-in provider skips); full
> RuboCop checked 265 files without offenses, Zeitwerk passed, and Brakeman 8.0.6
> reported 0 warnings/errors. The documentation contract test passed (5 runs,
> 143 assertions). No provider calls were made.
> M5 local-tool Agents now require an exact RubyLLM chat-registry entry that
> declares `function_calling` when a definition is saved, a Run is queued, and a
> worker restores the frozen Agent snapshot. Provider-hosted web search remains
> outside that local-tool gate; live provider acceptance is still unverified.

## Human understanding layer

- [x] Establish the internal `docs/` current-reality layer with a readable system guide,
      architecture diagrams, operations notes, and changelog.
- [x] Maintain the public implementation docs, architecture diagrams, operating notes,
      and roadmap as one self-contained view of the application.
- [x] Connect the Projects list/create page to the Project-boundary explanation, including
      the Rails form, slug identity, resource ownership, and source-anchored evidence.
- [ ] For every future comprehension-impacting change, update the affected internal docs,
      diagrams, status/evidence labels, and changelog in the same thematic work unit.

## Foundation

- [x] Initialize the Rails 8.1.3.1 app with SQLite, Tailwind, Vite, Hotwire,
      and the local Solid Queue baseline.
- [x] Lock Ruby 4.0.2 and RubyLLM 2.0.0 in the project.
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

## M3 gate record — 2026-09-16

- [x] Tool Lab exposes the two allowlisted Ruby-defined tools, including
      schemas, approval policy, and enable/disable state.
- [x] OpenRouter Run #11 completed a real `project_snapshot` tool call.
- [x] OpenRouter Run #13 paused for `save_run_note`, recorded the approval,
      resumed through the existing queue worker, and created a report Artifact
      without duplicating the user prompt.

- [x] Add the local `LifecycleEvent` catalog and Run inspector timeline for
      Run/Attempt/tool/approval/Artifact transitions, with metadata-only payloads
      and idempotent event keys.
- [x] Preserve the Attempt invariant across approval continuation: the resumed
      provider request receives a new Attempt while the original tool invocation
      remains attached to its original Attempt.
- [x] Add an explicit Project Tool Lab execution mode, freeze the effective
      RubyLLM `calls`/`concurrency` options into each new Run, and conservatively
      fall back to sequential execution for unsupported models or side-effecting
      tools.
- [x] Make the recorder idempotently retain separate audit rows and lifecycle
      request/completion events for multiple tool calls.

## M4 foundation — 2026-09-16

- [x] Add Project-owned Knowledge collections and inline text sources in SQLite.
- [x] Normalize and checksum source text before persistence.
- [x] Add deterministic character-window chunking with overlap, position, and
      inspectable source offsets.
- [x] Add synchronous ingestion with replaceable chunks, ready/failed status,
      and chunker metadata.
- [x] Add bounded lexical retrieval that returns score, matched terms, source,
      and chunk evidence rather than hiding an answer behind an LLM call.
- [x] Add Knowledge workspace routes, navigation, collection/source forms, and
      evidence search UI with project-boundary integration coverage.
- [x] Verify the local text path with targeted model/service/integration tests;
      provider credentials are not required.

### M4 gate status: `PARTIAL` · local text slice `LOCAL_VERIFIED`

This slice satisfies the small local document-set ingestion/search foundation
without claiming the full M4 milestone acceptance. It did not yet create embedding
records or call a provider for embeddings/reranking.

## M4 embeddings + retrieval — 2026-09-17

- [x] Add a `KnowledgeEmbedding` record per chunk and embedding model, storing
      provider, dimensions, packed vector, content checksum, status and usage
      metadata; re-embedding the same model replaces rows instead of mixing
      dimensions or models.
- [x] Define a vector adapter interface and ship the bounded
      `sqlite_application_cosine` adapter (Float32 blobs + application-side
      cosine) rather than introducing PostgreSQL/pgvector.
- [x] Add `Ai::Knowledge::EmbeddingCatalog` capability/configuration gating so
      unconfigured or non-embedding models are refused with a readable reason.
- [x] Add `Ai::Knowledge::Embedder` with batched embedding, per-chunk fallback,
      partial/failed collection state and secret-filtered error summaries.
- [x] Extend retrieval with `lexical`, `semantic` and `hybrid` modes that keep
      score, cosine similarity, lexical score and matched terms inspectable, and
      skip stale embeddings whose checksum no longer matches their chunk.
- [x] Add `Ai::Knowledge::Search` mode resolution with explicit degradation:
      semantic/hybrid falls back to lexical evidence and states why.
- [x] Add embed/re-embed/clear controls, embedding status, coverage and mode
      selection to the Knowledge workspace UI with project-boundary coverage.
- [x] Consolidate provider-key redaction into `Ai::ErrorText` and cover both
      `sk-` and `sk_` key prefixes.
- [x] Verify with targeted model/service/integration tests and one real
      OpenRouter free-embedding dogfood run.

### M4 gate status: `PARTIAL` · embedding + retrieval slice `LOCAL_VERIFIED` + `OPENROUTER_DOGFOOD`

Embedding, semantic/hybrid retrieval and evidence are implemented for the
bounded local corpus. Rerank, file/Active Storage ingestion, OCR/extraction and
provenance artifacts remain outstanding, so this is still not the complete M4
milestone.

### M4 embedding dogfood record — 2026-09-17

- [x] OpenRouter `liquid/lfm-2.5-embedding-350m:free` embedded 2 chunks at 1024
      dimensions (130 input tokens) in roughly 1.4s; collection status `ready`
      with 2/2 coverage.
- [x] One semantic query ranked the SQLite corpus paragraph at cosine 0.5373
      above the tool-approval paragraph at 0.2334; hybrid retained both the
      lexical 0.6963 and cosine 0.5373 components.
- [x] Only one provider and one free embedding model were exercised; cross-
      provider embedding compatibility is still unaccepted.

## M4 vector adapter spike — 2026-09-17

- [x] Add an opt-in `sqlite_vector_extension` adapter behind the existing
      `Ai::Knowledge::VectorStore` interface using the external sqlite-vector
      loadable extension, keeping `sqlite_application_cosine` as the default.
- [x] Keep evidence semantics identical by using exact `vector_full_scan`
      cosine only; no quantization, so no recall claim is introduced.
- [x] Read through a dimension-scoped derived index
      (`knowledge_vector_index_<dimension>`) because sqlite-vector declares one
      dimension per column and does not check per-row blob length.
- [x] Fall back explicitly: registry, inspector and result header report the
      effective adapter and the reason when the extension is unavailable.
- [x] Verify locally against the real macOS arm64 binary: same ranking as the
      default adapter within 3.5e-07, end-to-end semantic search identical.

### Vector adapter status: `sqlite_vector_extension` `PARTIAL` · spike `LOCAL_VERIFIED`

Enabled only by explicit configuration; not the default, not distributed with
the app, and not benchmarked.

## M4 rerank — 2026-09-17

- [x] Add `Ai::Knowledge::RerankCatalog` gating rerank on the registry's
      `rerank` output modality plus provider configuration, so the toggle only
      offers compatible providers.
- [x] Add `Ai::Knowledge::Reranker` over `RubyLLM.rerank` with secret-filtered
      errors and normalized (index, score) results.
- [x] Make rerank a second stage in `Ai::Knowledge::Search`: it reorders
      evidence and records `rerank_score` / `pre_rank`, never rewriting the
      retrieval score, cosine, lexical components or chunk evidence.
- [x] Report explicitly when rerank is unavailable, unselected or failing, and
      keep the original evidence in that case.
- [x] Surface the toggle, pre/post rank, rerank score and the not-applied note
      in the Knowledge workspace with integration coverage.
- [x] Verify with targeted service/integration tests and one real OpenRouter
      free rerank-model dogfood run.

### M4 rerank status: `IMPLEMENTED` · `LOCAL_VERIFIED` + `OPENROUTER_DOGFOOD`

Only one provider and one free rerank model were exercised; rerank quality is a
model property, not an app guarantee.

### M4 rerank dogfood record — 2026-09-17

- [x] OpenRouter `nvidia/llama-nemotron-rerank-vl-1b-v2:free` reranked 3 chunks;
  scores 0.6758 / 0.111 / 0.0009 with pre-rank positions preserved in evidence.
- [x] On a lexical tie (0.7833) the reranker promoted a term-dense off-topic
  chunk above the semantically correct one; recorded as a caveat, not a defect
  in the plumbing.
- [ ] Other rerank providers (Cohere, Voyage non-free tiers) and `top_n`
  behaviour on larger candidate sets remain unverified.

## RubyLLM 2.0 alignment — 2026-09-18

- [x] Move the pinned gem from `ruby_llm 2.0.0.rc3` to `2.0.0.rc4` and re-check
      every provider interaction against the 2.0 API.
- [x] Consume RubyLLM instrumentation through an adapter:
      `Ai::RubyLlmInstrumentation` maps `*.ruby_llm` notifications onto
      `ai.provider.*` lifecycle events with a whitelisted payload and
      `source = ruby_llm`.
- [x] Correlate notifications with Runs through `Ai::ExecutionContext`, because
      the notification payload's chat is RubyLLM's own object rather than an
      application record.
- [x] Label provider-hosted tool calls explicitly (`tool_invocations.remote`)
      and surface it in the Run inspector.

### RubyLLM alignment status: `IMPLEMENTED` · `LOCAL_VERIFIED` + `OPENROUTER_DOGFOOD`

Only chat-provider notifications were exercised live; tool-call notifications
and provider-hosted/remote tools were covered by tests only.

## M4 documents — 2026-09-18

- [x] Add file sources: `KnowledgeItem` gains `source_kind: file`, an Active
      Storage attachment, MIME/size validation and upload from the workspace.
- [x] Add `Ai::Knowledge::Extractor` with a local reader for text-like files and
      `RubyLLM.ocr` for PDFs/images behind `Ai::Knowledge::OcrCatalog` gating.
- [x] Run extraction in `DocumentExtractionJob` (Active Job) and
      keep failures on the item instead of raising inside the web request.
- [x] Write a durable `ocr_document` Artifact with provenance: extractor,
      filename, content type, byte size, page count, provider/model, blob
      checksum and content checksum.
- [x] Make `Artifact` ownable by a KnowledgeItem (`run_id` now optional) so
      document provenance does not need a Run.
- [x] Verify locally with service/integration tests, one real upload-to-search
      dogfood run and an HTTP render check.

### M4 document status: `IMPLEMENTED` · `LOCAL_VERIFIED`

Local extraction is proven; the provider OCR path has test coverage only,
because no OCR-capable provider is configured in this environment.

## RubyLLM 2.0.0 stable — 2026-09-20

- [x] Pin RubyLLM to `2.0.0` in `Gemfile` and `Gemfile.lock`; `bundle update ruby_llm` completed successfully.
- [x] Keep the existing Rails message data and migrations. The repository was
      already on the 2.0 schema shape; no 1.x data migration was applied.
- [x] Run the full Rails test suite against the stable dependency bundle.
- [ ] Exercise configured provider paths after the stable upgrade.

### Stable upgrade status: `IMPLEMENTED` · dependency resolution only

The full Rails suite passed against the stable bundle (154 tests, 1,003
assertions, one skipped test). No schema migration, deployment, or live provider
dogfood was part of this verification.

## M5.1 — Per-Run provider web search and citations — 2026-09-20

- [x] Add an unchecked-by-default web-search option on the Chat form; its
      authorization applies only to the Run submitted with that form.
- [x] Freeze the selected provider-tool names into the Run `input_snapshot` and
      configure RubyLLM from that snapshot, clearing tools left on a reused Chat.
- [x] Persist normalized provider citations as a `citation_set` Artifact linked
      to the Run and Attempt; record the Artifact id and provider-tool step count in the
      Run result summary.
- [x] Show provider tool activity and safe HTTP(S)-only citation links in the
      Chat and Run inspector.
- [x] Add focused automated coverage for option snapshots, provider-tool
      clearing, and citation Artifact persistence/redaction.
- [ ] Dogfood at least one configured provider/model combination that supports
      hosted web search.

### M5.1 status: `PARTIAL` · local automated coverage present, provider dogfood pending

RubyLLM 2.0 persists citations and provider tool calls on Messages. The app
adds a normalized citation Artifact for Run-level inspection. The model
registry does not expose a reliable per-model hosted-search capability flag.
RubyLLM rejects protocols without the requested tool alias, and provider/model
requests rejected during execution become failed Runs; the app cannot currently
prove every selected model will honor or invoke search. No live search was
performed for this slice.

## M5.2 — Saved Agent definitions and Run execution skeleton — 2026-09-20

- [x] Add Project-owned, revisioned AgentDefinition CRUD with a strict local-tool
      allowlist, `web_search` provider-tool allowlist, and bounded generation options.
- [x] Require an exact RubyLLM chat-registry model entry declaring
      `function_calling` for local-tool Agents at definition save, Run enqueue,
      and every worker restoration; fail closed when metadata is absent.
- [x] Freeze the JSON-safe definition snapshot into each Agent Run; give the
      Run a dedicated Chat transcript so approval and cancellation remain scoped.
- [x] Rebuild the RubyLLM Agent from the Run snapshot and advance with one
      `Agent#step` at a time in an `ActiveJob::Continuable` job.
- [x] Record Agent step events, Attempts, citations, provider-tool activity,
      local tool/approval activity and terminal cancellation status.
- [x] Route approval continuations back through `AgentRunJob` with the decided
      invocation id and paused generation; atomically claim only a permitted Run
      state using a generation-fenced database lease with heartbeat and expiry.
- [x] Keep delayed generic duplicates out of `waiting_for_approval`; retry
      transient heartbeat database errors within the known lease window and
      enqueue a recovery delivery if ownership becomes uncertain.
- [x] Fence RubyLLM Message and usage persistence, streamed chunk recording,
      provider lifecycle events, tool invocation records and built-in note writes
      with the current Run lease.
- [x] Compare each Run's frozen local tool contract with the current registered
      contract before rebuilding its Agent; fail clearly on contract drift.
- [x] Make `save_run_note` reuse its Artifact by persisted RubyLLM tool-call id.
- [x] Treat RubyLLM's blank assistant placeholder as an interrupted provider step;
      fail the Attempt, remove the placeholder and retry from the preceding Chat turn.
- [x] Persist initial execution, approval continuation and worker recovery intents
      in a primary-database delivery outbox before queue dispatch.
- [x] Add a recurring dispatcher with retry backoff and recovery scans for expired
      Agent leases, unclaimed Runs and fully decided approval waits.
- [x] Add deterministic automated coverage for snapshot immutability, outbox
      dispatch/retry, stale-lease and approval recovery, generation fencing,
      terminal cancellation, and step/citation timeline linkage.
- [x] Assert that provider, model, instructions, local/provider tools, and
      generation options remain frozen in an already-queued Run after all six
      Agent definition contract fields are edited.
- [x] Exercise a deterministic two-step `AgentRunJob` through continuation,
      Attempt recording, transcript persistence, timeline events and success.
- [x] Exercise the Agent definition and launch pages through a request-level
      integration flow, then reload the Run inspector with its frozen revision,
      step timeline and citation Artifact.
- [x] Exercise approved and denied tool decisions through the durable Agent Run
      delivery, Agent job continuation and local `save_run_note` side effect.
- [x] Recover a blank assistant placeholder as a failed Attempt and resume from
      a newly claimed expired Run lease through `AgentRunJob`.
- [x] Keep a Run cancelled when an Agent response returns before step finalization.
- [x] Replay a committed `save_run_note` with the same persisted tool-call id and
      verify it reuses one Artifact.
- [x] Exercise Solid Queue worker interruption/restart and at-least-once replay
      boundaries with the idempotent local `save_run_note` tool.
- [x] Cover an accepted queue enqueue whose outbox acknowledgement is lost,
      then verify expired-claim redelivery is fenced by the Run lease and creates
      only one successful Run report; execute the stale duplicate Agent Job and
      verify it exits before rebuilding the Agent.
- [x] Show background-job readiness separately from web availability, including
      recent recurring-scheduler, dispatcher, maintenance-worker and due-outbox state.
- [ ] Dogfood a provider/model with web search and a multi-step Agent task.
- [ ] Verify the local-tool Agent gate against a real provider/model request; the
      registry declaration is only a local admission hint.

### M5.2 status: `PARTIAL` · local crash/replay, lost-ack redelivery fencing, and provider-free result/approval/cancellation UI review verified; live provider behavior pending

The deterministic suite verifies definition and Run snapshots, primary outbox
dispatch acknowledgement/retry, queued and expired-lease recovery, fully decided
multi-approval recovery, lease-generation fencing, cancellation terminal state,
and step/citation timeline linkage. A deterministic fake Agent now exercises
`AgentRunJob#perform` through a queued
continuation and two successful steps, including Attempts, transcript, and
lifecycle events. A provider-free flow also exercises approved and denied
`save_run_note` decisions through the durable delivery and continuation; stale
delivery generations are rejected. A request-level UI integration test creates
an Agent definition, queues its frozen revision, runs a cited fake Agent through
two steps, updates the definition and reloads the inspector to verify the
original snapshot, timeline and linked citation Artifact. A manual browser check
at 390px and desktop widths reviewed a synthetic successful report with citation
links and step timeline, a pending approval, the denied/queued continuation
state, and a cancelled Run with expired approval and cancelled tool details.
The Run and Chat pages had no document-level horizontal overflow at 390px; the
Attempt table contained its own horizontal scroll. The browser used an isolated
Rails test database and test queue adapter, so no Run worker or provider call
occurred. A Selenium system test now exercises the JavaScript cancel
confirmation: dismissal leaves the Run and Attempt running, and acceptance
cancels both. Request integration also covers the cancellation endpoint.
A Solid Queue drill killed a forked worker
after the note Artifact committed but before RubyLLM stored the tool result; the
replacement job replayed the same tool-call id, reused the Artifact, and completed
the Run. A provider-free cancellation race pauses RubyLLM's completion boundary,
cancels from another thread, then verifies the late response is not persisted.
An additional deterministic dispatcher regression accepts the first enqueue,
simulates a lost outbox acknowledgement, expires the delivery claim, and confirms
redelivery uses the same job arguments; the Run lease admits one execution and
the success transaction leaves one report Artifact. This covers the cross-database
at-least-once window without changing its delivery semantics. Real provider calls
and provider-backed worker outcomes remain unverified. The regression then runs
the stale duplicate through `AgentRunJob#perform` after success and verifies the
terminal guard returns before Agent reconstruction.
The Runtime inspector no longer claims unconditional `healthy`: under Solid Queue
it checks process heartbeats against Solid Queue's liveness threshold, confirms
that the scheduler includes `dispatch_agent_run_deliveries`, confirms that a
worker handles the `maintenance` queue, and shows due primary-database outbox
deliveries. Test mode is labelled explicitly because its Active Job adapter only
captures jobs. This is process-readiness evidence, not proof that a provider call
will succeed.
Local-tool Agents also fail closed unless the exact model appears in the
RubyLLM chat registry with declared `function_calling` support. Definition
validation, pre-enqueue admission and each worker restoration apply the same
check; provider-hosted `web_search` is outside this rule. Automated coverage
proves these application boundaries only, not provider acceptance.
Agent Jobs persist model/tool calls and resume from the Chat transcript with
at-least-once semantics. Run-row locking fences transcript/usage persistence
and current local database writes against lease takeover; a provider request
already accepted upstream cannot be recalled, so an interrupted request may
still incur cost before a later delivery retries it. The built-in
`project_snapshot` tool is read-only and the current `save_run_note` crash window
is covered by a worker kill/replay drill; future side-effect tools need their own
idempotency verification. Provider-free browser review now covers the completed
report/citation, pending and denied approval, cancellation and narrow layout
states. M5 remains partial pending live provider evidence.
After adding full provider/model/instructions/local tool/provider tool/options
snapshot assertions and post-enqueue definition mutation, the focused M5 suite
passed under Ruby 4.0.2: 23 runs, 368 assertions, no failures or skips. The
tests used configured-provider stubs and fake Agent behavior; no provider call
was made. The full Rails suite then passed 251 runs and 2,083 assertions, with
no failures/errors and 2 skips. The cancel-confirmation system test has a prior
separate result of 1 run and 6 assertions; the latest full local system-test run
could not bind Selenium's loopback port and stopped before assertions (see the
release-readiness record below).
Initial, approval and recovery intents are saved in the primary
database and dispatched with retries to the separate Solid Queue database. A
recurring dispatcher also scans expired leases and approved waits so worker
crashes do not depend on an `ensure` callback. Queue insertion and outbox
acknowledgement cannot share a transaction; a crash between them can enqueue a
duplicate, which is fenced by the Run lease. Delivery depends on the Solid Queue
recurring scheduler running in development and production.

## M5.3 — Durable Agent research report — 2026-09-20

- [x] Persist the final saved assistant answer as a `report` Artifact in the same
      Run-locked success transaction; keep failed and cancelled Runs report-free.
- [x] Link the report to its source message, final Attempt, frozen Agent revision,
      provider/model and all citation-set Artifacts for the Run.
- [x] Render the report in the Run inspector with in-page links to its citations.
- [x] Cover report persistence, retry idempotency, citation linkage, cross-Chat
      rejection and cancellation behavior with provider-free tests.
- [x] Expand the opt-in OpenRouter Agent test to check the live report's final
      Attempt, frozen revision, source message and citations, then render the
      report/citation links in the Run inspector.
- [ ] Verify the report and citation presentation with a real Agent/provider Run.

### M5.3 status: `PARTIAL` · local report flow implemented; live Agent evidence pending

Successful Agent Runs now produce a durable report Artifact in the same database
transaction that marks the Run successful. The Artifact records the final
assistant message, final Attempt, provider/model, frozen Agent identity and
citation Artifact IDs; the inspector links back to those sources. A successful
Run therefore cannot commit without its report, and cancellation or failure does
not create one. This local behavior does not prove live provider output quality.

## M5.4 — Cancel pending approvals with their Run — 2026-09-20

- [x] Expire pending approvals and cancel unfinished local tool invocations in
      the same transaction that marks their Run cancelled.
- [x] Record `ai.approval.expired` and `ai.tool.cancelled` lifecycle events with
      links to the affected approval and invocation.
- [x] Serialize tool-call reconciliation with Run cancellation and skip sync for
      terminal Runs so a chat reload cannot restore stale approval controls.
- [x] Persist a RubyLLM denial result for each unfinished approval, so the
      existing Chat no longer contains unanswered tool calls; do not leave a
      Chat-level cancellation request when pending approval state exists.
- [x] Resolve local calls with a tool result and remote/server calls with the
      provider-specific RubyLLM approval response.
- [x] Cover cancellation after an approval is persisted but before the Run
      status changes to `waiting_for_approval`.
- [x] Cover expired approval, cancelled invocation, denial result, later Chat
      messages, absent continuation delivery, rejected late decisions and cleared
      chat UI in a provider-free integration test.
- [x] Review synthetic completed-result/citation, pending/denied approval,
      cancelled Run, and 390px/desktop layouts in the browser.
- [x] Exercise the native cancel confirmation in Selenium: dismissal preserves
      running state; acceptance cancels both the Run and Attempt.
- [ ] Complete live Agent/provider dogfood and review provider-backed outcomes.

### M5.4 status: `PARTIAL` · cancellation cleanup and provider-free browser presentation verified; live provider behavior remains open

Cancelling a Run now closes any pending approvals and unfinished tool calls in
the Run-locked transaction. It also writes a structured RubyLLM denial result,
so a later Chat message is not blocked by an unanswered tool call. Cancelling a
Run already waiting for approval does not leave a Chat-level cancel request.
Remote approvals use RubyLLM's provider-specific protocol response; local calls
receive a local tool result, without executing either tool.
The inspector no longer re-imports pending RubyLLM tool-call state after the Run
reaches a terminal status. Approval and tool cancellation remain distinct
lifecycle events, and a stale decision cannot create an Agent continuation
delivery.

## M5.5 — RubyLLM Responses/MCP provider-hosted tool approvals — 2026-09-20

- [x] Convert persisted remote ToolCalls with no decision or result into local
      pending ToolInvocation and Approval records.
- [x] Show provider-hosted requests in the same Chat approval surface as local
      tools, label where execution happens, and explain that approval lets the
      selected provider execute the remote call.
- [x] Route approve/deny through the existing ApprovalService and durable Agent
      outbox; let RubyLLM 2.0 Responses create the `mcp_approval_response` result.
- [x] Cover remote request inspection, Chat approval, Agent denial/outbox,
      decision persistence and protocol result association with synthetic
      RubyLLM records without network calls.
- [x] Exercise approved and denied MCP provider-hosted requests through the
      durable Agent outbox, `AgentRunJob` continuation, local RubyLLM protocol
      response and final report Artifact.
- [ ] Dogfood one configured provider/model that returns a hosted approval
      request and inspect the full continuation and final answer.

### M5.5 status: `PARTIAL` · local approval and Agent continuation covered; live provider behavior pending

Within RubyLLM 2.0's Responses/MCP approval protocol, hosted approval requests
now appear as ordinary persisted Approval records and use the same guarded
decision and continuation path as local tools. The Chat surface labels each
invocation as local or provider-hosted and explains that the selected provider
executes a remote call after approval. Deterministic tests exercise both
decisions through a persisted Agent continuation and final report, and inspect
the `mcp_approval_response` result shape. They do not prove that a live
provider/model emits an approval request or resumes successfully after the
decision; no broader provider-hosted approval compatibility is claimed.

## M5.6 — Close approvals on failed Runs — 2026-09-21

- [x] Do not create Approval records while syncing a failed tool call; limit
      ordinary error tool results to local invocations that were running.
- [x] After the lease check, expire pending approvals and finalize their
      ToolInvocations inside the same transaction that marks the Run failed.
- [x] Persist local denial results and remote MCP `mcp_approval_response`
      denials for calls that were still awaiting approval, without executing
      tools or sending another provider request.
- [x] Preserve an already-approved remote MCP call with no saved result as an
      unknown external outcome; do not fabricate a denial or replay it.
- [x] Block new Runs on the same Chat after an approved remote call's outcome
      becomes unknown; mark a remote call cancelled in progress the same way.
- [x] Cover local and remote failure cleanup, absent approval continuation,
      stale UI decisions, and a stale execution lease that must leave approval
      state untouched.
- [ ] Complete live Agent/provider dogfood and review provider-backed outcomes.

### M5.6 status: `PARTIAL` · pending-call cleanup, unknown remote outcomes and same-Chat replay blocking verified locally; live provider behavior remains open

When an Agent step fails, pending approvals are no longer left actionable on a
terminal Run. The failure path closes pending Approval and ToolInvocation state
under the Run lock, writes a local denial result for an unstarted local call,
and stores a RubyLLM Responses denial message for a remote call that is still
awaiting approval. If a remote call was already approved but has no saved
provider result, the app preserves the approved decision, records an unknown
external outcome and blocks further Runs in that Chat. A remote call cancelled
while in progress is also marked unknown. Neither path fabricates a denial or
automatically replays the call. Focused provider-free checks pass: 19 runs,
199 assertions. Live provider behavior remains open.

## M5.7 — Freeze queued Chat context and handle queue rejection — 2026-09-21

- [x] Snapshot the ordered RubyLLM message context under the Chat row lock and
      allow only one active Run per Chat.
- [x] Fail closed before the first provider request if the persisted Chat context
      changed while the Run was queued.
- [x] Record the Run's message ID boundary so a reproduction export can include
      its prompt, assistant/tool messages and approval continuation without
      including messages from later Runs.
- [x] Mark a Chat Run and its first Attempt failed when the queue adapter rejects
      the job.
- [x] Add focused provider-free coverage for context drift, enqueue rejection,
      concurrent submissions, multi-turn export and approval continuation.

### M5.7 status: `PARTIAL` · local queue/context/export safeguards have focused provider-free coverage; live provider behavior remains open

The Run snapshot reads persisted messages directly, so enqueue does not require
provider credentials and a memoized RubyLLM Chat cannot hide newer database
messages. It preserves tool calls, provider raw content, citations, reasoning
signatures and cache boundaries. A worker reloads the persisted Chat before
comparing it to the frozen context. Run-owned messages are bounded by persisted
message IDs for export, including approval waiting and continuation. Attachment
payloads remain excluded. Focused provider-free coverage passed: 14 runs, 135
assertions, 0 failures/errors/skips. No provider calls were made.

## M5 cross-slice lifecycle regression — 2026-09-21

- [x] Re-run the local Agent definition, execution, approval, delivery/replay,
      cancellation and report lifecycle coverage together after the M5 changes.
- [x] Record the focused result: 12 test files, 47 runs, 501 assertions,
      0 failures, 0 errors and 0 skips.
- [ ] Run the opt-in hosted-search Agent dogfood test with an explicitly
      configured provider before marking M5 complete.

The focused run used a sanitized temporary copy of the worktree, with the Vite
test manifest built locally. It passed without provider credentials or network
requests. This gives local evidence across the M5 lifecycle paths; it does not
verify real provider search, citations, tool behavior, or hosted CI. M5 remains
`PARTIAL`; the opt-in live acceptance in
`test/integration/openrouter_live_test.rb` is the earliest pending M5 gate.
The 12 files were `test/integration/agent_run_flow_test.rb`,
`test/integration/agent_run_cancellation_race_test.rb`,
`test/integration/agent_run_worker_replay_test.rb`,
`test/jobs/agent_run_delivery_dispatcher_job_test.rb`,
`test/jobs/agent_run_job_test.rb`, `test/integration/tool_approval_flow_test.rb`,
`test/models/agent_definition_test.rb`, `test/models/agent_run_delivery_test.rb`,
`test/models/run_agent_execution_test.rb`,
`test/services/ai/agent_model_eligibility_test.rb`,
`test/services/ai/agent_research_report_recorder_test.rb`, and
`test/services/ai/agent_run_executor_test.rb`.

## M6 — Media operations — 2026-09-20

- [x] Add a speech-capability catalog and allow a saved assistant reply to be
      submitted as a dedicated asynchronous speech Run.
- [x] Freeze the source message, reply text, provider and model in the Run
      snapshot; record the model/provider in its Attempt.
- [x] Persist generated audio as an Active Storage-backed `audio` Artifact with
      source, provider, model, format, MIME type, size and SHA-256 metadata.
- [x] Show the audio player and download link in the Run inspector; map RubyLLM
      speech instrumentation to the originating Run and Attempt.
- [x] Estimate cost using RubyLLM's `audio_tokens` category; leave missing
      provider usage or registry pricing unknown.
- [x] Fence completion writes against concurrent cancellation and recover speech
      Runs stuck in `queued` or `running` for 30 minutes as visible failures;
      do not replay an uncertain provider request automatically.
- [x] Cover queueing, rejected enqueue, fake synthesis success/failure, audio
      persistence, lifecycle mapping, cancellation race, stale queued/running
      recovery and token-category pricing with local automated tests.
- [ ] Dogfood one configured speech provider/model and inspect format, voice,
      usage, cost and actual playback.
- [x] Add capability-gated image generation and transcription Runs; run provider
      work in Solid Queue and persist image, source audio and transcript Artifacts.
- [x] Add capability-gated video Runs; render and poll through RubyLLM inside a
      Solid Queue worker, persist video Artifacts, and fail stale work without replay.
- [x] Verify image, video and transcription queue-to-Artifact flows with fake
      RubyLLM responses, including Run inspector rendering and usage/cost state.
- [x] Disable Chat entry actions for image, video, speech and transcription when
      the RubyLLM catalog has no model declaring the required capability.
- [x] Verify stale image/transcription/video work fails without replay while
      recent media Runs remain active.
- [x] Commit media failure and Attempt state together under the Run lock so a
      late failure cannot overwrite a concurrent cancellation.
- [x] Upload transcription source audio before creating the Run; upload generated
      image, video and speech bytes before committing success; purge unattached
      blobs when normal failures prevent attachment.
- [x] Schedule cleanup of Active Storage Blobs left unattached for 24 hours after
      a process stops between upload and database attachment.
- [x] Normalize whitespace-only transcription output to the supported empty
      transcript representation and retain `empty_transcript: true`.
- [x] Verify source and generated media bytes are downloadable; storage upload
      failures create no successful Run/Attempt or orphan Blob database row.
- [x] Treat rejected Active Job enqueue as a visible queued failure and close
      stale speech/media Runs that no worker claimed within 30 minutes without
      calling or replaying a provider request.
- [x] Add deterministic coverage for media failure/cancellation races, rejected
      speech/image/video/transcription enqueues and stale queued-job recovery.
- [x] Persist the provider video-job reference observed at RubyLLM submission as
      support evidence in the Run timeline, and redact it from reproduction exports.
- [ ] Add durable provider-job resumption for video where providers expose a
      serializable job reference; keep uncertain submissions from being replayed.
- [ ] Dogfood configured image, video and transcription models; inspect output,
      usage, cost and provider compatibility.

### M6 status: `PARTIAL` · media paths locally tested; provider dogfood and durable video resumption open

Speech, image generation, video generation and transcription use capability-filtered
RubyLLM models and background Runs. Media outputs and transcript text are stored as
Artifacts. Speech fake-provider tests cover queueing, enqueue rejection, success
and failure, audio Artifact persistence, cancellation, and stale queued/running
recovery. Image, video and transcription have integration coverage from the queued
web request through output Artifact and Run inspector. Chat entry actions now show
unavailable states when no catalog model declares the operation. These tests do not establish
live provider compatibility. Recovery coverage confirms stale running work fails
without replay and recent work remains active. The
RubyLLM video submission event now stores a string provider job reference as
`submitted` evidence in the Run timeline; reproduction exports redact that
reference. This helps identify a provider-accepted job during support work, but
does not resume polling. New tests cover failures after cancellation, late
successful image and video responses after stale recovery, rejected enqueue results
for speech/image/video/transcription, and stale queued recovery for
speech/image/video/transcription; transcription recovery retains its source
Artifact. The latest focused slice also
checks that transcription source and generated image/video/audio bytes are
downloadable, upload failures leave no successful Run or orphan Blob row, and
the daily cleanup purges only unattached Blobs older than 24 hours. The focused
speech/media regression set passed 23 runs and 296 assertions. The full Rails
suite passed 257 runs and 2,156 assertions, with 0 failures, 0 errors and 2 skips.
RubyLLM video polling runs synchronously inside its queue worker, and RubyLLM 2.0.0
has no public API to restore a `VideoJob` from a persisted provider job ID. The
observed ID is support evidence only; rebuilding polling through RubyLLM internals
would not provide a stable recovery contract. The app does not claim durable video
resumption. The recurring scheduler must run for
stale-Run recovery. An interrupted provider request fails after 30 minutes and
requires a new Run to retry because replaying an uncertain request could duplicate
its cost.

## M7 — Evaluation datasets — 2026-09-20

- [x] Store bounded dataset cases in immutable, numbered revisions; edits create
      a new revision and existing executions retain their original revision.
- [x] Compare 2–5 configured structured-output models over one revision, with
      one ordinary child Run and Attempt per model/case.
- [x] Freeze one dataset revision and Experiment snapshot across the whole
      comparison; retain an immutable model list and separate Execution per model.
- [x] Freeze experiment, model and case inputs; do not send expected outputs to
      the provider. Compare the returned JSON value exactly and retain each
      actual output, status, error, Run link and cost for inspection.
- [x] Show aggregate pass/fail counts and allow safe resume of queued cases
      only when the child Run and all Attempts have not started.
- [x] Check queue admission for each case and Batch submission job; keep rejected
      individual cases eligible for retry with a visible sanitized error, and
      fail a rejected Batch submission locally before it can reach a provider.
- [x] Check queue admission for explicit Batch refresh requests; show an alert on
      rejection and leave the saved execution and child Runs unchanged.
- [x] Add an opt-in provider Batch path for one configured model advertising both
      structured-output and batch capabilities; preserve a Run/Attempt per case.
- [x] Persist provider batch ID/status, map RubyLLM's ordered Batch messages back
      to frozen case positions, and reconcile a saved batch record after an app-side
      save interruption or a late local-store write.
- [x] Mark submissions without a recoverable provider ID as uncertain; never
      automatically resubmit, and keep provider batch work out of ordinary
      30-minute case recovery.
- [x] Allow a human to close an unreconciled submission as a local failure after
      acknowledging that this cannot cancel remote work and a new run may duplicate cost.
- [x] Recover cases stale for 30 minutes as visible failures without replaying
      an uncertain provider request; fence late structured completion writes.
- [x] Cover frozen revisions, exact matches/mismatches, unstarted resume,
      worker recovery, completion races, dataset editing and Project deletion.
- [x] Add deterministic fake-batch coverage for submit readiness, ordered store
      reconciliation and late-store recovery, refresh mapping, partial failures,
      per-case Artifact/Attempt linkage and response-token mapping.
- [x] Show side-by-side per-case outcomes and per-model pass/fail/pending/cost
      summaries, with each result linked to its raw Run and Attempt inspector.
- [x] Classify provider response and schema outcomes independently, preserving
      unknown, cancelled and not-attempted cases outside known-outcome rates.
- [x] Summarize app-observed individual request latency, token coverage, and
      reported/estimated cost by currency; keep Batch waiting time out of latency.
- [ ] Dogfood a configured structured-output provider/model and review quality,
      usage, cost and failure behavior.
- [x] Extend immutable cases with bounded optional tags; freeze them in each
      revision and Run snapshot, show them in dataset/comparison views, and keep
      them out of provider prompts.
- [x] Add project-scoped attachment references to immutable cases with explicit
      provider-input rules and safe deletion behavior. Attachments are revision-owned,
      bounded to 5 per case / 50 per dataset revision / 10 MB each / 50 MB per
      revision, and restricted to text, JSON, CSV, PDF, JPEG or PNG. Each add/remove creates a new revision;
      earlier revisions retain their files; project deletion purges them. Files
      remain local review material and never enter individual or Batch prompts.
      Limits are checked after multipart parsing; any future network deployment
      must also configure request-body and part-count limits at its ingress.
      The byte bound is per revision; no lifetime dataset/project storage cap is
      enforced, so repeated revision uploads can grow retained storage.
- [x] Check raw upload bytes before creating a revision: PDF header, JPEG/PNG
      signatures, JSON parsing, CSV syntax and UTF-8/control-byte validity for
      text. Declared MIME selects the check; missing or generic MIME may use the
      filename extension to select it. This does not fully decode documents or
      scan for malicious payloads.
      CSV/JSON parsing, binary-text rejection and stream-position restoration have automated coverage (2026-09-26).
- [x] Add append-only human review records for completed case outputs; keep
      reviewer judgment separate from exact-JSON and provider metrics.
- [x] Add optional bounded per-case rubric criteria to immutable revisions and
      copy them into the case result and local Run context, outside generation
      prompts except when a separate automated judge is explicitly selected.
- [x] Require append-only human review ratings for each configured criterion and
      show per-case counts by rating with no combined score.
- [x] Add an opt-in automated rubric judge with a frozen target/prompt/schema,
      separate Run/Attempt/cost records, input-boundary disclosure, and safe
      queue recovery; keep expected outputs, tags and attachments out of the
      judge prompt and preserve exact-match/human-review metrics.
- [ ] Dogfood the rubric judge with a configured provider and review rating
      quality, usage and cost.

### M7 status: `PARTIAL` · comparison, outcome metrics, bounded case tags and attachments, human rubric ratings, optional automated rubric judgments, and individual/provider-batch paths have provider-free local evidence; attachment byte validation has focused automated coverage, while provider dogfood and judge calibration remain open

Each comparison stores one immutable group record with the dataset revision,
Experiment snapshot and selected model list. It creates one existing-style
EvaluationExecution per model, then one ordinary child Run/Attempt per case.
The summary compares pass/fail/mismatch and pending counts by model, and the
case matrix links each cell to its raw Run; total cost stays unknown if any case
does not have a reported or estimated amount. Partial queue rejection remains
visible on the affected case and can be retried without changing the comparison
inputs. Per-model metrics separate received, failed, cancelled, unknown and
not-attempted transport outcomes; response and schema rates use only their known
outcomes as denominators. Individual latency is app-observed Attempt duration,
with median shown when samples exist and p95 shown only at 20 or more samples;
provider Batch elapsed time is excluded because it includes submission wait and
refresh time. Token totals show usage coverage, and reported and estimated cost
are grouped separately by currency without treating missing amounts as zero.
These are execution diagnostics, not a provider availability measure or quality
score. Completed outputs can receive append-only human reviews with an acceptable,
needs-work or inconclusive verdict, a self-reported reviewer label and optional
rationale. When a case has a rubric, each review also rates every criterion as
meets, partially meets, does not meet or not applicable. Per-case counts include
all recorded reviews and N/A ratings; they are descriptive and no combined score
is produced. Reviews preserve prior entries and do not change exact-match status
or execution metrics. The application has no authenticated reviewer identity;
review labels are descriptive metadata, not verified identities or a consensus
score. An opt-in rubric judge runs separately for completed outputs, freezes its
model and prompt/schema versions, and stores ratings and provider cost in a
separate judgment Run. It receives only the case input, generated output and
rubric; expected output, tags and attachment names/content/IDs are excluded.
Queue rejection stays resumable while the Run and Attempt remain unstarted;
recovery re-enqueues only those unstarted judgments. A started request that
stales becomes `submission_unknown`, is never automatically replayed, and late
responses are fenced. These model-generated ratings are not calibrated truth,
do not change exact-match or human-review records, and are excluded from the
generation evaluation's provider metrics. The individual workflow's configured-
provider dogfood and judge quality/cost review remain open. Cases also accept up to 12 unique, non-empty tags
of at most 40 characters; tags remain in immutable dataset and execution
snapshots, are copied into each child Run's local evaluation context, and appear
in current-case, comparison and execution views. They are not added to provider
prompts or used to change metrics. Case attachments are revision-owned and
excluded from individual and Batch prompts, with up to 5 files per case and 50
files per dataset revision (10 MB each, 50 MB per revision); no cumulative
storage quota is enforced.
The individual workflow uses fake RubyLLM
responses in automated checks. A case
is passed only when its returned JSON structure exactly matches the expected JSON;
the separate optional rubric judge does not affect that result. Expected output is retained in the case snapshot but
excluded from generation and judge prompts. Provider Batch requests retain one Run and
Attempt per case, and their ordered results feed those same inspectors using
RubyLLM's submission-order result contract. The RubyLLM Active Record batch store
can reconcile the provider ID after its save but before the Workbench save,
including a late write after the execution entered `submission_unknown`. If
neither local store has the ID, the submission remains uncertain and is never
replayed automatically. Runs and Attempts stay open while the outcome is
uncertain so a later store record can still be reconciled. After 30 minutes, an
explicit operator action rechecks the local batch store before closing the
execution and child Runs as failed; it warns that the provider request may still
be active and does not cancel or resubmit it.
Batch refresh is explicit and reports “queued” only after queue admission; a
rejected refresh leaves the execution, provider reference and child Runs unchanged.
Deterministic fake-batch tests cover submission readiness, exact ordered Store
reconciliation (including a late record after an
unknown result), ordered refresh with a cancelled case, per-case JSON Artifacts,
Attempt linkage and token mapping. Queue rejection now has an explicit boundary:
individual cases remain queued with a sanitized error and can be retried, while a
rejected Batch submission is closed as a local failure before provider work. It
is not mislabeled `submission_unknown`. Queue tests use a fake adapter outcome;
they do not prove provider compatibility. The recurring scheduler must run for
stale submission recovery.

## M8 — Run reproduction export — 2026-09-20

- [x] Add an explicit per-Run JSON download with frozen input/result context,
      app and RubyLLM versions, Attempts, sanitized tool/event metadata and
      relevant textual Artifacts.
- [x] Redact sensitive fields, URL userinfo, signed URL signatures and session
      token query values, common credential patterns and local host paths; omit
      audio bytes and all other binary payloads.
- [x] Add a sharing disclosure in the Run inspector and sentinel-based tests
      across snapshots, errors, Attempts, tools, events and Artifacts.
- [x] Save append-only upstream candidate reports as Run Artifacts with a
      human-set category, expected/observed behavior, minimal repro steps,
      regression-test reference and Run/provider/model/version evidence.
- [x] Download a Markdown issue draft that embeds the existing redacted
      reproduction JSON; classification, review and external submission remain
      manual.
- [x] Cover candidate validation, append-only storage, evidence capture,
      URL credential and signed-query redaction in exports and Markdown drafts,
      binary omission and download behavior with provider-free tests (4 runs,
      112 assertions; no provider calls).
- [x] Freeze and validate queued Chat context, close rejected Runs/Attempts,
      bound reproduction messages through approval continuation, and omit
      attachment payloads; focused provider-free coverage passed (14 runs,
      135 assertions).
- [x] Bound the complete reproduction export by formatted bytes, aggregate text,
      nested depth/items/value nodes, record sections and per-section Chat message
      counts and a capped artifact scan. Bound Markdown candidate drafts too.
      Include omission counts in schema v2 and fall back to a compact Run summary
      if the formatted bundle still exceeds 512 KiB. Budget regressions now cover nested collections/depth, aggregate text/value
      counts, escaped-byte overflow, recent messages, Artifact scanning and
      oversized Markdown fallback (2026-09-27).
- [x] Publish a capability matrix that maps Workbench operations to RubyLLM
      registry/application gates and separates registry declarations from live
      provider compatibility evidence.
- [ ] Review export behavior with representative real Runs and expand the
      upstream RubyLLM gap-reporting workflow.
### M8 status: `PARTIAL` · export, candidate drafts and total-budget limits have provider-free automated coverage; the capability matrix is documented, while real Run review and the external workflow remain open

The export is intended for inspection and reproduction, not guaranteed to be
safe to publish without review. Text fields are bounded, known secret fields and
common credential patterns are redacted, and binary artifacts are excluded. URL
userinfo credentials and known signed-query signatures/session tokens are
replaced while scheme, host, path and non-secret query values remain available.
Schema v2 limits formatted output to 512 KiB, aggregate text to 100,000 characters,
nested depth to 8, nested collections to 50 values, record sections to 100 items,
and each prior/current Chat message section to its latest 100 messages. It scans at
most 1,000 Artifact rows and caps Markdown issue drafts at 768 KiB. It reports
omission counts; an over-budget JSON bundle degrades to a small Run summary instead
of returning an oversized export. This bounds output size but can omit relevant
context, so reviewers should check `truncation` before using a bundle.
Chat exports include the frozen prior message context and messages persisted
during that Run, including tool protocol fields needed to inspect approval turns.
The worker checks that the Chat still matches the queued context before it makes
a provider request; only one active Run per Chat is admitted. Attachment payloads
remain excluded, and provider state, mutable provider configuration, and
nondeterministic output cannot be replayed exactly. Focused provider-free coverage
for context freezing/drift, queue rejection, duplicate submissions, attachment
omission, approval continuation and export boundaries passed (14 runs, 135
assertions). Representative real Runs and arbitrary private data/custom secret
formats still need human review.
The capability matrix records each operation's registry/application admission
rule, current implementation evidence and provider boundary. Historical Chat,
structured-output, embedding and rerank dogfood ran before the stable 2.0.0 pin;
the matrix does not treat it as current stable-version acceptance. Representative
real Runs, review of the broader upstream-gap workflow, and manual external
submission remain open.

## Open-source release readiness — 2026-09-21

- [ ] Have the project owner select and add a public redistribution license.
- [ ] Confirm GitHub private vulnerability reporting is enabled or publish a
      private maintainer contact path; repository files cannot prove this setting.
- [x] Review public-reference documentation for fresh-checkout setup and keep
      the single-user deployment boundary explicit.
- [x] Align `SECURITY.md` attachment-validation guidance with the current
      format checks and document the multipart, decoding and malware-scan limits.
- [x] Run Ruby and frontend advisory scans with current local databases; no
      vulnerabilities were reported in this scan.
- [x] Run Brakeman 8.0.6 against the current worktree: 0 warnings and 0 errors.
      `bundle exec brakeman --no-pager` was used because the repo wrapper's
      latest-version check could not resolve release metadata in this sandbox.
- [x] Run the full local Rails suite after the M7 attachment slice:
      294 runs, 2,524 assertions, 0 failures/errors and 2 opt-in provider tests
      skipped. Full RuboCop checked 256 files without offenses; Zeitwerk passed.
- [x] Re-run local verification after M5.7 context/export changes: serial Rails
      suite 315 runs / 2,758 assertions, 0 failures/errors and 2 opt-in provider
      skips; full RuboCop 265 files with no offenses; Zeitwerk passed; Brakeman
      8.0.6 reported 0 warnings/errors; documentation contract test passed with
      5 runs / 143 assertions. No provider calls were made.
- [x] Run the Selenium system tests with loopback permission:
      2 runs, 9 assertions, 0 failures/errors/skips. The sandboxed attempt was
      blocked at `127.0.0.1:9514` before assertions; the permitted retry passed.
- [x] Build the production Docker image locally from a fresh build context using
      Node 24.21.0; `npm ci`, npm audit and Vite production build passed.
- [ ] Confirm the production Docker build passes in hosted CI; a local build does
      not provide hosted runner evidence.
- [x] Exclude local `vendor/bundle` contents from Docker build context and omit
      development/test groups from the production bundle.
- [x] Add a Docker image build to CI; a successful hosted CI run is still pending.
- [x] Ignore the complete root `/specs/` directory in Git and Docker context;
      confirm no Specs files are tracked in this repository.
- [x] Ignore Rails credentials decryption keys under both `config/` and
      `config/credentials/` in Git and Docker build context.
- [x] Document the optional `libvips` system dependency for Active Storage image
      variants and add a non-fatal, non-installing hint to `bin/setup`.
- [x] On the current macOS host, verify `ruby-vips` loads and
      `ImageProcessing::Vips` generates a resized PNG using libvips 8.18.6.
- [ ] Manually verify setup with and without `libvips` on macOS and Debian/Ubuntu:
      without it, the hint appears and setup continues; with it, the hint is absent
      and an image variant can be generated. The macOS image transformation passed,
      but the pinned-Node setup path, missing-libvips branch and Debian/Ubuntu checks
      remain open.

### Release readiness: `PARTIAL` · implementation and packaging hardened; owner, manual and hosted-platform gates remain

The project targets a self-contained public reference-app repository. The
remaining gates are the owner's license choice, confirmation of a private
vulnerability reporting path, a successful hosted Docker build, full clean-checkout
setup with the pinned Node.js runtime, and manual libvips setup checks on macOS and
Debian/Ubuntu. The static setup review matched `.ruby-version`/`.nvmrc`,
`bin/setup`, CI and Docker guidance; the development Rails/Vite listeners bind
explicitly to `127.0.0.1`. A local production Docker build later passed using
Node 24.21.0 and completed a clean Vite build, but this does not provide hosted CI
or full `bin/setup` evidence. The host Node remains 24.14.0 while the repository
pins 24.21.0.

An isolated `bin/vite dev` launch resolved the listener address to
`127.0.0.1:3036`, then the OS sandbox rejected opening the socket (`EPERM`). A
later loopback `bin/dev` launch reached Rails while the development DB still had
the evaluation-batch migration pending; that additive migration has since been
applied and the development schema is current. Manual browser checks used Rails
test mode with a temporary SQLite database and test queue adapter; they covered
Project creation, Agent definition save, Run queueing and the Runtime panel at a
390px viewport, but not worker execution or provider output. An unprivileged
system-test attempt also stopped before assertions because Selenium could not bind
`127.0.0.1:9514`; the later loopback-permitted run passed (2 runs, 9 assertions).
Hosted CI's system-test result remains pending. The prior Docker socket denial was
resolved by the local production image build recorded above.

## Known implementation gap

- [x] Add a unified local lifecycle event catalog for `ai.run`, `ai.attempt`,
      `ai.agent`, `ai.tool`, `ai.approval` and `ai.artifact`; the current
      implementation is deliberately application-level and metadata-only.
- [x] Add a per-Run event JSON download with stable chronological ordering,
      related record IDs, redaction, a 100-event limit and explicit omissions.
      It excludes Chat/snapshot/Artifact records and freezes an event ID watermark.
- [ ] Add provider-native tracing/metrics or historical backfill;
      these are not implied by the local `LifecycleEvent` timeline or export.

## Explicitly deferred

- [x] M3 code-defined tools, tool-call inspection, and approval/denial continuation.
- [ ] M3 parallel tool calls and deeper provider/tool compatibility dogfooding;
      the explicit local path and multiple-call recorder are verified, but live
      provider behavior is still not accepted.
- [ ] M4 cross-provider embedding compatibility, batch-failure semantics and a
      measured corpus/query-scale record before promoting the sqlite-vector
      adapter to the default; the application-side adapter remains the default
      by design.
- [ ] Package or provision the sqlite-vector binary per platform (Linux VPS,
      Kamal, Docker, CI); the spike relies on a manually downloaded binary that
      is deliberately not committed.
- [ ] M4 provider embeddings for providers other than OpenRouter; only one free
      OpenRouter embedding model has been dogfooded so far.
- [ ] M4 rerank breadth: other rerank providers, `top_n` on larger candidate
      sets, and a persisted rerank record for cost/latency comparison.
- [ ] M4 provider file references: track provider-side file id, lifecycle and
      expiry when a file is uploaded to a provider for OCR or later use.
- [ ] M4 real OCR dogfood against a configured OCR provider (Cohere `parse-v5.0`
      or Mistral OCR) and page/offset level provenance per chunk.
- [ ] M5 remaining work: verify live provider web search and a multi-step Agent
      task, then inspect provider-backed output, citations and approval
      continuation. Local worker crash/replay and provider-free browser review
      of report, citation, approval, cancellation and narrow layouts are covered.
- [x] M6 speech and fake-provider image/video/transcription paths locally verified;
      stale-work no-replay recovery is covered; real provider acceptance and
      durable video resumption remain open.
- [x] M7 immutable cross-model comparison summaries, individual evaluation and
      a capability-gated provider-batch path implemented with deterministic
      fake-provider coverage; optional rubric judge queue/recovery paths are also
      covered locally; live provider acceptance and judge quality review remain open.
- [x] M8 redacted per-Run JSON export, append-only candidate reports and Markdown
      issue drafts implemented and candidate-path coverage added; representative
      data review and deployment readiness remain open.

The sequence is active: M6 speech/image/video/transcription have local fake-provider
test evidence; M5 live provider evidence remains open and does not
block local work. M7 comparison and Batch slices have local evidence; M8 export
and candidate-report slices remain partial pending representative review and
release acceptance. These are slices, not completion claims.
