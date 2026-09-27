# uv Python-runtime migration: manual test plan

Covers Phases 0-3 and the follow-ups (Dependency Editor, relocatable venvs). Design
and rationale: `docs/uv-python-runtime-migration.md`.

The migration is gated behind the `pythonRuntimeUsesUV` advanced setting (default NO),
so most of this plan is exercised by turning the gate on in a dev instance. Run
everything in a separate suite so it never touches your real iTerm2.

---

## 0. Environment, setup, and conventions

- **Build & run a dev instance:** `make run` (launches `build/Development/iTerm2.app`
  with `-suite iterm2-alt5`). The suite name is the working-directory basename
  (`iterm2-alt5`). AppleScript-target this instance by its FULL path, not `"iTerm2"`.
- **Suite defaults** (note the advanced-setting key is capitalized-first-letter):
  - Gate on/off: `defaults write iterm2-alt5 PythonRuntimeUsesUV -bool YES` (or `NO`).
  - Enable the API server (needed to launch scripts): `defaults write iterm2-alt5 EnableAPIServer -bool YES`.
  - Set these BEFORE launching the instance (they are read at startup).
- **Paths (this suite):**
  - Scripts: `~/Library/Application Support/iterm2-alt5/Scripts`
  - uv state: `~/Library/Application Support/iterm2-alt5/uv/` (`bin/uv`, `python/`, `cache/`, `venvs/<minor>/`)
  - A full-env script container has: `setup.cfg`, the source under `<name>/<name>.py`,
    and either `iterm2env/` (legacy) or `.venv/` + `python-runtime.json` (uv).
- **Launch a script:** `osascript -e 'tell application "<abs>/iTerm2.app" to launch API script named "NAME"'`
  (or absolute path). Basic scripts are single `.py` files at the top level.
- **Reset uv state between runs:** quit the instance, then
  `rm -rf ~/Library/Application\ Support/iterm2-alt5/uv` and delete any test scripts.
  To reset the gate: `defaults delete iterm2-alt5 PythonRuntimeUsesUV`.
- **Observe results:** Script Console (Scripts menu) shows each script's output and any
  "Script Failed" banner. Backend can be confirmed on disk (`.venv`+`python-runtime.json`
  vs `iterm2env`).

Hardware coverage: run sections 2-8 on **Apple Silicon** and again on an **Intel** Mac
(macOS 13+). Section 1 requires a **macOS 12** machine.

---

## 1. Phase 0: macOS 12 farewell notice (requires macOS 12)

1. On a macOS 12 machine, first launch of the build.
   - Expect: a one-time alert that a future beta requires macOS 13. Dismiss it.
2. Relaunch.
   - Expect: the alert does NOT reappear (one-time via `NoSyncHaveShownMacOS13RequirementNotice`).
3. On macOS 13+: launch the build.
   - Expect: NO alert.

---

## 2. Gate OFF: legacy behavior is unchanged (regression safety)

With `PythonRuntimeUsesUV` unset/NO:

1. Create a new full-environment Python script (Scripts menu > New Python Script >
   Full Environment). Let it install.
   - Expect: it downloads/uses the bundled runtime; the script folder gets `iterm2env/`
     (NOT `.venv`); it launches and can talk to the API.
2. Run a basic script (New Python Script > Basic).
   - Expect: uses the bundled runtime; runs normally.
3. Open the Python REPL (Scripts menu).
   - Expect: apython REPL opens with the iTerm2 banner, as before.
4. Open the Dependency Editor on the full-env script; add/remove a package.
   - Expect: legacy pip3 confirmation + visible pip run, exactly as before.

No `.venv` or `python-runtime.json` should appear anywhere in this section.

---

## 3. Gate ON: fresh provisioning + launch

Set `PythonRuntimeUsesUV YES` and `EnableAPIServer YES`; remove any prior uv state.

1. **First full-env script (cold uv):** create a new Full Environment script.
   - Expect: a "Downloading uv..." window (first time only), then provisioning; the
     folder gets `.venv/` + `python-runtime.json` (`backend: uv`), NOT `iterm2env`.
   - `~/.../uv/bin/uv` exists; `~/.../uv/python/` has the interpreter.
