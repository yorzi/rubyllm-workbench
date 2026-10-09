# Capability matrix

Updated: 2026-10-09 · Rails 8.1.4 · RubyLLM 2.1.0

This is the single place where Workbench records **what each operation
admits** and **what evidence exists for it**. Other documents link here rather
than repeating test counts or dogfood results.

Two kinds of evidence are kept apart:

- **Local**: deterministic tests with fake providers. They prove Workbench's
  own behavior (records, states, recovery, redaction), not provider
  compatibility.
- **Live**: a real provider request, recorded with its date, model and cost.

Current 2.1.0 flow acceptance is dated 2026-10-09 below. Rows explicitly marked
historical retain the RubyLLM 2.0.0 record. New framework APIs do not
automatically add Workbench features or provider acceptance.

RubyLLM registry metadata is only an admission hint. A model appearing in a
picker means its registry entry passes the rule below and its provider is
configured. It does not prove that a provider account, model revision, plan or
region will accept the request.

## Operations

| Operation | Admission rule | Local evidence | Live evidence (version/date stated) |
| --- | --- | --- | --- |
| Chat (streaming) | Any configured chat model in the RubyLLM registry. | Run/Attempt lifecycle, streaming, frozen context, drift rejection, queue rejection, cancellation. | Passed on 2.1, 2026-10-09: `liquid/lfm-2.5-2.6b:free`, persisted reply and first-output timing. |
| Structured output | Configured model declaring `structured_output`; batch-suffixed models excluded. | Schema validation, JSON Artifacts, comparison executions. | Passed on 2.1, 2026-10-09: `liquid/lfm-2.5-2.6b:free`, valid schema and JSON Artifact. No quality claim. |
| Local tools with approval | Tool enabled for the Project. Saved Agents with local tools require the exact provider/model registry entry to explicitly declare `function_calling`, checked on save, on enqueue and on every worker restore. | Approval, denial, expiry, cancellation, failed-Run closure, unknown remote outcomes, parallel-call policy. | Passed on 2.1, 2026-10-09: `save_run_note` approval, continuation and report on `liquid/lfm-2.5-2.6b:free`. Parallel calls remain manual. |
| Provider web search | `web_search` is an allowlisted RubyLLM provider tool. There is no reliable Workbench model-level web-search capability gate; the provider may reject the tool or the model may not use it. | Snapshotting, citations, usage-only tool accounting; native 2.1 streaming regression. | Passed on 2.0 in an Agent Run on `openai/gpt-5-nano`: search counted, citation stored, using the then-required patch. 2.1 live check pending. |
| Saved Agents | As for local tools; provider tools are outside the local-tool gate. | Durable outbox, execution lease and generation fencing, crash/replay drill, cancellation race, empty-answer guard, research report. | Passed on 2.1, 2026-10-09: two-step Agent (`project_snapshot`, final answer/report) on `liquid/lfm-2.5-2.6b:free`. Hosted search remains historical 2.0 evidence. |
| Knowledge embeddings | RubyLLM embedding-model registry plus provider configuration. | Chunking, checksums, stale-vector skipping, vector adapters, lexical/semantic/hybrid retrieval, explicit degradation, selected-provider preservation, native collection/query ownership and no copied batch charge. | Passed on 2.1, 2026-10-09: `liquid/lfm-2.5-embedding-350m:free`, 3 chunks, 1,024 dimensions, semantic and hybrid requests. No retrieval-quality claim. |
| Knowledge rerank | Registry model whose output modality includes `rerank`, plus configuration. | Pre/post rank kept alongside unchanged retrieval evidence. | Passed on 2.1, 2026-10-09: `nvidia/llama-nemotron-rerank-vl-1b-v2:free`, applied ranking with 3 results. No ranking-quality claim. |
| Grounded source answers | Configured interactive structured-output model; lexical/semantic/hybrid, optional explicit rerank, at most 8 × 800-character chunks. | Original MIT corpus/import, frozen corpus/vector revisions and text/offsets, independently owned retrieval/answer Attempts, actual HTTP contract, exact quotes, explicit degradation, refusal, cancellation/recovery and responsive inspector/map. | Passed for one hybrid/reranked title case on 2.1, 2026-10-09, including linked native Evaluation. The complete five-case group remains partial/manual because earlier untrusted-source outputs violated structure/citation rules. No semantic-quality claim. |
| Document OCR | Model declares `ocr` and its provider is configured. | Local extraction and provenance Artifacts. | Not tested: no OCR model is available through OpenRouter's registry entries. |
| Evaluation comparison | 2-5 configured models declaring `structured_output`. | Frozen revision and Experiment snapshot, per-case Runs, outcome metrics, queue rejection, recovery. | Partial on 2.1, 2026-10-09: Liquid and Nvidia each returned valid case output in separate invocations; no complete two-model/one-case invocation passed. Dots schema failure, Apodex provider error and Liquid rate limiting remain visible. Historical 2.0 comparison is below. |
| Native saved-answer Evaluation | Exact versioned case question on a successful imported-case answer. Local assertions or explicitly selected configured structured reviewer. | Public RubyLLM::Evaluation + Agent reviewer, one HTTP request for two criteria, immutable independent snapshot/checksum, no answer replay/cost duplication, native result vs transport outcome, owner ledger, cancellation/recovery/UI. | Passed on 2.1, 2026-10-09: title-validation answer, native assertions and native Nvidia free reviewer completed together; 5 total workflow POSTs. No quality/calibration claim. |
| Native typed Judge | Configured registry judgment model and supported decision protocol; OpenRouter chat is excluded. | Public RubyLLM::Judge through native Evaluation, TypeSafe one-POST HTTP fixture, probability measurements without an invented threshold, independent owner usage. | Manual: no supported typed-provider live call or calibration performed. Free OpenRouter reviewer is a different API. |
| Rubric judge (experimental) | Optional; runs only after a successful case output. | Prompt isolation (expected output, tags and attachments are never sent), separate Run/Attempt/cost, recovery, late-response fencing. | Partial on 2.1, 2026-10-09: Liquid judgments completed for successful Liquid/Nvidia outputs; the complete intended pair is still pending. Uncalibrated; never changes exact-match results. |
| Human reviews | Completed case outputs; ratings from a fixed allowlist. | Append-only reviews and per-criterion ratings. | Not applicable (no provider). |
| Case attachments | Up to 5 files per case, 50 per revision, 10 MB each, 50 MB per revision. | Format prechecks (PDF header, JPEG/PNG signatures, JSON, CSV, UTF-8 text), revision ownership, purge on Project deletion. Excluded from every provider prompt. | Not applicable. The checks do not fully decode files or scan for malware; there is no lifetime storage cap. |
| Provider Batch evaluation | Model declares `structured_output` and `batch`, and the provider reports `batches?`; one provider per execution. | Submission, refresh, ordered reconciliation, malformed-index rejection. | Not tested. No live provider Batch compatibility is claimed. |
| Speech generation (experimental) | Model declares `speech_generation`; optional provider voice identifier. | Audio Artifacts, storage failure, recovery, cancellation. | Passed on 2.1, 2026-10-09: free Fish raw REST and RubyLLM/Rails paths independently accepted, one POST each. MP3/attachment/playback controls verified; quality/listening remains manual. Current speech uses this OpenRouter route; local TTS is an optional future adapter and does not block development. |
| Audio transcription (experimental) | Model declares `transcription`. | Source-audio and transcript Artifacts, blank-transcript handling. | Manual on 2.1; historical 2.0 success used `mistralai/voxtral-mini-3b-2507`. |
| Image generation (experimental) | Model declares `image_generation`. | Image Artifacts, storage failure, late-response fencing. | Manual on 2.1; historical 2.0 success used `black-forest-labs/flux.2-klein-4b`, reported $0.014. |
| Video generation (experimental) | Model type is `video` with video output. | Submission, polling, provider job reference in the timeline. | Not tested. Workbench cannot durably restore a VideoJob or link its 2.1 job-ledger cost to the Attempt yet. |
| Run reproduction and event export | Explicit per-Run download; no provider request. | Schema v2 budgets (512 KiB, 100,000 characters, latest 100 messages, bounded nesting), redaction, omission reporting. | Not applicable. Redaction is best-effort; review a real Run's export before sharing it. |
| Upstream gap reports (experimental) | Manual classification of a Run. | Append-only candidates, redacted Markdown issue drafts. | Not applicable. Drafts need a manual privacy review. |

