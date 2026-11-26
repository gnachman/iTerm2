"""Tests for tools/swift_migration/lane_clone.py, the build lanes.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_lane_clone.py'

Every test builds its own throwaway "orchestrator" checkout in a temporary
directory: a repository with one submodule whose upstream is a local bare
repository. After setup the submodule's URL, in .gitmodules and in the
checkout's configuration, is changed to an https URL under .invalid, so a
lane that went to the network (or to the upstream) for the submodule would
fail instead of quietly working. Nothing here touches this checkout, the
network, or the owner's git configuration (GIT_CONFIG_GLOBAL=/dev/null,
GIT_CONFIG_NOSYSTEM=1). No test depends on timing: a dead lock holder is a
child process that has been killed and waited for.
"""

import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(os.path.dirname(HERE), 'lane_clone.py')

IDENTITY = {
    'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@example.invalid',
    'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@example.invalid',
}
BAD_URL = 'https://example.invalid/sub.git'
PROJECT = 'iTerm2.xcodeproj/project.pbxproj'


def base_env():
    env = {
        'PATH': '/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
        'HOME': os.environ.get('HOME', '/nonexistent'),
        'GIT_CONFIG_GLOBAL': '/dev/null',
        'GIT_CONFIG_NOSYSTEM': '1',
        'LANG': 'en_US.UTF-8',
    }
    env.update(IDENTITY)
    return env


def git(cwd, *args, check=True, env=None):
    full_env = base_env()
    full_env.update(env or {})
    proc = subprocess.run(['git', '-c', 'core.hooksPath=/dev/null'] + list(args), cwd=cwd,
                          env=full_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          universal_newlines=True)
    if check and proc.returncode != 0:
        raise AssertionError('git %s failed in %s: %s' % (' '.join(args), cwd, proc.stderr))
    return proc


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)


def read(path):
    with open(path) as f:
        return f.read()


def digest_tree(top):
    """A digest of every file under top (names and contents), for 'unchanged'
    checks. The object store is left out: a three-way apply writes blobs
    there, which changes nothing anyone can see."""
    h = hashlib.sha256()
    for root, dirs, files in os.walk(top):
        if os.path.basename(root) == '.git' and 'objects' in dirs:
            dirs.remove('objects')
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(root, name)
            h.update(os.path.relpath(path, top).encode())
            if os.path.islink(path):
                h.update(os.readlink(path).encode())
            else:
                with open(path, 'rb') as f:
                    h.update(f.read())
    return h.hexdigest()


class LaneBase(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp(prefix='lane_clone.'))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = os.path.join(self.tmp, 'orch')
        self.lanes = os.path.join(self.tmp, 'lanes')
        sub_up = os.path.join(self.tmp, 'sub-up.git')
        git(self.tmp, 'init', '-q', '--bare', '-b', 'main', sub_up)
        seed = os.path.join(self.tmp, 'sub-seed')
        git(self.tmp, 'init', '-q', '-b', 'main', seed)
        write(os.path.join(seed, 'lib.c'), 'int lib;\n')
        git(seed, 'add', 'lib.c')
        git(seed, 'commit', '-q', '-m', 'sub 1')
        git(seed, 'push', '-q', sub_up, 'main')
        git(self.tmp, 'init', '-q', '-b', 'master', self.repo)
        write(os.path.join(self.repo, 'a.txt'), ''.join('line %d\n' % i for i in range(1, 21)))
        write(os.path.join(self.repo, 'b.txt'), 'bee\n')
        write(os.path.join(self.repo, '.gitignore'), 'Build/\ntmp/\n')
        write(os.path.join(self.repo, PROJECT), '// project\n')
        git(self.repo, 'add', '.')
        git(self.repo, '-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', sub_up, 'sub')
        git(self.repo, 'commit', '-q', '-m', 'one')
        # From here on, fetching the submodule from anywhere but the
        # orchestrator's own submodule repository fails.
        git(self.repo, 'config', '-f', '.gitmodules', 'submodule.sub.url', BAD_URL)
        git(self.repo, 'config', 'submodule.sub.url', BAD_URL)
        git(self.repo, 'commit', '-q', '-am', 'bad url')
        self.config_before = read(os.path.join(self.repo, '.git', 'config'))

    def run_tool(self, *args, expect=0, env=None, cwd=None):
        full_env = base_env()
        full_env.update(env or {})
        proc = subprocess.run([sys.executable, '-B', TOOL, '--repo', self.repo,
                               '--lanes-dir', self.lanes] + list(args),
                              cwd=cwd or self.repo, env=full_env, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, universal_newlines=True)
        if expect is not None and proc.returncode != expect:
            self.fail('lane_clone %s exited %d, expected %d\nstdout:\n%s\nstderr:\n%s'
                      % (' '.join(args), proc.returncode, expect, proc.stdout, proc.stderr))
        return proc

    def acquire(self, *args, expect=0):
        """Acquires a lane held by this test process, which stays alive."""
        proc = self.run_tool('acquire', '--holder-pid', str(os.getpid()), *args, expect=expect)
        return proc.stdout.strip() if expect == 0 else proc

    def head(self, cwd):
        return git(cwd, 'rev-parse', 'HEAD').stdout.strip()

    def dead_pid(self):
        child = subprocess.Popen(['/bin/sleep', '1000'])
        child.kill()
        child.wait()
        return child.pid

    def status_json(self):
        return json.loads(self.run_tool('status', '--json').stdout)

    def lane_entry(self, number):
        return [e for e in self.status_json()['lanes'] if e['lane'] == number][0]

    def saved_files(self):
        saved_dir = os.path.join(self.lanes, 'saved')
        if not os.path.isdir(saved_dir):
            return []
        return sorted(os.path.join(saved_dir, n) for n in os.listdir(saved_dir))

    def holder_file(self, number):
        return os.path.join(self.lanes, 'locks', 'lane-%d' % number, 'holder.json')


