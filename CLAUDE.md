# RubyLLM Workbench

Read and follow [AGENTS.md](AGENTS.md) and the canonical AI policy in
[docs/AI_USAGE_GUIDE.md](docs/AI_USAGE_GUIDE.md). These files share the project's
instructions for Claude Code and Codex; do not maintain a separate policy here.

The project uses Rails Minitest, RubyLLM's native providers and default offline
tests. Start with focused `bin/rails test` checks. Only run real provider calls
within the user's authorized scope using the explicit live entry points.

Actual capability evidence is in [docs/CAPABILITIES.md](docs/CAPABILITIES.md),
and gem findings are in [docs/UPSTREAM_ISSUES.md](docs/UPSTREAM_ISSUES.md).
