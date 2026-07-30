# Replacing the bundled Python runtime with uv

## Status

Design + implementation plan. Investigation complete; decisions locked. Target: iTerm2
3.7.x (post-beta) or 3.8.

## Build process (per phase - follow strictly, in phase order)

Each phase is executed with TDD using this loop:

1. Write tests (failing first).
2. Implement.
3. Run tests; iterate until the code is correct and tests pass.
4. Launch a subagent to review the code.
5. Address its findings. Go to step 4 until no meaningful issues remain.
6. Proceed to the next phase.

Phases run in order: Phase 0 (notice beta) -> 1 (provisioner) -> 2 (provision/launch)
-> 3 (migration) -> 4 (target bump + enable) -> 5 (delete legacy).

### Development uv source (temporary)

Until the signed universal binary is hosted on iterm2.com with the min/max-macOS
manifest (a release-infra task owned by the author, needed before the Phase 4 beta),
use this URL for the uv download during development:

    https://releases.astral.sh/github/uv/releases/download/0.12.0/uv-aarch64-apple-darwin.tar.gz

Notes: this is an arch-specific (aarch64) `.tar.gz`, not the eventual `lipo`'d universal
binary, and it is served from Astral's mirror, not iterm2.com. Signature verification
and the manifest are stubbed/relaxed against this dev source and wired up for real when
hosting moves to iterm2.com.

## Motivation

iTerm2 ships a hand-built Python runtime (multiple CPython versions, the `iterm2`
module, and pyobjc as an optional extra) as an on-demand optional component. It is
built outside this repo by two sibling projects:

- `~/git/iterm2-pyenv` (orchestration scripts + built zips)
- `~/git/pyenv` (a fork of pyenv whose `python-build` compiles CPython and every C
  dependency from source, statically, to avoid depending on Homebrew/system libs)

Problems:

- The build is a pile of hacks: static readline 8.3 built privately, gdbm without
  readline, static openssl/sqlite/xz/zlib/zstd/gettext, `fdupes` hardlink dedupe,
  `templatize.sh` path rewriting (`__ITERM2_ENV__` / `__ITERM2_PYENV__`), an
  interactive `read`-gated pip dance run twice "to beat pip into submission,"
  RSA-signed delta zips.
- It is single-arch. The pyenv fork already flipped to arm64-only at runtime build
  80, and the app already splits manifests by OS (`manifest.json` vs
  `manifest-new.json`, `iTermAdvancedSettingsModel.m:940-948`).
- macOS 27 (September 2026) drops Rosetta 2, so an Intel binary can no longer run on
  Apple Silicon. Intel users (on macOS <=26) must still be supported, which today
  means maintaining the hack pipeline for that arch too.

The reason the runtime exists in the first place remains true: we cannot assume the
user has build tools or Homebrew.

## Why uv solves it

uv provisions Python from **python-build-standalone**, which ships **native x86_64
and native arm64** macOS binaries (deployment floors 10.9 / 11.0), with **no compiler
required** on the user's machine. That is exactly the constraint that motivated the
custom runtime, satisfied by prebuilt binaries. uv itself is a single standalone Rust
binary; it does not need Python to run.

Result: native Intel Python without Rosetta, native ARM Python from the same tool,
and the entire compile pipeline is deleted.

Key facts:

- uv env vars we rely on: `UV_PYTHON_INSTALL_DIR`, `UV_CACHE_DIR`,
  `UV_PYTHON_PREFERENCE=only-managed`, `UV_NO_CONFIG`, `UV_PYTHON_INSTALL_MIRROR`
  (deferred; see below), `UV_PYTHON_DOWNLOADS`.
- python-build-standalone offers CPython ~3.8 through ~3.14. 3.7 is not available.
- uv's own supported macOS floor is 13 (Ventura).

## Locked decisions

1. **uv delivery: download on demand.** A signed, `lipo`'d universal uv binary hosted
   on iterm2.com, fetched via the existing signature-verified optional-component
   downloader on first Python-scripting use. Not bundled in the app.