## Live dogfood record

### 2026-10-09 — Rails source answers, bounded free attempts

Four focused invocations selected `liquid/lfm-2.5-2.6b:free` (twice) and
`nvidia/nemotron-3-super-120b-a12b:free` (twice), rechecking public catalog and
registry prices, disabling retries and model fallback. They admitted **7 POST
requests** in total (2, 2, 1, 2). Known Run ledger cost was $0; that subtotal
does not establish an account invoice or independently identify the upstream.

- Normal title-validation questions produced stored answers with valid
  snapshot IDs and exact quotes on both selected routes. One Nvidia response
  was a consistent refusal, also stored correctly. Initially the harness
  demanded an answer; it now accepts valid refusals in accordance with the
  owner's integration-only acceptance scope. Expected facts remain manual.
- The misleading `token_dump` source did not produce a complete accepted case
  group: Liquid returned inconsistent output and Nvidia returned an invalid
  citation. The first Liquid result also exposed an unnecessary empty-reason
  constraint; answered reasons now remain raw metadata, while every displayed
  claim still needs a valid exact quote. Refusal consistency and quote checks
  remain strict. No invalid response was relabelled as a valid Artifact.
- No tools, hosted search or paid fallback were admitted. These responses do
  not prove comprehensive prompt-injection resistance or a gem defect.
