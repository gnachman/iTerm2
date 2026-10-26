#!/usr/bin/env python3
# Whether each shell integration script loads inside a multiplexer.
#
# It loads where TERM starts with "tmux" (only tmux sets that, and it survives an ssh from a tmux
# pane to another host, where $TMUX does not) or where $TMUX is set (tmux with a screen* terminal
# type), or where TERM=screen-256color, which many tmux users set. It skips for other screen* TERMs
# without $TMUX: screen, or an old tmux pane across an ssh hop, which can't be told apart.
# ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX still forces it on.
#
# Each case sources the generated script (Resources/shell_integration) in a fresh shell with a
# controlled environment and asks the shell whether integration loaded. A shell that isn't
# installed is skipped.
#
#   python3 tests/shell_integration_multiplexer_test.py

import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SCRIPTS = os.path.join(ROOT, "Resources", "shell_integration")


def script(shell):
    return os.path.join(SCRIPTS, "iterm2_shell_integration." + shell)


class Loader:
    """Runs `shell` with `env`, sourcing its script, and reports whether integration loaded."""

    def __init__(self, home):
        self.home = home

    def env(self, extra):
        env = {"HOME": self.home, "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin",
               "LANG": "en_US.UTF-8"}
        env.update(extra)
        return env

    def run(self, argv, env, stdin=None):
        proc = subprocess.run(argv, env=env, input=stdin, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=60)
        return proc.stdout.decode("utf-8", "replace")

    def bash(self, extra):
        out = self.run(["/bin/bash", "--norc", "--noprofile", "-i", "-c",
                        'source "$1"; echo "LOADED=[$ITERM_SHELL_INTEGRATION_INSTALLED]"', "x",
                        script("bash")], self.env(extra))
        return "LOADED=[Yes]" in out

    def zsh(self, extra):
        out = self.run(["/bin/zsh", "-f", "-i", "-c",
                        'source "$1"; echo "LOADED=[$ITERM_SHELL_INTEGRATION_INSTALLED]"', "x",
                        script("zsh")], self.env(extra))
        return "LOADED=[Yes]" in out

    def tcsh(self, extra):
        # tcsh -c is not interactive; the script checks $prompt, which this sets.
        commands = 'set prompt="> "\nsource %s\necho "LOADED=[$?iterm2_shell_integration_installed]"\n' % script("tcsh")
        out = self.run(["/bin/tcsh", "-f"], self.env(extra), stdin=commands.encode())
        return "LOADED=[1]" in out

    def fish(self, extra):
        out = self.run([shutil.which("fish"), "--no-config", "-i", "-c",
                        'source $argv[1]; if functions -q -- iterm2_status; echo "LOADED=[yes]"; end',
                        script("fish")], self.env(extra))
        return "LOADED=[yes]" in out

    def xonsh(self, extra):
        # xonsh sources only files with a xonsh extension.
        copy = os.path.join(self.home, "integration.xsh")
        shutil.copyfile(script("xonsh"), copy)
        out = self.run([shutil.which("xonsh"), "--no-rc", "-i", "-c",
                        'source %s; print("LOADED=[%%s]" %% $ITERM2_INTEGRATION)' % copy],
                       self.env(extra))
        return "LOADED=[True]" in out


SHELLS = {
    "bash": "/bin/bash",
    "zsh": "/bin/zsh",
    "tcsh": "/bin/tcsh",
    "fish": shutil.which("fish"),
    "xonsh": shutil.which("xonsh"),
}

ITERM = {"TERM_PROGRAM": "iTerm.app", "LC_TERMINAL": "iTerm2"}
TMUX = "/tmp/tmux-501/default,123,0"

# (description, environment, loads)
CASES = [
    ("not in a multiplexer", dict(ITERM, TERM="xterm-256color"), True),
    ("in a tmux pane", {"TERM": "tmux-256color", "TMUX": TMUX, "TMUX_PANE": "%1",
                        "TERM_PROGRAM": "tmux", "LC_TERMINAL": "iTerm2"}, True),
    ("in a tmux pane, LC_TERMINAL not forwarded", {"TERM": "tmux-256color", "TMUX": TMUX,
                                                   "TMUX_PANE": "%1", "TERM_PROGRAM": "tmux"}, True),
    ("on a host reached by ssh from a tmux pane", {"TERM": "tmux-256color"}, True),
    ("in tmux with a screen terminal type", {"TERM": "screen", "TMUX": TMUX, "TMUX_PANE": "%1",
                                             "TERM_PROGRAM": "tmux"}, True),
    ("in screen", {"TERM": "screen", "STY": "123.ttys001.host"}, False),
    # Many tmux users set this; it counts as tmux even where $TMUX doesn't reach, which screen
    # set up the same way shares.
    ("screen-256color on a host reached by ssh from a tmux pane", {"TERM": "screen-256color"}, True),
    ("in screen.xterm-256color", {"TERM": "screen.xterm-256color", "STY": "123.ttys001.host"}, False),
    ("forced on in screen", {"TERM": "screen", "ITERM_ENABLE_SHELL_INTEGRATION_WITH_TMUX": "1"}, True),
    ("in screen with TMUX set but empty", {"TERM": "screen", "TMUX": ""}, False),
    ("in tmux with a screen-256color terminal type", {"TERM": "screen-256color", "TMUX": TMUX,
                                                      "TMUX_PANE": "%1", "TERM_PROGRAM": "tmux"}, True),
    ("TERM=linux in tmux", {"TERM": "linux", "TMUX": TMUX, "TERM_PROGRAM": "tmux"}, False),
    ("TERM=dumb in tmux", {"TERM": "dumb", "TMUX": TMUX, "TERM_PROGRAM": "tmux"}, False),
]


class MultiplexerTest(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.loader = Loader(self.home)

    def tearDown(self):
        shutil.rmtree(self.home, ignore_errors=True)

    def check(self, shell):
        if not SHELLS[shell]:
            self.skipTest(shell + " is not installed")
        for description, env, loads in CASES:
            with self.subTest(shell=shell, case=description):
                self.assertEqual(getattr(self.loader, shell)(env), loads, description)
        # zsh and xonsh also stay out of other terminals; the others don't check.
        other = {"TERM": "xterm-256color", "TERM_PROGRAM": "Apple_Terminal"}
        with self.subTest(shell=shell, case="in another terminal"):
            self.assertEqual(getattr(self.loader, shell)(other), shell not in ("zsh", "xonsh"))
        # TERM_PROGRAM=tmux counts as iTerm2's only inside tmux.
        not_tmux = {"TERM": "xterm-256color", "TERM_PROGRAM": "tmux"}
        with self.subTest(shell=shell, case="TERM_PROGRAM=tmux outside tmux"):
            self.assertEqual(getattr(self.loader, shell)(not_tmux), shell not in ("zsh", "xonsh"))
        # tmux running in another terminal: plain tmux discards the codes, so loading is harmless.
        tmux_elsewhere = {"TERM": "tmux-256color", "TMUX": TMUX, "TERM_PROGRAM": "tmux"}
        with self.subTest(shell=shell, case="in tmux in another terminal"):
            self.assertTrue(getattr(self.loader, shell)(tmux_elsewhere))

    def test_bash(self):
        self.check("bash")

    def test_zsh(self):
        self.check("zsh")

    def test_tcsh(self):
        self.check("tcsh")

    def test_fish(self):
        self.check("fish")

    def test_xonsh(self):
        self.check("xonsh")


if __name__ == "__main__":
    unittest.main()
