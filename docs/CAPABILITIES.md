# Capability matrix

Updated: 2026-09-28 · RubyLLM 2.0.0

This matrix describes when Workbench offers each operation and what its model
catalog checks. RubyLLM registry metadata is a selection hint: it does not prove
that a particular provider account, endpoint, model revision, plan or region will
accept a request. The last column separates local implementation evidence from
provider evidence.

| Workbench operation | Admission rule | Implementation and evidence boundary |
| --- | --- | --- |
| Chat and model explorer | RubyLLM chat-model registry; `Ai::ModelCatalog` reports provider configuration. The explorer filters `streaming`, `vision`, `function_calling` and `structured_output`. | Persisted Chat Runs and declared capability badges. An OpenRouter `openrouter/free` Chat Run succeeded on 2026-09-16; this historical single-model run predates the stable 2.0.0 pin and does not verify every registry model. |
| Structured Experiment and evaluation | Interactive, configured models declaring `structured_output`; batch-suffixed models are excluded from individual selections. | Schema-constrained Runs and local JSON/schema checks. Two OpenRouter free targets produced valid JSON Artifacts on 2026-09-16, before the stable 2.0.0 pin. A valid exact JSON match does not measure semantic quality or guarantee arbitrary schemas. |
| Evaluation review and optional rubric judge | Optional case rubric with 1–8 bounded criteria; completed human reviews rate every criterion using a fixed allowlist. The opt-in automated judge runs only after a successful output. | Human reviews are append-only; focused checks passed: 18 runs, 237 assertions. The optional judge uses a separate Run/Attempt and cost record; focused prompt-isolation, queue/recovery and late-response checks passed: 24 runs, 259 assertions. It sends case input, generated output and rubric to the selected provider, excluding expected output, tags and attachments. Ratings do not change exact JSON outcomes or provider metrics and are not a calibrated quality score. No provider dogfood has been run. |
| Evaluation case attachments | Attach files to a case through its project-scoped dataset; adding or removing files creates an immutable revision. | Up to 5 files per case and 50 files per dataset revision; 10 MB each and 50 MB total per revision. The multipart MIME selects the format check; when missing or `application/octet-stream`, filename extension selects the check. Before a new revision is created, uploads are checked for a PDF header, JPEG/PNG signatures, valid JSON, CSV syntax, or UTF-8 text without binary control bytes. These checks establish basic format consistency, not that PDFs/images fully decode or are free of malicious/polyglot content. Prior revisions retain their files; project deletion removes attachment rows and purges blobs. Files and their local metadata are excluded from individual and Batch provider prompts. Focused provider-free coverage passed for the earlier attachment slice: 8 runs, 87 assertions; the added content validator has not been tested in this pass. The storage bound is per revision; there is no lifetime dataset/project storage cap. App limits apply after multipart parsing, so a network deployment also needs ingress request-body and part-count limits. |
| Saved Agent tools | Local tool keys must be enabled for the Project; when local tools are selected, the exact provider/model pair must appear in the RubyLLM chat registry and explicitly declare `function_calling`. The same gate runs during definition validation, before Run records are created, and before each worker restoration. Provider tools are allowlisted to `web_search` and are outside this local-tool gate. | Deterministic tests cover supported, unsupported and missing registry metadata at each boundary. Registry metadata is only an admission hint; provider/model acceptance and live Agent behavior remain unverified. |
| Provider web search | `web_search` is an allowlisted RubyLLM provider tool. There is no reliable Workbench model-level web-search capability gate. | Opt-in request snapshots, tool-call handling and citation recording have local coverage. A live integration test is opt-in but has not been run for this slice; the provider may reject the tool or the model may not invoke it. |
| Knowledge embeddings | RubyLLM embedding-model registry plus provider configuration. | Optional embedding generation and local lexical/semantic/hybrid retrieval. On 2026-09-17 OpenRouter embedded two chunks at 1,024 dimensions; this predates the stable 2.0.0 pin and covers one provider/model only. Cross-provider vectors and retrieval quality are not established. |
| Knowledge reranking | Registry model whose output modality includes `rerank`, plus provider configuration. | Pre-rerank evidence remains available. A 2026-09-17 OpenRouter run reranked three chunks but promoted an off-topic chunk over a relevant result; this predates the stable pin and is a quality caveat, not a guarantee. Other providers and larger candidate sets remain unverified. |
| Document OCR | Model declares `ocr` and provider configuration is present. | Local extraction and provenance paths are covered; live OCR dogfood and page-level provenance remain open. |
| Speech generation | Model declares `speech_generation` and provider configuration is present. | Fake-provider Runs persist downloadable audio Artifacts. Live format, voice, playback, usage/cost and provider compatibility remain unverified. |
| Image generation | Model declares `image_generation` and provider configuration is present. | Fake-provider Runs persist image Artifacts. No live endpoint, output quality, MIME/size or usage evidence is claimed. |
| Video generation | Model type is `video` and output modality includes `video`; provider configuration is present. | Fake-provider submission/polling persists video Artifacts and a provider job reference. RubyLLM 2.0.0 has no public API to restore `VideoJob` from that ID; durable resumption and live compatibility remain open. |
| Audio transcription | Model declares `transcription` and provider configuration is present. | Fake-provider Runs retain source-audio and transcript Artifacts. Live language, format, quality and usage compatibility remain unverified. |
| Provider Batch evaluation | Configured model declares both `structured_output` and `batch`; the provider class must also report `batches?`; one provider per Batch execution. | Fake Batch coverage exercises submission, refresh and ordered Run/Attempt reconciliation. No live provider Batch compatibility is claimed. |
| Run reproduction export | Explicit per-Run download; no provider request is made. | Export schema v2 caps formatted JSON at 512 KiB, aggregate text at 100,000 characters, nested values by depth/item/node limits, record sections at 100 items and artifact scanning at 1,000 rows. Chat history sections retain at most the latest 100 messages. JSON reports omitted counts; if the byte cap is exceeded, it returns a small Run summary with an omission reason. Markdown issue drafts are capped at 768 KiB. Redaction remains best-effort and real-Run privacy review is still required. |