class CreateTests(LaneBase):
    def test_create_makes_worktree_with_submodule_without_network(self):
        sub_before = digest_tree(os.path.join(self.repo, 'sub'))
        self.run_tool('create', '1')
        lane = os.path.join(self.lanes, 'lane-1')
        self.assertEqual(self.head(lane), self.head(self.repo))
        self.assertEqual(read(os.path.join(lane, 'sub', 'lib.c')), 'int lib;\n')
        self.assertEqual(self.head(os.path.join(lane, 'sub')),
                         git(self.repo, 'rev-parse', 'HEAD:sub').stdout.strip())
        self.assertEqual(git(lane, 'status', '--porcelain', '--ignore-submodules=none').stdout, '')
        listed = git(self.repo, 'worktree', 'list', '--porcelain').stdout
        self.assertIn('worktree %s\n' % lane, listed)
        # Nothing of the orchestrator's changed: configuration, submodule
        # working tree, index entries, status.
        self.assertEqual(read(os.path.join(self.repo, '.git', 'config')), self.config_before)
        self.assertEqual(digest_tree(os.path.join(self.repo, 'sub')), sub_before)
        self.assertEqual(git(self.repo, 'status', '--porcelain', '--ignore-submodules=none').stdout, '')

    def test_create_without_arguments_makes_every_lane(self):
        self.run_tool('create', '--count', '2')
        for n in (1, 2):
            self.assertTrue(os.path.isdir(os.path.join(self.lanes, 'lane-%d' % n, 'sub')))
        self.assertFalse(os.path.exists(os.path.join(self.lanes, 'lane-3')))

    def test_refuses_to_run_from_inside_a_lane(self):
        self.run_tool('create', '1')
        lane = os.path.join(self.lanes, 'lane-1')
        proc = subprocess.run([sys.executable, '-B', TOOL, 'status'], cwd=lane, env=base_env(),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn('inside a lane', proc.stderr)

    def test_refuses_lanes_dir_made_for_another_repository(self):
        self.run_tool('create', '1')
        other = os.path.join(self.tmp, 'other')
        git(self.tmp, 'init', '-q', '-b', 'master', other)
        write(os.path.join(other, 'x'), 'x\n')
        git(other, 'add', 'x')
        git(other, 'commit', '-q', '-m', 'x')
        proc = subprocess.run([sys.executable, '-B', TOOL, '--repo', other, '--lanes-dir',
                               self.lanes, 'status'], env=base_env(), stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, universal_newlines=True)
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn('belongs to', proc.stderr)

    def test_refuses_lanes_dir_inside_the_working_tree_unless_ignored(self):
        proc = subprocess.run([sys.executable, '-B', TOOL, '--repo', self.repo, '--lanes-dir',
                               os.path.join(self.repo, 'lanes'), 'create', '1'],
                              env=base_env(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True)
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn('inside the working tree', proc.stderr)
        proc = subprocess.run([sys.executable, '-B', TOOL, '--repo', self.repo, '--lanes-dir',
                               os.path.join(self.repo, 'tmp', 'lanes'), 'create', '1'],
                              env=base_env(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(git(self.repo, 'status', '--porcelain').stdout, '')

    def test_default_lanes_dir_is_beside_the_repository(self):
        proc = subprocess.run([sys.executable, '-B', TOOL, 'create', '1'], cwd=self.repo,
                              env=base_env(), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(os.path.isdir(self.repo + '.lanes/lane-1/sub'))


class AcquireTests(LaneBase):
    def test_acquire_prints_path_and_a_second_acquire_gets_another_lane(self):
        first = self.acquire('--purpose', 'unit A author')
        second = self.acquire('--purpose', 'unit B author')
        self.assertEqual(first, os.path.join(self.lanes, 'lane-1'))
        self.assertEqual(second, os.path.join(self.lanes, 'lane-2'))
        entry = self.lane_entry(1)
        self.assertEqual(entry['state'], 'held')
        self.assertEqual(entry['purpose'], 'unit A author')
        self.assertEqual(entry['pid'], os.getpid())

    def test_last_lane_is_reserved_for_full_suite(self):
        self.acquire()
        self.acquire()
        proc = self.acquire(expect=3)
        self.assertIn('no free lane', proc.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.lanes, 'lane-3')))
        full = self.acquire('--full-suite', '--purpose', 'gate')
        self.assertEqual(full, os.path.join(self.lanes, 'lane-3'))
        proc = self.acquire('--full-suite', expect=3)
        self.assertIn('no free lane', proc.stderr)

    def test_full_suite_never_takes_an_ordinary_lane(self):
        self.run_tool('create', '1')
        full = self.acquire('--full-suite')
        self.assertEqual(full, os.path.join(self.lanes, 'lane-3'))

    def test_acquire_prefers_a_lane_already_made(self):
        self.run_tool('create', '2')
        self.assertEqual(self.acquire(), os.path.join(self.lanes, 'lane-2'))

    def test_acquire_resets_to_head_and_keeps_ignored_build_products(self):
        lane = self.acquire()
        write(os.path.join(lane, 'Build', 'product.o'), 'object\n')
        write(os.path.join(lane, 'stray.txt'), 'untracked\n')
        write(os.path.join(lane, 'b.txt'), 'changed in lane\n')
        write(os.path.join(lane, 'sub', 'lib.c'), 'int changed;\n')
        proc = self.run_tool('release', '1')
        # The edit inside the submodule is saved aside and named, not lost.
        saved = self.saved_files()
        sub_saved = [p for p in saved if 'sub' in os.path.basename(p) and
                     '+int changed;' in read(p)]
        self.assertEqual(len(sub_saved), 1, saved)
        self.assertIn('submodule sub', proc.stderr)
        self.assertIn(sub_saved[0], proc.stderr)
        write(os.path.join(self.repo, 'b.txt'), 'bee two\n')
        git(self.repo, 'commit', '-q', '-am', 'two')
        lane = self.acquire()
        self.assertEqual(lane, os.path.join(self.lanes, 'lane-1'))
        self.assertEqual(self.head(lane), self.head(self.repo))
        self.assertEqual(read(os.path.join(lane, 'b.txt')), 'bee two\n')
        self.assertFalse(os.path.exists(os.path.join(lane, 'stray.txt')))
        self.assertEqual(read(os.path.join(lane, 'sub', 'lib.c')), 'int lib;\n')
        self.assertEqual(read(os.path.join(lane, 'Build', 'product.o')), 'object\n')
        self.assertEqual(git(lane, 'status', '--porcelain', '--ignore-submodules=none').stdout, '')

    def test_acquire_moves_submodule_to_the_new_gitlink(self):
        lane = self.acquire()
        self.run_tool('release', '1')
        sub = os.path.join(self.repo, 'sub')
        write(os.path.join(sub, 'lib.c'), 'int lib2;\n')
        git(sub, 'commit', '-q', '-am', 'sub 2')
        git(self.repo, 'add', 'sub')
        git(self.repo, 'commit', '-q', '-m', 'bump sub')
        lane = self.acquire()
        self.assertEqual(self.head(os.path.join(lane, 'sub')), self.head(sub))
        self.assertEqual(read(os.path.join(lane, 'sub', 'lib.c')), 'int lib2;\n')

    def test_acquire_fails_clearly_when_submodule_commit_is_missing(self):
        # The orchestrator records a submodule commit its own submodule
        # repository does not have.
        self.acquire()
        self.run_tool('release', '1')
        fake = '1234567890123456789012345678901234567890'
        git(self.repo, 'update-index', '--cacheinfo', '160000,%s,sub' % fake)
        git(self.repo, 'commit', '-q', '-m', 'phantom gitlink')
        proc = self.acquire(expect=1)
        self.assertIn(fake, proc.stderr)
        self.assertEqual(self.lane_entry(1)['state'], 'free')

    def test_apply_staged_brings_only_the_named_staged_changes(self):
        write(os.path.join(self.repo, 'a.txt'), 'staged change\n')
        write(os.path.join(self.repo, 'new.txt'), 'new file\n')
        git(self.repo, 'add', 'a.txt', 'new.txt')
        write(os.path.join(self.repo, 'b.txt'), 'unstaged change\n')
        lane = self.acquire('--apply-staged', 'a.txt', 'new.txt')
        self.assertEqual(read(os.path.join(lane, 'a.txt')), 'staged change\n')
        self.assertEqual(read(os.path.join(lane, 'new.txt')), 'new file\n')
        self.assertEqual(read(os.path.join(lane, 'b.txt')), 'bee\n')
        staged = git(lane, 'diff', '--cached', '--name-only').stdout.split()
        self.assertEqual(sorted(staged), ['a.txt', 'new.txt'])

    def test_apply_staged_with_nothing_staged_fails_and_frees_the_lane(self):
        proc = self.acquire('--apply-staged', 'a.txt', expect=1)
        self.assertIn('nothing staged', proc.stderr)
        self.assertEqual(self.lane_entry(1)['state'], 'free')

    def test_apply_patch_file(self):
        write(os.path.join(self.repo, 'a.txt'), 'from a parked patch\n')
        patch = git(self.repo, 'diff', '--binary').stdout
        git(self.repo, 'checkout', '--', 'a.txt')
        path = os.path.join(self.tmp, 'parked.patch')
        write(path, patch)
        lane = self.acquire('--apply-patch', path)
        self.assertEqual(read(os.path.join(lane, 'a.txt')), 'from a parked patch\n')


class LockTests(LaneBase):
    def test_stale_lock_is_reported_and_cleared_only_by_release_stale(self):
        self.run_tool('acquire', '--holder-pid', str(self.dead_pid()), '--purpose', 'gone')
        self.acquire('--purpose', 'alive')
        self.assertEqual(self.lane_entry(1)['state'], 'stale')
        self.assertEqual(self.lane_entry(2)['state'], 'held')
        text = self.run_tool('status').stdout
        self.assertIn('stale', text)
        # A stale lane is not handed out again until it is released.
        self.acquire(expect=3)
        self.run_tool('release', '--stale')
        self.assertEqual(self.lane_entry(1)['state'], 'free')
        self.assertEqual(self.lane_entry(2)['state'], 'held')
        self.assertEqual(self.acquire(), os.path.join(self.lanes, 'lane-1'))

    def test_default_holder_outlives_wrapper_commands(self):
        # Run as a Claude Code session runs it: through a shell, here with
        # /usr/bin/time and env in front. The holder must be a process that
        # is still alive afterwards (an ancestor of this test), not one of
        # the wrappers, which have exited by the time status runs.
        command = ('/usr/bin/time -p /usr/bin/env %s -B %s --repo %s --lanes-dir %s acquire'
                   % tuple(shlex.quote(a) for a in (sys.executable, TOOL, self.repo, self.lanes)))
        proc = subprocess.run(['/bin/sh', '-c', command], env=base_env(),
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        entry = self.lane_entry(1)
        self.assertEqual(entry['state'], 'held', entry)

    def test_release_saves_uncollected_work_and_cleans_the_lane(self):
        lane = self.acquire()
        write(os.path.join(lane, 'b.txt'), 'work\n')
        write(os.path.join(lane, 'untracked.txt'), 'never added\n')
        proc = self.run_tool('release', '1')
        saved = [os.path.join(self.lanes, 'saved', n)
                 for n in os.listdir(os.path.join(self.lanes, 'saved'))]
        self.assertEqual(len(saved), 1)
        self.assertIn(saved[0], proc.stderr)
        text = read(saved[0])
        self.assertIn('+work', text)
        self.assertIn('+never added', text)
        entry = self.lane_entry(1)
        self.assertEqual(entry['state'], 'free')
        self.assertFalse(entry['dirty'])

    def test_release_of_clean_lane_saves_nothing(self):
        self.acquire()
        self.run_tool('release', '1')
        self.assertFalse(os.path.exists(os.path.join(self.lanes, 'saved')) and
                         os.listdir(os.path.join(self.lanes, 'saved')))

    def test_status_shows_dirty_and_commit(self):
        lane = self.acquire()
        self.assertFalse(self.lane_entry(1)['dirty'])
        write(os.path.join(lane, 'b.txt'), 'x\n')
        entry = self.lane_entry(1)
        self.assertTrue(entry['dirty'])
        self.assertEqual(entry['commit'], self.head(self.repo))
        self.assertEqual(self.lane_entry(2)['state'], 'missing')
        self.assertTrue(self.lane_entry(3)['reserved'])


class CollectTests(LaneBase):
    def test_collect_prints_tracked_and_added_changes_and_warns_about_unadded(self):
        lane = self.acquire()
        write(os.path.join(lane, 'b.txt'), 'bee changed\n')
        write(os.path.join(lane, 'added.txt'), 'added\n')
        git(lane, 'add', 'added.txt')
        write(os.path.join(lane, 'loose.txt'), 'loose\n')
        proc = self.run_tool('collect', '1')
        self.assertIn('+bee changed', proc.stdout)
        self.assertIn('+added', proc.stdout)
        self.assertNotIn('loose', proc.stdout)
        self.assertIn('loose.txt', proc.stderr)
        self.assertIn('not added', proc.stderr)

    def test_collect_to_index_applies_to_the_orchestrator(self):
        lane = self.acquire()
        write(os.path.join(lane, 'b.txt'), 'bee changed\n')
        write(os.path.join(lane, 'added.txt'), 'added\n')
        git(lane, 'add', 'added.txt')
        write(os.path.join(lane, 'loose.txt'), 'loose\n')
        self.run_tool('collect', '1', '--to-index')
        self.assertEqual(read(os.path.join(self.repo, 'b.txt')), 'bee changed\n')
        self.assertEqual(read(os.path.join(self.repo, 'added.txt')), 'added\n')
        self.assertFalse(os.path.exists(os.path.join(self.repo, 'loose.txt')))
        staged = git(self.repo, 'diff', '--cached', '--name-only').stdout.split()
        self.assertEqual(sorted(staged), ['added.txt', 'b.txt'])

    def test_collect_merges_when_orchestrator_moved_on_without_conflict(self):
        lane = self.acquire()
        a = read(os.path.join(lane, 'a.txt')).replace('line 2\n', 'line two\n')
        write(os.path.join(lane, 'a.txt'), a)
        mine = read(os.path.join(self.repo, 'a.txt')).replace('line 19\n', 'line nineteen\n')
        write(os.path.join(self.repo, 'a.txt'), mine)
        git(self.repo, 'commit', '-q', '-am', 'meanwhile')
        self.run_tool('collect', '1', '--to-index')
        text = read(os.path.join(self.repo, 'a.txt'))
        self.assertIn('line two\n', text)
        self.assertIn('line nineteen\n', text)

    def test_collect_conflict_is_refused_and_changes_nothing(self):
        lane = self.acquire()
        write(os.path.join(lane, 'b.txt'), 'lane version\n')
        write(os.path.join(self.repo, 'b.txt'), 'orchestrator version\n')
        git(self.repo, 'commit', '-q', '-am', 'meanwhile')
        write(os.path.join(self.repo, 'a.txt'), 'other staged work\n')
        git(self.repo, 'add', 'a.txt')
        index_before = git(self.repo, 'ls-files', '-s').stdout
        tree_before = digest_tree(self.repo)
        proc = self.run_tool('collect', '1', '--to-index', expect=4)
        self.assertIn('does not apply cleanly', proc.stderr)
        self.assertEqual(git(self.repo, 'ls-files', '-s').stdout, index_before)
        self.assertEqual(git(self.repo, 'ls-files', '-u').stdout, '')
        self.assertEqual(digest_tree(self.repo), tree_before)

    def test_collect_refuses_the_project_file_unless_allowed(self):
        lane = self.acquire()
        write(os.path.join(lane, PROJECT), '// clobbered\n')
        write(os.path.join(lane, 'b.txt'), 'bee changed\n')
        proc = self.run_tool('collect', '1', '--to-index', expect=4)
        self.assertIn(PROJECT, proc.stderr)
        self.assertIn('--allow-project', proc.stderr)
        self.assertEqual(read(os.path.join(self.repo, PROJECT)), '// project\n')
        self.assertEqual(read(os.path.join(self.repo, 'b.txt')), 'bee\n')
        self.run_tool('collect', '1', '--to-index', '--allow-project')
        self.assertEqual(read(os.path.join(self.repo, PROJECT)), '// clobbered\n')

    def test_collect_refuses_a_submodule_change(self):
        lane = self.acquire()
        sub = os.path.join(lane, 'sub')
        write(os.path.join(sub, 'lib.c'), 'int moved;\n')
        git(sub, 'commit', '-q', '-am', 'moved')
        write(os.path.join(lane, 'b.txt'), 'bee changed\n')
        proc = self.run_tool('collect', '1')
        self.assertNotIn('Subproject commit', proc.stdout)
        self.assertIn('sub', proc.stderr)
        gitlink_before = git(self.repo, 'ls-files', '-s', 'sub').stdout
        proc = self.run_tool('collect', '1', '--to-index', expect=4)
        self.assertIn('submodule', proc.stderr)
        self.assertEqual(git(self.repo, 'ls-files', '-s', 'sub').stdout, gitlink_before)
        self.assertEqual(read(os.path.join(self.repo, 'b.txt')), 'bee\n')

    def test_collect_includes_commits_an_agent_made_in_the_lane(self):
        lane = self.acquire()
        write(os.path.join(lane, 'b.txt'), 'committed by mistake\n')
        git(lane, 'commit', '-q', '-am', 'oops')
        write(os.path.join(lane, 'a.txt'), 'and more\n')
        proc = self.run_tool('collect', '1')
        self.assertIn('+committed by mistake', proc.stdout)
        self.assertIn('+and more', proc.stdout)
        self.assertIn('commit', proc.stderr)

    def test_collect_of_a_clean_lane_is_empty(self):
        self.acquire()
        proc = self.run_tool('collect', '1', '--to-index')
        self.assertEqual(proc.stdout, '')
        self.assertIn('nothing to collect', proc.stderr)
        self.assertEqual(git(self.repo, 'status', '--porcelain').stdout, '')

    def test_collect_handles_binary_files(self):
        lane = self.acquire()
        with open(os.path.join(lane, 'blob.bin'), 'wb') as f:
            f.write(bytes(range(256)) * 4)
        git(lane, 'add', 'blob.bin')
        self.run_tool('collect', '1', '--to-index')
        with open(os.path.join(self.repo, 'blob.bin'), 'rb') as f:
            self.assertEqual(f.read(), bytes(range(256)) * 4)


class DestroyTests(LaneBase):
    def test_destroy_removes_lane_and_its_registration(self):
        lane = self.acquire()
        write(os.path.join(lane, 'Build', 'product.o'), 'object\n')
        self.run_tool('release', '1')
        self.run_tool('destroy', '1')
        self.assertFalse(os.path.exists(lane))
        listed = git(self.repo, 'worktree', 'list', '--porcelain').stdout
        self.assertNotIn(lane, listed)
        common = os.path.join(self.repo, '.git', 'worktrees')
        self.assertFalse(os.path.isdir(common) and os.listdir(common))
        self.assertEqual(self.lane_entry(1)['state'], 'missing')
        self.assertEqual(read(os.path.join(self.repo, '.git', 'config')), self.config_before)

    def test_destroy_refuses_a_held_lane_without_force(self):
        lane = self.acquire()
        proc = self.run_tool('destroy', '1', expect=4)
        self.assertIn('held', proc.stderr)
        self.assertTrue(os.path.isdir(lane))
        self.run_tool('destroy', '1', '--force')
        self.assertFalse(os.path.exists(lane))
        self.assertEqual(self.lane_entry(1)['state'], 'missing')

    def test_destroy_saves_uncollected_work(self):
        lane = self.acquire()
        write(os.path.join(lane, 'b.txt'), 'work\n')
        self.run_tool('destroy', '1', '--force')
        saved = os.listdir(os.path.join(self.lanes, 'saved'))
        self.assertEqual(len(saved), 1)
        self.assertIn('+work', read(os.path.join(self.lanes, 'saved', saved[0])))


class ReviewTests(LaneBase):
    # B1: changes only inside a submodule.
    def test_submodule_only_change_is_reported_and_saved_on_release(self):
        lane = self.acquire()
        write(os.path.join(lane, 'sub', 'lib.c'), 'int only_in_sub;\n')
        write(os.path.join(lane, 'sub', 'new_in_sub.c'), 'int fresh;\n')
        entry = self.lane_entry(1)
        self.assertTrue(entry['dirty'])
        self.assertEqual(entry['dirty_submodules'], ['sub'])
        self.assertIn('dirty (submodule sub)', self.run_tool('status').stdout)
        proc = self.run_tool('release', '1')
        saved = self.saved_files()
        self.assertEqual(len(saved), 1, saved)
        text = read(saved[0])
        self.assertIn('+int only_in_sub;', text)
        self.assertIn('+int fresh;', text)
        self.assertIn('submodule sub', proc.stderr)
        self.assertIn(saved[0], proc.stderr)
        self.assertEqual(read(os.path.join(lane, 'sub', 'lib.c')), 'int lib;\n')

    def test_submodule_only_change_is_saved_on_destroy(self):
        lane = self.acquire()
        write(os.path.join(lane, 'sub', 'lib.c'), 'int only_in_sub;\n')
        proc = self.run_tool('destroy', '1', '--force')
        saved = self.saved_files()
        self.assertEqual(len(saved), 1, saved)
        self.assertIn('+int only_in_sub;', read(saved[0]))
        self.assertIn('submodule sub', proc.stderr)

    # N4: the save made when re-acquiring a dirty free lane.
    def test_reacquiring_a_dirty_free_lane_saves_its_work(self):
        lane = self.acquire()
        self.run_tool('release', '1')
        write(os.path.join(lane, 'b.txt'), 'written after release\n')
        write(os.path.join(lane, 'sub', 'lib.c'), 'int after_release;\n')
        proc = self.run_tool('acquire', '--holder-pid', str(os.getpid()))
        texts = [read(p) for p in self.saved_files()]
        self.assertEqual(len(texts), 2, self.saved_files())
        self.assertTrue(any('+written after release' in t for t in texts))
        self.assertTrue(any('+int after_release;' in t for t in texts))
        self.assertIn('submodule sub', proc.stderr)
        self.assertEqual(read(os.path.join(lane, 'b.txt')), 'bee\n')

    # N1: a save that fails must not be followed by a reset.
    def test_failed_save_on_acquire_leaves_the_lane_untouched(self):
        lane = self.acquire()
        self.run_tool('release', '1')
        write(os.path.join(lane, 'b.txt'), 'precious\n')
        git(lane, 'init', '-q', os.path.join(lane, 'nested'))
        proc = self.run_tool('acquire', '--holder-pid', str(os.getpid()), expect=1)
        self.assertNotIn('Traceback', proc.stderr)
        self.assertIn('not reset', proc.stderr)
        self.assertEqual(read(os.path.join(lane, 'b.txt')), 'precious\n')
        self.assertTrue(os.path.isdir(os.path.join(lane, 'nested', '.git')))
        self.assertEqual(self.lane_entry(1)['state'], 'free')

    # N2: concurrent acquires.
    def test_parallel_acquires_hand_out_each_lane_once(self):
        self.run_tool('create', '--count', '3')
        procs = [subprocess.Popen([sys.executable, '-B', TOOL, '--repo', self.repo,
                                   '--lanes-dir', self.lanes, 'acquire', '--holder-pid',
                                   str(os.getpid())], cwd=self.repo, env=base_env(),
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  universal_newlines=True) for _ in range(10)]
        results = [(p.wait(),) + p.communicate() for p in procs]
        codes = sorted(r[0] for r in results)
        paths = sorted(r[1].strip() for r in results if r[0] == 0)
        self.assertEqual(codes, [0, 0] + [3] * 8, [r[2] for r in results])
        self.assertEqual(paths, [os.path.join(self.lanes, 'lane-1'),
                                 os.path.join(self.lanes, 'lane-2')])

    def test_no_free_lane_message_leaves_held_lanes_alone(self):
        lane = self.acquire()
        self.acquire()
        write(os.path.join(lane, 'b.txt'), 'dirty\n')
        index = git(lane, 'rev-parse', '--path-format=absolute', '--git-path', 'index').stdout.strip()
        before = os.stat(index).st_mtime_ns
        self.acquire(expect=3)
        self.assertEqual(os.stat(index).st_mtime_ns, before)

    # N3: errors end in the tool's message.
    def test_missing_patch_file_is_a_clean_error(self):
        proc = self.run_tool('acquire', '--holder-pid', str(os.getpid()), '--apply-patch',
                             os.path.join(self.tmp, 'no-such.patch'), expect=1)
        self.assertNotIn('Traceback', proc.stderr)
        self.assertIn('no-such.patch', proc.stderr)
        self.assertEqual(self.lane_entry(1)['state'], 'missing')

    def fake_path(self, ps_script):
        bin_dir = os.path.join(self.tmp, 'bin')
        os.makedirs(bin_dir)
        os.symlink(shutil.which('git', path=base_env()['PATH']), os.path.join(bin_dir, 'git'))
        if ps_script is not None:
            write(os.path.join(bin_dir, 'ps'), ps_script)
            os.chmod(os.path.join(bin_dir, 'ps'), 0o755)
        return bin_dir

    def test_missing_ps_is_not_a_traceback(self):
        proc = self.run_tool('acquire', '--purpose', 'x', env={'PATH': self.fake_path(None)},
                             expect=None)
        self.assertNotIn('Traceback', proc.stderr)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_failing_ps_is_not_a_traceback(self):
        proc = self.run_tool('acquire', env={'PATH': self.fake_path('#!/bin/sh\nexit 1\n')},
                             expect=None)
        self.assertNotIn('Traceback', proc.stderr)
        self.assertEqual(proc.returncode, 0, proc.stderr)

    # N4: pid reuse.
    def test_live_pid_with_another_start_time_is_stale(self):
        self.acquire()
        holder = json.loads(read(self.holder_file(1)))
        self.assertTrue(holder['pid_start'])
        holder['pid_start'] = 'Mon Jan 1 00:00:00 2001'
        write(self.holder_file(1), json.dumps(holder))
        self.assertEqual(self.lane_entry(1)['state'], 'stale')

    # N5: shared refs changed while the lane was held.
    def test_stash_and_branch_changes_are_warned_about(self):
        git(self.repo, 'branch', 'existing')
        lane = self.acquire()
        write(os.path.join(lane, 'b.txt'), 'stashed\n')
        git(lane, 'stash', '-q')
        git(lane, 'branch', 'made-in-lane')
        git(lane, 'branch', '-f', 'existing', 'HEAD~1')
        write(os.path.join(lane, 'b.txt'), 'real work\n')
        for args in (('collect', '1'), ('release', '1')):
            proc = self.run_tool(*args)
            self.assertIn('changed while the lane was held', proc.stderr)
            self.assertIn('stash list grew from 0 to 1', proc.stderr)
            self.assertIn('made-in-lane', proc.stderr)
            self.assertIn('existing', proc.stderr)

    def test_no_ref_warning_when_nothing_changed(self):
        lane = self.acquire()
        write(os.path.join(lane, 'b.txt'), 'work\n')
        proc = self.run_tool('collect', '1')
        self.assertNotIn('changed while the lane was held', proc.stderr)

    # N6: destroy names the DerivedData folder.
    def test_destroy_names_the_derived_data_folder(self):
        import plistlib
        home = os.path.join(self.tmp, 'home')
        folder = os.path.join(home, 'Library', 'Developer', 'Xcode', 'DerivedData',
                              'iTerm2-abcdef')
        os.makedirs(folder)
        other = os.path.join(os.path.dirname(folder), 'iTerm2-other')
        os.makedirs(other)
        lane = self.acquire()
        with open(os.path.join(folder, 'info.plist'), 'wb') as f:
            plistlib.dump({'WorkspacePath': os.path.join(lane, 'iTerm2.xcodeproj')}, f)
        with open(os.path.join(other, 'info.plist'), 'wb') as f:
            plistlib.dump({'WorkspacePath': '/elsewhere/iTerm2.xcodeproj'}, f)
        proc = self.run_tool('destroy', '1', '--force', env={'HOME': home})
        self.assertIn(folder, proc.stderr)
        self.assertNotIn(other, proc.stderr)


class SubmodulesComeAndGoTests(LaneBase):
    """Upstream removes a submodule and adds another (2026-11-25: the nightly
    clone's lanes still held submodules/railroad_dsl, whose borrowed objects
    were gone, and `status` failed). The orchestrator's checkout loses the
    module's repository and configuration as nightly_clone.sh refresh now
    removes them."""

    def setUp(self):
        LaneBase.setUp(self)
        self.run_tool('create', '--count', '2')

    def remove_sub(self, drop_module=True):
        git(self.repo, 'rm', '-q', 'sub')
        git(self.repo, 'commit', '-q', '-m', 'remove sub')
        if drop_module:
            shutil.rmtree(os.path.join(self.repo, '.git', 'modules', 'sub'))
            git(self.repo, 'config', '--remove-section', 'submodule.sub')

    def add_sub2(self):
        up = os.path.join(self.tmp, 'sub2-up')
        git(self.tmp, 'init', '-q', '-b', 'main', up)
        write(os.path.join(up, 'two.c'), 'int two;\n')
        git(up, 'add', 'two.c')
        git(up, 'commit', '-q', '-m', 'sub2 1')
        git(self.repo, '-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', up, 'sub2')
        git(self.repo, 'commit', '-q', '-m', 'add sub2')

    def assert_clean_at_head(self, lane):
        self.assertEqual(self.head(lane), self.head(self.repo))
        self.assertFalse(os.path.lexists(os.path.join(lane, 'sub')))
        self.assertEqual(read(os.path.join(lane, 'sub2', 'two.c')), 'int two;\n')
        self.assertEqual(git(lane, 'status', '--porcelain', '--ignore-submodules=none').stdout, '')

    def test_status_acquire_release_survive_a_removed_and_an_added_submodule(self):
        self.remove_sub()
        self.add_sub2()
        proc = self.run_tool('status')
        self.assertIn('lane-1  free', proc.stdout)
        lane = self.acquire()
        self.assert_clean_at_head(lane)
        self.assertEqual(self.saved_files(), [])
        self.run_tool('release', '1')
        self.assertEqual(self.lane_entry(1)['dirty'], False)
        self.assertEqual(self.saved_files(), [])

    def test_release_of_a_lane_held_across_the_removal(self):
        self.acquire()
        self.remove_sub()
        self.add_sub2()
        self.assertEqual(self.lane_entry(1)['state'], 'held')
        self.run_tool('release', '1')
        self.assertEqual(self.saved_files(), [])
        lane = self.acquire()
        self.assert_clean_at_head(lane)

    def test_untracked_leftover_of_a_former_submodule_is_removed(self):
        # `git checkout` in a lane leaves the old submodule's directory
        # behind ("unable to rmdir ... Directory not empty").
        lane = os.path.join(self.lanes, 'lane-1')
        self.remove_sub()
        self.add_sub2()
        git(lane, '-c', 'submodule.recurse=false', 'checkout', '-q', '--detach', self.head(self.repo))
        self.assertTrue(os.path.isdir(os.path.join(lane, 'sub', '.git')))
        self.run_tool('status')
        # The lane's HEAD moved since its base, so that change is saved as
        # usual; the leftover is not, and does not stop the acquire.
        self.assertEqual(self.acquire(), lane)
        self.assert_clean_at_head(lane)

    def test_ignored_leftover_with_the_module_still_present_is_removed(self):
        # The orchestrator kept .git/modules/sub, and the new tip ignores the
        # path, so `git clean` without -x would leave it.
        lane = os.path.join(self.lanes, 'lane-1')
        git(self.repo, 'rm', '-q', 'sub')
        write(os.path.join(self.repo, '.gitignore'), 'Build/\ntmp/\nsub/\n')
        git(self.repo, 'add', '.gitignore')
        git(self.repo, 'commit', '-q', '-m', 'remove sub, ignore it')
        self.assertEqual(self.acquire(), lane)
        self.assertFalse(os.path.lexists(os.path.join(lane, 'sub')))
        self.assertEqual(self.saved_files(), [])

    def test_leftover_with_uncommitted_work_is_kept(self):
        lane = os.path.join(self.lanes, 'lane-1')
        write(os.path.join(lane, 'sub', 'lib.c'), 'precious, longer\n')
        self.remove_sub()
        self.assertTrue(self.lane_entry(1)['dirty'])
        proc = self.run_tool('acquire', '--holder-pid', str(os.getpid()), expect=1)
        self.assertNotIn('Traceback', proc.stderr)
        self.assertIn('not reset', proc.stderr)
        self.assertEqual(read(os.path.join(lane, 'sub', 'lib.c')), 'precious, longer\n')

    def test_untracked_nested_repository_that_was_never_a_submodule_is_kept(self):
        lane = os.path.join(self.lanes, 'lane-1')
        self.remove_sub()
        git(lane, 'init', '-q', os.path.join(lane, 'nested'))
        proc = self.run_tool('acquire', '--holder-pid', str(os.getpid()), expect=1)
        self.assertIn('not reset', proc.stderr)
        self.assertTrue(os.path.isdir(os.path.join(lane, 'nested', '.git')))


if __name__ == '__main__':
    unittest.main()
