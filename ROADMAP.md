# Roadmap

Updated: 2026-10-09 · Rails 8.1.4 · RubyLLM 2.1.0

The objective is a readable, reproducible Rails reference application that
demonstrates deep RubyLLM integration. Strengthen evidence visitors can inspect
before adding more independent labs. Current behavior is in
[SYSTEM_GUIDE.md](docs/SYSTEM_GUIDE.md), verification in
[CAPABILITIES.md](docs/CAPABILITIES.md), and the visitor route in
[SHOWCASE.md](docs/SHOWCASE.md).

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
acceptance and Linux/container/hosted CI checks before public hosting.

- [x] Pin RubyLLM 2.1.0, apply its Rails migration, verify Rails is already at
      the latest stable 8.1.4, and remove obsolete patches.
- [x] Preserve ledger costs and exclude encrypted credentials from Docker.
- [x] Add a ten-minute tour, skills-to-code map and source-linked diagrams.
- [x] MIT license, contribution/security guides, issue/PR templates, blank
      environment example and opt-in provider tests exist.
- [ ] Run live acceptance on 2.1 with explicit provider/model selection and a
      cost budget. Retain 2.0 evidence as history.
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

## P1 — one integrated case study with measured quality

Next, strengthen the existing Knowledge → Agent → Evaluation path. Suggested
case: answering questions about a small, redistributable Rails application
from source excerpts, with citations and refusal when evidence is absent.
The first provider-free development slice is a licensed corpus and labelled
query set, lexical recall@k/MRR runner, and tests for missing evidence and
misleading retrieved instructions. Add measured semantic/hybrid/rerank runs
only after choosing a provider/model and budget. Keep the synthetic tour
separate from the measured case study.

1. Version a corpus and labelled query set with relevant chunk IDs, missing-
   answer cases and misleading retrieved instructions. Measure recall@k and
   reciprocal rank for lexical, semantic, hybrid and reranked retrieval on
   the same corpus/model/chunk revision. Record sample count, latency, cost
   and machine. Keep source text separate from tool authority.
2. Add a bounded grounded-answer workflow that freezes source IDs, checksums,
   offsets, retrieval options and embedding model into a Run. Validate returned
   citations against the snapshot. Test empty evidence, stale sources,
   unsupported claims and cancellation. Citation validity alone is not truth.
3. Integrate `RubyLLM::Evaluation` and `RubyLLM::Judge` 2.1 on that case set.
   Keep native evaluation distinct from the immutable application ledger and
   avoid duplicate calls. Compare exact matching with a human-calibrated
   qualitative rubric; publish disagreements and failures.
4. Attribute one-shot embedding, rerank and media usage to an application
   owner. Preserve reported/estimated provenance before serialization when
   public callbacks permit it; never infer it from a ledger total. Reconcile
   retries and hosted-tool fees without counting a request twice.

Completion: a reproducible case study with commands, corpus licence, frozen
inputs, measured outcomes and a useful failure analysis. Live calls require
deliberate authorization and a bounded budget.

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