2. **Python source: upstream python-build-standalone** (uv's default). A self-hosted
   mirror via `UV_PYTHON_INSTALL_MIRROR` is a drop-in fallback for later; no
   architectural change needed to add it. Pin a known-good uv version rather than
   always pulling latest.
3. **Deployment target: bump the app from macOS 12 to macOS 13**, but only after a
   farewell-notice beta warns macOS 12 users (Phase 0), and the eventual 13-only build
   is gated by Sparkle `minimumSystemVersion` so 12 users are never offered an
   unlaunchable update. The bump itself is deferred to Phase 4 (paired with enabling
   uv). This meets uv's supported floor head-on and removes the need to verify uv on
   12. (The target was set to 12 in commit `8963d0574`, 2025-07-02.)
4. **Per-script metadata: keep `setup.cfg`.** Reuse `iTermSetupCfgParser` unchanged;
   drive `uv venv` + `uv pip install` from it. No pyproject.toml migration now.
5. **uv only at provision time; launch is a bare exec of the venv Python.** No uv
   process and no network on any script launch. uv (and the network) are involved
   only when creating, importing, migrating, upgrading, or editing dependencies.
   This makes "basic-script launch is offline" an architectural guarantee.
6. **Do not conflate uv artifacts with the legacy `iterm2env` names.** Old iTerm2
   builds locate a runtime by the exact strings `iterm2env` / `saved-iterm2env` and
   read `iterm2env-metadata.json`, expecting the pyenv tree layout. uv artifacts use
   new names so an old build sees "no runtime I recognize" and declines gracefully
   instead of misreading a flat venv.
7. **Forced Python-version remap only for 3.7.** python-build-standalone has no 3.7.
   Everything 3.8+ keeps its pinned minor. 3.7 is remapped to **3.9** (last release
   before the 3.10 `collections.abc` alias removal; negligibly riskier than 3.8 and
   avoids the one genuinely disruptive removal). Any forced minor bump is announced
   with a suppressible modal warning, not just a Script Console line.
8. **Drop `aioconsole`/`apython`.** stdlib `python -m asyncio` provides top-level
   `await` (since 3.8), which was apython's only real benefit.
9. **Gate the whole change behind an advanced setting; keep both code paths during
   development.** A boolean `iTermAdvancedSettingsModel` setting (proposed
   `pythonRuntimeUsesUV`, default NO) selects the runtime backend. Default NO means
   shipping `master` behaves exactly as today, so development happens on `master`
   without a long-lived branch. This is a genuine behavior toggle the user sets
   intentionally, so it is a normal (syncable) advanced setting, not `NoSync`. The
   legacy path and the uv path coexist until Phase 5 removes the setting and the
   legacy code together.

## Development gating (transitional)

The setting has an asymmetric effect, which is what makes both paths safe to coexist:

- **Provisioning branches on the setting.** Creating, importing, migrating, or
  editing dependencies of a script uses uv iff the setting is ON. With it OFF, all of
  these behave exactly as today (download the bundled runtime, pyenv tree layout, no
  auto-migration). uv is downloaded lazily on first provisioning, so users who never
  enable it never fetch it.
- **Launch branches on what is on disk, NOT on the setting.** A script with `.venv` +
  `python-runtime.json` launches via `exec .venv/bin/python`; a script with a legacy
  `iterm2env` launches the legacy way. So toggling the setting never strands an
  already-provisioned script - a uv-provisioned script keeps working even after the
  setting is turned back off (its launch is just a bare python exec and needs no uv),
  and a legacy script keeps working with the setting on until it is actually migrated.

Lifecycle of the default (there is no telemetry; rollout is by flipping the default,
not by measuring adoption):

1. Development: default NO, deployment target still macOS 12. `master` ships today's
   behavior; the author flips the gate on locally (on macOS 13+) to test. A separate
   Phase 0 notice beta warns macOS 12 users of the coming drop.
2. Beta: when ready, bump the deployment target to macOS 13 (Phase 4) and in the same
   beta flip the default to YES for all beta users. Both code paths still exist, so the
   gate remains an escape hatch - a user hitting a problem can turn it off and fall back
   to the legacy runtime. macOS 12 users are not offered this build (appcast
   `minimumSystemVersion`).
3. Stable: keep the default YES in stable releases.
4. Only after uv has shipped as the default through a beta cycle and into stable does
   Phase 5 remove the setting and the legacy path.

## What does NOT change (runtime swap, not a protocol change)

- The API transport and auth: unix socket at `.../private/socket`, TCP `localhost:1912`
  fallback, `api.iterm2.com` subprotocol, and the `ITERM2_COOKIE`/`ITERM2_KEY`
  cookie-and-key AppleScript handshake. `it2cli` and every existing `iterm2` client
  keep working. No wire break.
- The `iterm2` PyPI module (vendored at `api/library/python/iterm2/`) and its minimum
  library version gate 0.24 (`iTermWebSocketConnection.m:31`).
- The spaceless AppSupport symlink (`NSFileManager+iTerm.m:183`) — kept; venv shebangs
  still dislike spaces.
- `iTermSignatureVerifier` + `rsa_pub.pem` — repurposed to verify the uv binary.

## Target on-disk layout

- uv binary: `<spacelessAppSupport>/uv/bin/uv`
- uv-managed interpreters: `<AppSupport>/uv/python/` (`UV_PYTHON_INSTALL_DIR`)
- uv cache: `<AppSupport>/uv/cache/` (`UV_CACHE_DIR`)
- shared basic-script venvs: `<AppSupport>/uv/venvs/<minor>/`
- per full-env script venv: `<script>/.venv/` (flat `bin/python`)
- per full-env script marker: `<script>/python-runtime.json`, schema:
  `{ "schema": 1, "backend": "uv", "uv_version": "...", "python": "3.9.x", "remapped_from": "3.7" }`

Launch contract (both kinds): `exec <venv>/bin/python <main.py> <args>` with
`ITERM2_COOKIE` / `ITERM2_KEY` / `SSL_CERT_FILE` in the environment. No uv, no network.

## Phase 0 - macOS 12 farewell notice beta (ships first, still supports macOS 12)

Bumping the deployment target strands macOS 12 users unless they get advance notice
first: their Sparkle updater would otherwise offer a 13-only build they cannot launch.
So the first shipped step is a notice, NOT the bump.

1. Release a 3.7.0 beta that still runs on macOS 12 (no deployment-target change) which
   shows macOS 12 users a notice: future 3.7.0 betas will require macOS 13 (Ventura) or
   later; this is the last beta that supports macOS 12. One-time / suppressible, stored
   under a `NoSync` flag.
2. This is decoupled from the uv work and requires none of it - ship it as early as
   possible to maximize advance notice.
3. Release-engineering plan for the eventual 13-only build (Phase 4): its Sparkle
   appcast entries must set `minimumSystemVersion = 13.0` so macOS 12 users are never
   offered an update they cannot launch and instead remain on this last-compatible
   beta. Confirm the shipping Sparkle honors per-item `minimumSystemVersion` (it does).

Exit: a beta is published warning macOS 12 users, and the appcast-gating plan for the
future 13-only build is confirmed.

Note on sequencing: Phases 1-3 (the uv implementation) are built with the deployment
target still at macOS 12 and the `pythonRuntimeUsesUV` gate defaulting OFF, so they can
merge to `master` and even ship in further macOS-12-compatible betas without affecting
anyone. The developer tests them locally on macOS 13+ with the gate on. The actual
target bump is deferred to Phase 4.

## Phase 1 - The uv provisioner (`sources/API/iTermUv`)

1. Acquire uv via the existing `iTermOptionalComponentDownloadWindowController`
   phases: download signed universal uv from `iterm2.com/downloads/uv/`, verify with
   `iTermSignatureVerifier` + `rsa_pub.pem`, install to `<spacelessAppSupport>/uv/bin/uv`,
   chmod +x.
2. Manifest is a list of entries, each
   `{ uv_version, url, signature, size, minimum_macos_version, maximum_macos_version }`.
   The app selects the newest entry whose macOS bracket includes the running OS and
   never downloads one outside it. This mirrors the legacy runtime manifest's
   `minimum_iterm_version`/`maximum_iterm_version` bracketing. Consequence: uv's
   supported macOS floor can never strand a user - a future uv that drops macOS 13 is
   simply not offered to macOS 13 users, who keep the last bracketed-compatible build.
   Each hosted uv version is pinned and tested; bump deliberately on iTerm2 releases
   via `performPeriodicUpgradeCheck`.
3. Provision-time environment (uv subprocesses only):
   - `UV_PYTHON_INSTALL_DIR = <AppSupport>/uv/python`
   - `UV_CACHE_DIR = <AppSupport>/uv/cache`
   - `UV_PYTHON_PREFERENCE = only-managed`
   - `UV_NO_CONFIG = 1`
   - `UV_PYTHON_DOWNLOADS = automatic`
4. Pure, testable arg builders: `venvArgs`, `pipInstallArgs`, `pythonListArgs`
   (discover which minors pbs offers).
5. `iTermUv` and the runtime downloader are defined behind protocols so tests can
   inject a fake (see Testing). Bake this into the API from the start.

Exit: given a version, `iTermUv` produces a working venv with `iterm2` installed.

## Phase 2 - Provision and launch

### 2a. Full-environment scripts

- `iTermPythonRuntimeDownloader.installPythonEnvironmentTo:...` (`:865`): replace the
  hard-link + shebang-rewrite + serial `pip3` block with `uv venv` at `<script>/.venv`
  + `uv pip install` the setup.cfg deps (`iterm2` still force-added).
- Write `<script>/python-runtime.json` (schema above).
- Teach `environmentForScript:` / `populateScriptItem:` / the launcher interpreter
  lookup the new `.venv` + `python-runtime.json` names and the flat `bin/python`
  layout. Legacy is distinguished by "has `iterm2env`" vs "has `.venv` +
  `python-runtime.json`."

Current full-env layout (for reference):

    Scripts/MyScript/
      setup.cfg
      metadata.json          (optional)
      iterm2env/             recursive hard-link clone of the shared runtime
        versions/<X.Y.Z>/bin/python3
      MyScript/
        MyScript.py          the main script

Only `iterm2env/` changes (-> `.venv/`, plus the new `python-runtime.json`);
`setup.cfg` and the `MyScript/MyScript.py` source layout are untouched.

#### Disk sharing, interpreter retention, relocation

Today each script's `iterm2env` is a recursive hard-link clone of the shared runtime
(`installPythonEnvironmentTo:` -> `linkItemAtPath:`, `:891`), purely so N scripts cost
~1 runtime on disk (with copy-on-write for the few rewritten files, e.g. the pip3
shebang). uv preserves this dedup differently, and we DELETE the manual hard-link
machinery:

- Interpreter is shared, not copied: `.venv/bin/python` is a symlink to the single
  managed interpreter in `UV_PYTHON_INSTALL_DIR`. The interpreter lives once and every
  venv points at it.
- Package files are shared via uv's global cache using `UV_LINK_MODE` (default `clone`
  / APFS reflink on macOS, falling back to `hardlink`, then `copy`). Set
  `UV_LINK_MODE=clone` explicitly.

