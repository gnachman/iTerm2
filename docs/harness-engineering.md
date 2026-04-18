# Harness Engineering — MomenTerm

> MomenTerm is an AI development orchestration hub built on top of iTerm2.

## Project Profile
- **Type**: macOS terminal application (iTerm2 fork + AI tooling)
- **Language**: Objective-C / Swift hybrid (~2,100 source files)
- **Build**: Xcode + Makefile
- **Deployment**: macOS 12+ (local distribution, not App Store)
- **Team**: AI-assisted 1-person development

## AI Automation Scope

Permitted automated actions:
- File creation (sources/, mt-cli/, docs/)
- Adding files to Xcode project via `tools/add_file_to_xcodeproj.rb`
- Writing documentation
- Running builds and tests
- Git status/diff/log read operations

Restricted (require explicit human confirmation):
- Force push, reset --hard
- Removing submodules
- Changing Info.plist bundle identifiers
- Publishing npm packages

## Static Analysis Policy (pre-push)

Enabled:
- [x] Swift compilation (`tools/build.sh`) — must succeed
- [x] Warnings-as-errors enforcement
- [ ] lint (no swiftlint yet — future)
- [ ] Security scan (future)

## Guardrail Rules

1. No `fatalError` or `assert` — use `it_fatalError` and `it_assert`
2. No Auto Layout in the terminal window or toolbelt
3. No JS/HTML/CSS inline over 1 line — use iTermBrowserTemplateLoader
4. No `NSUserDefaults.standardUserDefaults` — use `[iTermUserDefaults userDefaults]`
5. No associated objects without permission
6. New files must be `git add`-ed and added to Xcode project
7. No AI-generated markdown files in commits (summaries, plans, etc.)
8. Curly quotes in user-visible strings: " " ' '
9. Deployment target is macOS 12 — no availability checks for older versions

## Document Structure

```
docs/
├── harness-engineering.md   ← This file
├── architecture.md          ← System overview
├── development-guide.md     ← Build, test, code rules
├── build-system.md          ← Makefile reference
├── openspec.md              ← PAI specification
├── mcp-server-setup.md      ← MCP server setup
├── db-setup.md              ← Database configuration
├── deployment-guide.md      ← Deployment guide
├── github-guide.md          ← GitHub workflow
├── ci-cd-guide.md           ← CI/CD configuration
├── operations-guide.md      ← Operations runbook
└── components/              ← Component documentation
```

## Hook Policy

- `.hooks/pre-commit` — Secret detection, .env guard
- `.hooks/pre-push` — Build verification

Install: `cp .hooks/pre-commit .git/hooks/ && cp .hooks/pre-push .git/hooks/`

## Model Policy

- Default: `sonnet` (speed + cost efficiency)
- Escalate to `opus` when: repeated failures, architectural decisions, security review
- Return to `sonnet` after resolution
