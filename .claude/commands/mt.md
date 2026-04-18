Run the MomenTerm project orchestration workflow.

You are acting as the `mt` orchestrator for this project. Based on the user's request, perform the appropriate MomenTerm operation.

## Available Operations

### Project Management
- `mt init` — Initialize project, create .agentignore and handoff.md
- `mt projects list` — Show all registered projects
- `mt projects add <path>` — Register a new project

### Environment Health
- `mt doctor` — Check Claude Code, Codex, git, Node.js availability
- `mt compatibility-check` — Check component compatibility

### Harness Engineering
- `mt harness` — Run interactive Harness Engineering interview and generate:
  - docs/harness-engineering.md
  - CLAUDE.md (if new)
  - AGENTS.md (if new)
  - .hooks/pre-commit and pre-push

### Vibe-Readiness
- `mt vibe` — Analyze project readiness and generate report.md with:
  - Overall score (0-100) and grade (A-F)
  - Category breakdown: Documentation, Harness, Tests, CI/CD, Hooks, Security
  - Priority action list

### Skills & Plugins
- `mt skills list` — Show available and installed skills
- `mt skills install <name>` — Install: db-supabase, db-neon, deploy-vercel, github-init, mcp-setup
- `mt plugins list` — Show installed plugins

### MCP Servers
- `mt mcp setup` — Configure MCP server with Claude Code integration
- `mt mcp status` — Show configured MCP servers

### Session Continuity
- `mt handoff show` — Show current work context from handoff.md
- `mt handoff sync` — Sync handoff.md with current git branch
- `mt handoff done <task>` — Mark a task as complete

### Upgrades
- `mt upgrade` — Check for and apply updates
- `mt rollback <version>` — Rollback to previous version

### Bootstrap
- `mt bootstrap` — Full setup: init + harness + vibe in one command

## How to Respond

1. Parse the user's intent (e.g., "check environment" → `mt doctor`)
2. Execute the equivalent logic directly or describe what `mt <command>` would do
3. If generating files, follow the patterns in docs/harness-engineering.md
4. Update handoff.md when completing significant work
5. Suggest next steps from the priority action list

## Context

- Project: $ARGUMENTS
- Working directory is a MomenTerm/iTerm2 project
- Key files: CLAUDE.md, AGENTS.md, handoff.md, docs/harness-engineering.md
- mt CLI source: mt-cli/src/