Consequences:

- Same-volume assumption: clone/hardlink needs the venv and cache on one volume. Both
  live under the user's home, so normally fine; a script on another volume falls back
  to `copy` (works, more disk).
- Interpreter retention: because venvs symlink the managed interpreter, never GC an
  interpreter minor while any venv references it. This replaces the current
  runtime-version GC (`finishInstallingRuntimeVersion:`) with a simpler "keep
  interpreters some venv uses" rule.
- Relocation: uv bakes absolute paths into `pyvenv.cfg` and console-script shebangs.
  We create `.venv` in-place at the final path, so no templatization is needed (this
  is why `__ITERM2_ENV__` / `performSubstitutions:` can be deleted). Moving/renaming a
  script dir later breaks its `.venv` - the same failure mode as moving a substituted
  `iterm2env` today. Mitigation: detect a path mismatch on launch and re-provision
  (cheap with uv).

### 2b. Basic scripts (shared venv, eager, offline launch)

- Maintain a shared venv per Python minor at `<AppSupport>/uv/venvs/<minor>/` with
  `iterm2` installed, provisioned eagerly (during the download/setup step, with
  progress UI). Launch execs its `bin/python` directly - guaranteed offline.
- `pathToStandardPyenvPythonWithPythonVersion:` returns the shared venv `bin/python`.
  A basic script's shebang selects the minor; provision that minor on first use if
  absent.

