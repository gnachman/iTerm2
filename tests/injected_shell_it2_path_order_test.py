#!/usr/bin/env python3
# Whether ~/.iterm2/bin ends up first on PATH in a shell iTerm2 injected shell integration into,
# after every startup file has run.
#
# Over SSH Integration (it2ssh) iTerm2 uploads its it2 to ~/.iterm2/bin and the shell-integration
# scripts put that directory first on PATH, so iTerm2's it2 wins over a pip or Homebrew it2. For
# zsh the scripts are loaded from the injected .zshenv, which runs before /etc/zprofile (whose
# path_helper moves every entry it does not know to the end of PATH) and before ~/.zprofile
# (where `brew shellenv` prepends /opt/homebrew/bin). So the directory has to be moved back to
# the front once those have run.
#
# Each case starts a real login, interactive shell the way iTerm2 injects it (a temporary HOME,
# the injected ZDOTDIR or ENV, the real /etc startup files), feeds it commands on stdin so it
# reaches its first prompt, and reports PATH and which it2 runs, both in the shell and in an
# `sh -c` child. Startup files in the temporary HOME prepend a directory holding a fake it2, as
# `brew shellenv` does, and run /usr/libexec/path_helper where it exists. A shell that is not
# installed is skipped.
#
#   python3 tests/injected_shell_it2_path_order_test.py

import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SCRIPTS = os.path.join(ROOT, "Resources", "shell_integration")
OTHER = os.path.join(ROOT, "OtherResources")
PATH_HELPER = "/usr/libexec/path_helper"
BASE_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"


def find_shell(name):
    for candidate in ("/bin/" + name, "/opt/homebrew/bin/" + name, "/usr/local/bin/" + name,
                      "/usr/bin/" + name):
        if os.access(candidate, os.X_OK):
            return candidate
    return None


ZSH = find_shell("zsh")
FISH = find_shell("fish")
# iTerm2 does not inject macOS's bash 3.2, so /bin/bash counts only elsewhere.
_BASH_CANDIDATES = ["/opt/homebrew/bin/bash", "/usr/local/bin/bash", "/usr/bin/bash"]
if os.uname().sysname != "Darwin":
    _BASH_CANDIDATES.append("/bin/bash")
BASH = next((c for c in _BASH_CANDIDATES if os.access(c, os.X_OK)), None)

PROBE = "\n".join([
    'echo "RESULT_PATH=$PATH"',
    'echo "RESULT_IT2=$(command -v it2)"',
    'echo "RESULT_RUN=$(it2)"',
    "sh -c 'echo \"RESULT_SH=$(command -v it2) $(it2)\"'",
    "exit",
    "",
])


def path_helper_line():
    """A line for a POSIX-ish startup file that reorders PATH as macOS's /etc/zprofile does."""
    if os.access(PATH_HELPER, os.X_OK):
        return 'eval "$(%s -s)"\n' % PATH_HELPER
    return ""


class Fixture:
    def __init__(self, test):
        self.tmp = tempfile.mkdtemp(prefix="it2path")
        test.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        self.inject = os.path.join(self.tmp, "inject")
        os.makedirs(self.home)
        os.makedirs(self.inject)
        self.it2_bin = os.path.join(self.home, ".iterm2", "bin")
        self.fake_bin = os.path.join(self.home, "qa-fakebin")
        self.make_it2(self.it2_bin, "ITERM2")
        self.make_it2(self.fake_bin, "FAKE")

    def make_it2(self, directory, label):
        os.makedirs(directory, exist_ok=True)
        path = os.path.join(directory, "it2")
        with open(path, "w") as f:
            f.write("#!/bin/sh\necho %s\n" % label)
        os.chmod(path, 0o755)

    def write_home(self, name, text):
        with open(os.path.join(self.home, name), "w") as f:
            f.write(text)

    def env(self, extra):
        env = {"HOME": self.home, "PATH": BASE_PATH, "LANG": "en_US.UTF-8",
               "TERM": "xterm-256color", "USER": os.environ.get("USER", "nobody"),
               "SHELL": "/bin/sh"}
        env.update(extra)
        return env

    def run(self, argv, env, prefix="", probe=PROBE):
        proc = subprocess.run(argv, env=env, input=(prefix + probe).encode("utf-8"),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
                              cwd=self.home)
        out = proc.stdout.decode("utf-8", "replace")
        results = {}
        for line in out.splitlines():
            # Prompts and escape sequences can share the line with a result.
            for key in ("RESULT_PATH", "RESULT_IT2", "RESULT_RUN", "RESULT_SH", "RESULT_HOOKS"):
                marker = key + "="
                if marker in line:
                    results[key] = line.split(marker, 1)[1].strip()
        return results, out

    def zsh(self, probe=PROBE):
        shutil.copy(os.path.join(OTHER, ".zshenv"), self.inject)
        shutil.copy(os.path.join(SCRIPTS, "iterm2_shell_integration.zsh"), self.inject)
        return self.run([ZSH, "-l", "-i"],
                        self.env({"ZDOTDIR": self.inject, "ITERM_INJECT_SHELL_INTEGRATION": "1"}),
                        probe=probe)

    def fish(self):
        # What FishShellIntegrationInjection does: XDG_DATA_DIRS names a directory whose
        # fish/vendor_conf.d holds the loader, which sources the script at the first prompt.
        conf = os.path.join(self.inject, "fish", "vendor_conf.d")
        os.makedirs(conf)
        shutil.copy(os.path.join(OTHER, "vendor_conf.d", "iterm2-shell-integration-loader.fish"),
                    conf)
        shutil.copy(os.path.join(SCRIPTS, "iterm2_shell_integration.fish"), self.inject)
        return self.run([FISH, "-l", "-i"],
                        self.env({"XDG_DATA_DIRS": self.inject,
                                  "IT2_FISH_XDG_DATA_DIRS": self.inject,
                                  "XDG_CONFIG_HOME": os.path.join(self.home, ".config")}),
                        # fish reading commands from a pipe never draws a prompt, so stand in
                        # for the first one.
                        prefix="emit fish_prompt\n")

    def bash(self):
        shutil.copy(os.path.join(OTHER, "bash-si-loader"), self.inject)
        shutil.copy(os.path.join(SCRIPTS, "iterm2_shell_integration.bash"), self.inject)
        # What BashShellIntegrationInjection does to `bash -l`.
        return self.run([BASH, "--posix", "-l", "-i"],
                        self.env({"ENV": os.path.join(self.inject, "bash-si-loader"),
                                  "IT2_BASH_INJECT": "1",
                                  "HISTFILE": os.path.join(self.home, ".bash_history"),
                                  "IT2_BASH_UNEXPORT_HISTFILE": "1"}))


