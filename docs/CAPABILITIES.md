# Capability matrix

Updated: 2026-09-28 · Rails 8.1.4 · RubyLLM 2.0.0

This is the single place where Workbench records **what each operation
admits** and **what evidence exists for it**. Other documents link here rather
than repeating test counts or dogfood results.

Two kinds of evidence are kept apart:

- **Local**: deterministic tests with fake providers. They prove Workbench's
  own behavior (records, states, recovery, redaction), not provider
  compatibility.
- **Live**: a real provider request, recorded with its date, model and cost.

RubyLLM registry metadata is only an admission hint. A model appearing in a
picker means its registry entry passes the rule below and its provider is
configured. It does not prove that a provider account, model revision, plan or
region will accept the request.

## Operations

| Operation | Admission rule | Local evidence | Live evidence (2026-09-28 unless noted) |
| --- | --- | --- | --- |
| Chat (streaming) | Any configured chat model in the RubyLLM registry. | Run/Attempt lifecycle, streaming, frozen context, drift rejection, queue rejection, cancellation. | Passed: `nvidia/nemotron-3-super-120b-a12b:free`. |
| Structured output | Configured model declaring `structured_output`; batch-suffixed models excluded. | Schema validation, JSON Artifacts, comparison executions. | Passed: `nvidia/nemotron-3-super-120b-a12b:free`. A valid exact JSON match does not measure semantic quality. |
| Local tools with approval | Tool enabled for the Project. Saved Agents with local tools require the exact provider/model registry entry to explicitly declare `function_calling`, checked on save, on enqueue and on every worker restore. | Approval, denial, expiry, cancellation, failed-Run closure, unknown remote outcomes, parallel-call policy. | Passed: `save_run_note` approval and continuation on `nvidia/nemotron-3-super-120b-a12b:free` and `openai/gpt-5-nano`. Parallel tool calls not tested live. |
| Provider web search | `web_search` is an allowlisted RubyLLM provider tool. There is no reliable Workbench model-level web-search capability gate; the provider may reject the tool or the model may not use it. | Snapshotting, citation Artifacts, usage-only tool accounting. | Passed in an Agent Run on `openai/gpt-5-nano`: search counted, citation stored. Requires the OpenRouter streaming workaround below. |
| Saved Agents | As for local tools; provider tools are outside the local-tool gate. | Durable outbox, execution lease and generation fencing, crash/replay drill, cancellation race, empty-answer guard, research report. | Passed: two-step Agent (`project_snapshot`, then a searched, cited answer) on `openai/gpt-5-nano`. |
| Knowledge embeddings | RubyLLM embedding-model registry plus provider configuration. | Chunking, checksums, stale-vector skipping, vector adapters, lexical/semantic/hybrid retrieval, explicit degradation. | Passed: `liquid/lfm-2.5-embedding-350m:free`, 1,024 dimensions. Cross-provider vectors and retrieval quality are not established. |
| Knowledge rerank | Registry model whose output modality includes `rerank`, plus configuration. | Pre/post rank kept alongside unchanged retrieval evidence. | Passed: `nvidia/llama-nemotron-rerank-vl-1b-v2:free`. A 2026-09-17 run once promoted an off-topic chunk; rerank scores need human review. |
| Document OCR | Model declares `ocr` and its provider is configured. | Local extraction and provenance Artifacts. | Not tested: no OCR model is available through OpenRouter's registry entries. |
| Evaluation comparison | 2-5 configured models declaring `structured_output`. | Frozen revision and Experiment snapshot, per-case Runs, outcome metrics, queue rejection, recovery. | Passed: 2 models x 3 cases (`nvidia/nemotron-3-super-120b-a12b:free`, `dots-studio/dots-3-note-preview:free`). |
| Rubric judge (experimental) | Optional; runs only after a successful case output. | Prompt isolation (expected output, tags and attachments are never sent), separate Run/Attempt/cost, recovery, late-response fencing. | Passed: judgments completed on the comparison above. Uncalibrated; never changes exact-match results. |
| Human reviews | Completed case outputs; ratings from a fixed allowlist. | Append-only reviews and per-criterion ratings. | Not applicable (no provider). |
| Case attachments | Up to 5 files per case, 50 per revision, 10 MB each, 50 MB per revision. | Format prechecks (PDF header, JPEG/PNG signatures, JSON, CSV, UTF-8 text), revision ownership, purge on Project deletion. Excluded from every provider prompt. | Not applicable. The checks do not fully decode files or scan for malware; there is no lifetime storage cap. |
| Provider Batch evaluation | Model declares `structured_output` and `batch`, and the provider reports `batches?`; one provider per execution. | Submission, refresh, ordered reconciliation, malformed-index rejection. | Not tested. No live provider Batch compatibility is claimed. |
| Speech generation (experimental) | Model declares `speech_generation`; optional provider voice identifier. | Audio Artifacts, storage failure, recovery, cancellation. | Passed: `deepgram/flux-tts:free` with voice `flux-bree-en`. |
| Audio transcription (experimental) | Model declares `transcription`. | Source-audio and transcript Artifacts, blank-transcript handling. | Passed: `mistralai/voxtral-mini-3b-2507` transcribed the speech output word for word. |
| Image generation (experimental) | Model declares `image_generation`. | Image Artifacts, storage failure, late-response fencing. | Passed: `black-forest-labs/flux.2-klein-4b`, reported cost $0.014. |
| Video generation (experimental) | Model type is `video` with video output. | Submission, polling, provider job reference in the timeline. | Not tested. RubyLLM 2.0.0 has no public API to restore a `VideoJob`, so durable resumption is open. |
| Run reproduction and event export | Explicit per-Run download; no provider request. | Schema v2 budgets (512 KiB, 100,000 characters, latest 100 messages, bounded nesting), redaction, omission reporting. | Not applicable. Redaction is best-effort; review a real Run's export before sharing it. |
| Upstream gap reports (experimental) | Manual classification of a Run. | Append-only candidates, redacted Markdown issue drafts. | Not applicable. Drafts need a manual privacy review. |

