# TODO — M0/M1/M2/M3 core complete; M4 rerank/documents implemented; provider breadth and page-level evidence pending

> Current correction (2026-09-18): M4 rerank plus file upload/local extraction/provenance
> are implemented and locally verified. Provider file references, real OCR dogfood,
> page-level provenance, and broader cross-provider compatibility remain partial or deferred.

## Human understanding layer

- [x] Establish the internal `docs/` current-reality layer with a readable system guide,
      architecture diagrams, operations notes, and changelog.
- [x] Align the internal docs with the canonical Specs baseline without rewriting the
      pulled Specs; document the two systems and their different purposes.
- [x] Connect the Projects list/create page to the Project-boundary explanation, including
      the Rails form, slug identity, resource ownership, and source-anchored evidence.
- [ ] For every future comprehension-impacting change, update the affected internal docs,
      diagrams, status/evidence labels, and changelog in the same thematic work unit.

## Foundation

- [x] Initialize the Rails 8.1.3.1 app with SQLite, Tailwind, Vite, Hotwire,
      and the local Solid Queue baseline.
- [x] Lock Ruby 4.0.2 and RubyLLM 2.0.0.rc4 in the project.
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
without claiming the complete M4 Specs gate. It did not yet create embedding
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
Specs gate.

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
- [x] Run extraction in `DocumentExtractionJob` (Active Job, per the Specs) and
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

## Known implementation gap

- [x] Add a unified local lifecycle event catalog for `ai.run`, `ai.attempt`,
      `ai.tool`, `ai.approval` and `ai.artifact`; the current implementation is
      deliberately application-level and metadata-only.
- [ ] Add provider-native tracing/metrics, event export or historical backfill;
      these are not implied by the local `LifecycleEvent` timeline.

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
- [ ] M5 agents, durable research, and provider-hosted/server tools.
- [ ] M6-M8 media, batch/evals, exports, deployment, and
      public-reference polish.
