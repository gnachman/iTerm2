# MomenTerm — Open Spec

> Project specification for AI agents and human contributors.

## Overview

MomenTerm is an iTerm2-based AI development orchestration hub for macOS.
It integrates terminal workflows with AI tools (Claude Code, Codex), project management,
MCP servers, and guardrail enforcement.

## Architecture

### App Target: iTerm2 (produces MomenTerm.app)
- Language: Objective-C + Swift (arm64, macOS 12+)
- Build: `make run` (Development), `make` (release)
- Swift files in app target: `Phony.swift`, `GeneratedAssetSymbols.swift` only

### Library Target: iTerm2SharedARC
- All MomenTerm Swift/ObjC sources live here
- ObjC files import `#import "iTerm2SharedARC-Swift.h"` for Swift bridging

### CLI: mt-cli/
- Language: TypeScript, Node.js, CommonJS output
- Package: `momenterm` (npm)
- Entry: `dist/index.js`

## Components

| Component | File | Description |
|---|---|---|
| Project Window | `MomentermProjectWindowController.swift` | NSPanel project manager |
| Project Model | `MomentermProjectModel.swift` | MTSpace + MTProject data |
| Status Bar | `MomentermStatusBarProjectComponentImpl.m` | ObjC status bar component |
| AI Tool Check | `MomentermAIToolChecker.swift` | claude/codex detection |
| New Tab CWD | `MomentermNewTabHandler.swift` | CWD preservation |
| Korean IME | `sources/iTermKeyboardHandler.m` | Single-Enter IME fix |

## CLI Commands

| Command | Description |
|---|---|
| `mt init` | Initialize project |
| `mt doctor` | Environment health check |
| `mt harness` | Harness Engineering setup |
| `mt vibe` | Vibe-readiness analysis |
| `mt skills install <name>` | Install skill (gstack/omc/open-spec/...) |
| `mt mcp setup` | Configure MCP server |
| `mt mcp scope` | Apply least-privilege scope policy |
| `mt guardrail check` | Detect guardrail violations |
| `mt projects list` | List registered projects |

## Guardrail Rules

1. No secrets/credentials in staged files
2. No .env files committed
3. No AI-generated markdown in commits
4. No node_modules committed
5. .gitignore must cover .env and node_modules
6. docs/harness-engineering.md must exist
7. Binary files > 1MB flagged for Git LFS

## Settings

| Key | Default | Description |
|---|---|---|
| `MomentermSingleEnterCommitsIME` | YES | Korean IME single-Enter behavior |
