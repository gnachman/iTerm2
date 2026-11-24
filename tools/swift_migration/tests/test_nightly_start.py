"""Tests for tools/swift_migration/nightly_start.sh, the nightly start script.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_nightly_start.py'

No test starts a real Claude Code session. A stub `claude` in a temporary
directory stands in for it: called as `claude /usage` it prints the text in
$STUB_USAGE (or fails with $STUB_USAGE_EXIT, or hangs with
$STUB_USAGE_HANG); called any other way, which happens inside the tmux
pane, it records its arguments, one per line, and the environment it was
given, tries the pushes the guards must block and the fetch and local
clones they must allow (with plain git, no model involved), and exits with
$STUB_EXIT. With $STUB_HANG
it instead reads its terminal until a line contains /exit, as Claude Code
ends on /exit.

The session runs in the real tmux, on a private socket in the test's
temporary directory (NIGHTLY_TMUX_SOCKET); teardown kills that server and
no other. The tests that need tmux are skipped, visibly, without it.

Each test makes a throwaway "owner" checkout and a nightly clone of it with
the real nightly_clone.sh setup (its only remote a read-only bare mirror),
so the preflight, the refresh and the git guards are tested on real
repositories and nothing touches this checkout. Logs and the lock go to a
temporary NIGHTLY_ROOT.

The fixed "now" is Thursday 2026-11-19 at 1am in America/Los_Angeles, the
fifth night after the Saturday noon reset: the ceiling is 5/7 = 71.4%.
"""

import json
import os
import plistlib
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(TOOL_DIR))
SCRIPT = os.path.join(TOOL_DIR, 'nightly_start.sh')
CLONE_TOOL = os.path.join(TOOL_DIR, 'nightly_clone.sh')
LANE_TOOL = os.path.join(TOOL_DIR, 'lane_clone.py')
PLIST = os.path.join(TOOL_DIR,
                     'com.googlecode.iterm2.swift-migration-nightly.plist')
TMUX = shutil.which('tmux') or next(
    (p for p in ('/opt/homebrew/bin/tmux', '/usr/local/bin/tmux')
     if os.access(p, os.X_OK)), None)

STUB = r'''#!/bin/sh
if [ "$1" = "/usage" ] && [ $# -eq 1 ]; then
  echo usage >> "$STUB_DIR/usage_calls"
  if [ -n "${STUB_USAGE_HANG:-}" ]; then
    echo $$ > "$STUB_DIR/usage_pid"
    exec sleep 600
  fi
  if [ -n "${STUB_USAGE_EXIT:-}" ]; then echo "error" ; exit "$STUB_USAGE_EXIT"; fi
  cat "$STUB_USAGE"
  exit 0
fi
echo "start $$" >> "$STUB_DIR/sessions"
for a in "$@"; do printf '%s\n' "$a"; done > "$STUB_DIR/session_args"
env > "$STUB_DIR/session_env"
pwd > "$STUB_DIR/session_pwd"
git rev-parse HEAD > "$STUB_DIR/session_head"
if [ -d "$NIGHTLY_ROOT/lock" ]; then echo held > "$STUB_DIR/lock_during_session"; fi
# The guards, exercised with plain git: every push fails, fetching and
# cloning from a local path work.
# Only ever inside the test's throwaway checkout, never anywhere else.
case "$(pwd -P)" in
  "$STUB_SAFE_ROOT"/*) ;;
  *) echo "not in the throwaway checkout: $(pwd -P)" > "$STUB_DIR/git_results"
     echo 'stub refused'; exit 99 ;;
esac
{
  for target in origin "$STUB_REMOTE" "file://$STUB_REMOTE" \
      https://nightly-test.invalid/r.git ssh://git@nightly-test.invalid/r.git \
      git@nightly-test.invalid:r.git; do
    if git push "$target" HEAD:refs/heads/pushed-by-stub >/dev/null 2>&1; then
      echo "push $target: SUCCEEDED"
    else
      echo "push $target: failed"
    fi
  done
  if git -C . push origin HEAD:refs/heads/pushed-by-stub >/dev/null 2>&1; then
    echo "push -C: SUCCEEDED"; else echo "push -C: failed"; fi
  # The owner's (throwaway) checkout, by absolute path, file:// URL and
  # relative path: pushInsteadOf is the only environment layer here.
  if git push "$STUB_OWNER" HEAD:refs/heads/pushed-by-stub >/dev/null 2>&1; then
    echo "push owner path: SUCCEEDED"; else echo "push owner path: failed"; fi
  if git push "file://$STUB_OWNER" HEAD:refs/heads/pushed-by-stub >/dev/null 2>&1; then
    echo "push owner file url: SUCCEEDED"; else echo "push owner file url: failed"; fi
  if git push "../$(basename "$STUB_OWNER")" HEAD:refs/heads/pushed-by-stub >/dev/null 2>&1; then
    echo "push owner relative: SUCCEEDED"; else echo "push owner relative: failed"; fi
  # With $STUB_LOCAL_PUSH, the local-path routes into the owner's checkout
  # that no environment layer stops: a remote with an explicit pushurl,
  # send-pack, a relative path that starts with neither / nor . (from the
  # parent directory, with --git-dir), and a fetch run in his checkout.
  if [ -n "${STUB_LOCAL_PUSH:-}" ]; then
    night=$(pwd -P)
    if (cd .. && git --git-dir="$night/.git" push "$(basename "$STUB_OWNER")" \
          HEAD:refs/heads/pushed-by-stub-relative >/dev/null 2>&1); then
      echo "push relative from parent: SUCCEEDED"; else echo "push relative from parent: failed"; fi
    if git -C "$STUB_OWNER" fetch -q "$night" HEAD:refs/heads/fetched-by-stub >/dev/null 2>&1; then
      echo "fetch into owner: SUCCEEDED"; else echo "fetch into owner: failed"; fi
    git remote add stubv "$STUB_OWNER" && git config remote.stubv.pushurl "$STUB_OWNER"
    if git push stubv HEAD:refs/heads/pushed-by-stub-pushurl -f >/dev/null 2>&1; then
      echo "push pushurl remote: SUCCEEDED"; else echo "push pushurl remote: failed"; fi
    git remote remove stubv
    if git send-pack "$STUB_OWNER" HEAD:refs/heads/pushed-by-stub-send-pack >/dev/null 2>&1; then
      echo "send-pack: SUCCEEDED"; else echo "send-pack: failed"; fi
  fi
  if git fetch -q origin 2>/dev/null; then echo "fetch: ok"; else echo "fetch: failed"; fi
  # A Swift package resolved as Xcode's SwiftPM does it: a mirror clone into
  # its repositories cache, an update of it, then the working copy made by a
  # local clone that shares the cache's objects (--shared: alternates), a
  # checkout and a submodule update. Here from a scratch package repository,
  # by path.
  spm="$STUB_DIR/spm"
  if git init -q -b master "$STUB_DIR/package" >/dev/null 2>&1 &&
     git -C "$STUB_DIR/package" commit -q --allow-empty -m package >/dev/null 2>&1 &&
     git clone -q -c core.symlinks=true -c core.fsmonitor=false -c core.longpaths=true \
         --mirror "$STUB_DIR/package" "$spm/repositories/r" >/dev/null 2>&1 &&
     git -C "$spm/repositories/r" remote update -p >/dev/null 2>&1 &&
     git clone -q -c core.symlinks=true -c core.fsmonitor=false -c core.longpaths=true \
         --shared --no-checkout "$spm/repositories/r" "$spm/checkouts/r" >/dev/null 2>&1 &&
     git -C "$spm/checkouts/r" checkout -q -f master >/dev/null 2>&1 &&
     git -C "$spm/checkouts/r" submodule update -q --init --recursive >/dev/null 2>&1 &&
     [ -s "$spm/checkouts/r/.git/objects/info/alternates" ]; then
    echo "package clone: ok"; else echo "package clone: failed"; fi
  if git clone -q "file://$STUB_REMOTE" "$STUB_DIR/file-clone" >/dev/null 2>&1; then
    echo "file clone: ok"; else echo "file clone: failed"; fi
  if git status --porcelain >/dev/null 2>&1; then echo "status: ok"; else echo "status: failed"; fi
} > "$STUB_DIR/git_results"
if [ -n "${STUB_TMUX:-}" ]; then
  "$STUB_TMUX" show-options -g update-environment > "$STUB_DIR/update_env" 2>&1
fi
if [ -n "${STUB_OWNER_BRANCH:-}" ]; then
  git -C "$STUB_OWNER" branch "$STUB_OWNER_BRANCH"
fi
if [ -n "${STUB_HIDE_RULES:-}" ]; then
  echo 'a rule from the night' > CLAUDE.md
  git add CLAUDE.md && git commit -q -m 'night adds a rule'
  git update-ref refs/remotes/origin/master HEAD
fi
if [ -n "${STUB_COMMIT_RULES:-}" ]; then
  echo "# changed by the night" >> .claude/agents/migration-author.md
  git commit -q -am 'night changes an agent definition'
fi
if [ -n "${STUB_SWITCH_BRANCH:-}" ]; then git checkout -q -b "$STUB_SWITCH_BRANCH"; fi
if [ -n "${STUB_RACE_HOLD:-}" ]; then
  while [ ! -e "$STUB_DIR/release" ] && [ -d "$STUB_DIR" ]; do sleep 0.05; done
fi
if [ -n "${STUB_ESCAPE:-}" ]; then
  # Children that leave the session's process group and session, as Claude
  # Code's Bash tool and the migration's tools can.
  "$STUB_PYTHON" -c '
import os, subprocess, sys, time
d = sys.argv[1]
p = subprocess.Popen(["/bin/sleep", "600"], start_new_session=True)
open(os.path.join(d, "newsession"), "w").write(str(p.pid))
r, w = os.pipe()
if os.fork() == 0:
    os.setsid()
    pid = os.fork()
    if pid == 0:
        os.execv("/bin/sleep", ["/bin/sleep", "601"])
    os.write(w, str(pid).encode())
    os._exit(0)
os.close(w)
open(os.path.join(d, "doublefork"), "w").write(os.read(r, 32).decode())
open(os.path.join(d, "ready"), "w").close()
time.sleep(600)
' "$STUB_DIR" &
  while [ ! -e "$STUB_DIR/ready" ]; do sleep 0.05; done
  /bin/sleep 602 &
  echo $! > "$STUB_DIR/plainchild"
fi
if [ -n "${STUB_HANG:-}" ]; then
  while IFS= read -r line; do
    case "$line" in *"/exit"*) echo exit > "$STUB_DIR/session_exit"; exit 0 ;; esac
  done
fi
if [ -n "${STUB_TRUST_DIALOG:-}" ]; then
  echo "Quick safety check: Is this a project you created or one you trust?"
  while IFS= read -r line; do
    case "$line" in *"/exit"*) exit 0 ;; esac
  done
fi
if [ -n "${STUB_DIALOG:-}" ]; then
  echo "Some other startup question nobody will answer? (y/n)"
  while IFS= read -r line; do
    case "$line" in *"/exit"*) exit 0 ;; esac
  done
fi
if [ -n "${STUB_TAMPER_CONFIG:-}" ]; then
  # Last, so that none of the stub's own git commands run it.
  git config core.fsmonitor "$STUB_TAMPER_CONFIG"
  mkdir -p .git/hooks && cp "$STUB_TAMPER_CONFIG" .git/hooks/post-index-change
fi
echo 'stub done'
exit "${STUB_EXIT:-0}"
'''

