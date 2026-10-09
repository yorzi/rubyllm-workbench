# Documentation

This set explains the workbench's current behavior, evidence, limits and
planned growth. Everything needed to understand and run it is in this
checkout.

Updated: 2026-10-09

## If you have five minutes

For a portfolio walkthrough, start with [SHOWCASE.md](SHOWCASE.md), which
maps the synthetic tour to engineering decisions, source and verification.

1. [SYSTEM_GUIDE.md](SYSTEM_GUIDE.md): what the application does and how to
   read its output.
2. [CAPABILITIES.md](CAPABILITIES.md): what each operation admits and what
   evidence exists for it, including the latest live provider run.
3. [ARCHITECTURE.md](ARCHITECTURE.md): how requests, records, jobs and approval
   continuations connect.
4. [OPERATIONS.md](OPERATIONS.md): setup, the demo tour, provider
   configuration, verification and troubleshooting.
5. [CHANGELOG.md](CHANGELOG.md): what changed and why.

## What each document covers

| Document | Question it answers |
| --- | --- |
| `SYSTEM_GUIDE.md` | What does the application do, and what can I infer from its output? |
| `CAPABILITIES.md` | Which gates admit each operation, and what is verified locally or live? |
| `ARCHITECTURE.md` | How do services, jobs, records and states connect? |
| `OPERATIONS.md` | How do I run, verify and troubleshoot it? |
| `AI_USAGE_GUIDE.md` | How do contributors configure AI, isolate tests and run authorized low-cost acceptance? (Chinese working guide) |
| `UPSTREAM_ISSUES.md` | Which RubyLLM/Rails findings are confirmed, excluded or still awaiting reproduction? |
| `LEARNING.md` | How does the in-page, source-anchored explanation layer work? |
| `SHOWCASE.md` | What engineering skills can a visitor inspect in ten minutes? |
| `RELEASING.md` | What still needs verification and authorization before publication? |
| `UPGRADE_REVIEW_2026-10-08.md` | The RubyLLM 2.1 upgrade and current project audit |
| `CHANGELOG.md` | What changed, and why? |
| `UPGRADE_REVIEW_2026-09-26.md` | The Rails 8.1.4 upgrade review and the defects it found |
| `../IMPLEMENTATION_MAP.md` | Where does each capability live in the code? |
| `../ROADMAP.md` | What comes next, and what is out of scope? |

## Status labels and evidence

Status labels describe the code, with a short description of current behavior,
evidence and limits kept separately:

- **`IMPLEMENTED`**: the path exists and meets its current acceptance.
- **`PARTIAL`**: some paths work; compatibility or evidence is incomplete.
- **`PLANNED`**: not implemented.
- **`DEPRECATED`**: still present but no longer recommended.
- **`REMOVED`**: the path and its entry point are gone.

Evidence is recorded in [CAPABILITIES.md](CAPABILITIES.md) as either **local**
(deterministic tests with fake providers) or **live** (a real provider
request, with its date, model and cost). A passing local check, a commit, a
health endpoint or one live run does not by itself prove deployment, public
availability, business outcomes or long-term provider compatibility.

## Keeping the docs true

For each behavior change, in the same commit:

1. Update the affected guide, diagram or operations section.
2. Update [CAPABILITIES.md](CAPABILITIES.md) when admission rules or evidence
   change. It is the only place for test counts and live results.
3. Add a [CHANGELOG.md](CHANGELOG.md) entry.
4. Update [ROADMAP.md](../ROADMAP.md) when scope changes.

`test/docs/human_system_docs_test.rb` keeps the core documents linked and the
key concepts present.
