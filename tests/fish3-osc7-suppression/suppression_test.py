#!/usr/bin/env python3
"""End-to-end test of fish OSC 7 native-emitter suppression + machineID reporting.

Runs the REAL assembled Resources/shell_integration/iterm2_shell_integration.fish
against a given fish binary in a pty, exercising BOTH install orders:

  * manual  - `source ~/.iterm2_shell_integration.fish` in config.fish (pre-prompt)
  * loader  - the injected OtherResources/vendor_conf.d loader (first-prompt)

For each it asserts that after startup the native emitter is silenced (no OSC 7
lacking ?machineID= during two cd's) and that our machineID reports are emitted.

This exists because the regression it guards against only reproduces on fish 3.x
(where __fish_config_interactive defines __update_cwd_osc UNCONDITIONALLY, with no
`functions --query` guard), and the hermetic encoder suite cannot build fish 3.x.
See README.md for how to build a fish 3.x binary to point this at.

Usage:  FISH=/path/to/fish3/build/fish python3 suppression_test.py
        python3 suppression_test.py /path/to/fish            (arg overrides $FISH)
"""
import os, sys, tempfile, shutil, re, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
INTEG = os.path.join(REPO, "Resources/shell_integration/iterm2_shell_integration.fish")
LOADER = os.path.join(REPO, "OtherResources/vendor_conf.d/iterm2-shell-integration-loader.fish")

FISH = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("FISH", "fish"))


def _run(env):
    # Drive a real interactive fish under `script` (a pty), the same mechanism the
    # hermetic encoder suite uses - reliable across fish versions where a raw
    # pty.fork + termios dance was not. Read to process exit so nothing is truncated.
    # The two cd's each render a fresh prompt, so a live native emitter leaks one bare
    # OSC 7 per cd, pushing the total above the single startup run-once. macOS `script`
    # syntax: `script -q /dev/null <cmd...>`.
    out = subprocess.run(["script", "-q", "/dev/null", FISH, "-i"],
                         input="cd /tmp\ncd /usr\nexit\n",
                         capture_output=True, text=True, env=env, timeout=30)
    return out.stdout + out.stderr


def _analyze(data):
    all7 = re.findall(r"\x1b\]7;(file://[^\x07]*)\x07", data)
    return {
        "bare_total": [t for t in all7 if "machineID=" not in t],
        "ours_total": [t for t in all7 if "machineID=" in t],
        "all": all7,
    }


def _base_env(home):
    env = dict(os.environ)
    env.update(HOME=home, XDG_CONFIG_HOME=home + "/.config",
               XDG_DATA_HOME=home + "/.local/share",
               TERM="xterm-256color", TERM_PROGRAM="iTerm.app", LC_TERMINAL="iTerm2")
    return env


def test_manual():
    root = tempfile.mkdtemp()
    try:
        home = root + "/home"
        os.makedirs(home + "/.config/fish"); os.makedirs(home + "/.local/share")
        shutil.copy(INTEG, home + "/.iterm2_shell_integration.fish")
        with open(home + "/.config/fish/config.fish", "w") as f:
            f.write("source $HOME/.iterm2_shell_integration.fish\n")
        env = _base_env(home); env["XDG_DATA_DIRS"] = root + "/empty"
        return _analyze(_run(env))
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_loader():
    root = tempfile.mkdtemp()
    try:
        home = root + "/home"; V = root + "/vendored"
        os.makedirs(home + "/.config/fish"); os.makedirs(home + "/.local/share")
        os.makedirs(V + "/fish/vendor_conf.d")
        shutil.copy(LOADER, V + "/fish/vendor_conf.d/iterm2-shell-integration-loader.fish")
        shutil.copy(INTEG, V + "/iterm2_shell_integration.fish")
        env = _base_env(home)
        env["XDG_DATA_DIRS"] = V
        env["IT2_FISH_XDG_DATA_DIRS"] = V
        return _analyze(_run(env))
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main():
    try:
        ver = subprocess.run([FISH, "--version"], capture_output=True, text=True).stdout.strip()
    except Exception as e:
        print(f"cannot run fish at {FISH!r}: {e}"); return 2
    print(f"fish: {FISH}\n{ver}\n")
    ok = True
    for name, fn in [("manual (config.fish, pre-prompt)", test_manual),
                     ("loader (vendor_conf.d, first-prompt)", test_loader)]:
        r = fn()
        ours = len(r["ours_total"]); bare = len(r["bare_total"])
        # <=1 bare total means at most the startup run-once; a surviving native
        # emitter adds one bare per cd, pushing this to >=3.
        passed = bare <= 1 and ours >= 2
        ok = ok and passed
        print(f"[{'PASS' if passed else 'FAIL'}] {name}")
        print(f"       bare native OSC 7 (total):   {bare}  (want <=1: only startup run-once)")
        print(f"       our machineID reports:       {ours}  (want >=2)")
        if not passed:
            for t in r["all"]:
                print(f"         [{'OURS ' if 'machineID=' in t else 'NATIVE'}] {t[:88]}")
    print("\nRESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