NOW = '2026-11-19T01:00'


def usage_text(used):
    return ('Current week (all models): %d%% used · resets Nov 21 at '
            '12pm (America/Los_Angeles)\n' % used)


def wait_until(predicate, bound=60.0):
    end = time.monotonic() + bound
    while time.monotonic() < end:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


GIT_ENV = {'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_NOSYSTEM': '1',
           'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@example.invalid',
           'GIT_COMMITTER_NAME': 't',
           'GIT_COMMITTER_EMAIL': 't@example.invalid'}


def git(cwd, *args):
    return subprocess.run(['git'] + list(args), cwd=cwd, check=True,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          universal_newlines=True,
                          env=dict(os.environ, **GIT_ENV)).stdout


def make_writable(top):
    for root, dirs, files in os.walk(top):
        for name in dirs + files:
            path = os.path.join(root, name)
            if not os.path.islink(path):
                os.chmod(path, os.stat(path).st_mode | stat.S_IWUSR)


@unittest.skipUnless(TMUX, 'tmux is not installed; the nightly start is untested')
class NightlyBase(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp(prefix='nightly_test.'))
        # A cleanup runs even when setUp fails; tearDown would not.
        self.addCleanup(self.cleanup)
        self.stub_dir = os.path.join(self.tmp, 'stub')
        os.mkdir(self.stub_dir)
        self.claude = os.path.join(self.stub_dir, 'claude')
        with open(self.claude, 'w') as fh:
            fh.write(STUB)
        os.chmod(self.claude, os.stat(self.claude).st_mode | stat.S_IXUSR)
        self.root = os.path.join(self.tmp, 'nightly')
        self.usage = os.path.join(self.tmp, 'usage.txt')
        self.set_usage(usage_text(54))
        self.holders = []
        self.socket = os.path.join(self.tmp, 's')
        # The owner's throwaway checkout, with the agent definitions where
        # the real repository tracks them, and its nightly clone, made by
        # the real nightly_clone.sh.
        self.owner = os.path.join(self.tmp, 'owner')
        git(self.tmp, 'init', '-q', '-b', 'master', self.owner)
        agents = os.path.join(self.owner, '.claude', 'agents')
        os.makedirs(agents)
        for name in ('migration-author.md', 'migration-reviewer.md'):
            shutil.copy(os.path.join(REPO, '.claude', 'agents', name), agents)
        with open(os.path.join(self.owner, '.gitignore'), 'w') as fh:
            fh.write('tmp/\n.claude/*\n!.claude/agents/\n')
        git(self.owner, 'add', '.')
        git(self.owner, 'commit', '-q', '-m', 'init')
        self.prepare_owner()
        # The project's upstream (GitHub in real life), which the owner's
        # checkout tracks as origin; fetched as file:// through the test hook.
        self.up = os.path.join(self.tmp, 'up.git')
        git(self.tmp, 'init', '-q', '--bare', '-b', 'master', self.up)
        git(self.owner, 'remote', 'add', 'origin', 'file://' + self.up)
        self.push_owner()
        self.repo = os.path.join(self.tmp, 'night')
        self.lanes = self.repo + '.lanes'
        self.remote = self.repo + '.origin.git'
        subprocess.run(['/bin/bash', CLONE_TOOL, 'setup', '--source',
                        self.owner, '--clone', self.repo], check=True,
                       stdout=subprocess.DEVNULL,
                       env=dict(os.environ, NIGHTLY_TEST_ALLOW_FILE_UPSTREAM='1', **GIT_ENV))

    def push_owner(self):
        git(self.owner, 'push', '-q', 'origin', 'master')
        git(self.owner, 'fetch', '-q', 'origin')

    def prepare_owner(self):
        """A subclass's additions to the owner's checkout before the clone
        is made."""

    def lane_tool(self, *args, env=None, expect=0):
        """lane_clone.py for the clone, in env (default: the test's)."""
        proc = subprocess.run([sys.executable, '-B', LANE_TOOL, '--repo', self.repo]
                              + list(args), env=env or dict(os.environ, **GIT_ENV),
                              cwd=self.tmp, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, universal_newlines=True,
                              timeout=300)
        self.assertEqual(proc.returncode, expect, proc.stdout + proc.stderr)
        return proc

    def cleanup(self):
        for proc in getattr(self, 'holders', []):
            if proc.poll() is None:
                proc.kill()
            proc.wait()
        repo = getattr(self, 'repo', os.path.join(self.tmp, 'night'))
        for sock in (os.path.join(self.tmp, 's'),
                     os.path.join(repo + '.runs', 'tmux.sock')):
            subprocess.run([TMUX, '-S', sock, 'kill-server'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # A child that a broken sweep left: only the /bin/sleep this test
        # started, never a reused pid.
        for name in ('newsession', 'doublefork', 'plainchild'):
            try:
                pid = int(self.read_stub(name))
            except (OSError, ValueError):
                continue
            command = subprocess.run(['ps', '-o', 'command=', '-p', str(pid)],
                                     stdout=subprocess.PIPE,
                                     universal_newlines=True).stdout.strip()
            if command.startswith('/bin/sleep 60'):
                os.kill(pid, signal.SIGKILL)
        make_writable(self.tmp)
        shutil.rmtree(self.tmp)

    def set_usage(self, text):
        with open(self.usage, 'w', encoding='utf-8') as fh:
            fh.write(text)

    def env(self, now=NOW, **extra):
        env = {
            'PATH': self.stub_dir + ':/usr/bin:/bin:/usr/sbin:/sbin',
            'HOME': os.environ.get('HOME', self.tmp),
            'TZ': 'America/Los_Angeles',
            'CLAUDE_BIN': self.claude,
            'PYTHON': sys.executable,
            'NIGHTLY_ROOT': self.root,
            'NIGHTLY_CLONE': self.repo,
            'NIGHTLY_SOURCE': self.owner,
            'STUB_OWNER': self.owner,
            'NIGHTLY_TMUX': TMUX,
            'NIGHTLY_TMUX_SOCKET': self.socket,
            'NIGHTLY_INTERRUPT_WAIT': '1',
            'NIGHTLY_NOW': now,
            'NIGHTLY_CAFFEINATE': '0',
            'NIGHTLY_TEST_ALLOW_FILE_UPSTREAM': '1',
            'STUB_DIR': self.stub_dir,
            'STUB_USAGE': self.usage,
            'STUB_REMOTE': self.remote,
            'STUB_SAFE_ROOT': os.path.realpath(self.tmp),
            'STUB_PYTHON': sys.executable,
            'ANTHROPIC_API_KEY': 'must-not-reach-claude',
            'GH_TOKEN': 'must-not-reach-claude',
            'GITHUB_TOKEN': 'must-not-reach-claude',
            'GH_ENTERPRISE_TOKEN': 'must-not-reach-claude',
            'SSH_AUTH_SOCK': '/nonexistent/agent.sock',
        }
        env.update(GIT_ENV)
        env.update(extra)
        return env

    def run_script(self, args=(), now=NOW, **extra):
        return subprocess.run(['/bin/bash', SCRIPT] + list(args),
                              env=self.env(now, **extra), cwd=self.tmp,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              universal_newlines=True, timeout=300)

    def stub_file(self, name):
        return os.path.join(self.stub_dir, name)

    def read_stub(self, name):
        with open(self.stub_file(name)) as fh:
            return fh.read()

    def session_env(self):
        result = {}
        for line in self.read_stub('session_env').splitlines():
            if '=' in line:
                key, value = line.split('=', 1)
                result[key] = value
        return result

    def session_args(self):
        return self.read_stub('session_args').split('\n')[:-1]

    def session_started(self):
        return os.path.exists(self.stub_file('session_args'))

    def lock_dir(self):
        return os.path.join(self.root, 'lock')

    def make_lock(self, pid):
        os.makedirs(self.lock_dir())
        with open(os.path.join(self.lock_dir(), 'pid'), 'w') as fh:
            fh.write('%d\n' % pid)

    def start_holder(self, name):
        holder = os.path.join(self.tmp, name)
        with open(holder, 'w') as fh:
            fh.write('#!/bin/sh\nwhile :; do sleep 1; done\n')
        os.chmod(holder, os.stat(holder).st_mode | stat.S_IXUSR)
        proc = subprocess.Popen(['/bin/sh', holder])
        self.holders.append(proc)
        return proc

    def option_values(self, args, flag):
        """The values after flag up to the next option."""
        i = args.index(flag) + 1
        values = []
        while i < len(args) and not args[i].startswith('--'):
            values.append(args[i])
            i += 1
        return values


class NightlyStartTest(NightlyBase):
    # Permitted start.

    def test_permitted_start(self):
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        args = self.session_args()
        # Interactive: no --print and nothing that only --print takes. The
        # prompt is the positional argument, last, after an option that
        # takes exactly one value.
        for flag in ('-p', '--print', '--permission-prompts', '--output-format',
                     '--verbose', '--max-budget-usd', '--agents', '--bare',
                     '--dangerously-skip-permissions'):
            self.assertNotIn(flag, args)
        self.assertNotIn('bypassPermissions', args)
        self.assertIn('docs/swift-migration/orchestration.md from the top',
                      args[-1])
        self.assertEqual(args[-3], '--session-id')
        joined = '\n'.join(args) + '\n'
        for flag, value in [('--model', 'opus'),
                            ('--permission-mode', 'auto')]:
            self.assertIn('%s\n%s\n' % (flag, value), joined)
        self.assertEqual(
            os.path.realpath(self.read_stub('session_pwd').strip()),
            os.path.realpath(self.repo))
        env = self.session_env()
        self.assertEqual(env['SWIFT_MIGRATION_NIGHTLY'], '1')
        self.assertNotIn('ANTHROPIC_API_KEY', env)
        self.assertTrue(env['TMUX'].startswith(self.socket + ','), env['TMUX'])
        self.assertEqual(env['TERM'], 'tmux-256color')
        # Logs under NIGHTLY_ROOT/<date>/.
        night_dir = env['SWIFT_MIGRATION_NIGHT_DIR']
        self.assertTrue(night_dir.startswith(
            os.path.join(self.root, '2026-11-19') + os.sep), night_dir)
        for name in ('nightly_start.log', 'usage.txt', 'command.txt',
                     'session.sh', 'prompt.txt', 'pane.log', 'supervisor.log',
                     'session.status', 'session-settings.json'):
            self.assertTrue(os.path.exists(os.path.join(night_dir, name)),
                            name)
        # The terminal output, through tmux pipe-pane.
        with open(os.path.join(night_dir, 'pane.log')) as fh:
            self.assertIn('stub done', fh.read())
        # The lock was held during the session and released after it, and
        # the tmux server is gone.
        self.assertTrue(os.path.exists(self.stub_file('lock_during_session')))
        self.assertFalse(os.path.exists(self.lock_dir()))
        self.assertNotEqual(subprocess.run(
            [TMUX, '-S', self.socket, 'list-sessions'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode, 0)

    def test_where_things_are_is_logged(self):
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('%s -S %s attach -t swift-migration' % (TMUX, self.socket),
                      proc.stdout)
        session_id = self.session_args()[-2]
        encoded = ''.join(c if c.isalnum() else '-' for c in self.repo)
        self.assertIn(os.path.join(os.environ['HOME'], '.claude', 'projects',
                                   encoded, session_id + '.jsonl'),
                      proc.stdout)
        self.assertIn(os.path.join(self.repo, 'tmp',
                                   'swift-migration-night-2026-11-19.md'),
                      proc.stdout)
        self.assertIn('[ "$(git -C %s symbolic-ref -q --short HEAD)" = master ] '
                      '&& git -C %s fetch %s master && git -C %s merge '
                      '--ff-only FETCH_HEAD'
                      % (self.owner, self.owner, self.repo, self.owner),
                      proc.stdout)
        proc = self.run_script(NIGHTLY_LAUNCHD_LOG='/some/launchd.log')
        self.assertIn('launchd log: /some/launchd.log', proc.stdout)

    def test_project_settings_load_but_no_mcp(self):
        # The clone has no .claude/settings.local.json, so settings sources
        # are not restricted and the project's CLAUDE.md and agents load.
        # No MCP server or connector.
        self.assertEqual(self.run_script().returncode, 0)
        args = self.session_args()
        self.assertNotIn('--setting-sources', args)
        self.assertIn('--strict-mcp-config', args)
        self.assertNotIn('--mcp-config', args)

    def test_agent_definitions_are_checked_in_the_clone(self):
        # The owner drops one (a change the clone takes by fast-forward, so
        # it is not a rule change the owner has yet to take).
        os.remove(os.path.join(self.owner, '.claude', 'agents',
                               'migration-reviewer.md'))
        git(self.owner, 'commit', '-q', '-am', 'drop reviewer')
        self.push_owner()
        proc = self.run_script()
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertIn('agent definitions', proc.stdout)
        self.assertFalse(self.session_started())

    def test_local_settings_in_the_clone_are_refused(self):
        with open(os.path.join(self.repo, '.claude', 'settings.local.json'),
                  'w') as fh:
            fh.write('{"permissions": {"allow": ["Bash(git *)"]}}\n')
        self.assertRefusedAfterRefresh('settings.local.json')

    def test_session_settings(self):
        self.assertEqual(self.run_script().returncode, 0)
        args = self.session_args()
        path = args[args.index('--settings') + 1]
        with open(path) as fh:
            settings = json.load(fh)
        # Shell commands go to the classifier even when an allow rule from
        # the user's settings matches; prompts are denied; no connectors.
        self.assertIs(settings['autoMode']['classifyAllShell'], True)
        self.assertIs(settings['permissions']['denyInsteadOfPrompting'], True)
        self.assertIs(settings['disableClaudeAiConnectors'], True)
        deny = settings['permissions']['deny']
        for rule in ('Bash(git push *)', 'Bash(git * push *)',
                     'Bash(git * push)', 'Bash(git send-pack *)',
                     'Bash(git * send-pack *)', 'Bash(gh *)',
                     'Bash(osascript *)', 'Bash(launchctl *)',
                     'Bash(sudo *)', 'Bash(open *)', 'Bash(it2 *)',
                     'Bash(*/it2 *)', 'Bash(tmux *)', 'Bash(*/tmux *)',
                     'Bash(*gitlab-issue-*)',
                     # A remote with an explicit pushurl, and send-pack or
                     # receive-pack by any route.
                     'Bash(git remote *)', 'Bash(git * remote *)',
                     'Bash(*pushurl*)', 'Bash(*send-pack*)',
                     'Bash(*receive-pack*)'):
            self.assertIn(rule, deny)
        # Local-path transports are allowed (the owner, 2026-11-23), so
        # nothing denies the settings that govern them.
        for rule in deny:
            self.assertNotIn('protocol.file', rule)
            self.assertNotIn('GIT_PROTOCOL_FROM_USER', rule)
        # Network access is the owner's to allow (2026-11-20).
        for rule in deny:
            self.assertNotIn('curl', rule)
            self.assertNotIn('WebSearch', rule)

    def test_outward_tools_are_removed(self):
        self.assertEqual(self.run_script().returncode, 0)
        args = self.session_args()
        removed = self.option_values(args, '--disallowedTools')
        for tool in ('mcp__*', 'RemoteTrigger', 'CronCreate', 'CronDelete',
                     'CronList', 'PushNotification', 'Workflow',
                     'DesignSync', 'ScheduleWakeup'):
            self.assertIn(tool, removed)
        # The orchestrator needs subagents and to message them.
        for tool in ('Task', 'Agent', 'SendMessage'):
            self.assertNotIn(tool, removed)

    def test_git_and_gh_guards_in_the_environment(self):
        self.assertEqual(self.run_script().returncode, 0)
        env = self.session_env()
        count = int(env['GIT_CONFIG_COUNT'])
        config = [(env['GIT_CONFIG_KEY_%d' % i], env['GIT_CONFIG_VALUE_%d' % i])
                  for i in range(count)]
        self.assertIn(('credential.helper', ''), config)
        # Local-path transports are not refused (the owner, 2026-11-23).
        self.assertNotIn('protocol.file.allow', [k for k, v in config])
        self.assertNotIn('GIT_PROTOCOL_FROM_USER', env)
        blocked = [v for k, v in config if k.endswith('.pushinsteadof')
                   or k.endswith('.pushInsteadOf')]
        for prefix in ('https://', 'http://', 'ssh://', 'git@', 'git://',
                       'file://', '/', '.'):
            self.assertIn(prefix, blocked)
        self.assertEqual(env['GIT_TERMINAL_PROMPT'], '0')
        self.assertEqual(env['GIT_ASKPASS'], '/usr/bin/false')
        self.assertEqual(env['SSH_ASKPASS'], '/usr/bin/false')
        self.assertNotIn('SSH_AUTH_SOCK', env)
        for name in ('GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN'):
            self.assertNotIn(name, env)
        gh_dir = env['GH_CONFIG_DIR']
        self.assertTrue(gh_dir.startswith(env['SWIFT_MIGRATION_NIGHT_DIR']))
        self.assertEqual(os.listdir(gh_dir), [])
        self.assertTrue(os.access(env['GIT_SSH_COMMAND'], os.X_OK))
        # The marker the sweep looks for, unique to this run.
        self.assertTrue(env['SWIFT_MIGRATION_NIGHT_ID'])
        # And they work: every push to a URL, a path or origin fails before
        # reaching anything, the owner's checkout by absolute path, file://
        # URL and ../ relative path included; fetching
        # from origin (the mirror, by path), a Swift package resolution
        # from a local repository the way SwiftPM does it, and a file://
        # clone all work; status works.
        results = self.read_stub('git_results')
        self.assertNotIn('SUCCEEDED', results)
        for line in ('push owner path: failed', 'push owner file url: failed',
                     'push owner relative: failed', 'fetch: ok',
                     'package clone: ok', 'file clone: ok', 'status: ok'):
            self.assertIn(line, results)
        self.assertEqual(results.count('failed'), 10, results)
        for repo in (self.remote, os.path.join(self.owner, '.git')):
            refs = subprocess.run(['git', '--git-dir', repo, 'for-each-ref'],
                                  stdout=subprocess.PIPE,
                                  universal_newlines=True).stdout
            self.assertNotIn('pushed-by-stub', refs)

    def test_local_routes_into_the_owner_checkout_are_reported_not_stopped(self):
        # What allowing local-path transports makes possible: writing refs
        # in the owner's checkout through a remote with an explicit pushurl
        # (which pushInsteadOf does not rewrite), send-pack (which ignores
        # it), a push to a relative path that starts with neither / nor .
        # (run from his parent directory with --git-dir), or a fetch run in
        # his checkout from the clone. No environment layer stops them; the
        # deny rules catch the plain push, send-pack and remote forms, the
        # classifier reviews the rest (the fetch matches no deny rule), and
        # the owner-refs comparison reports every one in the morning log.
        proc = self.run_script(STUB_LOCAL_PUSH='1')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        results = self.read_stub('git_results')
        self.assertIn('push pushurl remote: SUCCEEDED', results)
        self.assertIn('send-pack: SUCCEEDED', results)
        self.assertIn('push relative from parent: SUCCEEDED', results)
        self.assertIn('fetch into owner: SUCCEEDED', results)
        self.assertIn("THE OWNER'S REPOSITORY CHANGED DURING THE NIGHT",
                      proc.stdout)
        self.assertIn('refs/heads/pushed-by-stub-pushurl', proc.stdout)
        self.assertIn('refs/heads/pushed-by-stub-send-pack', proc.stdout)
        self.assertIn('refs/heads/pushed-by-stub-relative', proc.stdout)
        self.assertIn('refs/heads/fetched-by-stub', proc.stdout)
        self.assertNotIn('NIGHTLY_ALLOW_LOCAL_GIT', proc.stdout)

    def test_ssh_wrapper_refuses_receive_pack_only(self):
        self.assertEqual(self.run_script().returncode, 0)
        wrapper = self.session_env()['GIT_SSH_COMMAND']
        proc = subprocess.run([wrapper, 'host.invalid',
                               "git-receive-pack 'r.git'"],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True, timeout=60)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn('refused', proc.stderr)

    def test_night_ids_differ_between_runs(self):
        self.assertEqual(self.run_script().returncode, 0)
        first = self.session_env()['SWIFT_MIGRATION_NIGHT_ID']
        self.assertEqual(self.run_script().returncode, 0)
        self.assertNotEqual(first, self.session_env()['SWIFT_MIGRATION_NIGHT_ID'])

    def test_clean_stop_time_is_in_the_prompt(self):
        # Hard limit: the earlier of 6 hours from 01:00 and 07:00, so 07:00
        # PST. The stop sequence needs 1 + 300 + 60 + 10 + 20 seconds
        # (NIGHTLY_INTERRUPT_WAIT is 1 here), so it starts at 06:53:29; the
        # clean stop is 45 minutes before the hard limit, 06:15.
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        prompt = self.session_args()[-1]
        self.assertIn('2026-11-19 06:15:00 PST', prompt)
        self.assertIn('2026-11-19 07:00:00 PST', prompt)
        self.assertIn('clean stop by 2026-11-19 06:15:00 PST; the stop '
                      'sequence starts at 2026-11-19 06:53:29 PST; hard limit '
                      '2026-11-19 07:00:00 PST', proc.stdout)
        self.assertIn('Stopping cleanly', prompt)
        self.assertIn('kills the session and everything it started', prompt)

    def test_git_state_logged_before_and_after(self):
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=self.repo,
                              stdout=subprocess.PIPE,
                              universal_newlines=True).stdout.strip()
        for when in ('before', 'after'):
            self.assertIn('git %s: HEAD %s' % (when, head), proc.stdout)
            self.assertIn('git %s: branches master' % when, proc.stdout)
            self.assertIn('git %s: origin/master %s' % (when, head),
                          proc.stdout)
            self.assertIn('git %s: status lines 0' % when, proc.stdout)
        self.assertNotIn('NO LONGER ON', proc.stdout)

    def test_branch_change_is_loud(self):
        proc = self.run_script(STUB_SWITCH_BRANCH='elsewhere')
        self.assertIn('HEAD IS NO LONGER ON master', proc.stdout)
        self.assertIn('elsewhere', proc.stdout)

    def test_required_programs_are_logged(self):
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        for name, path in (('git', '/usr/bin/git'),
                           ('xcodebuild', '/usr/bin/xcodebuild'),
                           ('expect', '/usr/bin/expect'),
                           ('ruby', '/usr/bin/ruby'),
                           ('python3', '/usr/bin/python3'),
                           ('claude', self.claude),
                           ('tmux', TMUX)):
            self.assertIn('program %s: %s' % (name, path), proc.stdout)

    def test_missing_required_program(self):
        proc = self.run_script(
            NIGHTLY_REQUIRED_PROGRAMS='git nightly-no-such-program')
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertIn('nightly-no-such-program', proc.stdout)
        self.assertFalse(self.session_started())

    # Nothing is started.

    def test_ceiling_reached(self):
        # Sunday 1am: ceiling 1/7 = 14.3%; 54% used is over it.
        proc = self.run_script(now='2026-11-15T01:00')
        self.assertEqual(proc.returncode, 1, proc.stdout)
        self.assertIn('ceiling', proc.stdout)
        self.assertFalse(self.session_started())
        self.assertFalse(os.path.exists(self.lock_dir()))

    def test_usage_unparseable(self):
        self.set_usage('something else entirely\n')
        proc = self.run_script()
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertFalse(self.session_started())
        self.assertFalse(os.path.exists(self.lock_dir()))

    def test_usage_command_fails(self):
        proc = self.run_script(STUB_USAGE_EXIT='1')
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertFalse(self.session_started())

    def test_sigterm_during_usage_check(self):
        proc = subprocess.Popen(['/bin/bash', SCRIPT],
                                env=self.env(STUB_USAGE_HANG='1'),
                                cwd=self.tmp, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT,
                                universal_newlines=True)
        try:
            pidfile = self.stub_file('usage_pid')
            self.assertTrue(wait_until(lambda: os.path.exists(pidfile)
                                       and os.path.getsize(pidfile) > 0))
            with open(pidfile) as fh:
                usage_pid = int(fh.read())
            started = time.monotonic()
            proc.send_signal(signal.SIGTERM)
            out, _ = proc.communicate(timeout=120)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate()
        self.assertEqual(proc.returncode, 2, out)
        self.assertIn('signal', out)
        self.assertTrue(wait_until(lambda: not alive(usage_pid)))
        self.assertLess(time.monotonic() - started, 60)
        self.assertFalse(self.session_started())
        self.assertFalse(os.path.exists(self.lock_dir()))

    def test_lock_held(self):
        holder = self.start_holder('fake_nightly_start.sh')
        self.make_lock(holder.pid)
        proc = self.run_script()
        self.assertEqual(proc.returncode, 3, proc.stdout)
        self.assertIn(str(holder.pid), proc.stdout)
        self.assertFalse(self.session_started())
        # Usage is not even read while another run holds the lock.
        self.assertFalse(os.path.exists(self.stub_file('usage_calls')))
        # The other run's lock is left alone.
        self.assertTrue(os.path.isdir(self.lock_dir()))

    def test_stale_lock_dead_pid(self):
        dead = subprocess.Popen(['/usr/bin/true'])
        dead.wait()
        self.make_lock(dead.pid)
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('stale', proc.stdout)
        self.assertTrue(self.session_started())
        self.assertFalse(os.path.exists(self.lock_dir()))
        leftovers = [n for n in os.listdir(self.root) if n.startswith('lock')]
        self.assertEqual(leftovers, [])

    def test_stale_lock_pid_reused_by_another_program(self):
        # A live process that is not a nightly start (the pid was reused).
        other = self.start_holder('something_else.sh')
        self.make_lock(other.pid)
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('stale', proc.stdout)
        self.assertTrue(self.session_started())

    def test_lock_without_pid_file_is_held_while_young(self):
        # Another run may have made the directory and not yet written its
        # pid; a young lock without a pid is treated as held.
        os.makedirs(self.lock_dir())
        proc = self.run_script()
        self.assertEqual(proc.returncode, 3, proc.stdout)
        self.assertFalse(self.session_started())

    def test_lock_without_pid_file_is_stale_when_old(self):
        os.makedirs(self.lock_dir())
        old = 1700000000  # 2023, long ago
        os.utime(self.lock_dir(), (old, old))
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertTrue(self.session_started())

    def test_outside_the_start_window(self):
        # launchd runs a missed midnight job when the Mac wakes; at 9am the
        # owner is about, so nothing starts and usage is not read.
        proc = self.run_script(now='2026-11-19T09:00')
        self.assertEqual(proc.returncode, 6, proc.stdout)
        self.assertFalse(self.session_started())
        self.assertFalse(os.path.exists(self.stub_file('usage_calls')))

    def test_window_last_second(self):
        proc = self.run_script(now='2026-11-19T04:59:59')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertTrue(self.session_started())

    def test_window_closes_at_five(self):
        proc = self.run_script(now='2026-11-19T05:00:00')
        self.assertEqual(proc.returncode, 6, proc.stdout)
        self.assertFalse(self.session_started())

    # Preflight: the checkout must be in a state to work in.

    def assertRefused(self, why, code=8, **extra):
        proc = self.run_script(**extra)
        self.assertEqual(proc.returncode, code, proc.stdout)
        self.assertIn('preflight', proc.stdout)
        self.assertIn(why, proc.stdout)
        self.assertFalse(self.session_started())
        self.assertFalse(os.path.exists(self.stub_file('usage_calls')))
        self.assertFalse(os.path.exists(self.lock_dir()))
        return proc

    def git_dir_path(self, *parts):
        return os.path.join(self.repo, '.git', *parts)

    def test_preflight_index_lock_of_a_running_git_is_refused_and_kept(self):
        with open(self.git_dir_path('index.lock'), 'w'):
            pass
        # A process whose command line names the clone, as git working on
        # it would.
        holder = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(600)',
                                   self.repo])
        self.holders.append(holder)
        proc = self.assertRefused('index.lock')
        self.assertIn(str(holder.pid), proc.stdout)
        self.assertTrue(os.path.exists(self.git_dir_path('index.lock')))

    def test_preflight_removes_a_stale_index_lock(self):
        with open(self.git_dir_path('index.lock'), 'w'):
            pass
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('removed a stale lock %s' % self.git_dir_path('index.lock'), proc.stdout)
        self.assertFalse(os.path.exists(self.git_dir_path('index.lock')))
        self.assertTrue(self.session_started())

    def test_dry_run_keeps_a_stale_index_lock(self):
        with open(self.git_dir_path('index.lock'), 'w'):
            pass
        proc = self.run_script(['--dry-run'])
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('a real run would remove', proc.stdout)
        self.assertTrue(os.path.exists(self.git_dir_path('index.lock')))

    def stand_in_clone_tool(self, refresh_body):
        """A nightly_clone.sh that runs refresh_body for refresh and status
        and hands everything else to the real one."""
        path = os.path.join(self.stub_dir, 'clone_tool.sh')
        with open(path, 'w') as fh:
            fh.write('#!/bin/bash\ncase "$1" in refresh|status) %s ;; '
                     '*) exec /bin/bash %s "$@" ;; esac\n' % (refresh_body, CLONE_TOOL))
        os.chmod(path, 0o755)
        return path

    def test_refresh_that_hangs_is_killed_at_the_bound(self):
        pidfile = os.path.join(self.stub_dir, 'refresh_child')
        tool = self.stand_in_clone_tool('sleep 600 & echo $! > %s; wait' % pidfile)
        started = time.monotonic()
        proc = self.run_script(NIGHTLY_CLONE_TOOL=tool, NIGHTLY_REFRESH_SECONDS='3')
        self.assertLess(time.monotonic() - started, 120)
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertIn('the refresh did not finish within 3 seconds', proc.stdout)
        self.assertFalse(self.session_started())
        with open(pidfile) as fh:
            child = int(fh.read())
        self.assertTrue(wait_until(lambda: not alive(child)), 'the refresh child survived')
        self.assertFalse(os.path.exists(self.lock_dir()))

    def test_refresh_within_the_bound_is_untouched(self):
        tool = self.stand_in_clone_tool(
            'echo "nightly_clone: upstream-commits: none"; sleep 1; exit 0')
        proc = self.run_script(NIGHTLY_CLONE_TOOL=tool, NIGHTLY_REFRESH_SECONDS='30')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('refresh: nightly_clone: upstream-commits: none', proc.stdout)
        self.assertTrue(self.session_started())

    def test_preflight_rebase(self):
        for name in ('rebase-merge', 'rebase-apply'):
            os.mkdir(self.git_dir_path(name))
            self.assertRefused('rebase')
            self.assertTrue(os.path.isdir(self.git_dir_path(name)))
            os.rmdir(self.git_dir_path(name))

    def test_preflight_merge_cherry_pick_revert_bisect(self):
        head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=self.repo,
                              stdout=subprocess.PIPE,
                              universal_newlines=True).stdout
        for name, why in (('MERGE_HEAD', 'merge'),
                          ('CHERRY_PICK_HEAD', 'cherry-pick'),
                          ('REVERT_HEAD', 'revert'),
                          ('BISECT_LOG', 'bisect')):
            path = self.git_dir_path(name)
            with open(path, 'w') as fh:
                fh.write(head)
            self.assertRefused(why)
            self.assertTrue(os.path.exists(path))
            os.remove(path)

    def test_preflight_detached_head(self):
        git(self.repo, 'checkout', '-q', '--detach')
        self.assertRefused('detached')

    def test_preflight_wrong_branch(self):
        git(self.repo, 'checkout', '-q', '-b', 'topic')
        self.assertRefused('topic')

    def test_preflight_branch_comes_from_the_clone_configuration(self):
        conf = os.path.join(self.repo, '.git', 'swift-migration-nightly.conf')
        git(self.tmp, 'config', '-f', conf, 'nightly.branch', 'topic')
        # The configuration is not trusted: it must agree with setup's.
        self.assertRefused('nightly.branch', code=12)

    def test_preflight_not_a_nightly_clone(self):
        plain = os.path.join(self.tmp, 'plain')
        os.mkdir(plain)
        proc = self.assertRefused('nightly clone', NIGHTLY_CLONE=plain)
        self.assertIn('nightly_clone.sh setup --clone %s' % plain, proc.stdout)

    def test_preflight_origin_is_not_the_mirror(self):
        git(self.repo, 'remote', 'set-url', 'origin', self.owner)
        self.assertRefused('not the mirror', code=12)

    def test_preflight_origin_push_url(self):
        git(self.repo, 'config', 'remote.origin.pushurl', self.remote)
        self.assertRefused('push URL', code=12)

    def test_preflight_another_remote(self):
        git(self.repo, 'remote', 'add', 'github', 'https://example.invalid/r.git')
        self.assertRefused('remote.github.url', code=12)

    def canary(self):
        self.marker = os.path.join(self.tmp, 'CANARY-RAN')
        path = os.path.join(self.tmp, 'canary.sh')
        with open(path, 'w') as fh:
            fh.write('#!/bin/sh\necho "$0 $*" >> %s\nexit 0\n' % self.marker)
        os.chmod(path, 0o755)
        return path

    def test_preflight_refuses_config_that_runs_programs_and_never_runs_it(self):
        canary = self.canary()
        git(self.repo, 'config', 'core.fsmonitor', canary)
        self.assertRefused('core.fsmonitor', code=12)
        proc = self.run_script(['--dry-run'])
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('a real run would exit 12', proc.stdout)
        self.assertFalse(os.path.exists(self.marker))

    def test_config_written_by_the_session_never_runs_after_it(self):
        canary = self.canary()
        proc = self.run_script(STUB_TAMPER_CONFIG=canary)
        self.assertIn('git after: HEAD', proc.stdout)
        self.assertIn("THE CLONE'S LAYOUT OR CONFIGURATION WAS CHANGED DURING "
                      'THE NIGHT', proc.stdout)
        self.assertIn('core.fsmonitor', proc.stdout)
        if os.path.exists(self.marker):
            with open(self.marker) as fh:
                self.fail('the canary ran: ' + fh.read())

    def test_preflight_refuses_anything_under_claude_the_owner_does_not_track(self):
        # Ignored files there are invisible to git status but load into the
        # session (settings, hooks, skills, commands, a CLAUDE.md).
        for name in ('settings.json', 'settings.local.json',
                     os.path.join('hooks', 'h.sh'),
                     os.path.join('skills', 's', 'SKILL.md'), 'CLAUDE.md'):
            path = os.path.join(self.repo, '.claude', name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w') as fh:
                fh.write('{}\n')
            proc = self.assertRefusedAfterRefresh(
                os.path.join('.claude', name))
            self.assertIn('not tracked upstream', proc.stdout)
            # The message says how to clear it.
            self.assertIn('remove', proc.stdout)
            os.remove(path)

    def test_preflight_refuses_rule_changes_the_owner_has_not_taken(self):
        with open(os.path.join(self.repo, 'CLAUDE.md'), 'w') as fh:
            fh.write('a new rule from the night\n')
        git(self.repo, 'add', 'CLAUDE.md')
        git(self.repo, 'commit', '-q', '-m', 'night adds CLAUDE.md')
        proc = self.assertRefusedAfterRefresh('CLAUDE.md')
        self.assertIn('not upstream', proc.stdout)
        # Once the owner has taken the commit and pushed it, it is upstream.
        git(self.owner, 'fetch', '-q', self.repo, 'master')
        git(self.owner, 'merge', '-q', '--ff-only', 'FETCH_HEAD')
        self.push_owner()
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)

    def test_preflight_refuses_agent_definition_changes_not_taken(self):
        with open(os.path.join(self.repo, '.claude', 'agents',
                               'migration-reviewer.md'), 'a') as fh:
            fh.write('\nanother rule\n')
        git(self.repo, 'commit', '-q', '-am', 'night edits the reviewer')
        self.assertRefusedAfterRefresh('.claude/agents/migration-reviewer.md')

    def assertRefusedAfterRefresh(self, why):
        # Checked after the refresh (which needs the lock and a usage
        # reading), against the owner's master as just fetched.
        proc = self.run_script()
        self.assertEqual(proc.returncode, 8, proc.stdout)
        self.assertIn('preflight', proc.stdout)
        self.assertIn(why, proc.stdout)
        self.assertFalse(self.session_started())
        self.assertFalse(os.path.exists(self.lock_dir()))
        return proc

    def test_rule_change_hidden_by_moving_origin_master_is_still_listed(self):
        # The session commits a CLAUDE.md and moves origin/master to its
        # commit; the comparison uses the owner's master read from his
        # repository, so the change is still reported.
        proc = self.run_script(STUB_HIDE_RULES='1')
        self.assertIn('THE NIGHT CHANGED RULE FILES', proc.stdout)
        self.assertIn('A CLAUDE.md', proc.stdout)

    def test_rule_changes_made_during_the_night_are_listed_loudly(self):
        proc = self.run_script(STUB_COMMIT_RULES='1')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('THE NIGHT CHANGED RULE FILES', proc.stdout)
        self.assertIn('.claude/agents/migration-author.md', proc.stdout)

    # The owner's repositories, compared before and after.

    def test_owner_repository_change_is_reported_and_blocks_nothing(self):
        # The owner's repository is shared with his other agents and
        # worktrees, so a change overnight is reported, not a stop.
        before = git(self.owner, 'rev-parse', 'master').strip()
        proc = self.run_script(STUB_OWNER_BRANCH='made-at-night')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn("THE OWNER'S REPOSITORY CHANGED DURING THE NIGHT",
                      proc.stdout)
        self.assertIn('+ . %s refs/heads/made-at-night' % before, proc.stdout)
        self.assertEqual(os.listdir(self.root) and
                         [n for n in os.listdir(self.root)
                          if 'OWNER' in n or 'pending' in n], [])
        # The next night starts as usual.
        os.remove(self.stub_file('session_args'))
        self.assertEqual(self.run_script().returncode, 0)
        self.assertTrue(self.session_started())

    def test_no_owner_change_is_said_quietly(self):
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('owner check: the owner\'s repositories are as they were',
                      proc.stdout)
        self.assertNotIn("THE OWNER'S REPOSITORY CHANGED", proc.stdout)

    def test_claude_worktrees_do_not_stop_the_next_night(self):
        # Claude Code may leave its agent worktrees there.
        path = os.path.join(self.repo, '.claude', 'worktrees', 'agent-1', 'x.txt')
        os.makedirs(os.path.dirname(path))
        with open(path, 'w') as fh:
            fh.write('x\n')
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)

    # The clone and its refresh.

    def test_missing_clone(self):
        gone = os.path.join(self.tmp, 'no-clone-here')
        proc = self.run_script(NIGHTLY_CLONE=gone)
        self.assertEqual(proc.returncode, 8, proc.stdout)
        self.assertIn('does not exist', proc.stdout)
        self.assertIn('nightly_clone.sh setup --clone %s' % gone, proc.stdout)
        self.assertFalse(self.session_started())
        self.assertFalse(os.path.exists(self.stub_file('usage_calls')))
        self.assertFalse(os.path.exists(gone))

    def test_dry_run_without_a_clone_says_so_and_what_it_would_do(self):
        gone = os.path.join(self.tmp, 'no-clone-here')
        proc = self.run_script(['--dry-run'], NIGHTLY_CLONE=gone)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('the nightly clone %s does not exist' % gone, proc.stdout)
        self.assertIn('nightly_clone.sh setup --clone %s' % gone, proc.stdout)
        self.assertIn('trust', proc.stdout)
        self.assertIn('attach -t swift-migration', proc.stdout)
        self.assertFalse(os.path.exists(gone))
        self.assertFalse(self.session_started())

    def owner_commit(self, name, text=None):
        with open(os.path.join(self.owner, name), 'w') as fh:
            fh.write(text if text is not None else name + '\n')
        git(self.owner, 'add', name)
        git(self.owner, 'commit', '-q', '-m', name)
        self.push_owner()
        return git(self.owner, 'rev-parse', 'HEAD').strip()

    def clone_commit(self, name):
        with open(os.path.join(self.repo, name), 'w') as fh:
            fh.write(name + '\n')
        git(self.repo, 'add', name)
        git(self.repo, 'commit', '-q', '-m', name)
        return git(self.repo, 'rev-parse', 'HEAD').strip()

    def test_refresh_owner_ahead_fast_forwards_before_the_session(self):
        new = self.owner_commit('day.txt')
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.read_stub('session_head').strip(), new)
        self.assertIn('fast-forward', proc.stdout)

    def test_refresh_clone_ahead_continues_from_the_clone(self):
        night = self.clone_commit('night.txt')
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.read_stub('session_head').strip(), night)

    def test_refresh_rebase_conflict_refuses(self):
        night = self.clone_commit('same.txt')
        self.owner_commit('same.txt', 'the upstream version\n')
        proc = self.run_script()
        self.assertEqual(proc.returncode, 9, proc.stdout)
        self.assertIn('rebase-failed', proc.stdout)
        self.assertIn('rebase', proc.stdout)
        self.assertFalse(self.session_started())
        self.assertEqual(git(self.repo, 'rev-parse', 'HEAD').strip(), night)
        self.assertFalse(os.path.exists(self.lock_dir()))
        status = os.path.join(self.night_dir_of(proc), 'refresh.status')
        with open(status) as fh:
            self.assertIn('rebase-failed', fh.read())

    def night_dir_of(self, proc):
        for line in proc.stdout.splitlines():
            if 'logs in ' in line:
                return line.split('logs in ', 1)[1].strip()
        self.fail('no run directory in\n' + proc.stdout)

    def test_refresh_rebases_the_night_onto_the_upstream_before_the_session(self):
        self.clone_commit('night.txt')
        upstream = self.owner_commit('day.txt')
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        head = self.read_stub('session_head').strip()
        self.assertEqual(git(self.repo, 'rev-parse', head + '^').strip(), upstream)
        self.assertIn('nightly_clone: rebased: 1 commits onto %s' % upstream, proc.stdout)
        night_dir = self.session_env()['SWIFT_MIGRATION_NIGHT_DIR']
        with open(os.path.join(night_dir, 'refresh.status')) as fh:
            status = fh.read()
        self.assertIn('nightly_clone: rebased: 1 commits', status)
        self.assertIn('nightly_clone: upstream-commits: taken', status)
        self.assertIn('nightly_clone: upstream: refreshed', status)
        prompt = self.session_args()[-1]
        self.assertIn(os.path.join(night_dir, 'refresh.status'), prompt)
        self.assertIn('section 1, step 4', prompt)
        self.assertNotIn('could not be fetched tonight', prompt)
        # The stale-lane release comes after the refresh.
        self.assertLess(proc.stdout.index('nightly_clone: rebased'),
                        proc.stdout.index('lanes: no lanes made yet'))

    def test_unreachable_upstream_is_in_the_status_file_and_the_night_goes_on(self):
        os.rename(self.up, self.up + '.gone')
        try:
            proc = self.run_script()
        finally:
            os.rename(self.up + '.gone', self.up)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertTrue(self.session_started())
        night_dir = self.session_env()['SWIFT_MIGRATION_NIGHT_DIR']
        with open(os.path.join(night_dir, 'refresh.status')) as fh:
            self.assertIn('nightly_clone: upstream: NOT REFRESHED', fh.read())
        self.assertIn('origin/master could not be fetched tonight', self.session_args()[-1])

    def test_dry_run_does_not_refresh(self):
        self.owner_commit('day.txt')
        before = git(self.repo, 'rev-parse', 'HEAD')
        mirror_before = git(self.remote, 'for-each-ref')
        proc = self.run_script(['--dry-run'])
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('refresh would fetch', proc.stdout)
        self.assertEqual(git(self.repo, 'rev-parse', 'HEAD'), before)
        self.assertEqual(git(self.remote, 'for-each-ref'), mirror_before)

    # The tmux socket.

    def start_squatter(self):
        subprocess.run([TMUX, '-S', self.socket, '-f', '/dev/null',
                        'new-session', '-d', '-s', 'squatter', 'sleep 600'],
                       check=True)

    def test_socket_already_in_use(self):
        self.start_squatter()
        proc = self.run_script()
        self.assertEqual(proc.returncode, 10, proc.stdout)
        self.assertIn('already listening', proc.stdout)
        self.assertFalse(self.session_started())
        # The other server is left alone.
        self.assertEqual(subprocess.run(
            [TMUX, '-S', self.socket, 'has-session', '-t', 'squatter'])
            .returncode, 0)
        self.assertFalse(os.path.exists(self.lock_dir()))

    def test_dry_run_reports_a_socket_in_use(self):
        self.start_squatter()
        proc = self.run_script(['--dry-run'])
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('a real run would exit 10', proc.stdout)

    def test_socket_path_too_long(self):
        long_dir = os.path.join(self.tmp, 'x' * 60, 'y' * 30)
        proc = self.run_script(NIGHTLY_TMUX_SOCKET=os.path.join(long_dir, 's'))
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertIn('at most 103', proc.stdout)
        self.assertFalse(self.session_started())

    def test_socket_directory_is_private(self):
        sock = os.path.join(self.tmp, 'sockdir', 's')
        proc = self.run_script(NIGHTLY_TMUX_SOCKET=sock)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(stat.S_IMODE(os.stat(os.path.dirname(sock)).st_mode),
                         0o700)

    def test_existing_socket_directory_is_not_chmodded(self):
        directory = os.path.join(self.tmp, 'existing')
        os.mkdir(directory, 0o755)
        os.chmod(directory, 0o755)
        proc = self.run_script(NIGHTLY_TMUX_SOCKET=os.path.join(directory, 's'))
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(stat.S_IMODE(os.stat(directory).st_mode), 0o755)

    def test_socket_directory_writable_by_others_is_refused(self):
        directory = os.path.join(self.tmp, 'shared')
        os.mkdir(directory)
        os.chmod(directory, 0o777)
        proc = self.run_script(NIGHTLY_TMUX_SOCKET=os.path.join(directory, 's'))
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertEqual(stat.S_IMODE(os.stat(directory).st_mode), 0o777)
        self.assertFalse(self.session_started())

    def test_update_environment_is_empty_so_an_attach_brings_nothing(self):
        proc = self.run_script(STUB_TMUX=TMUX)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.read_stub('update_env').strip(),
                         'update-environment')

    # The run directory, lock, logs and socket live outside the clone.

    def test_run_directory_and_socket_default_to_a_sibling_of_the_clone(self):
        env = self.env()
        del env['NIGHTLY_ROOT']
        del env['NIGHTLY_TMUX_SOCKET']
        proc = subprocess.run(['/bin/bash', SCRIPT], env=env, cwd=self.tmp,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              universal_newlines=True, timeout=300)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        runs = self.repo + '.runs'
        self.assertEqual(stat.S_IMODE(os.stat(runs).st_mode), 0o700)
        night_dir = self.session_env()['SWIFT_MIGRATION_NIGHT_DIR']
        self.assertTrue(night_dir.startswith(runs + os.sep), night_dir)
        self.assertTrue(self.session_env()['TMUX'].startswith(
            os.path.join(runs, 'tmux.sock') + ','))
        self.assertFalse(os.path.exists(os.path.join(self.repo, 'tmp',
                                                     'nightly')))

    def test_run_directory_inside_the_clone_is_refused(self):
        proc = self.run_script(NIGHTLY_ROOT=os.path.join(self.repo, 'tmp', 'n'))
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertIn('outside the clone', proc.stdout)
        self.assertFalse(self.session_started())

    # The session itself.

    def test_session_fails(self):
        proc = self.run_script(STUB_EXIT='9')
        self.assertEqual(proc.returncode, 4, proc.stdout)
        self.assertFalse(os.path.exists(self.lock_dir()))

    def test_deadline(self):
        proc = self.run_script(STUB_HANG='1', NIGHTLY_MAX_SECONDS='1',
                               NIGHTLY_GRACE_SECONDS='600')
        self.assertEqual(proc.returncode, 5, proc.stdout)
        # Escape, then /exit typed into the session, which ended on it.
        self.assertTrue(os.path.exists(self.stub_file('session_exit')),
                        proc.stdout)
        self.assertIn('typing /exit', proc.stdout)
        self.assertFalse(os.path.exists(self.lock_dir()))

    def test_deadline_kills_escaping_children_and_spares_others(self):
        control = subprocess.Popen(['/bin/sleep', '600'])
        self.holders.append(control)
        # The stop sequence needs 1 + 5 + 60 + 10 + 20 = 96 seconds, so with
        # a 100 second limit it starts after 4.
        proc = self.run_script(STUB_HANG='1', STUB_ESCAPE='1',
                               NIGHTLY_MAX_SECONDS='100',
                               NIGHTLY_GRACE_SECONDS='5')
        self.assertEqual(proc.returncode, 5, proc.stdout)
        for name in ('newsession', 'doublefork', 'plainchild'):
            pid = int(self.read_stub(name))
            self.assertTrue(wait_until(lambda: not alive(pid)),
                            '%s %d survived\n%s' % (name, pid, proc.stdout))
            if name != 'plainchild':
                self.assertIn('killed pid %d ' % pid, proc.stdout)
        self.assertIsNone(control.poll())
        self.assertNotIn('killed pid %d ' % control.pid, proc.stdout)
        self.assertIn('session root in the pane', proc.stdout)

    def test_session_that_makes_no_progress_is_a_failed_start(self):
        proc = self.run_script(STUB_DIALOG='1', NIGHTLY_STALL_SECONDS='3')
        self.assertEqual(proc.returncode, 14, proc.stdout)
        self.assertIn('no progress', proc.stdout)
        self.assertFalse(os.path.exists(self.lock_dir()))

    def test_session_waiting_at_the_trust_dialog_is_stopped(self):
        proc = self.run_script(STUB_TRUST_DIALOG='1')
        self.assertEqual(proc.returncode, 11, proc.stdout)
        self.assertIn('trust dialog', proc.stdout)
        self.assertFalse(os.path.exists(self.lock_dir()))

    def test_session_cannot_start(self):
        # A tmux that fails stands in for a session that cannot start.
        fake = os.path.join(self.stub_dir, 'faketmux')
        with open(fake, 'w') as fh:
            fh.write('#!/bin/sh\ncase "$*" in *new-session*) exit 1 ;; esac\n'
                     'exec %s "$@"\n' % TMUX)
        os.chmod(fake, 0o755)
        proc = self.run_script(NIGHTLY_TMUX=fake)
        self.assertEqual(proc.returncode, 4, proc.stdout)
        self.assertIn('could not be started', proc.stdout)
        self.assertFalse(self.session_started())

    def test_missing_claude(self):
        proc = self.run_script(CLAUDE_BIN=os.path.join(self.tmp, 'nope'))
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertFalse(os.path.exists(self.lock_dir()))

    def test_missing_tmux(self):
        proc = self.run_script(NIGHTLY_TMUX=os.path.join(self.tmp, 'nope'))
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertIn('cannot find tmux', proc.stdout)

    # Dry run.

    def test_dry_run_prints_the_command_and_starts_nothing(self):
        proc = self.run_script(['--dry-run'])
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertFalse(self.session_started())
        self.assertFalse(os.path.exists(self.lock_dir()))
        self.assertIn("--permission-mode auto", proc.stdout)
        self.assertIn("--model opus", proc.stdout)
        self.assertIn("--strict-mcp-config", proc.stdout)
        self.assertIn('deadline_run.py', proc.stdout)
        self.assertIn('--tmux-socket', proc.stdout)
        self.assertIn('new-session -d -s swift-migration', proc.stdout)
        self.assertIn('verdict: may start another agent', proc.stdout)
        self.assertIn('GIT_CONFIG_COUNT=', proc.stdout)
        self.assertIn('-u SSH_AUTH_SOCK', proc.stdout)
        self.assertIn('Bash(git push *)', proc.stdout)
        self.assertIn('attach -t swift-migration', proc.stdout)
        self.assertIn('update-environment', proc.stdout)
        self.assertNotIn('GIT_PROTOCOL_FROM_USER=0', proc.stdout)
        self.assertNotIn('protocol.file.allow', proc.stdout)
        self.assertNotEqual(subprocess.run(
            [TMUX, '-S', self.socket, 'list-sessions'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode, 0)

    def test_dry_run_reports_a_held_lock_and_the_ceiling(self):
        holder = self.start_holder('fake_nightly_start.sh')
        self.make_lock(holder.pid)
        proc = self.run_script(['--dry-run'], now='2026-11-15T01:00')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('lock: held by pid %d' % holder.pid, proc.stdout)
        self.assertIn('would not start: at or over the ceiling', proc.stdout)
        self.assertFalse(self.session_started())
        self.assertTrue(os.path.isdir(self.lock_dir()))

    def test_bad_option(self):
        proc = self.run_script(['--bogus'])
        self.assertEqual(proc.returncode, 64, proc.stdout)

    # A one-unit night (NIGHTLY_ONE_UNIT_DATE): on that local date only, the
    # weekly ceiling does not stop the start and the prompt asks for exactly
    # one unit. Sunday 2026-11-15 at 01:00 has a ceiling of 1/7 (14.3%) and
    # 54% is used, so without the option the night refuses with exit 1.

    ONE_UNIT_MARK = 'this night does exactly one unit'
    SUNDAY = '2026-11-15T01:00'

    def prompt_of(self, proc):
        with open(os.path.join(self.night_dir_of(proc), 'prompt.txt')) as fh:
            return fh.read()

    def test_one_unit_night_starts_over_the_ceiling(self):
        proc = self.run_script(now=self.SUNDAY,
                               NIGHTLY_ONE_UNIT_DATE='2026-11-15')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertTrue(self.session_started())
        self.assertIn('one-unit night applies', proc.stdout)
        self.assertIn('at or over tonight', proc.stdout)
        self.assertNotIn('not starting', proc.stdout)
        prompt = self.session_args()[-1]
        self.assertIn(self.ONE_UNIT_MARK, prompt)
        self.assertIn('start no second unit', prompt)
        self.assertIn('exit status 2', prompt)
        self.assertIn('lifecycle.md section 3', prompt)
        # The rest of the prompt is still there.
        self.assertIn('docs/swift-migration/orchestration.md from the top', prompt)
        self.assertIn('Stopping cleanly', prompt)

    def test_one_unit_night_under_the_ceiling_still_asks_for_one_unit(self):
        proc = self.run_script(NIGHTLY_ONE_UNIT_DATE='2026-11-19')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('one-unit night applies', proc.stdout)
        self.assertIn(self.ONE_UNIT_MARK, self.session_args()[-1])

    def test_one_unit_night_dry_run_over_the_ceiling(self):
        proc = self.run_script(['--dry-run'], now=self.SUNDAY,
                               NIGHTLY_ONE_UNIT_DATE='2026-11-15')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertFalse(self.session_started())
        self.assertIn('one-unit night applies', proc.stdout)
        self.assertIn('a real run would start anyway', proc.stdout)
        self.assertNotIn('would not start: at or over the ceiling', proc.stdout)
        self.assertIn(self.ONE_UNIT_MARK, self.prompt_of(proc))

    def test_one_unit_night_unknown_usage_still_stops(self):
        self.set_usage('something else entirely\n')
        proc = self.run_script(now=self.SUNDAY,
                               NIGHTLY_ONE_UNIT_DATE='2026-11-15')
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertFalse(self.session_started())
        self.assertFalse(os.path.exists(self.lock_dir()))

    def test_one_unit_night_crashing_usage_check_still_stops(self):
        # A zone that names a directory: ZoneInfo raises IsADirectoryError,
        # which usage_check.py does not catch, so Python exits 1. That is
        # not the ceiling verdict and must not start the night.
        self.set_usage('Current week (all models): 54% used \u00b7 resets '
                       'Nov 21 at 12pm (America)\n')
        proc = self.run_script(now='2026-11-15T01:00',
                               NIGHTLY_ONE_UNIT_DATE='2026-11-15')
        self.assertIn('IsADirectoryError', proc.stdout)
        self.assertIn('taken as unknown', proc.stdout)
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertFalse(self.session_started())

    def test_one_unit_night_failed_usage_command_still_stops(self):
        proc = self.run_script(now=self.SUNDAY, STUB_USAGE_EXIT='1',
                               NIGHTLY_ONE_UNIT_DATE='2026-11-15')
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertFalse(self.session_started())

    def test_one_unit_night_dry_run_unknown_usage(self):
        self.set_usage('something else entirely\n')
        proc = self.run_script(['--dry-run'], now=self.SUNDAY,
                               NIGHTLY_ONE_UNIT_DATE='2026-11-15')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('would not start: usage could not be determined',
                      proc.stdout)

    def test_one_unit_date_on_another_night_has_no_effect(self):
        proc = self.run_script(now=self.SUNDAY,
                               NIGHTLY_ONE_UNIT_DATE='2026-11-14')
        self.assertEqual(proc.returncode, 1, proc.stdout)
        self.assertIn('does not apply tonight', proc.stdout)
        self.assertNotIn('one-unit night applies', proc.stdout)
        self.assertFalse(self.session_started())

    def test_one_unit_date_on_another_night_leaves_the_prompt_alone(self):
        proc = self.run_script(NIGHTLY_ONE_UNIT_DATE='2026-11-23')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('does not apply tonight', proc.stdout)
        self.assertNotIn(self.ONE_UNIT_MARK, self.session_args()[-1])

    def test_no_one_unit_date_leaves_the_prompt_alone(self):
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertNotIn('NIGHTLY_ONE_UNIT_DATE', proc.stdout)
        self.assertNotIn(self.ONE_UNIT_MARK, self.session_args()[-1])

    def test_empty_one_unit_date_is_unset(self):
        # The plist template's placeholder installed empty.
        proc = self.run_script(now=self.SUNDAY, NIGHTLY_ONE_UNIT_DATE='')
        self.assertEqual(proc.returncode, 1, proc.stdout)
        self.assertNotIn('NIGHTLY_ONE_UNIT_DATE', proc.stdout)
        self.assertFalse(self.session_started())

    def test_malformed_one_unit_date_is_refused(self):
        for value in ('tonight', '2026-11-5', '2026-02-30', '2026-13-01',
                      ' 2026-11-15', '2026-11-15 ', '__ONE_UNIT_DATE__',
                      '2026/11/15', '2026-11-15T00:00'):
            with self.subTest(value=value):
                proc = self.run_script(now=self.SUNDAY,
                                       NIGHTLY_ONE_UNIT_DATE=value)
                self.assertEqual(proc.returncode, 64, proc.stdout)
                self.assertIn('NIGHTLY_ONE_UNIT_DATE', proc.stdout)
                self.assertFalse(self.session_started())
                self.assertFalse(os.path.exists(self.stub_file('usage_calls')))
                self.assertFalse(os.path.exists(self.lock_dir()))

    def test_nightly_prompt_still_replaces_the_one_unit_prompt(self):
        proc = self.run_script(now=self.SUNDAY,
                               NIGHTLY_ONE_UNIT_DATE='2026-11-15',
                               NIGHTLY_PROMPT='a test prompt')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.session_args()[-1], 'a test prompt')
        self.assertIn('one-unit night applies', proc.stdout)


class LanesTest(NightlyBase):
    """The nightly orchestrator's build lanes live in <clone>.lanes/,
    outside the clone, where the session may edit (claude --add-dir); lanes
    a dead session left held are released before the next one starts."""

    def test_session_may_edit_the_lanes_directory(self):
        self.assertFalse(os.path.exists(self.lanes))
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        args = self.session_args()
        self.assertEqual(self.option_values(args, '--add-dir'), [self.lanes])
        # The prompt stays last, after an option that takes one value.
        self.assertEqual(args[-3], '--session-id')
        self.assertEqual(stat.S_IMODE(os.stat(self.lanes).st_mode), 0o700)
        self.assertIn('lanes: %s' % self.lanes, proc.stdout)
        self.assertIn(self.lanes, args[-1])

    def test_lanes_directory_follows_the_clone_not_the_run_directory(self):
        # NIGHTLY_ROOT moves the logs; the lanes stay beside the clone,
        # where lane_clone.py puts them by default.
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.option_values(self.session_args(), '--add-dir'),
                         [self.lanes])
        self.assertFalse(os.path.exists(self.root + '.lanes'))

    def test_existing_lanes_directory_is_not_chmodded(self):
        os.mkdir(self.lanes)
        os.chmod(self.lanes, 0o755)
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(stat.S_IMODE(os.stat(self.lanes).st_mode), 0o755)

    def test_lanes_directory_writable_by_others_is_refused(self):
        os.mkdir(self.lanes)
        os.chmod(self.lanes, 0o777)
        proc = self.run_script()
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertIn(self.lanes, proc.stdout)
        self.assertFalse(self.session_started())
        self.assertEqual(stat.S_IMODE(os.stat(self.lanes).st_mode), 0o777)

    def test_lanes_directory_that_is_a_symbolic_link_is_refused(self):
        elsewhere = os.path.join(self.tmp, 'elsewhere')
        os.mkdir(elsewhere, 0o700)
        os.symlink(elsewhere, self.lanes)
        proc = self.run_script()
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertIn('symbolic link', proc.stdout)
        self.assertFalse(self.session_started())

    def test_dry_run_shows_the_add_dir_and_creates_nothing(self):
        proc = self.run_script(['--dry-run'])
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('--add-dir %s' % self.lanes, proc.stdout)
        self.assertIn('a real run would create %s' % self.lanes, proc.stdout)
        self.assertFalse(os.path.exists(self.lanes))

    def held_dirty_lane(self, holder_pid):
        self.lane_tool('create', '--count', '2')
        lane = self.lane_tool('acquire', '--purpose', 'unit author',
                              '--holder-pid', str(holder_pid)).stdout.strip()
        with open(os.path.join(lane, 'work.txt'), 'w') as fh:
            fh.write('uncollected\n')
        git(lane, 'add', 'work.txt')
        return lane

    def saved(self):
        directory = os.path.join(self.lanes, 'saved')
        return sorted(os.listdir(directory)) if os.path.isdir(directory) else []

    def test_lane_held_by_a_dead_session_is_released_and_its_work_saved(self):
        dead = subprocess.Popen(['/usr/bin/true'])
        dead.wait()
        lane = self.held_dirty_lane(dead.pid)
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('lane-1  stale  pid %d' % dead.pid, proc.stdout)
        self.assertIn('released lane 1', proc.stdout)
        saved = self.saved()
        self.assertEqual(len(saved), 1, saved)
        self.assertIn(os.path.join(self.lanes, 'saved', saved[0]), proc.stdout)
        with open(os.path.join(self.lanes, 'saved', saved[0])) as fh:
            self.assertIn('uncollected', fh.read())
        self.assertFalse(os.path.exists(os.path.join(self.lanes, 'locks', 'lane-1')))
        self.assertFalse(os.path.exists(os.path.join(lane, 'work.txt')))
        # Before the session began.
        log = proc.stdout
        self.assertLess(log.index('released lane 1'), log.index('starting the session'))
        self.assertTrue(self.session_started())

    def test_lane_held_by_a_live_process_is_left_alone(self):
        holder = self.start_holder('live_session.sh')
        lane = self.held_dirty_lane(holder.pid)
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('lane-1  held  pid %d' % holder.pid, proc.stdout)
        self.assertNotIn('released lane', proc.stdout)
        self.assertEqual(self.saved(), [])
        self.assertTrue(os.path.isdir(os.path.join(self.lanes, 'locks', 'lane-1')))
        self.assertTrue(os.path.exists(os.path.join(lane, 'work.txt')))

    def test_dry_run_lists_lanes_and_releases_nothing(self):
        dead = subprocess.Popen(['/usr/bin/true'])
        dead.wait()
        lane = self.held_dirty_lane(dead.pid)
        proc = self.run_script(['--dry-run'])
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('lane-1  stale  pid %d' % dead.pid, proc.stdout)
        self.assertIn('a real run would run release --stale', proc.stdout)
        self.assertNotIn('released lane', proc.stdout)
        self.assertTrue(os.path.isdir(os.path.join(self.lanes, 'locks', 'lane-1')))
        self.assertTrue(os.path.exists(os.path.join(lane, 'work.txt')))

    def test_no_lanes_made_yet_is_said_quietly(self):
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('no lanes made yet', proc.stdout)