class PathOrderAssertions:
    def assert_it2_first(self, fx, results, out):
        self.assertIn("RESULT_PATH", results, out)
        entries = results["RESULT_PATH"].split(":")
        self.assertEqual(entries[0], fx.it2_bin, out)
        self.assertEqual(entries.count(fx.it2_bin), 1, out)
        self.assertEqual(results.get("RESULT_IT2"), os.path.join(fx.it2_bin, "it2"), out)
        self.assertEqual(results.get("RESULT_RUN"), "ITERM2", out)
        self.assertEqual(results.get("RESULT_SH"),
                         os.path.join(fx.it2_bin, "it2") + " ITERM2", out)


@unittest.skipIf(ZSH is None, "zsh is not installed")
class ZshTests(unittest.TestCase, PathOrderAssertions):
    def test_zprofile_prepend_after_path_helper(self):
        # What `brew shellenv` in ~/.zprofile does, plus path_helper as /etc/zprofile runs it.
        fx = Fixture(self)
        fx.write_home(".zprofile", path_helper_line() + 'export PATH="$HOME/qa-fakebin:$PATH"\n')
        results, out = fx.zsh()
        self.assert_it2_first(fx, results, out)
        # The user's own entries survive, in their order.
        entries = results["RESULT_PATH"].split(":")
        self.assertEqual(entries[1], fx.fake_bin, out)

    def test_zshrc_and_zlogin_prepends(self):
        fx = Fixture(self)
        fx.write_home(".zshenv", 'export PATH="$HOME/qa-fakebin:$PATH"\n')
        fx.write_home(".zshrc", 'export PATH="/opt/qa-zshrc:$PATH"\n')
        fx.write_home(".zlogin", 'export PATH="/opt/qa-zlogin:$PATH"\n')
        results, out = fx.zsh()
        self.assert_it2_first(fx, results, out)
        entries = results["RESULT_PATH"].split(":")
        self.assertEqual(entries[1:3], ["/opt/qa-zlogin", "/opt/qa-zshrc"], out)

    def test_already_on_path_is_moved_not_duplicated(self):
        fx = Fixture(self)
        fx.write_home(".zprofile",
                      'export PATH="$HOME/qa-fakebin:$PATH:$HOME/.iterm2/bin:/opt/qa-tail"\n')
        results, out = fx.zsh()
        self.assert_it2_first(fx, results, out)
        self.assertIn("/opt/qa-tail", results["RESULT_PATH"].split(":"), out)

    def test_no_directory_leaves_path_alone(self):
        fx = Fixture(self)
        shutil.rmtree(os.path.join(fx.home, ".iterm2"))
        fx.write_home(".zprofile", 'export PATH="$HOME/qa-fakebin:$PATH"\n')
        results, out = fx.zsh()
        self.assertIn("RESULT_PATH", results, out)
        self.assertNotIn(fx.it2_bin, results["RESULT_PATH"].split(":"), out)
        self.assertEqual(results["RESULT_PATH"].split(":")[0], fx.fake_bin, out)

    def test_nounset(self):
        fx = Fixture(self)
        fx.write_home(".zshenv", "setopt nounset\n")
        fx.write_home(".zprofile", 'export PATH="$HOME/qa-fakebin:$PATH"\n')
        results, out = fx.zsh()
        self.assert_it2_first(fx, results, out)
        # /etc/zshrc and the script itself have unrelated complaints under nounset.
        self.assertNotIn("_iterm2_put_bin_first:", out, out)
        self.assertNotIn(".zshenv:", out, out)

    def test_hook_runs_once(self):
        # A later prepend, after the first prompt, is the user's choice and stays first.
        fx = Fixture(self)
        fx.write_home(".zprofile", 'export PATH="$HOME/qa-fakebin:$PATH"\n')
        results, out = fx.zsh(probe="\n".join([
            'export PATH="/opt/qa-later:$PATH"',
            'echo "RESULT_PATH=$PATH"',
            'echo "RESULT_HOOKS=${precmd_functions[*]}"',
            "exit",
            "",
        ]))
        self.assertIn("RESULT_PATH", results, out)
        self.assertEqual(results["RESULT_PATH"].split(":")[:2], ["/opt/qa-later", fx.it2_bin], out)
        self.assertIn("RESULT_HOOKS", results, out)
        self.assertNotIn("_iterm2_put_bin_first", results["RESULT_HOOKS"], out)

    def test_ksh_arrays_keeps_other_hooks(self):
        # Under ksh_arrays $precmd_functions is only its first element; the hook must still
        # remove only itself.
        fx = Fixture(self)
        fx.write_home(".zprofile", 'export PATH="$HOME/qa-fakebin:$PATH"\n')
        fx.write_home(".zshrc", "setopt ksh_arrays\nqa_hook() { :; }\nprecmd_functions+=(qa_hook)\n")
        results, out = fx.zsh(probe="\n".join([
            'echo "RESULT_PATH=$PATH"',
            'echo "RESULT_HOOKS=${precmd_functions[*]}"',
            "exit",
            "",
        ]))
        self.assertEqual(results.get("RESULT_PATH", "").split(":")[0], fx.it2_bin, out)
        self.assertEqual(results.get("RESULT_HOOKS", "").split(), ["iterm2_precmd", "qa_hook"], out)


