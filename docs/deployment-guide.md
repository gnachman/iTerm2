# Deployment Guide — MomenTerm

## macOS App Distribution

MomenTerm distributes as a macOS `.app` bundle (not App Store).

### Build Release

```bash
make Deployment          # Release build
# Output: build/Release/MomenTerm.app
```

### Code Signing

1. Set team ID in Xcode project settings
2. Configure entitlements in `MomenTerm.entitlements`
3. Run `codesign --verify --deep --strict MomenTerm.app`

### Distribution via Sparkle

The app uses [Sparkle](https://sparkle-project.org/) for auto-updates.
Configure the appcast URL in Info.plist: `SUFeedURL`.

## mt CLI Distribution

```bash
cd mt-cli
npm run build
npm publish                # Requires npm account
```

Install from npm:
```bash
npm install -g momenterm
mt --version
```

## CI/CD (GitHub Actions)

See `.github/workflows/` for build and release automation.

### Trigger release

```bash
git tag v0.2.0
git push origin v0.2.0
```

GitHub Actions will build, sign, and create a release draft.
