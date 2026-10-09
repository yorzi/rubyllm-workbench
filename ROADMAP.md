# Roadmap

Updated: 2026-10-09 · Rails 8.1.4 · RubyLLM 2.1.0

The objective is a readable, reproducible Rails reference application that
demonstrates deep RubyLLM integration. Strengthen evidence visitors can inspect
before adding more independent labs. Current behavior is in
[SYSTEM_GUIDE.md](docs/SYSTEM_GUIDE.md), verification in
[CAPABILITIES.md](docs/CAPABILITIES.md), and the visitor route in
[SHOWCASE.md](docs/SHOWCASE.md).
Track RubyLLM/Rails findings in [UPSTREAM_ISSUES.md](docs/UPSTREAM_ISSUES.md),
with reproduction status and an explicit application/provider boundary before
an upstream contribution.

## Current coverage

| Area | Implementation | Remaining gap |
| --- | --- | --- |
| Projects, model discovery, persisted streaming Chat | Implemented | Availability feedback when registry models stop being served. |
| Structured Experiments, tools, approvals | Implemented | Live parallel calls on a supporting provider. |
| Durable saved Agents | Implemented | Measured concurrency and a current-version live recovery walkthrough. |
| Knowledge extraction, embeddings, retrieval, rerank | Implemented | Quality dataset, scale measurements, grounded answers and live OCR. |
| Speech, transcription, image, video | Partial; experimental | Video resumption, video-job ledger attribution and live video. |
| Evaluation datasets, comparisons, reviews, judge, Batch | Implemented locally; judge experimental | Live Batch, judge calibration and native Evaluation/Judge integration. |
| Exports, lifecycle evidence, upstream drafts | Implemented; drafts experimental | Native OpenTelemetry export and an inspectable trace example. |
| Source-anchored learning | Implemented, including Agent/evaluation/retrieval maps | Extend explanations alongside each new native integration. |
| Read-only synthetic demo | Implemented and locally verified | Public hosting, TLS/host checks and external acceptance remain. The full workbench still requires trusted access. |

The old milestone gate records remain in git history (`TODO.md` at `e9c9faf`).
Both RubyLLM 2.0 production patches were removed after verifying released 2.1
fixes. Keep the remaining Agent usage-recorder seam isolated and tested.

## P0 — release the reference app and make the demo safe

Complete this before expanding the feature set. Follow
[RELEASING.md](docs/RELEASING.md).