- Later cases in the failed live scenario did not execute. The zero-request
  empty-evidence path passed through the real controller/job locally and in
  Selenium. The complete live group remains an explicit manual rerun; stop
  spending requests on repeated low-quality output for this iteration.
- Ignored reports: `tmp/dogfood/20261009T060429Z.jsonl`,
  `20261009T060936Z.jsonl`, `20261009T061100Z.jsonl`, and
  `20261009T061347Z.jsonl`. Test database records rolled back.

The latest local schema/state/quote contract passed offline tests. Live output
quality remains variable, and partial invocations are not combined into a
complete case-group result.

### 2026-10-09 — owned retrieval and native saved-answer evaluation

The current implementation extends source answers to semantic/hybrid and
explicit-provider rerank. Document batches and interactive search own native
`KnowledgeCollection` usage rows; query/rerank for an answer own its Attempts.
A batch is billed once rather than copied onto every chunk. Native retries
retain each physical request exactly once; unknown failure cost is retained.
No historical per-chunk data is retroactively converted into owned billing.

Native `RubyLLM::Evaluation` returns the saved answer from `perform`; it never
asks its generating model again. Local assertions make no API call. One Agent
reviewer request returns both criteria; a typed `RubyLLM::Judge` request is a
separate supported protocol. Native reports/results and application Run state
remain separate: a completed evaluation can report failed or measured checks.
Original answer cost is not included in evaluation cost.

Offline HTTP contracts exercise public APIs, actual native owner ledgers,
503→200 retry deduplication, quoted provenance, malformed judgments, absent
usage, source/vector drift, inconsistent vector dimensions, cancellation
before transport/during response, recovery, queue rejection and readonly demo.
The missing-usage/default-cache-zero behavior is a version-scoped RubyLLM
candidate in [UPSTREAM_ISSUES.md](UPSTREAM_ISSUES.md), not yet verified on main.
Native raw zero remains; normalized application cost can be unknown.

The new linked free scenario plans one document batch, query embedding,
rerank, answer and reviewer (**5 POSTs**), plus zero-request assertions.
Live evidence, in separate bounded invocations:

- Catalog timeout: `20261009T065656Z.jsonl`; preflight skipped, **0 POSTs**.
- Liquid answer route: `20261009T070620Z.jsonl`; batch/query/rerank succeeded,
  answer returned `RubyLLM::RateLimitError`; **4 POSTs**, failed answer Run,
  no native evaluation request. HTTP failure status is unavailable in the
  notification; do not invent a status code.