2. **Launch it** and have it use the API (e.g. create a window / set a variable).
   - Expect: launches under `.venv/bin/python` (Script Console shows the command);
     the API action happens; exit 0, no "Script Failed".
3. **Basic script:** create/run a basic script.
   - Expect: a shared venv appears at `~/.../uv/venvs/<minor>/`; the script runs under it.
4. **REPL:** open the Python REPL.
   - Expect: an interactive session running `python -m asyncio`; top-level `await` works
     (`await asyncio.sleep(0)`); the iTerm2 banner shows (the stdlib "Use await" header
     also appears - expected, see docs).
5. **HTTPS from a script:** run a script doing `urllib.request.urlopen("https://example.com")`.
   - Expect: succeeds (SSL_CERT_FILE points at the venv's certifi; no cert error).
6. **pyobjc:** run a script doing `import objc; import AppKit`.
   - Expect: imports succeed.
7. **Import a signed `.its`** full-env script (export one, then import).
   - Expect: signature confirmation, then uv provisioning; the imported script gets a
     `.venv` and launches.

---

## 4. Offline launch (after provisioning)

1. Provision + run a full-env script once (per section 3).
2. Turn off networking (or use Little Snitch / `nettop` to watch).
3. Launch the same script again.
   - Expect: it launches immediately with NO network activity (launch is a bare exec of
     `.venv/bin/python`; no uv, no download).
4. Launch a basic script whose shared venv already exists.
   - Expect: same - offline, immediate.

---

## 5. Migration of existing legacy scripts (gate ON)

1. **Happy path:** with the gate OFF, create a full-env script (gets `iterm2env`). Turn
   the gate ON, relaunch, and launch that script.
   - Expect: on launch it migrates - `iterm2env` is removed, `.venv` + `python-runtime.json`
     appear, no `saved-iterm2env` remains, and it runs under `.venv/bin/python`.
   - Relaunch: no re-migration (it is already uv).
2. **Version-bump warning:** create/hand-place a legacy full-env script whose `setup.cfg`
   has `python_requires = =3.7`. With the gate on, at startup (menu build).
   - Expect: ONE consolidated, permanently-silenceable warning naming that script and
     "3.7 -> 3.9". With several such scripts (incl. one in `AutoLaunch/`): a single
     warning lists all of them. Silence it; relaunch; it does not reappear.
   - After migrating that script: `python-runtime.json` shows `python: 3.9`,
     `remapped_from: 3.7`; it runs on 3.9.
3. **Preserve pinned minor:** legacy script pinned to an available minor (e.g. `=3.10`).
   - Expect: migrates to 3.10 (NOT bumped); no warning for it.
4. **Rollback on failure:** legacy script whose `setup.cfg` lists a bogus dependency
   (e.g. `install_requires = this-package-does-not-exist`). Launch with gate on.
   - Expect: migration fails; `iterm2env` is restored (from `saved-iterm2env`); the
     script still launches on the legacy env; an error is shown with uv's output.
5. **Interrupted-migration recovery (data safety):** launch a legacy script; while it is
   provisioning (downloading Python), Force Quit the app. Inspect the folder: it should
   have `saved-iterm2env` and possibly a partial `.venv`, and no `iterm2env`.
   - Relaunch and launch the script again.
   - Expect: the orphaned `saved-iterm2env` is recovered (never deleted); migration
     retries cleanly; the environment is never lost even if the retry also fails.

---

## 6. Gate toggling (never strands a provisioned script)

1. Provision a script under uv (gate on). Turn the gate OFF, relaunch.
   - Expect: the uv script STILL launches under its `.venv` (launch keys off on-disk
     state, not the gate). New scripts created now use the legacy runtime.
2. Turn the gate back ON.
   - Expect: uv scripts still launch under `.venv`; legacy scripts migrate on launch.

---

## 7. Dependency Editor (uv script)

On a uv-backed full-env script, open the Dependency Editor:

1. The Python-version popup shows a single version (the `.venv` minor from the marker).
2. **Add** a package (e.g. `requests`).
   - Expect: a confirmation showing a `uv pip install ... --only-binary :all: --python
     <.venv>/bin/python` command; a visible session runs it; the package appears in the
     table with its version; `setup.cfg` gains the dependency.
3. **Check for Updates** on a package.
   - Expect: runs `uv pip install <pkg> --upgrade ...`; version column refreshes.
4. **Remove** a package.
   - Expect: runs `uv pip uninstall ...`; the package leaves the table; `setup.cfg`
     drops it.
5. **Upgrade a basic script to full environment** (Dependency Editor upgrade action) with
   the gate on.
   - Expect: it builds a `.venv` (NOT `iterm2env`); the upgraded script is uv-backed.
6. Repeat 1-4 on a LEGACY script (gate off, or a not-yet-migrated one).
   - Expect: unchanged legacy pip3 behavior.

---

## 8. macOS-floor / availability edge

1. (If testable) On a macOS version below uv's manifest `minimum_macos_version`, trigger
   provisioning.
   - Expect: a clear "uv is not available for this version of macOS" error; no crash.
2. Confirm the interpreter architecture matches the host: on Intel,
   `file ~/.../uv/python/*/bin/python3*` reports `x86_64` (native, not Rosetta); on Apple
   Silicon, `arm64`.

---

## 9. Concurrency

1. Put several full-env scripts (or one plus the REPL) in `AutoLaunch/` with the gate on,
   cold uv state. Launch the instance so they start together.
   - Expect: uv downloads once (not once per script); shared per-minor venvs are built
     without corruption; every script/REPL comes up. No duplicate download windows.

---

## 10. Moved / renamed script folder (relocatable venvs)

1. Provision a uv full-env script; quit the instance.
2. Rename its folder (e.g. `Scripts/Foo` -> `Scripts/Bar`, and the inner `Foo/Foo.py`
   accordingly) or move it.
3. Relaunch and run it.
   - Expect: it still runs (venvs are created `--relocatable`; `.venv/bin/python` stays
     valid), imports work, HTTPS works.

---

## 11. macOS 27 (Rosetta removed)

Run on a macOS 27 beta (Rosetta 2 cannot be installed there). An "x86 fixture env"
means a legacy full-env script whose `iterm2env` python is Intel-only (copy one from a
macOS <= 26 install, or an old backup).

1. No Rosetta prompt, ever: with the gate OFF and no Python runtime installed, launch
   any Python script.
   - Expect: no "Install Rosetta?" dialog and no `softwareupdate --install-rosetta`
     window at any point.
2. Gate OFF, fresh install: launch a basic script with no runtime present.
   - Expect: the runtime downloads and is Apple Silicon (`file` on the runtime python
     shows arm64); the script runs.
3. Gate OFF, x86 fixture full-env script: launch it.
   - Expect: a Script Console line saying it is Intel-only and being rebuilt for Apple
     Silicon; the env is rebuilt from setup.cfg (arm64) and the script runs. If the
     rebuild fails, a clear error appears (not a cryptic exec failure).
4. Gate OFF, x86 fixture shared runtime: with an Intel-only shared runtime present,
   launch a basic script.
   - Expect: the shared runtime is replaced with the arm64 build and the script runs
     (or a clear "could not download" error, never an exec failure).
5. Gate ON, legacy script: launch an un-migrated legacy full-env script.
   - Expect: it migrates to uv and runs.
6. Gate ON, forced migration failure (e.g. add a bogus dependency to setup.cfg so the
   uv provision fails) on an x86 fixture env:
   - Expect: rollback restores `saved-iterm2env`; a clear alert + Script Console error
     says the env is Intel-only and cannot run, and to turn off the uv setting to
     rebuild. No exec failure, and the script folder is intact.

---

## Cleanup

Quit the instance; `rm -rf ~/Library/Application\ Support/iterm2-alt5/uv` and any test
scripts; `defaults delete iterm2-alt5 PythonRuntimeUsesUV`.