### 2c. REPL - drop aioconsole

- Replace bundled `aioconsole`/`apython` with stdlib `python -m asyncio` run against
  the shared venv, same cookie/key env (`iTermApplicationDelegate.m:3208`). A tiny
  startup shim blanks the stdlib REPL header so `repl_banner.txt` still shows
  (cosmetic).

### 2d. Certs

- `uv pip install certifi` into each venv; set `SSL_CERT_FILE` = `certifi.where()`.
  Drop `SSL_CERT_DIR` (the openssl tree is gone). Localhost API traffic needs no TLS;
  this matters only for user scripts making HTTPS calls.

Exit: new full-env script, basic script, and REPL run end-to-end on 13; socket
round-trip + `import objc` verified; basic-script launch confirmed to make no network
call.

## Phase 3 - Migration of existing installs

- Detection: a script with a legacy `iterm2env` and no `python-runtime.json` is
  legacy and must be migrated. (No integer "generation" number - that would reuse the
  conflated metadata we are moving away from.)
- Timing: migrate EAGERLY when the `pythonRuntimeUsesUV` gate is first enabled - scan
  all full-env scripts, compute which need a forced minor bump, show the one
  consolidated warning, then migrate them all. This pairs with the batched warning and
  makes testing deterministic (flip it, everything migrates). Newly imported/created
  scripts while the gate is on are provisioned via uv directly.