The M1/M2 Chat and structured-output runs and the M4 embedding/rerank runs are
historical evidence from 2026-09-16/17, before RubyLLM 2.0.0 became the project
pin on 2026-09-20. They do not establish acceptance on the current stable
dependency. Current outstanding provider checks are listed in [TODO.md](../TODO.md).

## Reading this matrix

- A model appearing in a picker means its registry metadata passes the named
  selection rule and the required provider configuration is present where the
  picker requires it. It is not a provider compatibility certification.
- Workbench tests use deterministic local responses for workflow coverage. They
  do not count as provider dogfood. Current provider and deployment evidence is
  tracked in [TODO.md](../TODO.md) and the [operations guide](OPERATIONS.md).
- Capability metadata changes with the RubyLLM registry. This file describes
  Workbench's selection policy, not a frozen inventory of every provider model.

Implementation sources: [ModelCatalog](../app/services/ai/model_catalog.rb),
[EmbeddingCatalog](../app/services/ai/knowledge/embedding_catalog.rb),
[RerankCatalog](../app/services/ai/knowledge/rerank_catalog.rb),
[OcrCatalog](../app/services/ai/knowledge/ocr_catalog.rb),
[SpeechCatalog](../app/services/ai/speech_catalog.rb),
[MediaCatalog](../app/services/ai/media_catalog.rb),
[AgentDefinition](../app/models/agent_definition.rb),
[AgentModelEligibility](../app/services/ai/agent_model_eligibility.rb), and
[AgentRunExecutor](../app/services/ai/agent_run_executor.rb),
[ChatTooling](../app/services/ai/chat_tooling.rb),
[EvaluationExecutor](../app/services/ai/evaluation_executor.rb), and
[EvaluationBatchSubmissionJob](../app/jobs/evaluation_batch_submission_job.rb).

## 2026-09-26 local regression update

Rails 8.1.4 / RubyLLM 2.0.0: 322 tests, 2,818 assertions, zero failures/errors, two opt-in live-provider skips. Browser tests: 2 tests / 9 assertions. Evaluation Batch collection rejects malformed indices before delivery; reproduction export preserves chronological Run messages. These checks do not establish live media, Agent search, Batch provider or judge compatibility. See [upgrade review](UPGRADE_REVIEW_2026-09-26.md).

## 2026-09-27 — Run event export

