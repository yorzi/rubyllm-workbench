# Rails / RubyLLM review: 2026-10-08

## Versions and upgrade

RubyGems' latest-version endpoints returned RubyLLM **2.1.0** and Rails
**8.1.4**. Rails was already current. RubyLLM was upgraded from 2.0.0 to an
exact 2.1.0 pin with a conservative bundle update and lockfile checksum.

Sources checked on this date:

- [RubyLLM on RubyGems](https://rubygems.org/gems/ruby_llm)
- [Rails on RubyGems](https://rubygems.org/gems/rails)
- [Official 2.1 upgrade guide](https://rubyllm.com/next/upgrading/)
- [Official 2.1 feature guide](https://rubyllm.com/next/whats-new-in-2-1/)

The gem's `ruby_llm:upgrade` generator created the additive schema migration:
MCP credential/provider-upload tables, paused tool state, message cache TTL,
server-tool usage, optional chat association, usage owner and the new
judgment/video/research operations. Schema support does not mean Workbench
has exposed MCP, native Judges/Evaluations or prompt caching.

## Findings and corrections

| Angle | Finding | Correction or remaining acceptance |
| --- | --- | --- |
| Compatibility | First regression found obsolete patch expectations and changed Batch validation. | Removed both production patches; kept released-parser/Batch regressions. |
| Batch safety | Unknown provider count can lose trailing failed cases. | Require the public chat manifest to match frozen cases before collection; RubyLLM 2.1 owns index validation. |
| Accounting | Ledger totals were ignored and historical calls repriced, losing hosted-tool fees. | Preserve `recorded_cost`, distinct from reported/estimated/unknown, in Runs, metrics, exports and dogfood. |
| Container privacy | Git ignored encrypted credentials but Docker copied them into images. | Exclude encrypted credentials from the build context. |
| Dependencies | Refreshed npm audit flagged `source-map-js` 1.2.1; the pinned scanner required a newer Brakeman. | Lock `source-map-js` 1.2.2 and Brakeman 8.1.0; rerun audits. |
| Setup | README implied all Rails commands loaded `.env`; only Foreman does. | Add a blank example and explain Foreman, environment and credentials paths. |
| Presentation | Agents/evaluations lacked teaching despite substantial engineering. | Add anchored topics and accessible execution maps, plus a retrieval map. |
| Mobile presentation | Full navigation occupied the first screen; explanations appeared below the feature. | Add an expandable menu and reveal the learning panel after its Turbo load; test a true 390px viewport. |
| Claims | Generic copy said all Knowledge work left Runs. | Correct the distinction between Run evidence and Knowledge source/retrieval records. |
| Online readiness | Writable app, no accounts; GET semantic search can call a provider. | Plan an isolated credential-free, allowlisted read-only demo before hosting. |
| 2.1 depth | MCP, native Judge/Evaluation, OpenTelemetry, uploads and cache TTL lack app examples. | Sequence a measured integrated case study, then focused native-integration slices. |
| Quality | Tiny exact-match cases and uncalibrated judging do not establish accuracy. | Add a labelled corpus/query set and calibration; publish separate outcome measures. |

## Removed patches and remaining private seam

Provider-free diagnostic scripts load the installed gem without Rails or a
Workbench patch. On 2.1, negative, duplicate and out-of-range Batch indices
are rejected; OpenRouter streaming retains citations and tool usage. Both
scripts remain regression probes in `script/diagnostics/`.

`Ai::EvaluationBatchResults` now uses public `Batch#chats`/`Batch#messages`.
A complete manifest preserves failed/missing slots without a provider count.
A lost manifest produces a visible refresh error and leaves cases untouched.
The Agent usage-recorder seam remains isolated in `Ai::RubyLlmInternals` to
fence framework persistence. The app does not claim to use only public APIs.

## Cost evidence

RubyLLM serializes a usage total without its original pricing provenance.
An explicit provider amount remains `reported`; registry calculation is
`estimated`; a saved ledger total is `recorded`; missing amounts stay
`unknown`. Known subtotals exclude unknown costs. Earlier Attempts are not
backfilled because original provenance cannot be reliably reconstructed.

## Diagram decision

The architecture guide already contains context, relationship, sequence and
state diagrams. Three small HTML execution maps now appear inside relevant
learning panels with conditional paths, source excerpts and limits. They
need no Mermaid runtime or remote asset; the detailed Agent/evaluation
diagrams remain in ARCHITECTURE.md.

## Validation and release boundaries

Results live in [CAPABILITIES.md](CAPABILITIES.md#verification-snapshot).
Regressions cover the upgraded ledger, accounting, metrics/exports, native
streaming evidence, manifest-based Batch collection and anchored learning.
Normal tests disable live flags; the 2026-09-28 live run is historical 2.0
evidence. GitHub still reports the repository as private. Publication,
current-version live acceptance and CI on the changed commit remain separate
steps in [RELEASING.md](RELEASING.md) and [ROADMAP.md](../ROADMAP.md).

Raw git history (58 commits) and the credential-free source copy produced no
Gitleaks findings. The first scan followed a local Git text-conversion rule
that decrypted an encrypted credentials blob; the raw blob itself was a
single encrypted envelope. The repeat scan disabled text conversion and
external diff drivers. Historical encrypted credentials remain in history;
the scan is not a guarantee that every secret format is detectable. GitHub's
private-vulnerability-reporting endpoint returned 404, so the reporting
channel still needs verification before publication.

Browser checks use `CI=1` and prebuilt Vite assets. This environment's Ruby
TCP probe returned a socket without an established peer on the closed test
port, causing Vite to report a development server and proxy assets to a 502.
CI mode bypasses that probe; the regression explicitly waits for Turbo.