- Shebangs: no user-authored file is edited. iTerm2 never executes a script via its
  shebang - the launcher invokes the interpreter explicitly (`argumentsToRunScript:`
  -> `it2_api_wrapper.sh <venv-python> <script.py>`), so a `.py` shebang is used only
  by `inferredPythonVersionFromScriptAt:` for version inference. Basic-script shebangs
  are left stale-but-harmless (re-inferred and re-remapped each launch). Full-env main
  scripts are untouched. `setup.cfg` `python_requires` is ALSO left as-is: the
  authoritative resolved version for a uv script is the `python-runtime.json` marker
  (which records `python` and `remapped_from`), and re-resolving a stale pin is
  idempotent (3.7 re-resolves to 3.9 again), so rewriting setup.cfg would only risk
  clobbering the user's other setup.cfg content for no behavioral gain. The one shebang
  rewrite done today
  (`replaceShebangInScriptAtPath:`, `:913`, fixing the pip3 console-script) is deleted
  outright - uv writes correct absolute shebangs for `.venv/bin/*` itself.
- Rebuild-with-rollback: reuse `upgradeFullEnvironmentScriptAt:` (`:62`) structure -
  move `iterm2env` -> `saved-iterm2env`, provision `.venv` via uv from setup.cfg,
  restore on failure. `saved-iterm2env` remains understandable to old builds if the
  user downgrades.
- Version remap (minimal, compatibility-preserving):
  - Preserve the pinned minor whenever pbs offers it (discover via `uv python list`).
  - Auto-bump patch only (e.g. 3.9.2 -> newest 3.9.x); no warning.
  - Force a minor bump only when pbs has no build for that minor - in practice only
    3.7 -> 3.9. The resolved version is recorded in `python-runtime.json`; setup.cfg
    and shebangs are left as-is (inference/re-resolution is idempotent).
- Warning for forced minor bumps (real dialog, not just console):
  - One consolidated modal `iTermWarning` at migration listing every affected script
    (e.g. `"MyScript": 3.7 -> 3.9`), not one dialog per script.
  - Body states plainly that Python minor versions are not guaranteed source-
    compatible, so a script may need changes.
  - Permanent stifle via `iTermWarning`'s suppression identifier under a
    `NoSync`-prefixed key ("Don't warn me about Python version changes again").
  - Also log per-script old->new to the Script Console as the durable record.
