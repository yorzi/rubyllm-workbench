# Roadmap

Where RubyLLM Workbench is going next. Current behavior is described in
[docs/SYSTEM_GUIDE.md](docs/SYSTEM_GUIDE.md) and its evidence in
[docs/CAPABILITIES.md](docs/CAPABILITIES.md). The milestone gate records that
used to live here are preserved in git history (`TODO.md` at commit `e9c9faf`).

Updated: 2026-09-28

## Where things stand

| Milestone | Scope | Status |
| --- | --- | --- |
| M0 | Rails baseline, Projects, provider configuration status | `IMPLEMENTED` |
| M1 | Model explorer, streaming Chat, Run/Attempt records, Run history | `IMPLEMENTED` |
| M2 | Structured Experiments compared across models | `IMPLEMENTED` |
| M3 | Tools, approvals, lifecycle timeline, parallel-call policy | `IMPLEMENTED` (parallel calls: no live evidence) |
| M4 | Knowledge: ingestion, embeddings, retrieval, rerank, file sources | `IMPLEMENTED` (OCR: no live evidence) |
| M5 | Provider web search and durable saved Agents | `IMPLEMENTED` |
| M6 | Speech, image, video and transcription | `PARTIAL`, experimental |
| M7 | Evaluation datasets, comparisons, reviews, rubric judge, Batch | `IMPLEMENTED` (Batch: no live evidence) |
| M8 | Reproduction and event export, upstream gap reports | `IMPLEMENTED`; gap reports experimental |

Scope is frozen for v0.1: no new milestone slices until the release gates
below are closed.

## v0.1 release gates

- [x] Hosted CI green on `main` (tests, system tests, lint, security scans,
      production assets, Docker build).
- [x] First live provider acceptance on the stable RubyLLM pin (2026-09-28).
- [x] Private RubyLLM seams isolated and covered by contract tests.
- [x] Demo tour for exploring without provider keys.
- [x] English documentation set.
- [ ] Owner: add the license and publish the private vulnerability reporting
      path.
- [ ] Owner: make the repository public and tag `v0.1.0`.
- [ ] Manually verify a clean `bin/setup` on Debian/Ubuntu with and without
      libvips (macOS verified).

## Next

- **Upstream.** File the prepared RubyLLM fix for streamed OpenRouter
  citations; drop both RubyLLM workarounds once released fixes are pinned
  (see [CAPABILITIES.md](docs/CAPABILITIES.md#rubyllm-workarounds)).
- **Hosted tool cost.** Record provider-reported cost (OpenRouter's `cost`
  includes search fees) so Runs that search stop understating cost.
- **Registry drift.** Surface models that fail with "No endpoints found" so
  pickers stop offering them, and report metadata gaps to models.dev.
- **Evidence breadth.** Live checks for video, OCR, provider Batch and
  parallel tool calls with a provider that supports each.
- **Durable video.** Resume a video job after a worker restart once RubyLLM
  exposes a public way to restore it.

## Later

- Provider file references with lifecycle and expiry for OCR and reuse.
- Page-level provenance for OCR chunks.
- Cross-provider embedding compatibility and a measured corpus/query-scale
  record before making the sqlite-vector adapter the default; package its
  binary per platform.
- Rerank breadth: more providers, `top_n` on larger candidate sets, persisted
  rerank records for cost and latency comparison.
- Provider-native tracing or metrics export; the local lifecycle catalog is
  intentionally application-level.
- A lifetime storage budget for evaluation attachments.

## Out of scope

- Accounts, teams, billing or multi-tenant isolation.
- Running code uploaded through the browser.
- Provider-stored conversation state; conversation history stays local, as in
  RubyLLM itself.
