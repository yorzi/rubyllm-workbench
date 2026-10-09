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
| Knowledge extraction, embeddings, retrieval, rerank | Implemented; owned semantic/hybrid/reranked source answers | Scale measurements, live OCR and saved-Agent case-study extension. Quality study deferred. |
| Speech, transcription, image, video | Partial; experimental | Video resumption, video-job ledger attribution and live video. |
| Evaluation datasets, comparisons, reviews, judge, Batch | Implemented locally; judge experimental | Live Batch, native typed Judge live acceptance and calibration. |
| Exports, lifecycle evidence, upstream drafts | Implemented; drafts experimental | Native OpenTelemetry export and an inspectable trace example. |
| Source-anchored learning | Implemented, including Agent/evaluation/retrieval maps | Extend explanations alongside each new native integration. |
| Read-only synthetic demo | Implemented and locally verified | Public hosting, TLS/host checks and external acceptance remain. The full workbench still requires trusted access. |

The old milestone gate records remain in git history (`TODO.md` at `e9c9faf`).
Both RubyLLM 2.0 production patches were removed after verifying released 2.1
fixes. Keep the remaining Agent usage-recorder seam isolated and tested.

## P0 — release the reference app and make the demo safe

Keep these release gates open while implementing locally reviewable workflow
slices. Publishing still requires their acceptance. Follow
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
- [x] Add shared AI contributor guidance, default HTTP isolation, safe live
      profiles and independent free TTS raw/RubyLLM flow acceptance. Keep
      missing costs/tokens unknown; local TTS remains a separate future adapter.
- [ ] Confirm the installation's independent Workbench key and monthly limit
      in OpenRouter Dashboard; repository guidance does not prove account setup.
- [ ] Complete the full two-model/one-case comparison when free capacity
      permits it. Keep hosted search/transcription/image as owner acceptance,
      and optional local TTS adapter deferred by owner choice.
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

Completed: original MIT Mini Notes corpus/import, lexical/semantic/hybrid
source-answer Runs, optional rerank, corpus/vector revision checks, exact
citations and local refusal. Native one-shot usage owners distinguish
collection imports/search from Run retrieval Attempts. Native
`RubyLLM::Evaluation` reuses saved answers with local assertions or one model
reviewer; typed `RubyLLM::Judge` uses a distinct supported decision protocol.
Neither replays answer generation or includes its cost again. Walkthrough:
[GROUNDED_ANSWERS.md](docs/GROUNDED_ANSWERS.md); actual acceptance is recorded
only in [CAPABILITIES.md](docs/CAPABILITIES.md).

Next executable work:

1. Preserve the full untrusted-source case group's manual acceptance status.
   Complete it only when a bounded explicit free-model invocation satisfies
   structure and citations; do not retry for answer quality.
2. Validate typed Judge live with a deliberately selected supported provider
   and agreed scope. OpenRouter structured reviewers are not typed Judges.
   Keep probabilities measured until a quality/calibration study is requested.
3. Investigate the missing-usage/default-cache-zero RubyLLM candidate on clean
   upstream main before drafting a fix; reproduce offline first. Extend native
   media/job ownership and cost provenance without inventing historical data.
4. Add a small saved-Agent walkthrough over these owned retrieval/evaluation
   boundaries, with explicit tool authority and one traceable case. Retain
   the existing direct source-answer path for an understandable introduction.

TTS decision: use the accepted OpenRouter Fish speech route now. The local TTS
adapter is an optional future extension and does not block development or
acceptance; no owner API details are required for the current speech flow.

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