- Migration only runs when the `pythonRuntimeUsesUV` gate is ON (see "Development
  gating"). With the gate OFF, legacy scripts are left untouched and run the legacy
  way.
- Escape hatch / fallback: if uv provisioning fails but an installed legacy
  `iterm2env` still runs, fall back to it rather than hard-failing (in addition to the
  gate, which can be turned off entirely).

Exit: a legacy full-env script, a legacy basic script (incl. a 3.7 one triggering the
warning), and a signed `.its` import all migrate and run; rollback verified by forcing
a failure.

## Phase 4 - Bump deployment target to macOS 13 and enable uv in beta

This is where macOS 12 is actually dropped. It is deferred to here (not Phase 0)
because uv requires macOS 13, so the target bump and enabling uv ship together, and
only after the Phase 0 notice beta has given macOS 12 users warning.

1. `iTerm2.xcodeproj/project.pbxproj`: `MACOSX_DEPLOYMENT_TARGET` 12 -> 13, all targets
   (mirror commit `8963d0574`; redo its dep rebuild if needed).
2. Update the two CLAUDE.md "deployment target is macOS 12" lines to 13.
3. Simplify now-dead `@available(macOS 13, *)` branches opportunistically.
4. In the SAME beta, flip the `pythonRuntimeUsesUV` default to YES (rollout step: beta
   default ON). uv needs macOS 13, so the bump and the enable are one release.
5. The 13-only Sparkle appcast entries set `minimumSystemVersion = 13.0` (planned in
   Phase 0); macOS 12 users, already warned, are not offered this build.
6. Build + `make run` smoke test on macOS 13.

Exit: a macOS-13-only beta ships with uv on by default.

## Phase 5 - Delete the old machinery (follow-up release)

Trigger: after uv has shipped as the default (gate YES) through a beta cycle and into
stable releases. There is no telemetry; this is a deliberate decision once uv-by-
default has proven out in the field, not a measured-adoption threshold.

- Make uv unconditional: delete the `pythonRuntimeUsesUV` advanced setting and the
  legacy provisioning path it guarded (the launch path already keys off on-disk state,
  so it needs only the legacy branch removed).
- Remove manifest complexity: `parsedManifestFromInputStream:` version/OS filtering,
  the site-packages delta fields, the `manifest.json` / `manifest-new.json` split
  (`iTermAdvancedSettingsModel.m:940-948`).
- Remove pyenv-tree code: `performSubstitutions:` (`__ITERM2_ENV__` / `__ITERM2_PYENV__`),
  `createDeepLinkTo:`, `pythonVersionsAt:` / `bestPythonVersionAt:`,
  `finishInstallingRuntimeVersion:` GC.
- Keep `iTermSignatureVerifier` + `rsa_pub.pem` (now verifies the uv binary).
- Retire the external build repos (`~/git/iterm2-pyenv`, the `~/git/pyenv` fork);
  stop hosting runtime zips once no supported iTerm2 fetches them.

## Testing

Integration and end-to-end tests are the primary way this change is derisked. The
riskiest parts are not the branching logic (easy to unit test) but the real chain:
uv provisions a native interpreter with no compiler -> installs iterm2/pyobjc from
wheels -> a launched script connects over the socket, authenticates, and drives the
API. The tests are tiered so the fast, hermetic ones run by default and the
network/hardware-bound ones run in a separate harness (mirroring the existing
`tools/run_ai_live.sh` split).

### Fidelity principle: the real uv carries the derisking

Testing orchestration against a FAKE uv only proves our code handled the result we
pretended uv returned. The actual risk here is uv's real contract - its venv layout,
exit codes, error text, interpreter selection - so a fake can pass while the real thing
drifts. Therefore the migration flow, provisioning, and rollback are all exercised
against the REAL uv (offline, against a primed pinned cache) in Tiers B/C, including a
real rollback triggered by a genuinely failing input (a bogus dependency, which fails
deterministically), not a simulated failure.

The split below is about WHICH suite, not fake-vs-real: the default ModernTests run
must be hermetic, zero-setup, and network-free, so it holds only what needs no uv at
all plus a few narrow seam-based checks. Everything needing real fidelity runs in the
harness.

- Pin an exact uv version and exact Python patch versions for reproducibility. Use a
  persistent `UV_CACHE_DIR` + `UV_PYTHON_INSTALL_DIR` so harness runs are warm and can
  run `--offline` after one priming run.
- Network-bound tests tolerate slowness (generous timeouts, retry transient network)
  per the no-flaky-tests rule and live outside the default ModernTests run.

### Tier A - hermetic tests (ModernTests, default run, no network, no real uv)

- Remap decisions (pure functions, no uv): preserve pinned minor, patch-only
  auto-bump, forced 3.7 -> 3.9, over an in-memory available-versions list.
- Launch-command construction: bare `exec <venv>/bin/python` with no uv in the command,
  correct env (`ITERM2_COOKIE`/`ITERM2_KEY`/`SSL_CERT_FILE`), backend selection driven
  by on-disk state (`.venv` vs `iterm2env`) independent of the gate.
- Downgrade-safety invariant: a migrated layout has no `iterm2env` +
  `iterm2env-metadata.json` an old build would misread.
- Consolidated warning batching: one warning listing many affected scripts + the
  suppression key. Uses the injectable seam to avoid provisioning N real envs; it
  simulates provisioning EFFECTS and does NOT assert exact uv arg strings (brittle,
  low value).

The injectable `iTermUv` seam exists only for these narrow cases (scale, isolation,
and precise failure injection where useful) - not as a fidelity substitute for the
real uv, which covers the full migration path in Tiers B/C.

### Tier B - provisioning integration (new harness, network, no full app)

New `tools/run_python_runtime_e2e.sh` (modeled on `run_ai_live.sh`), scoped by filter:

- Download + verify the signed uv binary.
- `uv venv` + install `iterm2 pyobjc certifi` with `--only-binary=:all:` - a passing
  install PROVES no compiler is needed for the standard dep set.
- Assert: `.venv` layout + `python-runtime.json`; `import iterm2`; `import objc` plus
  touching an AppKit symbol; `certifi.where()` resolves; selected Python version;
  and native arch (`platform.machine()` == host, no Rosetta).

### Tier C - end-to-end: a script drives the API (flagship)

Stand up a real API endpoint and run a provisioned script against it:

- Server: instantiate `iTermAPIServer` in-process bound to a temp socket (it is a
  plain instantiable class) and wire it to a test request handler that records/asserts
  the API operations the script performs. No full-app launch needed.
- Provision a script whose body connects via `iterm2` and performs an observable op
  (set a user variable / register an RPC / create a window), launch it through the real
  `iTermAPIScriptLauncher`, and assert the op landed and the child exited 0.
- Transport assertions: cookie/key auth accepted; unix socket path resolution and the
  TCP 1912 fallback; an HTTPS fetch inside the script succeeds (validates
  `SSL_CERT_FILE`/certifi).
- Offline relaunch: block network, relaunch, assert success (launch is a bare exec)
  and that the cache is untouched.
- Real migration (real uv): take a legacy full-env script fixture, run the ACTUAL
  migration, then assert the migrated script connects and drives the API. Include a
  real rollback case (migrate with a bogus dependency) asserting `iterm2env` is restored
  from `saved-iterm2env` and the script still runs.
- Matrix: basic / full-env / migrated-legacy x fresh-cache / warm-cache, gate ON; plus
  a gate-OFF run asserting the legacy path still works, and a toggle run (provision via
  uv, flip gate OFF, assert it still launches).

### Tier D - cross-architecture

Run tiers B and C on both an Intel and an Apple Silicon Mac on macOS 13. The Intel run
proves the core motivation (native x86_64 Python, no Rosetta).

### Follow-up

Add a CLAUDE.md workflow note (like the `run_ai_live.sh` one) directing that changes to
the uv provisioner / launcher / migration run `tools/run_python_runtime_e2e.sh`.

## Risks

- uv's macOS floor: RESOLVED by the manifest's `minimum_macos_version` /
  `maximum_macos_version` fields (Phase 1) - the app only ever downloads a uv build
  whose bracket includes the running OS, so a future uv that drops an older macOS is
  never offered to those users.
- python-build-standalone longevity: accepted. GitHub is not going away in the relevant
  horizon; the self-hosted mirror (`UV_PYTHON_INSTALL_MIRROR`) remains a drop-in
  fallback if that ever changes.

No open decisions remain. (3.7 -> 3.9 confirmed; in-process `iTermAPIServer` for Tier C
confirmed; injectable `iTermUv` seam is a settled Phase 1 constraint; wheel-only install
of iterm2/pyobjc/protobuf/websockets is covered by Tier B.)
