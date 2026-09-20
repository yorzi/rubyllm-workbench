# RubyLLM Workbench documentation

This documentation set explains the application's current behavior, evidence,
limits, and planned growth. The repository can be understood and run without
files outside this checkout.

Updated: 2026-09-20

## If you have five minutes

1. Read [SYSTEM_GUIDE.md](SYSTEM_GUIDE.md) for the product shape and current
   capability boundaries.
2. Review [ARCHITECTURE.md](ARCHITECTURE.md) to see how requests, records, and
   approval continuations connect.
3. Use [OPERATIONS.md](OPERATIONS.md) for local setup, provider configuration,
   and evidence interpretation.
4. Read [CHANGELOG.md](CHANGELOG.md) for the implementation history and the
   reasons behind recent changes.

## What each document covers

| Document | Question it answers |
| --- | --- |
| `SYSTEM_GUIDE.md` | What does the application do, and what should a user infer from its output? |
| `ARCHITECTURE.md` | How do the app's services, jobs, records, and states connect? |
| `OPERATIONS.md` | How do I run the application and interpret local or provider evidence? |
| `LEARNING.md` | How does the in-page, source-anchored explanation layer work? |
| `CHANGELOG.md` | What changed, why, and what evidence or limitations came with it? |
| `../IMPLEMENTATION_MAP.md` | Which product flows and code boundaries exist today? |
| `../TODO.md` | What is implemented, in progress, deferred, or planned? |

## How to read implementation status

The application code and migrations define runtime behavior. Existing tests and
recorded manual/provider evidence show which paths have been checked. The
implementation map and system guide summarize those facts for people; the TODO
and changelog record planned work and history.

Status labels describe implementation:

- **`IMPLEMENTED`**: the described code path exists and meets its current slice
  acceptance.
- **`PARTIAL`**: some paths work, while compatibility or evidence is incomplete.
- **`PLANNED`**: the capability has not been implemented in the current
  application.
- **`DEPRECATED`**: the path may still exist but is no longer recommended.
- **`REMOVED`**: the path and its user-facing entry point have been removed.

Verification evidence is separate from implementation status:

- **`LOCAL_VERIFIED`**: the named local test, browser check, or framework check
  was run.
- **`OPENROUTER_DOGFOOD`**: a specific local flow was tried with a configured
  OpenRouter provider. This does not establish production availability or a
  provider service guarantee.

A successful local check, commit, health endpoint, or provider dogfood run does
not by itself prove deployment, public availability, business outcomes, or
long-term provider compatibility.

## Updating these documents

For a feature change:

1. Check the current implementation map and related code, migrations, and
   existing tests before changing behavior.
2. Update the relevant TODO status and acceptance boundary.
3. Add a changelog entry describing the user-visible change, implementation
   locations, verification evidence, and remaining limits.
4. Update architecture, system, or operations documents when a data model,
   state transition, job, provider boundary, or setup command changes.
5. Keep claims aligned across README, SYSTEM_GUIDE, ARCHITECTURE,
   IMPLEMENTATION_MAP, and TODO.

Historical changelog entries preserve what was believed and verified at the
time. Corrections should be appended with a date instead of silently rewriting
that history.

## Questions to answer when returning to the project

1. Which milestone slices are implemented and what remains partial?
2. Which records are created for a chat, experiment, or other execution?
3. Which provider operations cross the RubyLLM boundary?
4. Which states require a human decision or a continuation job?
5. What does the latest provider check prove, and what does it leave unknown?
6. Which facts are local, provider-specific, deployed, or user-validated?
