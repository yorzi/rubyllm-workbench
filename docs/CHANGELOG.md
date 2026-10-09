# Changelog

Notable changes, newest first. Evidence for each capability lives in
[CAPABILITIES.md](CAPABILITIES.md). The detailed bilingual working notes kept
before the public-release cleanup are preserved in git history (see this file
at commit `8bd33c8`), together with the milestone gate records formerly in
`TODO.md` (commit `e9c9faf`).

## Unreleased

- Update Selenium WebDriver to 4.50.0 and its RubyZip dependency to 3.7.0
  ([#9](https://github.com/yorzi/rubyllm-workbench/pull/9)).
- Update image_processing to 2.2.0 while retaining lazy libvips loading
  ([#10](https://github.com/yorzi/rubyllm-workbench/pull/10)).
- Update Vite to 8.3.3 and vite-plugin-ruby to 5.2.5
  ([#11](https://github.com/yorzi/rubyllm-workbench/pull/11),
  [#12](https://github.com/yorzi/rubyllm-workbench/pull/12)).

## v0.1.0 (2026-10-09)

First public release of the Rails 8.1.4 / RubyLLM 2.1.0 reference app. See
[release notes](releases/v0.1.0.md) for installation, included workflows,
upgrade instructions and experimental/manual boundaries. The dated
engineering entries below describe the changes included in this release.

- Filter search questions, review/draft prose and serialized user input from
  request logs; preserve useful model and execution identifiers.
- Wait for the actual source-answer Turbo redirect on slow responses, with a
  controlled-delay browser regression.
- Add Linux clean-install checks with and without libvips, plus production
  container and isolated read-only demo runtime checks.
- Enable private vulnerability reporting and replace the obsolete RubyLLM 2.0
  draft release description with current, version-scoped evidence.

## Included work: owned retrieval and native saved-answer evaluation (2026-10-09)

- Attribute one-shot embedding/query/rerank usage with RubyLLM native owners;
  stop copying batch costs into chunk vectors. Export owner ledger rows and
  deduplicate live report accounting against Attempt mirrors.
- Extend source answers to semantic/hybrid and explicit-provider rerank;
  freeze corpus/vector revisions, resolve retrieval outside transactions,
  retain degradation and fence cancellation at native transport boundaries.
- Add native `RubyLLM::Evaluation` assertions and one-request Agent reviewer,
  plus supported typed `RubyLLM::Judge` decision measurements. Reuse saved
  answers in independent evaluation Runs and reports without replay/cost reuse.
- Add evaluation UI, recovery, offline HTTP contracts and browser coverage.
  Correct invalid ranking indices and inconsistent vector dimensions.
- Record the version-scoped missing-usage/default-zero upstream candidate;
  normalize ambiguous costs conservatively without changing vendor code.
- Use OpenRouter Fish for current TTS; optional local TTS no longer blocks work.
  Actual verification and live/manual boundaries are in `CAPABILITIES.md`.

## Included work: Rails source answers (2026-10-09)

- Add an original MIT Mini Notes source corpus, versioned cases and an
  idempotent import command that stops on edited source/chunk ownership.
- Add `grounded_answer` Runs: bounded lexical snapshots, one native RubyLLM
  structured request, exact-quote citation validation, source/model/history
  drift rejection and local refusal without a provider Attempt.
- Add queue rejection handling, duplicate-delivery guards, cancellation
  fencing and no-replay interrupted-worker recovery. Fix a cancellation race
  reproduced during review before accepting the new flow.
- Add source inspection and citation links, focused free-provider acceptance
  and desktop/mobile browser coverage. Integration evidence and manual
  quality boundaries are in `CAPABILITIES.md`.

## Included work: shared AI policy and free TTS acceptance (2026-10-09)

- Adopt the contributor's AI usage guide at `docs/AI_USAGE_GUIDE.md`, with
  shared `AGENTS.md`/`CLAUDE.md` instructions. Correct RSpec assumptions to the
  existing Rails Minitest suite, unsafe inline-key examples and proposed
  environment variables that do not configure the app.
- Add WebMock to the test bundle. Ordinary tests block external Ruby HTTP;
  explicit serial live profiles allow the official OpenRouter HTTPS host only.
- Add separate free TTS raw REST and native RubyLLM/Rails probes, with speech
  catalog/short-input guards, zero retries and no paid fallback. Retain pending
  local TTS acceptance separately. Record actual evidence in `CAPABILITIES.md`.
- Keep missing tokens unknown and add safe profile/timing/HTTP metadata to
  live reports. Integration routing also forbids client fallback without
  imposing free-model prices on explicitly authorized paid acceptance.

## Included work: RubyLLM 2.1 and showcase review (2026-10-08)

### Changed

- Upgrade RubyLLM to an exact 2.1.0 pin and add its Rails schema migration;
  Rails 8.1.4 remains the latest stable version. Add environment mappings for
  Hetzner and TypeSafe without enabling either provider.
- Remove the released OpenRouter streaming and Batch index patches. Batch
  collection now uses public APIs and requires the frozen chat manifest.
- Preserve serialized usage totals as `recorded_cost` with distinct provenance
  in Runs, evaluation metrics, exports and live-report output. Avoid repricing
  historical requests from current metadata.

### Added

- Source-anchored Agent and evaluation learning panels with compact execution
  maps, plus a Knowledge retrieval map and a mobile browser regression.
- Ten-minute showcase guide and a skills-to-code/test map, an updated P0–P2
  development plan, dated upgrade review and public-release checklist.
- Blank `.env.example`, with explicit Foreman versus standalone Rails loading
  instructions. Historical 2.0 live evidence remains labelled separately.

### Fixed

- Docker now excludes installation-local encrypted Rails credentials as well
  as their keys and environment files.
- Correct copy that implied Knowledge retrieval created Runs.
- Mobile navigation collapses above the feature; learning links reveal the
  explanation below it. Synthetic Run labels appear before the metrics.
- Update vulnerable `source-map-js` 1.2.1 to 1.2.2 and Brakeman to 8.1.0.
- Live reports sum known cost categories and do not label the subtotal an
  upper bound when some costs are unknown.

## Included work: public release preparation (2026-09-28)

### Added

- Opt-in live provider dogfood suite (`test/live/provider_dogfood_test.rb`) and
  `bin/dogfood`: eight scenarios through the real controllers, jobs and
  services. First live acceptance on RubyLLM 2.0.0 passed for chat, structured
  output, tool approval, an Agent with hosted web search, embeddings with
  rerank, an evaluation comparison with a rubric judge, speech, transcription
  and image generation.
- Synthetic demo tour (`bin/rails workbench:demo`) for exploring without
  provider keys.
- Optional provider voice for speech Runs.
- `provider_tool_usage` on Chat and Agent Runs for providers that report
  hosted tool use only as usage counters (OpenRouter), shown in the Run
  inspector.
- `Ai::RubyLlmInternals` and contract tests for every private RubyLLM seam.
- Experimental badges on media, the rubric judge and upstream gap reports.

### Fixed

- Streamed OpenRouter responses lost citations and server tool usage (RubyLLM
  2.0.0 bug), worked around in `lib/ruby_llm_workarounds/` until upstream
  ships a fix.
- Attempts never stored their finish reason.
- An Agent whose model exhausted its output budget succeeded with an empty
  report; it now fails with the cause.
- Hosted CI: the test job never installed npm packages, so Vite could not
  build.
- Declaring `ruby-vips` made libvips mandatory at boot; it is optional again.

### Changed

- Rails 8.1.4; image_processing 2.1 (remote-code-execution fixes); vite 8.3.1,
  vite-plugin-ruby 5.2.4, solid_cable 4.1.0; GitHub Actions moved to current
  majors.
- `Run` split into `Run::AgentExecutionLease` and `Run::ToolApprovalClosure`;
  the Agent lease heartbeat and transient database error rules extracted from
  `AgentRunJob`.
- Documentation rewritten in English and condensed; `TODO.md` replaced by
  [ROADMAP.md](../ROADMAP.md).

## 2026-09-27: Run event export

- Per-Run events JSON download: latest 100 lifecycle events, chronological,
  with related record IDs, redaction and explicit omissions.
- Export budget regressions for nested inputs, escaped bytes, Unicode text and
  oversized issue drafts.

## 2026-09-26: Rails 8.1.4 and RubyLLM Batch integrity

- Declared the `csv` gem, which Ruby 4 no longer bundles.
- Reproduction exports now select the newest messages and return them in
  chronological order.
- Evaluation Batch collection rejects malformed RubyLLM result indices before
  delivery (fixed upstream later in crmne/ruby_llm#993).
- See [UPGRADE_REVIEW_2026-09-26.md](UPGRADE_REVIEW_2026-09-26.md).

## 2026-09-21: Agent hardening, evaluation review and export budgets

- M5.5-M5.7: provider-hosted (Responses/MCP) tool approvals; failed Runs close
  pending approvals and mark approved remote calls without a result as
  outcome-unknown; queued Chat context is frozen and checked for drift.
- Local-tool Agents require an exact `function_calling` registry entry on
  save, enqueue and restore.
- M7: bounded case tags, rubric criteria with append-only human ratings, case
  attachments with format prechecks, and an optional rubric judge with prompt
  isolation.
- M8: signed-URL redaction and total size budgets for reproduction exports.
- Capability matrix (`docs/CAPABILITIES.md`) introduced.

## 2026-09-20: Saved Agents, media, evaluations and export

- M5.1: opt-in provider web search per Chat Run with citation Artifacts.
- M5.2: revisioned Agent definitions and dedicated Agent Runs with a durable
  outbox, expiring generation-fenced leases, crash recovery and cancellation.
- M5.3: research report Artifacts; M5.4: cancellation closes pending
  approvals.
- M6: speech, image, video and transcription Runs with stale-work recovery that
  never replays provider work.
- M7: revisioned evaluation datasets, cross-model comparisons, outcome metrics
  and a capability-gated provider Batch path.
- M8: redacted reproduction export and append-only upstream candidate reports.
- Pinned RubyLLM 2.0.0 stable; open-source setup, security policy and
  loopback-only local servers.

## 2026-09-18/19: RubyLLM 2.0 alignment, documents and learning layer

- Adopted RubyLLM 2.0 instrumentation through `Ai::RubyLlmInstrumentation`.
- Knowledge file sources with local extraction or OCR and provenance
  Artifacts.
- In-page "How this works" panels backed by a source-anchored topic registry.

## 2026-09-17: Embeddings, vector adapter and rerank

- Provider embeddings with lexical, semantic and hybrid retrieval evidence and
  explicit degradation.
- Opt-in sqlite-vector adapter behind the vector store interface.
- Optional compatible-provider rerank that keeps pre-rank evidence.

## 2026-09-16: Tools, lifecycle events and local Knowledge

- M3: code-defined tools, durable approvals and tool-call inspection.
- Lifecycle event catalog and Run timeline.
- Opt-in parallel tool-call policy with safe sequential fallback.
- M4 foundation: local text collections, deterministic chunks and lexical
  retrieval.

## M0-M2: foundation, Chat and structured comparison

- Rails 8.1 app with SQLite, Tailwind, Vite, Hotwire and Solid Queue.
- Projects, model explorer, persisted streaming Chats, Run/Attempt records
  with usage, cost and latency, and global Run history.
- Structured Experiments compared across models with one Run per target and
  schema-validated JSON Artifacts.
