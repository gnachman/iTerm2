# Operations Guide — MomenTerm

## Daily Development Flow

```bash
# 1. Open project
cd ~/path/to/MomenTerm

# 2. Check handoff
mt handoff show

# 3. Build & run
make run

# 4. Run tests (specific)
tools/run_tests.expect ModernTests/SomeTest

# 5. End of session — update handoff
mt handoff sync
```

## Key Paths

| Path | Purpose |
|---|---|
| `sources/` | Swift + ObjC source files |
| `mt-cli/` | mt CLI npm package |
| `docs/` | Project documentation |
| `tools/` | Build and utility scripts |
| `tests/` | Test suites |
| `.hooks/` | Git hooks source |
| `~/.momenterm/` | User config and registry |

## Build Commands

```bash
make run           # Debug build + run
make Development   # Debug build only
make Deployment    # Release build
tools/build.sh     # Build, log errors to tmp/build.log
```

## Adding New Swift Files

```bash
# Create file
touch sources/NewFeature.swift

# Add to git
git add sources/NewFeature.swift

# Add to Xcode project
tools/add_file_to_xcodeproj.rb sources/NewFeature.swift iTerm2SharedARC
```

## mt CLI Development

```bash
cd mt-cli
npm install        # Install deps
npm run build      # Compile TypeScript
node dist/index.js --help  # Test locally
npm link           # Link globally as `mt`
```

## Guardrail Incidents

If a guardrail fires:
1. Read the error message carefully
2. Do NOT bypass with `--no-verify`
3. Fix the underlying issue
4. Re-run the command

## Model Escalation

When stuck:
1. Note the problem in handoff.md
2. Escalate to opus: add `--model claude-opus-4-6` flag
3. Resolve issue
4. Return to sonnet for continued work