class LaneSessionEnvironmentTest(NightlyBase):
    """lane_clone.py works in exactly the environment nightly_start.sh gives
    the session, on a clone with a submodule."""

    def prepare_owner(self):
        sub_up = os.path.join(self.tmp, 'sub-up.git')
        seed = os.path.join(self.tmp, 'sub-seed')
        git(self.tmp, 'init', '-q', '--bare', '-b', 'main', sub_up)
        git(self.tmp, 'init', '-q', '-b', 'main', seed)
        with open(os.path.join(seed, 'lib.txt'), 'w') as fh:
            fh.write('one\n')
        git(seed, 'add', 'lib.txt')
        git(seed, 'commit', '-q', '-m', 'sub one')
        git(seed, 'push', '-q', sub_up, 'main')
        git(self.owner, '-c', 'protocol.file.allow=always', 'submodule', 'add', '-q',
            sub_up, 'submodules/sub')
        # Fetching the submodule from its URL would now go to the network.
        git(self.owner, 'config', '-f', '.gitmodules', 'submodule.submodules/sub.url',
            'https://nightly-test.invalid/sub.git')
        git(self.owner, 'add', '.gitmodules')
        git(self.owner, 'commit', '-q', '-m', 'add sub')

    def test_create_acquire_collect_and_release_in_the_session_environment(self):
        proc = self.run_script()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        env = self.session_env()
        # It is the session's environment, in which a local-path fetch from
        # origin (the mirror) works.
        self.assertIn('SWIFT_MIGRATION_NIGHT_ID', env)
        fetch = subprocess.run(['git', 'fetch', '-q', 'origin'], cwd=self.repo, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               universal_newlines=True)
        self.assertEqual(fetch.returncode, 0, fetch.stdout)
        owner_before = subprocess.run(['/bin/bash', CLONE_TOOL, 'owner-refs', '--source',
                                       self.owner], stdout=subprocess.PIPE,
                                      universal_newlines=True).stdout
        self.lane_tool('create', '--count', '2', env=env)
        # A reviewer's lane: the orchestrator's staged change applied.
        with open(os.path.join(self.repo, 'unit.txt'), 'w') as fh:
            fh.write('the unit\n')
        git(self.repo, 'add', 'unit.txt')
        lane = self.lane_tool('acquire', '--purpose', 'unit reviewer', '--holder-pid',
                              str(os.getpid()), '--apply-staged', 'unit.txt',
                              env=env).stdout.strip()
        self.assertEqual(lane, os.path.join(self.lanes, 'lane-1'))
        with open(os.path.join(lane, 'unit.txt')) as fh:
            self.assertEqual(fh.read(), 'the unit\n')
        self.assertTrue(os.path.exists(os.path.join(lane, 'submodules', 'sub', 'lib.txt')))
        self.assertIn('unit.txt', subprocess.run(
            ['git', 'diff', '--cached', '--name-only'], cwd=lane, env=env,
            stdout=subprocess.PIPE, universal_newlines=True).stdout)
        self.lane_tool('release', '1', env=env)
        # An author's lane: its change collected into the clone's index.
        git(self.repo, 'rm', '-q', '--cached', 'unit.txt')
        os.remove(os.path.join(self.repo, 'unit.txt'))
        lane = self.lane_tool('acquire', '--purpose', 'unit author', '--holder-pid',
                              str(os.getpid()), env=env).stdout.strip()
        with open(os.path.join(lane, 'new.txt'), 'w') as fh:
            fh.write('authored\n')
        subprocess.run(['git', 'add', 'new.txt'], cwd=lane, env=env, check=True)
        self.lane_tool('collect', '1', '--to-index', env=env)
        self.assertEqual(git(self.repo, 'diff', '--cached', '--name-only'), 'new.txt\n')
        self.lane_tool('release', '1', env=env)
        status = self.lane_tool('status', env=env).stdout
        self.assertIn('lane-1  free', status)
        # The registrations pass the clone's check, the clone shows only the
        # collected file, and the owner's repositories are untouched.
        check = subprocess.run(['/bin/bash', CLONE_TOOL, 'check', '--source', self.owner,
                                '--clone', self.repo], stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, universal_newlines=True)
        self.assertEqual(check.returncode, 0, check.stdout)
        self.assertEqual(git(self.repo, 'status', '--porcelain'), 'A  new.txt\n')
        owner_after = subprocess.run(['/bin/bash', CLONE_TOOL, 'owner-refs', '--source',
                                      self.owner], stdout=subprocess.PIPE,
                                     universal_newlines=True).stdout
        self.assertEqual(owner_before, owner_after)