@unittest.skipIf(FISH is None, "fish is not installed")
class FishTests(unittest.TestCase, PathOrderAssertions):
    def test_config_fish_prepend(self):
        # What `brew shellenv` in config.fish does.
        fx = Fixture(self)
        config = os.path.join(fx.home, ".config", "fish")
        os.makedirs(config)
        with open(os.path.join(config, "config.fish"), "w") as f:
            f.write('set -gx PATH "$HOME/qa-fakebin" $PATH\n')
        results, out = fx.fish()
        self.assert_it2_first(fx, results, out)


def load_framer():
    spec = importlib.util.spec_from_file_location("framer_for_path_test",
                                                  os.path.join(OTHER, "framer.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TCSH = find_shell("tcsh")


# tcsh can't be injected, so the conductor asks the framer to put ~/.iterm2/bin on the login
# shell's PATH (IT2_PUT_BIN_ON_PATH). This starts tcsh with the environment the framer would
# give it and checks that it2 is found by name. On macOS /etc/csh.login runs path_helper, which
# moves the directory after the system ones, so this asserts it is found, not that it is first.
@unittest.skipIf(TCSH is None, "tcsh is not installed")
class TcshTests(unittest.TestCase):
    def framer_environment(self, fx):
        framer = load_framer()
        saved = dict(os.environ)
        try:
            os.environ.clear()
            os.environ.update(fx.env({"IT2_PUT_BIN_ON_PATH": "1"}))
            # As the framer's main() does when it starts.
            framer.claim_put_bin_flag()
            return framer.login_shell_environment()
        finally:
            os.environ.clear()
            os.environ.update(saved)

    def test_it2_is_found_by_name(self):
        fx = Fixture(self)
        env = self.framer_environment(fx)
        self.assertNotIn("IT2_PUT_BIN_ON_PATH", env)
        probe = "\n".join([
            'echo "RESULT_IT2=`which it2`"',
            'echo "RESULT_RUN=`it2`"',
            "sh -c 'echo \"RESULT_SH=$(command -v it2) $(it2)\"'",
            "exit",
            "",
        ])
        proc = subprocess.run(["-tcsh"], executable=TCSH, env=env, input=probe.encode("utf-8"),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
                              cwd=fx.home)
        out = proc.stdout.decode("utf-8", "replace")
        it2 = os.path.join(fx.it2_bin, "it2")
        self.assertIn("RESULT_IT2=" + it2, out)
        self.assertIn("RESULT_RUN=ITERM2", out)
        self.assertIn("RESULT_SH=%s ITERM2" % it2, out)


@unittest.skipIf(BASH is None, "no injectable bash is installed")
class BashTests(unittest.TestCase, PathOrderAssertions):
    def test_bash_profile_prepend_after_path_helper(self):
        fx = Fixture(self)
        fx.write_home(".bash_profile",
                      path_helper_line() + 'export PATH="$HOME/qa-fakebin:$PATH"\n')
        results, out = fx.bash()
        self.assert_it2_first(fx, results, out)


if __name__ == "__main__":
    unittest.main()
