# Bumping the macOS deployment target

A repeatable procedure for raising iTerm2's minimum macOS version. Written
after the macOS 12 -> 13 bump; substitute the new floor for "13.0" below.

The work spans four kinds of place: the app's own Xcode targets, the
Makefile that builds the native/vendored libraries, the git submodules we
vend, and the local Swift packages. Then everything is rebuilt and the
deprecations that the new floor surfaces are fixed.

## 0. Pick the value

Use `N.0` (e.g. `13.0`). Historically the app targets drifted to `.4`
values (12.4); standardize on `.0` when you bump. macOS 12 is the last
release whose bundled Python runtime is used; the uv interpreters require
macOS 13, so crossing 13 also lets uv become an unconditional default
(see step 9).

## 1. Makefile

`Makefile` has a single source of truth for the native builds:

```
DEPLOYMENT_TARGET=13.0
```

Every native recipe (openssl, libssh2, libgit2, libsixel) references
`$(DEPLOYMENT_TARGET)`, so this one line covers them. Confirm nothing else
hardcodes a version:

```
grep -nE "macos1[0-9]|version-min=1[0-9]|OSX_DEPLOYMENT_TARGET" Makefile | grep -v '\$(DEPLOYMENT_TARGET)'
```

## 2. Main project: iTerm2.xcodeproj

Bump every `MACOSX_DEPLOYMENT_TARGET` that is below the new floor, and
leave intentional outliers alone:

- Bump the app-family values (the bulk, plus `it2core`).
- Leave targets that are already higher (e.g. the browser / WebExtensions
  targets at 15.0) - do not lower them.
- Leave deliberately-ancient test-only targets (e.g.
  `iTerm2ForApplescriptTesting` at 10.12); a low floor there is harmless
  because the shipped app requires the new minimum.

Find what belongs to what:

```
python3 - <<'EOF'
import re
f=open('iTerm2.xcodeproj/project.pbxproj').read()
for m in re.finditer(r'([0-9A-F]{24}) /\* (\w+) \*/ = \{\n\t\t\tisa = XCBuildConfiguration;(.*?)\};',f,re.S):
    dt=re.search(r'MACOSX_DEPLOYMENT_TARGET = ([0-9.]+);',m.group(3))
    if dt: print(dt.group(1), m.group(2))
EOF
```

## 3. App-embedded sub-projects (not submodules)

These build into frameworks the app links, and their pbxprojs are tracked
in the main repo. Bump each one's app-level `MACOSX_DEPLOYMENT_TARGET`
(leave their old demo/test alt-configs):

- BetterFontPicker/BetterFontPicker.xcodeproj
- ColorPicker/ColorPicker.xcodeproj
- SearchableComboListView/SearchableComboListView.xcodeproj
- SignedArchive/SignedArchive.xcodeproj
- ThirdParty/GZIP/GZIP.xcodeproj
- iTermBrowserPlugin/iTermBrowserPlugin.xcodeproj (bump its `12`, leave the
  15.x WebExtensions targets)

Framework `Info.plist` `LSMinimumSystemVersion` values and the demo/test
plists use `$(MACOSX_DEPLOYMENT_TARGET)` or are Xcode-generated, so they
inherit automatically - no hand-editing.

## 4. Submodules we vend (github.com/gnachman/*)

Only bump submodules whose remote is `github.com/gnachman/*`. Others
(BTree, fmdb, libgit2, libsixel, libssh2, powerline-extra-symbols,
noise-c) are left alone: a dependency built for a lower floor links and
runs fine inside a higher-floor app, and we do not want to drift them from
upstream.

List the remotes to be sure:

```
git config -f .gitmodules --get-regexp url
```

The vendored ones with a macOS Xcode target: **CoreParse, Highlightr,
MultiCursor, NMSSH, Sparkle, SwiftyMarkdown**. For each:

1. Bump **every** `MACOSX_DEPLOYMENT_TARGET` in its `.xcodeproj` that is
   below the floor (leave anything already higher). Do not bump just the
   "main" config: a partial bump leaves the framework building at the old
   min (this is exactly why NMSSH kept building at 10.15 through the 11->12
   bump). NMSSH also carries prebuilt `NMSSH-OSX/Libraries/lib/*.a`
   (openssl/libssh2) that get rebuilt at the new floor by the deps build.
2. Commit inside the submodule: `git -C submodules/X commit -m "Bump
   deployment target to macOS 13"`. These land on a detached HEAD.
3. Bump the superproject pointer: `git add submodules/X`.
4. **Push the fork** so other machines/CI can fetch the new SHA:
   `git -C submodules/X push origin HEAD:<branch>`.

Not bumped, and why:

- openssl (gnachman fork) builds via the Makefile `DEPLOYMENT_TARGET`,
  no pbxproj target to touch.