class StaleLockRaceTest(NightlyBase):
    """Two starts racing on a stale lock must never both run a session."""

    def test_race_on_a_stale_lock(self):
        for attempt in range(30):
            shutil.rmtree(self.root, ignore_errors=True)
            for name in ('sessions', 'release', 'session_args'):
                if os.path.exists(self.stub_file(name)):
                    os.remove(self.stub_file(name))
            self.make_lock(99999999)  # no such pid
            barrier = os.path.join(self.tmp, 'barrier')
            shutil.rmtree(barrier, ignore_errors=True)
            os.mkdir(barrier)
            # Both runs judge the lock stale; the first to do so waits until
            # the other has replaced the lock and started its session.
            env = self.env(STUB_RACE_HOLD='1',
                           NIGHTLY_LOCK_TEST_BARRIER=barrier)
            procs = [subprocess.Popen(['/bin/bash', SCRIPT], env=env,
                                      cwd=self.tmp, stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT,
                                      universal_newlines=True,
                                      start_new_session=True)
                     for _ in range(2)]
            try:
                def starts():
                    if not os.path.exists(self.stub_file('sessions')):
                        return 0
                    return self.read_stub('sessions').count('start')
                # One run replaces the lock and holds its session open
                # until released, so a second session can only come from a
                # broken lock. Then the waiting run acts on its stale
                # judgment; wait for it to give up (or for a second
                # session).
                self.assertTrue(wait_until(lambda: starts() >= 1, 120),
                                '\n'.join(p.stdout.read() for p in procs
                                           if p.poll() is not None))
                with open(os.path.join(barrier, 'go'), 'w'):
                    pass
                self.assertTrue(wait_until(
                    lambda: starts() >= 2 or any(p.poll() is not None
                                                 for p in procs), 120))
                self.assertLess(starts(), 2, 'attempt %d: two sessions'
                                % attempt)
                with open(self.stub_file('release'), 'w'):
                    pass
                outs = [p.communicate(timeout=120)[0] for p in procs]
            finally:
                # Release any held session first: the sessions run in their
                # own session (deadline_run.py), out of reach of killpg.
                with open(self.stub_file('release'), 'w'):
                    pass
                for p in procs:
                    if p.returncode is not None:
                        continue
                    try:
                        p.communicate(timeout=120)
                    except subprocess.TimeoutExpired:
                        os.killpg(p.pid, signal.SIGKILL)
                        p.communicate()
            codes = sorted(p.returncode for p in procs)
            self.assertLess(starts(), 2, 'attempt %d: two sessions' % attempt)
            self.assertIn(3, codes, 'attempt %d: %s\n%s' % (attempt, codes,
                                                           '\n'.join(outs)))
            self.assertTrue(set(codes) <= {0, 3}, '%s\n%s'
                            % (codes, '\n'.join(outs)))