- Explicit Nvidia answer/reviewer route: `20261009T070810Z.jsonl`;
  **5 POSTs**, all HTTP 200, 29 assertions. `title-validation` produced a
  validated cited answer, followed by passed native assertions and passed
  reviewer results. Three succeeded Runs; no replay or added original cost.
  Models: `liquid/lfm-2.5-embedding-350m:free`,
  `nvidia/llama-nemotron-rerank-vl-1b-v2:free`,
  `nvidia/nemotron-3-super-120b-a12b:free`. Document batch owner had one
  ledger row, query/rerank/reviewer had separate Attempt owners; generation's
  Chat ledger was mirrored once. Known recorded subtotal **USD 0**, 7,932
  aggregate input tokens; aggregate output tokens remain unknown because
  embedding/rerank omit that field. Attributed cost coverage is complete,
  but this is not independent invoice/upstream-model verification.

Total real transport in this slice: **9 verified-free POSTs**, no paid route,
no automatic model fallback. Reports are ignored local files under
`tmp/dogfood/`; test database records rolled back. The passing invocation
stands alone; partial attempts are not combined to claim a full pass.
The complete five-case group, typed Judge live acceptance, reviewer
calibration and model/retrieval quality are separate boundaries.

OpenRouter Fish is the current TTS route; its independent earlier acceptance
below remains applicable to the unchanged speech implementation. A local TTS
API is not required or awaited for current development.

### 2026-10-09 — free TTS, independent REST and RubyLLM paths

Requested model: `fish-audio/s2.1-pro-free:free`; input: a fixed 22-character
synthetic phrase. Both commands rechecked the current speech catalog's zero
prices, disabled retries and used no paid fallback. No voice was supplied;
Fish's provider default accepted the request. This does not establish a
portable default voice for other models.

- Raw REST: HTTP 200, `audio/mpeg`, MP3 signature, 27,166 bytes. `ffprobe`
  decoded it as MP3, 44,100 Hz mono, 1.697875 seconds. The report records the
  generation ID and SHA256; the adapter was not involved.
- RubyLLM/Rails: one successful POST, `RubyLLM::Speech`, successful Speech
  Run, attached audio Artifact (31,346 bytes), matching SHA256 and inspector
  playback/download controls. 16 assertions passed; test records rolled back.
  This is rendered-control evidence, not a human listening or browser autoplay
  test. The raw and adapter audio bytes need not be identical.
- Total live synthesis: **2 POST requests**, both using the verified free ID.
  The sandbox-only attempt failed DNS before any synthesis POST and is kept
  separate from provider compatibility evidence.
- Neither speech response supplied billed usage/cost or independently exposed
  the actual upstream/model. Cost and tokens remain **unknown**; zero catalog
  prices and the displayed known-cost subtotal do not establish an invoice.
  The report correction now preserves missing tokens as unknown rather than 0.
- Ignored local reports: `tmp/dogfood/20261009T053308Z-raw-tts.json` and
  `tmp/dogfood/20261009T053410Z.jsonl`; the raw MP3 stays beside its report.

This accepts RubyLLM → OpenRouter → the selected Fish route on this date.
It does not certify the planned local TTS service, native Fish provider,
voice quality or future capacity. No task-owned service was started.

### 2026-10-09 — RubyLLM 2.1, free integration acceptance

Five core scenarios passed in the initial serial run: streaming, structured
output, tool approval/continuation, Knowledge embedding/retrieval/rerank and a
saved Agent with a local tool. The sixth, a two-model/one-case comparison with
two intended judgments, remains partial after bounded diagnostics. Successful
case outputs and judgments across different invocations do not make that
comparison pass. Four separate scenarios were intentionally not called:
hosted search, transcription, image and pending local TTS.

Five harness invocations admitted **23 POST requests** in total (13, 2, 2, 3,
3). Selected IDs were explicit OpenRouter `:free` entries with zero known
catalog prices. Known Run ledger costs sum to **$0**; this is recorded ledger
evidence, not a provider invoice. One-shot embedding/query/rerank cost and
token coverage remain unknown and are excluded from that subtotal. There
were no paid fallback or cloud TTS requests. Reports are local ignored files
under `tmp/dogfood/20261009*.jsonl`; they contain transient test Run IDs, and
transactions roll back rather than adding live examples to the demo.

Corrections made during this acceptance:

- Embedding catalog checks and query embedding now preserve the selected
  provider instead of resolving a same-ID model under another provider.
- Retrieval counts/candidates exclude another provider's same-ID vectors
  after partial re-embedding. The optional native SQLite partition is rebuilt
  from fresh candidates, so same-count vector replacement and filtering before
  top-k do not reuse stale rows. This correction has local regression evidence;
  the live Knowledge check used the default application-cosine adapter.
