# CI/CD Guide — MomenTerm

## GitHub Actions Workflows

### Build & Test (`.github/workflows/test.yml`)

Triggers on: push to master, pull requests

Steps:
1. Checkout with submodules
2. Setup Xcode
3. Install dependencies
4. Build: `make Development`
5. Run tests: `tools/run_tests.expect ModernTests`

### Release (`.github/workflows/release.yml` — future)

Triggers on: tag push (`v*`)

Steps:
1. Build release: `make Deployment`
2. Code sign
3. Create GitHub release
4. Upload artifact

## Local Pre-Push Validation

```bash
cp .hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

The pre-push hook runs `tools/build.sh` and blocks push if build fails.

## mt CLI CI

```bash
cd mt-cli
npm run build    # TypeScript compile
npm test         # (future)
```