- adblock-rust, railroad_dsl (Rust) and iTerm2-shell-integration (shell)
  have no Apple deployment target and emit no Apple deprecation warnings.
- SFSymbolEnum is a codegen package (its output compiles under the app's
  target), so its own platform is irrelevant.

## 5. Local Swift packages

Bump `.macOS(.vN)` in each manifest:

- WebExtensionsFramework/Package.swift (covers BrowserExtensionShared too)
- Companion/CompanionCore/Package.swift (CompanionNoise/Protocol/Transport)
- it2cli/Package.swift, cc-status/Package.swift, pwmplugin/Package.swift

Caveats:

- The `.vN` enum must exist in that package's `swift-tools-version`
  (`.v13` needs 5.7+). Older-tooled packages (e.g. tools 5.1/5.3) cannot
  name it - either raise the tools version or leave the package.
- Packages the app consumes via a prebuilt framework (built from an
  `.xcodeproj`, e.g. Highlightr/SwiftyMarkdown) do not read `Package.swift`
  during the app build, so those manifests do not affect app warnings.
  Bump them for standalone/SPM consumers only.

## 6. Rebuild the vendored dependencies

```
make -j16 paranoid-deps
```

`paranoid-deps` runs `tools/check-submodule-cleanliness` first, which
**aborts non-interactively if any submodule is dirty or points at a
different commit than the superproject index**. So before running it:
commit the submodule edits (step 4) and stage their pointers, and clear
transient build dirs the previous run left (e.g. `submodules/*/build*`,
`submodules/openssl/build-fat`, `submodules/CoreParse/Build`). A rebuild
re-dirties NMSSH's `.a` files; fold those into its commit (amend) and
re-stage the pointer.

Verify the rebuilt binaries carry the new floor:

```
otool -l ThirdParty/NMSSH.framework/Versions/A/NMSSH | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}'
plutil -extract LSMinimumSystemVersion raw ThirdParty/CoreParse.framework/Versions/A/Resources/Info.plist
```

## 7. Rebuild the standalone universal binaries

The committed CLI/adapter binaries (`it2cli/bin/it2`, `cc-status/bin/cc-status`,
`pwmplugin/binaries/*`) are universal and must be rebuilt to pick up the
new floor:

```
make BUILD_DIR="$PWD/Build" UNIVERSAL=1 paranoid-it2cli paranoid-cc-status paranoid-pwmadapters
```

`BUILD_DIR=...` is required: the sandboxed sub-make cannot run
`xcodebuild -showBuildSettings` to discover it, and `it2cli`/`cc-status`
do not pass it through (only `pwmadapters` does). Verify each slice:

```
for b in it2cli/bin/it2 cc-status/bin/cc-status pwmplugin/binaries/*; do
  echo "$b $(lipo -archs "$b"): $(otool -l "$b" | awk '/minos/{printf "%s ",$2}')"
done
```

## 8. Fix the deprecations the new floor surfaces

The project builds warnings-as-errors, so `make Development` stops at the
first newly-deprecated API. To survey them all at once, build with the
promotion disabled:

```
make clean
xcodebuild -scheme iTerm2 -configuration Development -destination 'platform=macOS' \
  -skipPackagePluginValidation CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO ARCHS="arm64" ONLY_ACTIVE_ARCH=YES SYMROOT="$PWD/Build" \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=NO GCC_TREAT_WARNINGS_AS_ERRORS=NO > tmp/w.log 2>&1
grep -E "deprecated in macOS 13|first deprecated in macOS 13" tmp/w.log | sort -u
```

Then fix:

- Swift deprecations must be fixed (they cannot be suppressed inline).
- ObjC deprecations can be fixed, or wrapped in
  `#pragma clang diagnostic ignored "-Wdeprecated-declarations"` when the
  migration is behaviorally risky (e.g. SCEvents' run-loop -> dispatch-queue
  FSEvents change, for which no upstream/fork migration exists).

**`make clean` gotcha:** the clean target runs `rm -rf ThirdParty && git
checkout ThirdParty`, which reverts uncommitted edits under `ThirdParty/`
(e.g. a SCEvents pragma). Commit ThirdParty fixes before cleaning.

Finish with a clean `make Development` (warnings-as-errors on) to prove it
is green.

## 9. uv Python runtime default

The uv interpreters need macOS 13. Once the floor is 13+, the
`pythonRuntimeUsesUV` advanced-setting default in
`sources/Settings/iTermAdvancedSettingsModel.m` can be plain `YES` (drop
any OS-conditional helper).

## Reference

Prior bumps: the macOS 11->12 change was `8963d0574` (app + rebuilt deps)
plus `fa7b231` (submodule deployment targets, via per-submodule "Bump
deployment target" commits and pointer moves).