- Rails notification exceptions now record failed provider lifecycle events.
  Rejected requests previously could be labelled succeeded/received; a real
  notification-bus regression verifies failure classification without an API.
- The suite requires every scheduled case and intended judgment to complete;
  partial output no longer passes a comparison. Quality/exact-match scores
  are outside this integration acceptance.
- Cost reports separate unknown one-shot usage from known Run costs, include
  early-failed Runs and requested models, and save failure classes rather than
  generated content. Free gates, output caps and request ceilings have offline
  regressions.

Dots returned schema-invalid output under the small budget; Apodex returned a
provider error. A trial reasoning-disable parameter was rejected because the
Liquid endpoint mandates reasoning; that harness setting was removed. The
last comparison recorded a Liquid rate limit and a successful Nvidia case
plus judgment. Automatic retries stay off. Follow the
[manual acceptance list](OPERATIONS.md#remaining-manual-acceptance) when free
capacity is available; no model or retrieval quality is certified.
Framework findings and contribution candidates are tracked separately in
[UPSTREAM_ISSUES.md](UPSTREAM_ISSUES.md); application defects and provider
failures do not count as upstream bugs.

### Historical 2026-09-28 — RubyLLM 2.0

Historical record: Rails 8.1.4, RubyLLM 2.0.0. No live provider request was
made during the 2026-10-08 upgrade review.

The 2026-09-28 run used `bin/dogfood --paid` (see
[operations](OPERATIONS.md#live-provider-dogfood)) against OpenRouter. Every
scenario drives the real controllers, jobs and services and asserts on the
durable records. Each scenario passed at least once that day; free models
intermittently answered "No endpoints found" or "Service temporarily
overloaded", so a single run is not guaranteed green. Total OpenRouter spend
for the session, including diagnostics, was **$0.33**.

Earlier live checks (2026-09-16/17: chat, structured output, embeddings,
rerank) predate the stable 2.0.0 pin and are superseded by this record.

### Defects the live run found

All are fixed and covered by tests.

- **Speech Runs could not choose a voice.** Some TTS models have no default
  voice. Speech Runs now accept an optional, validated voice identifier.
- **Hosted tool use was invisible for OpenRouter.** OpenRouter reports hosted
  search only as usage counters. Runs now record `provider_tool_usage`.
- **Streamed OpenRouter responses lost citations** (RubyLLM 2.0.0 bug).
  OpenRouter's streaming `build_chunk` override omits `citations:` and
  `server_tool_use:`. Reproduce with
  `bundle exec ruby script/diagnostics/ruby_llm_openrouter_stream_citations.rb`.
  A self-disabling workaround restored both in that run. RubyLLM 2.1 fixes
  the parser; Workbench removed the patch and retains a native regression.
- **Attempts never stored a finish reason**, and an Agent whose reasoning
  model spent its output budget finished "successfully" with an empty report.
  Attempts now record `finish_reason`, and such a Run fails with the cause.

### Known provider and registry caveats

- RubyLLM 2.0.0's bundled registry lists models OpenRouter no longer serves
  (for example `nex-agi/*:free`) and understates others (it marks
  `google/gemma-4-31b-it:free` as lacking structured output). Pickers can
  therefore offer models that fail at request time.
- The old run repriced persisted usage from token metadata, so search costs
  could be understated. New Runs preserve the request-time ledger total as
  `recorded`, including fees when RubyLLM retained them. The ledger does not
  preserve original reported/estimated provenance; missing fees and unknown
  costs cannot be invented, and old Attempts are not backfilled.
- Free models are rate-limited and change availability without notice.

## RubyLLM workarounds

Both production patches were removed on the 2.1.0 pin after provider-free
verification of the released fixes.

| Removed patch | Current implementation | Regression |
| --- | --- | --- |
| Private Batch index-validation override | RubyLLM validates indices; `Ai::EvaluationBatchResults` checks the public chat manifest against frozen cases before collection. | Batch result/workflow tests and `script/diagnostics/ruby_llm_batch_indices.rb`. |
| OpenRouter streaming parser prepend | Native RubyLLM 2.1 chunks preserve citations, tool usage and reported cost. | `test/lib/openrouter_stream_evidence_test.rb` and the diagnostic script. |

`Ai::RubyLlmInternals` lists every private RubyLLM seam Workbench relies on, and
`test/services/ai/ruby_llm_internals_test.rb` fails when one moves.

## Verification snapshot

2026-10-09 open-source preflight, source baseline `8dbd787`, plus the request
privacy correction below:

| Check | Result |
| --- | --- |
| Tracked source / history secrets | Redacted Gitleaks: tracked Git archive clean (1.88 MB); all-ref raw history clean (64 commits, with textconv/external diff disabled) |
| Rails key / historical credentials | Exact local master-key bytes absent from all 1,172 reachable blobs; no historical key filename found. An encrypted credentials blob remains in old history; this is not evidence of plaintext exposure or a check of unknown older keys. |
| Dependency advisories | Fresh Ruby advisory checkout `b6604fa6b54cb6e9a140e3a12d1f1d15b695330c`: no known gem vulnerabilities; live npm audit: 0 vulnerabilities. No dependency was changed. |
| Licence / documentation / images | Root and original case corpus MIT licences present; 25 tracked Markdown files have no missing local targets; synthetic screenshot reviewed; tracked PNGs have no text/EXIF chunks |
| Credential-free source exercise | Fresh tracked archive, Ruby 4.0.2, reused installed gems, all external HTTP blocked: database preparation, 9 synthetic Runs, 5-source case import, separate read-only demo snapshot passed. Rack requests rejected Active Storage and Cable; provider configuration empty and jobs/mutations denied. No server, fresh dependency download or frontend build. |
| Request privacy correction | Search `q`, questions, review/draft text and serialized user-authored inputs now filtered; 3 request-level tests, 29 assertions, 0 failures/errors; focused RuboCop clean. This does not erase existing logs. |
| Remote / release boundary | GitHub repository private; remote main `83492c6` passed CI on 2026-09-28 and does not cover this candidate. Docker daemon unavailable; current Linux/container/runtime and outside-account acceptance remain pending. |

GitHub private vulnerability reporting returned 404 while the repository was
private. The feature supports public repositories; enable it immediately
after changing visibility and verify the form before announcing the release,
or provide a verified private contact. Source publication requires owner
authorization; no push, visibility change, tag or deployment occurred here.
No task-owned service was started. Pattern scans cannot certify every secret
or ignored local file; distribute tracked source rather than a workspace zip.

2026-10-09 owned retrieval / native Evaluation slice, pinned versions, macOS arm64:

| Check | Result |
| --- | --- |
| Rails suite | 506 runs, 4,360 assertions, 0 failures/errors, 13 default opt-in live skips |
| Selenium system suite | 6 runs, 82 assertions, 0 failures/errors; original flows plus native assertion submission/report and 390px evaluation form/report |
| Free linked acceptance | One complete hybrid/reranked title case + native assertions/reviewer: 5 HTTP 200 POSTs, 29 assertions; separate 0-POST catalog skip and 4-POST Liquid rate-limit failure retained; 9 POSTs total |
| Accounting regressions | Collection batch counted once; query/rerank/reviewer Attempts distinct; native retries mirrored once; late usage retained without state revival; unknown default-cache-only zero normalized conservatively |
| Style / autoload / assets | 338 Ruby files clean; Zeitwerk passed; forced Vite test build and final Tailwind build passed; source-anchored learning references passed |
| Static security / advisory check | Brakeman 8.1.0 local scan: 0 warnings/errors; installed-gem check against cached advisories: no vulnerabilities; staged gitleaks scan: no leaks |
| Upstream candidate | Missing-usage/cache-zero public API reproduction on locked 2.1.0: 1 WebMock-intercepted request, 0 real network/DB; main remains unverified |
| External/manual scope | Typed Judge live, full untrusted-source case group, quality/calibration, hosted CI, container/deployment unverified; current TTS is accepted OpenRouter Fish, optional local adapter deferred |

No paid request, model fallback, push, release or upstream submission occurred.
Task-owned loopback system-test processes exited; process-name-only inspection
found no task Ruby/Puma/ChromeDriver/Vite/Tailwind service remaining. Native report raw usage is distinct
from normalized application billing and neither establishes an independent invoice.


2026-10-09 Rails source answer slice, pinned versions, macOS arm64:

| Check | Result |
| --- | --- |
| Rails suite | 466 runs, 4,026 assertions, 0 failures/errors, 12 default opt-in live skips |
| Selenium system suite | 5 runs, 70 assertions, 0 failures/errors; local refusal, escaped output, citation navigation, learning map, desktop/390px layout and existing demo tests |
| Source import | Development database import and repeated import: 5 sources created, then 5 reused; identical source/chunk receipts and 0 provider requests |
| Style / autoload / assets | 323 Ruby files clean; Zeitwerk passed; forced Vite test build and Tailwind build passed; source-anchored learning references validated |
| Static security / advisory check | Brakeman 8.1.0 local scan: 0 warnings/errors; installed-gem audit against cached advisory data: no vulnerabilities |
| Live scope | Normal answers accepted; whole untrusted-source group remains partial/manual as recorded above; 7 verified-free POSTs, no paid request |
| External scope | Hosted CI, Linux/container runtime, release/deployment and local TTS adapter remain unverified; no task-owned service remains |

The cancellation race and mobile grid overflow found during implementation
were Workbench defects and were corrected. No Rails/RubyLLM gem defect was
confirmed. The tests establish execution and provenance, not answer quality.

2026-10-09 shared AI policy and free TTS slice, pinned versions, macOS arm64:

| Check | Result |
| --- | --- |
| Rails suite | 425 runs, 3,668 assertions, 0 failures/errors, 11 default opt-in live skips |
| Free TTS | Two independent successful synthesis POSTs (raw REST and RubyLLM/Rails); billed tokens/cost unknown; see the dated record above |
| Selenium system suite | 4 runs, 48 assertions, 0 failures/errors; WebMock permits the temporary loopback Rails service, which exited after testing |
| Style / autoload | 310 Ruby files clean; Zeitwerk passed; guide's 8 Ruby snippets parse and its contributor links resolve |
| Static security / gem advisory check | Brakeman 8.1.0 offline scan: 0 warnings/errors; installed-gem audit against the local advisory database: no vulnerabilities |
| Latest scanner check | `bin/brakeman --ensure-latest` could not resolve its remote release metadata in the sandbox; the direct local scan passed, without establishing newest scanner eligibility |
| External scope | No current hosted CI, Linux/container runtime or deployment verification; no paid request; no task-owned service remains |

WebMock is a test-only dependency. No product UI or provider defaults changed;
real acceptance uses explicit models. Local TTS and installation-level API key
budget settings remain owner follow-up. These tests do not establish model or
voice quality. No RubyLLM/Rails gem defect was confirmed in this slice.

2026-10-09 free acceptance and integrity corrections, pinned versions and
macOS arm64:

| Check | Result |
| --- | --- |
| Rails suite | 405 runs, 3,495 assertions, 0 failures/errors, 10 opt-in live skips |
| Free live scope | Five core flows passed; full comparison remains partial; 23 POSTs across five bounded invocations; four intentionally uncalled scenarios |
| Provider/notification/native-index regressions | Selected-provider filtering and real Rails exception notifications passed; native index maintenance exercised with real SQLite and a Ruby scan probe, not a native binary |
| Public thinking-disable probe | RubyLLM 2.1 `Chat#render` correctly emits `reasoning.enabled=false`; no network/database/provider call; candidate excluded |
| Style/autoload/static security | RuboCop: 303 files clean; Zeitwerk passed; Brakeman 8.1.0: 0 warnings/errors |
| External scope | No hosted CI, Docker runtime or deployment verification; Docker daemon socket unavailable; no service started for this acceptance |

No UI/assets/dependency changes were made in this slice. The browser/build
checks below belong to the earlier demo slice. Native runtime, fee-bearing
capabilities and full comparison remain explicit acceptance gaps.

2026-10-09 read-only demo development, same pinned versions and macOS arm64:

| Check | Result |
| --- | --- |
| Rails suite | 379 runs, 3,341 assertions, 0 failures/errors, 8 opt-in live skips; includes snapshot integrity and demo entrypoint checks |
| Selenium system suite | 4 runs, 48 assertions, 0 failures/errors; includes read-only desktop/true 390px navigation, explanations and lexical search |
| Actual production demo | Fresh isolated nine-Run snapshot; read-only SQLite, nil provider settings, rejected queue/database overrides; compiled assets/Turbo, desktop/390px and lexical search passed on loopback |
| Style/autoload/security | RuboCop and Zeitwerk passed; Brakeman 8.1.0: 0 warnings/errors; gem/npm audits: no vulnerabilities |
| Provider / container / hosted scope | No live calls, Linux/Docker runtime or current hosted CI; temporary preview stopped after checking |

This is synthetic local verification, not model quality or an externally
accessible deployment. The editable workbench and read-only viewer use
different databases and execution boundaries. See [DEMO.md](DEMO.md).

2026-10-08, macOS arm64, Ruby 4.0.2, Node 24.21.0, Rails 8.1.4,
RubyLLM 2.1.0:

| Check | Result |
| --- | --- |
| Rails suite | 370 runs, 2,977 assertions, 0 failures, 0 errors, 8 skips (opt-in live dogfood) |
| Selenium system tests | 3 runs, 29 assertions, 0 failures/errors; project creation, cancellation confirmation, true 390px learning/navigation, desktop synthetic Run |
| Source/doc/learning regression after UI edits | 26 runs, 266 assertions, 0 failures/errors |
| RuboCop / Zeitwerk | 293 Ruby files clean / passed |
| Brakeman / bundler-audit | Brakeman 8.1.0: 0 warnings/errors; refreshed gem advisory database: no vulnerabilities |
| npm audit | 0 vulnerabilities after `source-map-js` 1.2.2 update |
| Clean source setup | No keys, local databases, uploads or asset manifests; pinned Node, fresh `npm ci`, existing gem cache, `bin/setup --skip-server`, 5 synthetic Runs and test assets passed |
| Upgrade from baseline schema | Isolated 2.0 schema upgraded; Chat/Message/Run/Attempt and historical cost retained; new owner-ledger row persisted without a chat |
| Production assets | Rails/Tailwind/Vite build passed in the credential-free temporary copy |
| Secret review | No Gitleaks findings in raw 58-commit history or source-only copy; local text conversions disabled; encrypted credentials remain in older commits |
| Current live / hosted CI / Docker | Not run on 2.1; changed commit not pushed; Docker daemon unavailable locally |

This verifies a macOS setup with libvips available and reused installed gems;
it does not certify a fresh gem download, Linux/no-libvips installation,
container runtime, provider compatibility or a public deployment. The previous
remote green run is on the original commit, not this upgrade.

Historical baseline (before this upgrade):

2026-09-28, Rails 8.1.4, RubyLLM 2.0.0:

| Check | Result |
| --- | --- |
| Rails suite | 365 runs, 2,932 assertions, 0 failures, 0 errors, 8 skips (the opt-in live dogfood scenarios) |
| Selenium system tests | 2 runs, 9 assertions |
| RuboCop, Zeitwerk, Brakeman, bundler-audit, npm audit | Clean |
| Hosted CI (GitHub Actions) | Green: tests, system tests, lint, security scans, production assets, Docker build |

Re-run with the commands in [operations](OPERATIONS.md#verification).

## Reading this matrix

- Deterministic tests use fake providers. They do not count as live evidence.
- Capability metadata changes with the RubyLLM registry. This file describes
  Workbench's admission policy, not a frozen inventory of provider models.
- A "Passed" live row covers the named model on the named date only.

Implementation sources: [ModelCatalog](../app/services/ai/model_catalog.rb),
[EmbeddingCatalog](../app/services/ai/knowledge/embedding_catalog.rb),
[RerankCatalog](../app/services/ai/knowledge/rerank_catalog.rb),
[OcrCatalog](../app/services/ai/knowledge/ocr_catalog.rb),
[SpeechCatalog](../app/services/ai/speech_catalog.rb),
[MediaCatalog](../app/services/ai/media_catalog.rb),
[AgentModelEligibility](../app/services/ai/agent_model_eligibility.rb),
[ChatTooling](../app/services/ai/chat_tooling.rb),
[EvaluationExecutor](../app/services/ai/evaluation_executor.rb) and
[ProviderToolActivity](../app/services/ai/provider_tool_activity.rb).