## Live dogfood record

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
  A self-disabling workaround in `lib/ruby_llm_workarounds/` restores both; an
  upstream fix with specs is prepared.
- **Attempts never stored a finish reason**, and an Agent whose reasoning
  model spent its output budget finished "successfully" with an empty report.
  Attempts now record `finish_reason`, and such a Run fails with the cause.

### Known provider and registry caveats

- RubyLLM 2.0.0's bundled registry lists models OpenRouter no longer serves
  (for example `nex-agi/*:free`) and understates others (it marks
  `google/gemma-4-31b-it:free` as lacking structured output). Pickers can
  therefore offer models that fail at request time.
- Workbench cost figures come from token pricing. OpenRouter bills hosted
  search separately, so Runs that search understate their cost.
- Free models are rate-limited and change availability without notice.

## RubyLLM workarounds

| Workaround | Why | Remove when |
| --- | --- | --- |
| `Ai::EvaluationBatchResults` rejects duplicate, negative and out-of-range Batch result indices before delivery. | RubyLLM 2.0.0 accepts them. Fixed upstream in crmne/ruby_llm#993 (merged 2026-09-26, unreleased). | A RubyLLM release containing #993 is pinned. |
| `lib/ruby_llm_workarounds/openrouter_stream_evidence.rb` restores streamed OpenRouter citations and server tool usage. | RubyLLM 2.0.0 drops them. Installs only while a boot-time probe shows the gap. | A contract test fails, signalling the upstream parser maps them. |

`Ai::RubyLlmInternals` lists every private RubyLLM seam Workbench relies on, and
`test/services/ai/ruby_llm_internals_test.rb` fails when one moves.

## Verification snapshot

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