class PlistTest(unittest.TestCase):
    def load(self):
        with open(PLIST, 'rb') as fh:
            return plistlib.load(fh)

    def test_plist_is_valid_and_runs_at_midnight(self):
        data = self.load()
        self.assertEqual(data['Label'],
                         'com.googlecode.iterm2.swift-migration-nightly')
        self.assertEqual(data['StartCalendarInterval'],
                         {'Hour': 0, 'Minute': 0})
        self.assertEqual(data['ProgramArguments'][-1],
                         '__REPO__/tools/swift_migration/nightly_start.sh')
        self.assertFalse(data.get('RunAtLoad', False))
        self.assertNotIn('KeepAlive', data)

    def test_path_covers_the_tools(self):
        path = self.load()['EnvironmentVariables']['PATH'].split(':')
        for directory in ('/opt/homebrew/opt/ruby/bin',
                          '/Library/Frameworks/Python.framework/Versions/3.9/bin',
                          '/opt/homebrew/bin', '/usr/local/bin', '/usr/bin',
                          '/bin', '/usr/sbin', '/sbin'):
            self.assertIn(directory, path)
        # Homebrew's Ruby before the system one, as in the owner's shell.
        self.assertLess(path.index('/opt/homebrew/opt/ruby/bin'),
                        path.index('/usr/bin'))

    def test_environment_names_the_clone_and_locale(self):
        env = self.load()['EnvironmentVariables']
        self.assertEqual(env['NIGHTLY_CLONE'], '__CLONE__')
        self.assertEqual(env['LANG'], 'en_US.UTF-8')
        self.assertEqual(env['PYTHON'], '/Library/Frameworks/Python.framework/'
                         'Versions/3.9/bin/python3')
        self.assertEqual(env['NIGHTLY_LAUNCHD_LOG'], self.load()['StandardOutPath'])
        # tmux is found on PATH (Homebrew's).
        self.assertIn('/opt/homebrew/bin', env['PATH'].split(':'))

    def test_log_does_not_need_the_repository_tmp(self):
        data = self.load()
        for key in ('StandardOutPath', 'StandardErrorPath'):
            self.assertNotIn('__REPO__', data[key])
            self.assertTrue(data[key].startswith('__HOME__/Library/Logs/'),
                            data[key])

    def test_plutil_lint(self):
        proc = subprocess.run(['/usr/bin/plutil', '-lint', PLIST],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              universal_newlines=True)
        self.assertEqual(proc.returncode, 0, proc.stdout)


if __name__ == '__main__':
    unittest.main()
