# Code Signing Configuration for iTerm2

This document describes how code signing is configured in iTerm2 and how external developers can build the project without the official signing certificate.

## Overview

iTerm2 uses Xcode configuration files (xcconfig) to manage code signing settings. This allows:

- **Release builds** (Deployment, Beta, Nightly) to use the official Developer ID certificate
- **Development builds** to use automatic signing with Apple Development certificates
- **External developers** to easily override signing settings for local builds

## Configuration Files

All signing configuration files are located in the `Configurations/` directory:

| File | Purpose |
|------|---------|
| `Signing.xcconfig` | Base configuration used by Development builds. Sets `Apple Development` signing with automatic provisioning. |
| `Signing-Release.xcconfig` | Used by Deployment, Beta, and Nightly builds. Inherits from base config and overrides to use Developer ID with manual signing. |
| `Signing.local.xcconfig` | **Optional.** Local overrides that are gitignored. External developers create this file to use ad-hoc signing. |
| `Signing.local.xcconfig.example` | Template showing how to configure local overrides. |

## For External Developers

If you don't have access to the official iTerm2 signing certificate, follow these steps to build locally:

### 1. Create Local Signing Configuration

Copy the example file:

```bash
cp Configurations/Signing.local.xcconfig.example Configurations/Signing.local.xcconfig
```

### 2. Configure Ad-hoc Signing

Edit `Configurations/Signing.local.xcconfig` and add:

```
CODE_SIGN_IDENTITY = -
DEVELOPMENT_TEAM =
```

This configures ad-hoc signing, which doesn't require any Apple Developer account.

### 3. Build Normally

```bash
make Development    # For debug builds
make Deployment     # For release builds
```

Both configurations will now use ad-hoc signing.

### Alternative: Use Your Own Signing Identity

If you have your own Apple Developer account, you can use it instead:

```
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE
```

## How It Works

The project-level build configurations in Xcode are set up as follows:

| Configuration | Base xcconfig | Signing Identity |
|---------------|---------------|------------------|
| Development | `Signing.xcconfig` | Apple Development (automatic) |
| Deployment | `Signing-Release.xcconfig` | Developer ID Application (manual) |
| Beta | `Signing-Release.xcconfig` | Developer ID Application (manual) |
| Nightly | `Signing-Release.xcconfig` | Developer ID Application (manual) |

The `Signing.local.xcconfig` file (if present) is included at the end of `Signing.xcconfig`, so its settings override everything else.

## Dependencies

The pre-built dependencies in `ThirdParty/` (Sparkle, SwiftyMarkdown, etc.) are built with ad-hoc signing. When you build the main iTerm2 app, Xcode re-signs all embedded frameworks with the app's signing identity, so the original signature on these dependencies doesn't matter.

To rebuild dependencies:

```bash
make paranoiddeps
```

This builds all dependencies in a sandbox and doesn't require any specific signing certificate.

## Files Changed

The following files were modified to implement this system:

- `Configurations/Signing.xcconfig` - Created
- `Configurations/Signing-Release.xcconfig` - Created
- `Configurations/Signing.local.xcconfig.example` - Created
- `iTerm2.xcodeproj/project.pbxproj` - Added xcconfig references and removed hardcoded signing settings
- `submodules/Sparkle/Sparkle.xcodeproj/project.pbxproj` - Changed to ad-hoc signing
- `submodules/SwiftyMarkdown/SwiftyMarkdown.xcodeproj/project.pbxproj` - Changed to ad-hoc signing
- `.gitignore` - Added `Configurations/Signing.local.xcconfig`

## Troubleshooting

### "Conflicting provisioning settings" error

This usually means there's a mismatch between the signing identity and provisioning style. Make sure your `Signing.local.xcconfig` sets both:

```
CODE_SIGN_IDENTITY = -
DEVELOPMENT_TEAM =
```

### Build works but app won't launch

Ad-hoc signed apps may trigger Gatekeeper warnings. You can:

1. Right-click the app and select "Open" to bypass Gatekeeper
2. Or run: `xattr -cr build/Development/iTerm2.app`

### Changes not taking effect

Xcode caches build settings. Try:

1. Clean the build folder: `make clean`
2. Close and reopen Xcode
3. Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
