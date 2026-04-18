# OMC — oh-my-claudecode Configuration

## Project: MomenTerm

MomenTerm is an iTerm2 fork that serves as an AI development orchestration hub.

## Domain Objects

### Core Entities
- `MTSpace` — workspace grouping projects (name, id, projects[])
- `MTProject` — individual project (name, path, aiTool, lastOpened)
- `MomentermStatusBarProjectComponent` — status bar ObjC component
- `MomentermProjectWindowController` — NSPanel project manager

### AI Tool Registry
- Claude Code (`claude` binary) — primary AI tool
- Codex (`codex` binary) — secondary AI tool
- Checked on startup via `MomentermAIToolChecker`

### Key Flows
1. New tab → `MomentermNewTabHandler` preserves CWD
2. Status bar → shows project name + git branch + AI model
3. Project window → `MomenTerm Projects…` in Window menu
4. Korean IME → `MomentermSingleEnterCommitsIME` setting

## Agent Guidelines
- Executor: use `sonnet` model; escalate to `opus` for architecture decisions
- Review: always run `mt guardrail check` before committing
- Never use `fatalError` — use `it_fatalError` instead
- Never use Auto Layout in terminal window

## Harness
See `docs/harness-engineering.md` for full harness configuration.