Run event download is locally implemented with chronological ordering, related record IDs, redaction, event-count and byte limits. Export budget tests cover nested inputs, escaped bytes, Unicode text, latest messages, bounded Artifact scanning and oversized issue drafts. These are local evidence only; provider-native tracing and historical backfill remain unimplemented.

## 2026-09-28 — live provider dogfood on RubyLLM 2.0.0

First live acceptance on the stable pin, run with `bin/dogfood --paid` (see
[operations](OPERATIONS.md#live-provider-dogfood)). Every scenario drives the
real controllers, jobs and services against OpenRouter and asserts on the
durable records. Each scenario below passed at least once on this date; free
models intermittently returned "No endpoints found" or "Service temporarily
overloaded", so single runs are not guaranteed green. Total OpenRouter spend
for the whole session, including diagnostics: **$0.33**.

| Scenario | Model(s) | Evidence |
| --- | --- | --- |
| Streaming Chat | `nvidia/nemotron-3-super-120b-a12b:free` | Assistant reply persisted; time to first output recorded. |
| Structured output | `nvidia/nemotron-3-super-120b-a12b:free` | Schema-valid JSON Artifact. |
| Local tool approval and continuation | `nvidia/nemotron-3-super-120b-a12b:free`, `openai/gpt-5-nano` | Run paused for `save_run_note`; approval over HTTP resumed it; report Artifact written. |
| Agent with hosted web search | `openai/gpt-5-nano` | Two steps (`project_snapshot`, then a searched answer); search usage counted, citation Artifact and research report stored. |
| Embeddings, semantic search, rerank | `liquid/lfm-2.5-embedding-350m:free`, `nvidia/llama-nemotron-rerank-vl-1b-v2:free` | 3 chunks at 1,024 dimensions; semantic and reranked top hit both relevant. |
| Evaluation comparison with rubric judge | `nvidia/nemotron-3-super-120b-a12b:free`, `dots-studio/dots-3-note-preview:free` | 2 models x 3 cases, all cases terminal, schema-valid answers, judgments completed. |
| Speech then transcription round trip | `deepgram/flux-tts:free` (voice `flux-bree-en`), `mistralai/voxtral-mini-3b-2507` | MP3 Artifact; transcript matched the source text word for word. |
| Image generation | `black-forest-labs/flux.2-klein-4b` | JPEG Artifact, reported cost $0.014. |

Not covered: video generation, OCR (no OpenRouter model in the registry),
provider Batch (OpenRouter does not advertise it) and parallel tool calls.

### Defects found and fixed by this run

- **Speech Runs could not choose a voice.** Some TTS models (for example
  `deepgram/flux-tts`) have no default voice and reject the request. Speech Runs
  now accept an optional, validated voice identifier that is frozen in the
  Run snapshot.
- **Hosted tool use was invisible for OpenRouter.** OpenRouter reports hosted
  search only as usage counters, never as tool-call blocks. Runs now record
  `provider_tool_usage` counters (for example `web_search_requests`) and the
  Run inspector shows them.
- **Streamed OpenRouter responses lost citations (RubyLLM 2.0.0 bug).**
  OpenRouter's streaming `build_chunk` override omits the `citations:` and
  `server_tool_use:` fields that the generic parser maps. Reproduce with
  `bundle exec ruby script/diagnostics/ruby_llm_openrouter_stream_citations.rb`.
  A self-disabling workaround in `lib/ruby_llm_workarounds/` restores both
  until upstream fixes it; a test fails once the upstream parser maps them.
- **Attempts never stored a finish reason**, and an Agent whose reasoning
  model spent its whole output budget finished "successfully" with an empty
  report. Attempts now record `finish_reason`, and such a Run fails with the
  cause.
- **Registry drift.** RubyLLM 2.0.0's bundled registry lists models OpenRouter
  no longer serves (`nex-agi/*:free`) and understates others (it marks
  `google/gemma-4-31b-it:free` as lacking structured output, which the live
  API offers). Pickers built from the registry can therefore offer models
  that fail at request time.

### Remaining caveats

- Workbench cost figures come from token pricing. OpenRouter bills hosted
  search separately and Workbench does not yet record that fee, so Runs that
  search understate their cost.
- Free models are rate-limited and change availability without notice.