The isolated read-only synthetic demo now passes local request, database,
job and desktop/390px browser checks, including a real production-mode
preview. See [DEMO.md](docs/DEMO.md). Next complete current-version live
acceptance and Linux/container/hosted CI checks before public hosting. Free
2.1 acceptance now verifies five core flows; the full two-model comparison
remains partial under provider failures/limits. Its small manual rerun and
the deferred capability list are in [OPERATIONS.md](docs/OPERATIONS.md#remaining-manual-acceptance).

- [x] Pin RubyLLM 2.1.0, apply its Rails migration, verify Rails is already at
      the latest stable 8.1.4, and remove obsolete patches.
- [x] Preserve ledger costs and exclude encrypted credentials from Docker.
- [x] Add a ten-minute tour, skills-to-code map and source-linked diagrams.
- [x] MIT license, contribution/security guides, issue/PR templates, blank
      environment example and opt-in provider tests exist.
- [x] Run bounded free acceptance on 2.1 with explicit models; preserve five
      passed flows, partial comparison and uncalled manual capabilities in
      the evidence matrix. Retain 2.0 evidence as history.
- [ ] Complete the full two-model/one-case comparison when free capacity
      permits it. Keep hosted search/transcription/image as owner acceptance,
      and local TTS pending API details and adapter work.
- [ ] Verify hosted CI for the candidate commit, fresh Debian/Ubuntu setup
      with and without libvips, and the runtime container.
- [ ] Confirm private vulnerability reporting and review git history and
      synthetic screenshots. Publish/tag `v0.1.0` with owner authorization.
- [x] Implement a read-only demo with an isolated synthetic database and no
      provider credentials. Use an explicit route allowlist; permit only local
      lexical search and synthetic evidence downloads. Reject mutation,
      direct uploads and job submission; force GET search to lexical with no
      reranking. Tests prove crafted requests cannot call a provider, enqueue
      work or change records. Desktop and 390px browsing verified locally.
- [ ] Publish that demo with TLS and host checks and verify external access.
      Authenticate any deployment of the full workbench.

Completion: an unfamiliar Rails developer can install from a clean checkout,
complete the tour without a key, and inspect source/tests behind every claim.
Public access must not create a model-spending or upload endpoint.

## P1 — complete an understandable integrated workflow

Next, strengthen the existing Knowledge → Agent → Evaluation path. Suggested
case: answering questions about a small, redistributable Rails application
from source excerpts, with citations and refusal when evidence is absent.
Use a tiny licensed corpus and OpenRouter free models to verify the complete
path, durable evidence and failure behavior. Answer and retrieval quality
benchmarks are deferred by owner preference; they do not block integration
acceptance. Keep the synthetic tour separate from real requests.

1. Version a small corpus with relevant chunk IDs, missing-answer cases and
   misleading retrieved instructions. Verify lexical, semantic, hybrid and
   reranked requests on frozen corpus/model/chunk revisions. Keep source text
   separate from tool authority; record availability and flow outcomes.
2. Add a bounded grounded-answer workflow that freezes source IDs, checksums,
   offsets, retrieval options and embedding model into a Run. Validate returned
   citations against the snapshot. Test empty evidence, stale sources,
   unsupported claims and cancellation. Citation validity alone is not truth.
3. Integrate `RubyLLM::Evaluation` and `RubyLLM::Judge` 2.1 on that case set.
   Keep native evaluation distinct from the immutable application ledger and
   avoid duplicate calls. Compare exact matching with a human-calibrated
   qualitative rubric when quality study is requested; initially accept that
   each scheduled output and judgment completes and is stored correctly.
4. Attribute one-shot embedding, rerank and media usage to an application
   owner. Preserve reported/estimated provenance before serialization when
   public callbacks permit it; never infer it from a ledger total. Reconcile
   retries and hosted-tool fees without counting a request twice.

5. Connect the owner's local TTS API once endpoint, protocol, model and voice
   are provided. Reuse Speech Runs, Artifacts, Active Storage and playback;
   verify errors, cancellation and recovery. No cloud TTS fallback.

Completion: a reproducible workflow with commands, corpus licence, frozen
inputs, flow outcomes and useful failure evidence. Free calls are the default;
unavailable or fee-bearing capabilities remain explicit manual acceptance.

## P2 — RubyLLM 2.1 production integration

Take one slice at a time after the case study.

| Slice | Implementation | Acceptance |
| --- | --- | --- |
| MCP client | Code-registered read-only server, fixed endpoint/tool allowlist, progress/timeout/disconnect states. Distinguish elicitation/task pauses from approval. | Deterministic server fixtures, filtering and restart tests, one intentional live read. No arbitrary endpoint or write tool; add encrypted credentials only when needed. |
| Native tracing | Opt-in `RubyLLM::OpenTelemetry` with an in-memory exporter; correlate spans to Run/Attempt IDs. | No prompts, responses, arguments or secrets in spans; separate retries, tool/provider/queue time; export one synthetic trace. |
| Streaming and connections | Split SSE frames, terminal errors, disconnects, no retry after output; measure a public persistent Faraday adapter under bounded concurrency. | Provider-free transport regressions and measured connection/query/allocation counts with machine and versions. Do not borrow upstream benchmark results. |
| Files and prompt caching | Provider-upload reuse/expiry and explicit cache boundaries on supporting providers; keep originals and checksums. | Cross-process reuse, missing-upload recovery, model switching, cache reads/writes and TTL costs, each with a source-linked explanation. |

## Later, driven by evidence

- Complete live video, OCR, Batch and parallel-tool acceptance on supporting
  providers. Remove experimental labels only for verified scope.
- Add retrieval recall/MRR and human-calibrated answer/judge quality studies
  when requested; the current priority is integration with minimal cost.
- Obtain a public video-job restoration API before promising durable video.
- Add page-level OCR provenance and measured SQLite corpus/concurrency limits.
  Package the optional vector extension only after measuring it.
- Expand browser tests for approval/denial, interrupted jobs, degradation and
  exports as each case-study flow is implemented.
- Add lifetime storage budgets before remote workbench use with persistent
  users.

## Out of scope

Accounts, teams, billing, arbitrary browser-uploaded code, a plugin marketplace
and multi-tenant SaaS are separate projects. Keep SQLite until measured
workload constraints justify another store.
