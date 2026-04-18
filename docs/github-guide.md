# GitHub Guide — MomenTerm

## Branch Strategy

| Branch | Purpose |
|---|---|
| `master` | Stable, release-ready |
| `feature/*` | New features |
| `fix/*` | Bug fixes |
| `docs/*` | Documentation only |

## Commit Convention

```
<type>: <short description>

Types: feat, fix, docs, refactor, test, chore
```

Examples:
```
feat: Add project sidebar window controller
fix: Korean IME Enter key handling in PTYTextView
docs: Update harness engineering guide
```

## Pull Request Checklist

- [ ] Build passes: `make run`
- [ ] No new warnings
- [ ] Pre-commit hook passes
- [ ] docs/ updated if behavior changes
- [ ] handoff.md updated

## Protected Rules

- Never force-push to `master`
- Always create PRs for significant changes
- Co-author AI commits: `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`
