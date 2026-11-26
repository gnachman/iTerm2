"""Tests for tools/swift_migration/nightly_clone.sh, the nightly session's clone.

Run from the repository root:
    python3 -B -m unittest discover -s tools/swift_migration/tests -p 'test_nightly_clone.py'

Every test builds its own throwaway "owner" checkout in a temporary
directory: a repository on master with one submodule whose own upstream is
a local bare repository. The submodule's URL in .gitmodules is then changed
to an https URL under .invalid, so a setup or refresh that went to the
network for it would fail instead of quietly working. Nothing here touches
this checkout, the network, or the owner's git configuration
(GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_NOSYSTEM=1).
"""

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
SCRIPT = os.path.join(TOOL_DIR, 'nightly_clone.sh')
LANE_TOOL = os.path.join(TOOL_DIR, 'lane_clone.py')

IDENTITY = {
    'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@example.invalid',
    'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@example.invalid',
}


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


def git(cwd, *args, check=True):
    # The test's own git commands never run a repository's hooks, so that a
    # canary hook can only be run by the tool under test.
    proc = subprocess.run(['git', '-c', 'core.hooksPath=/dev/null'] + list(args), cwd=cwd, env=base_env(),
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          universal_newlines=True)
    if check and proc.returncode != 0:
        raise AssertionError('git %s failed in %s: %s'
                             % (' '.join(args), cwd, proc.stderr))
    return proc


def make_writable(top):
    for root, dirs, files in os.walk(top):
        for name in dirs + files:
            path = os.path.join(root, name)
            if not os.path.islink(path):
                os.chmod(path, os.stat(path).st_mode | stat.S_IWUSR)
    if os.path.exists(top):
        os.chmod(top, os.stat(top).st_mode | stat.S_IWUSR)


def writable_entries(top):
    """Paths under top (and top itself) that anyone may write."""
    found = []
    mask = stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH
    for root, dirs, files in os.walk(top):
        for name in [''] + dirs + files:
            path = os.path.join(root, name) if name else root
            if not os.path.islink(path) and os.stat(path).st_mode & mask:
                found.append(path)
    return found


class CloneBase(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp(prefix='nightly_clone.'))
        # A cleanup, not tearDown, so that a setUp that fails (in a
        # subclass's setup_clone, say) leaves nothing behind.
        self.addCleanup(self.remove_tmp)
        self.sub_up = os.path.join(self.tmp, 'sub-up.git')
        self.owner = os.path.join(self.tmp, 'owner')
        self.clone = os.path.join(self.tmp, 'night')
        self.mirror = self.clone + '.origin.git'
        # The submodule's upstream.
        git(self.tmp, 'init', '-q', '--bare', '-b', 'main', self.sub_up)
        seed = os.path.join(self.tmp, 'sub-seed')
        git(self.tmp, 'init', '-q', '-b', 'main', seed)
        self.write(seed, 'lib.txt', 'one\n')
        git(seed, 'add', 'lib.txt')
        git(seed, 'commit', '-q', '-m', 'sub one')
        git(seed, 'push', '-q', self.sub_up, 'main')
        self.sub_seed = seed
        # The owner's checkout, with the submodule.
        git(self.tmp, 'init', '-q', '-b', 'master', self.owner)
        self.write(self.owner, 'a.txt', 'a\n')
        git(self.owner, 'add', 'a.txt')
        git(self.owner, 'commit', '-q', '-m', 'init')
        git(self.owner, '-c', 'protocol.file.allow=always', 'submodule', 'add',
            '-q', self.sub_up, 'submodules/sub')
        # From here on, fetching the submodule from its .gitmodules URL
        # would go to the network and fail.
        git(self.owner, 'config', '-f', '.gitmodules',
            'submodule.submodules/sub.url',
            'https://nightly-test.invalid/sub.git')
        git(self.owner, 'add', '.gitmodules')
        git(self.owner, 'commit', '-q', '-m', 'add sub')
        os.makedirs(os.path.join(self.owner, 'tmp', 'parked'))
        self.write(os.path.join(self.owner, 'tmp', 'parked'), 'u.patch', 'p\n')
        os.makedirs(os.path.join(self.owner, 'tmp', 'stored-state-corpus', 'v'))
        self.write(os.path.join(self.owner, 'tmp', 'stored-state-corpus', 'v'),
                   'f.plist', 'x\n')
        os.makedirs(os.path.join(self.owner, 'tmp', 'codedb'))
        self.write(os.path.join(self.owner, 'tmp', 'codedb'), 'big.sqlite', 'x')
        with open(os.path.join(self.owner, '.gitignore'), 'w') as fh:
            fh.write('tmp/\n')
        git(self.owner, 'add', '.gitignore')
        git(self.owner, 'commit', '-q', '-m', 'ignore tmp')
        # The project's upstream (GitHub in real life): a bare repository the
        # owner's checkout pushes to and tracks as origin. Its file:// URL
        # is fetched only through the test hook NIGHTLY_TEST_ALLOW_FILE_UPSTREAM.
        self.up = os.path.join(self.tmp, 'up.git')
        git(self.tmp, 'init', '-q', '--bare', '-b', 'master', self.up)
        git(self.owner, 'remote', 'add', 'origin', 'file://' + self.up)
        self.push_owner()

    def push_owner(self):
        """The owner pushes his master to the upstream."""
        git(self.owner, '-c', 'protocol.file.allow=always', 'push', '-q', 'origin',
            'master')
        git(self.owner, '-c', 'protocol.file.allow=always', 'fetch', '-q', 'origin')

    def upstream_commit(self, name, text=None):
        """A commit that reaches the upstream (the owner commits and pushes)."""
        sha = self.commit(self.owner, name, text)
        self.push_owner()
        return sha

    def owner_takes_the_night(self):
        """The owner's morning: fetch the clone's master, fast-forward, push."""
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'merge', '-q', '--ff-only', 'FETCH_HEAD')
        self.push_owner()

    def remove_tmp(self):
        make_writable(self.tmp)
        shutil.rmtree(self.tmp)

    def write(self, directory, name, text):
        with open(os.path.join(directory, name), 'w') as fh:
            fh.write(text)

    def run_tool(self, *args, **extra):
        env = base_env()
        # The owner's checkout, as the launchd agent's environment gives it;
        # an explicit --source wins.
        env['NIGHTLY_SOURCE'] = self.owner
        # The test upstream is a file:// URL; real upstreams must be https.
        env['NIGHTLY_TEST_ALLOW_FILE_UPSTREAM'] = '1'
        env.update(extra)
        for name in [k for k, v in env.items() if v is None]:
            del env[name]
        return subprocess.run(['/bin/bash', SCRIPT] + list(args), env=env,
                              cwd=self.tmp, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT,
                              universal_newlines=True, timeout=300)

    def setup_clone(self, *more):
        proc = self.run_tool('setup', '--source', self.owner, '--clone',
                             self.clone, *more)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        return proc

    def head(self, repo, ref='master'):
        return git(repo, 'rev-parse', ref).stdout.strip()

    def commit(self, repo, name, text=None):
        self.write(repo, name, text if text is not None else name + '\n')
        git(repo, 'add', name)
        git(repo, 'commit', '-q', '-m', 'add ' + name)
        return self.head(repo, 'HEAD')

    def refresh(self, **extra):
        return self.run_tool('refresh', '--clone', self.clone, **extra)

    def saved_refs(self, prefix):
        return git(self.clone, 'for-each-ref', '--format=%(objectname)',
                   prefix).stdout.split()

    def tree_digest(self, top):
        """A checksum of every file under top except .git, with its mode."""
        import hashlib
        digest = hashlib.sha256()
        for root, dirs, files in os.walk(top):
            dirs[:] = sorted(d for d in dirs if d != '.git')
            for name in sorted(files):
                path = os.path.join(root, name)
                digest.update(os.path.relpath(path, top).encode())
                digest.update(str(os.lstat(path).st_mode).encode())
                if not os.path.islink(path):
                    with open(path, 'rb') as fh:
                        digest.update(fh.read())
        return digest.hexdigest()


class SetupTest(CloneBase):
    def test_setup_makes_a_read_only_mirror_and_a_clone_of_it(self):
        proc = self.setup_clone()
        self.assertEqual(self.head(self.clone), self.head(self.owner))
        self.assertEqual(git(self.mirror, 'rev-parse', '--is-bare-repository')
                         .stdout.strip(), 'true')
        # The clone's only remote is the mirror, and its push URL is one
        # git cannot use.
        remotes = git(self.clone, 'remote').stdout.split()
        self.assertEqual(remotes, ['origin'])
        self.assertEqual(git(self.clone, 'config', 'remote.origin.url')
                         .stdout.strip(), self.mirror)
        pushurl = git(self.clone, 'config', 'remote.origin.pushurl').stdout
        self.assertIn('nightly-push-disabled', pushurl)
        self.assertEqual(writable_entries(self.mirror), [])
        # The configuration the nightly start reads, inside .git/.
        conf = os.path.join(self.clone, '.git', 'swift-migration-nightly.conf')
        self.assertEqual(git(self.tmp, 'config', '-f', conf, 'nightly.source')
                         .stdout.strip(), self.owner)
        self.assertEqual(git(self.tmp, 'config', '-f', conf, 'nightly.mirror')
                         .stdout.strip(), self.mirror)
        # The owner's checkout is not a remote of either repository.
        self.assertNotIn(self.owner,
                         git(self.mirror, 'config', '--list').stdout)
        # How to take the night's work in the morning.
        self.assertIn('git -C %s fetch %s master' % (self.owner, self.clone),
                      proc.stdout)
        self.assertIn('merge --ff-only FETCH_HEAD', proc.stdout)
        self.assertIn('trust', proc.stdout)

    def test_setup_names_the_upstream_and_the_mirror_follows_it(self):
        proc = self.setup_clone()
        self.assertIn('upstream: file://' + self.up, proc.stdout)
        self.assertEqual(self.head(self.mirror), self.head(self.up))

    def test_setup_starts_from_the_owners_master_and_warns_about_unpushed_commits(self):
        local = self.commit(self.owner, 'unpushed.txt')
        proc = self.setup_clone()
        self.assertEqual(self.head(self.clone), local)
        self.assertEqual(self.head(self.mirror), self.head(self.up))
        self.assertIn('1 commits ahead of', proc.stdout)
        self.assertIn('0 behind', proc.stdout)
        self.assertIn('push', proc.stdout)

    def test_ssh_upstream_urls_are_fetched_over_https(self):
        for url, https in (('git@github.com:someone/proj.git',
                            'https://github.com/someone/proj.git'),
                           ('ssh://git@github.com/someone/proj',
                            'https://github.com/someone/proj'),
                           ('https://github.com/someone/proj',
                            'https://github.com/someone/proj')):
            git(self.owner, 'remote', 'set-url', 'origin', url)
            proc = self.run_tool('setup', '--source', self.owner, '--dry-run')
            self.assertEqual(proc.returncode, 0, proc.stdout)
            self.assertIn('upstream: %s' % https, proc.stdout)

    def test_setup_refuses_an_upstream_that_cannot_be_fetched_over_https(self):
        for url in ('file://' + self.up, self.up, 'http://example.invalid/r.git'):
            git(self.owner, 'remote', 'set-url', 'origin', url)
            proc = self.run_tool('setup', '--source', self.owner, '--clone', self.clone,
                                 NIGHTLY_TEST_ALLOW_FILE_UPSTREAM=None)
            self.assertEqual(proc.returncode, 64, proc.stdout)
            self.assertIn('https', proc.stdout)
            self.assertFalse(os.path.exists(self.clone))
            self.assertFalse(os.path.exists(self.mirror))

    def test_object_stores_share_no_files_with_the_owner(self):
        self.setup_clone()

        def inodes(top):
            found = set()
            for root, _, files in os.walk(top):
                for name in files:
                    st = os.stat(os.path.join(root, name))
                    found.add((st.st_dev, st.st_ino))
            return found
        owner = inodes(os.path.join(self.owner, '.git'))
        self.assertFalse(owner & inodes(self.mirror))
        self.assertFalse(owner & inodes(os.path.join(self.clone, '.git')))

    def test_submodules_come_from_the_owners_module_repositories(self):
        self.setup_clone()
        sub = os.path.join(self.clone, 'submodules', 'sub')
        self.assertTrue(os.path.exists(os.path.join(sub, 'lib.txt')))
        self.assertEqual(self.head(sub, 'HEAD'),
                         self.head(os.path.join(self.owner, 'submodules',
                                                'sub'), 'HEAD'))
        url = git(sub, 'config', 'remote.origin.url').stdout.strip()
        self.assertEqual(url, 'file://' + os.path.join(
            self.owner, '.git', 'modules', 'submodules', 'sub'))
        self.assertIn('nightly-push-disabled',
                      git(sub, 'config', 'remote.origin.pushurl').stdout)
        self.assertEqual(git(self.clone, 'status', '--porcelain').stdout, '')

    def test_tmp_items_are_copied_but_not_the_code_database(self):
        self.setup_clone()
        self.assertTrue(os.path.exists(os.path.join(
            self.clone, 'tmp', 'parked', 'u.patch')))
        self.assertTrue(os.path.exists(os.path.join(
            self.clone, 'tmp', 'stored-state-corpus', 'v', 'f.plist')))
        self.assertFalse(os.path.exists(os.path.join(self.clone, 'tmp',
                                                     'codedb')))

    def test_no_copy_tmp(self):
        self.setup_clone('--no-copy-tmp')
        self.assertFalse(os.path.exists(os.path.join(self.clone, 'tmp',
                                                     'parked')))

    def test_setup_refuses_an_existing_clone_or_mirror(self):
        self.setup_clone()
        before = self.head(self.clone)
        proc = self.run_tool('setup', '--source', self.owner, '--clone',
                             self.clone)
        self.assertNotEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('exists', proc.stdout)
        self.assertEqual(self.head(self.clone), before)

    def test_default_clone_path_is_a_sibling_of_the_source(self):
        proc = self.run_tool('setup', '--source', self.owner, '--dry-run')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn(os.path.join(self.tmp, 'iterm2-migration-nightly'),
                      proc.stdout)
        self.assertFalse(os.path.exists(os.path.join(
            self.tmp, 'iterm2-migration-nightly')))

    def test_pushes_from_the_clone_fail_without_any_environment_guard(self):
        self.setup_clone()
        self.commit(self.clone, 'night.txt')
        before = git(self.mirror, 'for-each-ref').stdout
        for target in ('origin', self.mirror, 'file://' + self.mirror):
            proc = git(self.clone, 'push', target,
                       'HEAD:refs/heads/pushed-by-test', check=False)
            self.assertNotEqual(proc.returncode, 0, target)
        self.assertEqual(git(self.mirror, 'for-each-ref').stdout, before)
        owner_refs = git(self.owner, 'for-each-ref').stdout
        self.assertNotIn('pushed-by-test', owner_refs)


class RefreshTest(CloneBase):
    def setUp(self):
        super().setUp()
        self.setup_clone()

    def test_nothing_new(self):
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('up to date', proc.stdout)
        self.assertIn('nightly_clone: upstream: refreshed', proc.stdout)

    def test_upstream_ahead_fast_forwards(self):
        new = self.upstream_commit('b.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('fast-forward', proc.stdout)
        self.assertEqual(self.head(self.clone), new)
        self.assertEqual(self.head(self.mirror), new)
        self.assertEqual(writable_entries(self.mirror), [])
        self.assertEqual(git(self.clone, 'status', '--porcelain').stdout, '')

    def test_owner_commits_not_pushed_do_not_reach_the_clone(self):
        # The upstream is origin/master, not the owner's local master.
        self.commit(self.owner, 'local-only.txt')
        before = self.head(self.clone)
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.head(self.clone), before)

    def test_clone_ahead_continues_from_the_clone(self):
        night = self.commit(self.clone, 'night.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('ahead', proc.stdout)
        self.assertEqual(self.head(self.clone), night)

    def test_owner_took_the_night_and_moved_on(self):
        self.commit(self.clone, 'night.txt')
        self.owner_takes_the_night()
        new = self.upstream_commit('day.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.head(self.clone), new)

    def test_owner_cherry_picked_the_night_after_moving(self):
        night = self.commit(self.clone, 'night.txt')
        self.commit(self.owner, 'day.txt')
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'cherry-pick', 'master..FETCH_HEAD')
        self.push_owner()
        upstream = self.head(self.owner)
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.head(self.clone), upstream)
        self.assertIn('nightly_clone: already-upstream: reset to %s' % upstream, proc.stdout)
        # The old head is kept under a ref, in case.
        self.assertIn(night, self.saved_refs('refs/nightly-saved/'))

    def test_owner_squashed_the_night_and_pushed(self):
        # Three night commits, squashed and reworded by the owner, then a
        # commit of his own on top: patch equivalence does not see them.
        base = self.head(self.clone)
        self.commit(self.clone, 'n.txt', 'one\n')
        self.commit(self.clone, 'n.txt', 'one\ntwo\n')
        night = self.commit(self.clone, 'n.txt', 'one\ntwo\nthree\n')
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'merge', '-q', '--ff-only', 'FETCH_HEAD')
        git(self.owner, 'reset', '-q', '--soft', base)
        git(self.owner, 'commit', '-q', '-m', 'the night, squashed')
        upstream = self.upstream_commit('day.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('nightly_clone: already-upstream: reset to %s' % upstream, proc.stdout)
        self.assertEqual(self.head(self.clone), upstream)
        self.assertIn(night, self.saved_refs('refs/nightly-saved/'))

    def test_diverged_rebases_the_clone_commits_onto_the_upstream(self):
        env_author = dict(base_env(), GIT_AUTHOR_NAME='Night Author',
                          GIT_AUTHOR_EMAIL='night@example.invalid',
                          GIT_AUTHOR_DATE='1700000000 +0100')
        self.write(self.clone, 'night.txt', 'night\n')
        git(self.clone, 'add', 'night.txt')
        subprocess.run(['git', '-c', 'core.hooksPath=/dev/null', 'commit', '-q', '-m',
                        'night work\n\nwith a body'], cwd=self.clone, env=env_author,
                       check=True)
        night = self.head(self.clone)
        upstream = self.upstream_commit('day.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('nightly_clone: rebased: 1 commits onto %s' % upstream, proc.stdout)
        self.assertIn('nightly_clone: upstream-commits: taken', proc.stdout)
        head = self.head(self.clone)
        self.assertEqual(git(self.clone, 'rev-parse', 'HEAD^').stdout.strip(), upstream)
        fmt = git(self.clone, 'log', '-1', '--format=%an|%ae|%ad|%B', '--date=raw',
                  head).stdout
        self.assertEqual(fmt.strip(), 'Night Author|night@example.invalid|1700000000 +0100|'
                         'night work\n\nwith a body')
        self.assertEqual(git(self.clone, 'rev-list', '--merges', 'HEAD').stdout, '')
        self.assertIn(night, self.saved_refs('refs/nightly/pre-rebase/'))
        self.assertEqual(git(self.clone, 'status', '--porcelain').stdout, '')
        # The owner's morning command fast-forwards to it.
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'merge', '-q', '--ff-only', 'FETCH_HEAD')
        self.assertEqual(self.head(self.owner), head)

    def test_rebase_drops_commits_already_upstream_and_commits_that_become_empty(self):
        self.commit(self.clone, 'kept.txt')
        taken = self.commit(self.clone, 'taken.txt')
        self.commit(self.clone, 'same.txt', 'same\n')
        # The owner cherry-picks one night commit (an equivalent patch) and
        # makes the change of another as part of a larger commit of his own.
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'cherry-pick', taken)
        self.write(self.owner, 'same.txt', 'same\n')
        self.write(self.owner, 'other.txt', 'other\n')
        git(self.owner, 'add', 'same.txt', 'other.txt')
        git(self.owner, 'commit', '-q', '-m', 'mine')
        upstream = self.upstream_commit('day.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('nightly_clone: rebased: 1 commits onto %s' % upstream, proc.stdout)
        self.assertEqual(git(self.clone, 'log', '--format=%s', upstream + '..HEAD').stdout,
                         'add kept.txt\n')

    def test_rebase_conflict_leaves_the_clone_exactly_as_it_was(self):
        night = self.commit(self.clone, 'a.txt', 'night version\n')
        self.commit(self.clone, 'night2.txt')
        self.upstream_commit('a.txt', 'day version\n')
        before = (self.head(self.clone),
                  git(self.clone, 'status', '--porcelain', '--ignored').stdout,
                  self.tree_digest(self.clone),
                  git(self.clone, 'for-each-ref', 'refs/heads').stdout)
        proc = self.refresh()
        self.assertEqual(proc.returncode, 9, proc.stdout)
        self.assertIn('nightly_clone: rebase-failed:', proc.stdout)
        self.assertIn(night[:12], proc.stdout)
        self.assertIn('a.txt', proc.stdout)
        self.assertIn('rebase', proc.stdout)
        after = (self.head(self.clone),
                 git(self.clone, 'status', '--porcelain', '--ignored').stdout,
                 self.tree_digest(self.clone),
                 git(self.clone, 'for-each-ref', 'refs/heads').stdout)
        self.assertEqual(before, after)
        self.assertIn(before[0], self.saved_refs('refs/nightly/pre-rebase/'))
        self.assertEqual(writable_entries(self.mirror), [])

    def test_rebase_of_a_submodule_pointer_change_is_refused(self):
        sub = os.path.join(self.clone, 'submodules', 'sub')
        git(sub, 'commit', '-q', '--allow-empty', '-m', 'local')
        git(self.clone, 'add', 'submodules/sub')
        git(self.clone, 'commit', '-q', '-m', 'move the submodule')
        before = self.head(self.clone)
        self.upstream_commit('day.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 9, proc.stdout)
        self.assertIn('rebase-failed', proc.stdout)
        self.assertIn('submodule', proc.stdout)
        self.assertEqual(self.head(self.clone), before)

    def test_rebase_of_a_merge_commit_is_refused(self):
        base = self.head(self.clone)
        git(self.clone, 'checkout', '-q', '-b', 'side')
        self.commit(self.clone, 'side.txt')
        git(self.clone, 'checkout', '-q', 'master')
        self.commit(self.clone, 'main.txt')
        git(self.clone, 'merge', '-q', '--no-ff', '-m', 'merge', 'side')
        git(self.clone, 'branch', '-q', '-D', 'side')
        before = self.head(self.clone)
        self.upstream_commit('day.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 9, proc.stdout)
        self.assertIn('merge commit', proc.stdout)
        self.assertEqual(self.head(self.clone), before)
        self.assertNotEqual(base, before)

    def test_rebase_conflict_then_reset_sets_the_night_aside(self):
        night = self.commit(self.clone, 'a.txt', 'night version\n')
        self.upstream_commit('a.txt', 'day version\n')
        self.assertEqual(self.refresh().returncode, 9)
        proc = self.run_tool('reset', '--clone', self.clone)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.head(self.clone), self.head(self.up))
        self.assertIn(night, self.saved_refs('refs/nightly-saved/'))

    def test_refresh_says_whether_upstream_commits_came_in(self):
        proc = self.refresh()
        self.assertIn('nightly_clone: upstream-commits: none', proc.stdout)
        before = self.head(self.clone)
        new = self.upstream_commit('b.txt')
        proc = self.refresh()
        self.assertIn('nightly_clone: upstream-commits: taken %s..%s (1 commits)'
                      % (before, new), proc.stdout)
        # The reset when the night is already upstream brings them too.
        self.commit(self.clone, 'night.txt')
        self.commit(self.owner, 'day.txt')
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'cherry-pick', 'master..FETCH_HEAD')
        self.push_owner()
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('nightly_clone: upstream-commits: taken %s..%s (2 commits)'
                      % (new, self.head(self.owner)), proc.stdout)

    def test_unreachable_upstream_is_loud_and_the_night_goes_on(self):
        night = self.commit(self.clone, 'night.txt')
        os.rename(self.up, self.up + '.gone')
        try:
            proc = self.refresh()
        finally:
            os.rename(self.up + '.gone', self.up)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('nightly_clone: upstream: NOT REFRESHED', proc.stdout)
        self.assertEqual(self.head(self.clone), night)
        self.assertEqual(writable_entries(self.mirror), [])

    def test_upstream_that_is_not_a_fast_forward_is_refused(self):
        # Someone force-pushed: the upstream's master no longer contains the
        # mirror's.
        old = self.head(self.mirror)
        rewritten = git(self.owner, 'commit-tree', '-m', 'rewritten',
                        self.head(self.owner) + '^{tree}').stdout.strip()
        git(self.owner, '-c', 'protocol.file.allow=always', 'push', '-q', '-f', 'origin',
            rewritten + ':refs/heads/master')
        before = self.head(self.clone)
        proc = self.refresh()
        self.assertEqual(proc.returncode, 9, proc.stdout)
        self.assertIn('force-pushed', proc.stdout)
        self.assertEqual(self.head(self.mirror), old)
        self.assertEqual(self.head(self.clone), before)
        self.assertEqual(writable_entries(self.mirror), [])

    def test_upstream_fetch_allows_https_only(self):
        # Without the test hook the file:// upstream is not fetched at all:
        # the guarded fetch allows the https transport only.
        new = self.upstream_commit('b.txt')
        proc = self.refresh(NIGHTLY_TEST_ALLOW_FILE_UPSTREAM=None)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('nightly_clone: upstream: NOT REFRESHED', proc.stdout)
        self.assertNotEqual(self.head(self.mirror), new)
        self.assertNotEqual(self.head(self.clone), new)

    def test_dirty_submodule_is_refused(self):
        self.write(os.path.join(self.clone, 'submodules', 'sub'), 'lib.txt',
                   'changed\n')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 8, proc.stdout)
        self.assertIn('submodules/sub', proc.stdout)

    def test_selftest_finds_non_local_transports_refused(self):
        proc = self.run_tool('selftest')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('refused', proc.stdout)

    def test_dirty_clone_is_refused(self):
        self.upstream_commit('b.txt')
        self.write(self.clone, 'a.txt', 'changed\n')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 8, proc.stdout)
        self.assertEqual(writable_entries(self.mirror), [])

    def test_mirror_made_writable_by_someone_is_read_only_again(self):
        make_writable(self.mirror)
        self.assertEqual(self.refresh().returncode, 0)
        self.assertEqual(writable_entries(self.mirror), [])

    def test_submodule_pointer_change_is_checked_out(self):
        self.commit(self.sub_seed, 'two.txt')
        git(self.sub_seed, 'push', '-q', self.sub_up, 'main')
        owner_sub = os.path.join(self.owner, 'submodules', 'sub')
        git(owner_sub, 'fetch', '-q', 'origin')
        git(owner_sub, 'checkout', '-q', 'origin/main')
        git(self.owner, 'add', 'submodules/sub')
        git(self.owner, 'commit', '-q', '-m', 'bump sub')
        self.push_owner()
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertTrue(os.path.exists(os.path.join(
            self.clone, 'submodules', 'sub', 'two.txt')))
        self.assertEqual(git(self.clone, 'status', '--porcelain').stdout, '')

    def colleague_bumps_the_submodule(self, url):
        """Someone else pushes a commit that moves the submodule to a commit
        the owner's submodule repository does not have, with .gitmodules
        naming url."""
        sha = self.commit(self.sub_seed, 'three.txt')
        git(self.sub_seed, 'push', '-q', self.sub_up, 'main')
        colleague = os.path.join(self.tmp, 'colleague')
        git(self.tmp, '-c', 'protocol.file.allow=always', 'clone', '-q', 'file://' + self.up,
            colleague)
        git(colleague, 'config', '-f', '.gitmodules', 'submodule.submodules/sub.url', url)
        git(colleague, 'update-index', '--cacheinfo', '160000,%s,submodules/sub' % sha)
        git(colleague, 'add', '.gitmodules')
        git(colleague, 'commit', '-q', '-m', 'bump sub elsewhere')
        git(colleague, '-c', 'protocol.file.allow=always', 'push', '-q', 'origin', 'master')
        return sha

    def test_missing_submodule_commit_is_fetched_from_the_upstream_url(self):
        sha = self.colleague_bumps_the_submodule('file://' + self.sub_up)
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        sub = os.path.join(self.clone, 'submodules', 'sub')
        self.assertEqual(self.head(sub, 'HEAD'), sha)
        self.assertTrue(os.path.exists(os.path.join(sub, 'three.txt')))

    def test_submodule_commit_that_cannot_be_fetched_is_left_loudly(self):
        sub = os.path.join(self.clone, 'submodules', 'sub')
        old = self.head(sub, 'HEAD')
        self.colleague_bumps_the_submodule('https://nightly-test.invalid/sub.git')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('nightly_clone: submodule-stale: submodules/sub', proc.stdout)
        self.assertEqual(self.head(sub, 'HEAD'), old)
        # The next refresh is not refused for it.
        self.assertEqual(self.refresh().returncode, 0)

    def test_status_is_read_only(self):
        new = self.upstream_commit('b.txt')
        before = git(self.mirror, 'for-each-ref').stdout
        clone_before = self.head(self.clone)
        proc = self.run_tool('status', '--clone', self.clone)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('refresh would fetch', proc.stdout)
        self.assertIn(new, proc.stdout)
        self.assertEqual(git(self.mirror, 'for-each-ref').stdout, before)
        self.assertEqual(self.head(self.clone), clone_before)

    def test_refresh_prints_the_morning_command(self):
        proc = self.refresh()
        self.assertIn('merge --ff-only FETCH_HEAD', proc.stdout)

    def test_missing_clone(self):
        proc = self.run_tool('refresh', '--clone',
                             os.path.join(self.tmp, 'nope'))
        self.assertEqual(proc.returncode, 8, proc.stdout)
        self.assertIn('setup', proc.stdout)

    def test_bad_option(self):
        self.assertEqual(self.run_tool('bogus').returncode, 64)

    def test_change_taken_and_reverted_resets_to_the_upstream(self):
        # The owner took the night's commit and then reverted it upstream:
        # the night's change is already decided upstream, so the clone
        # follows the upstream and keeps its old tip under a ref.
        night = self.commit(self.clone, 'night.txt')
        self.commit(self.owner, 'day.txt')
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'cherry-pick', 'FETCH_HEAD')
        git(self.owner, 'revert', '--no-edit', 'HEAD')
        self.push_owner()
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.head(self.clone), self.head(self.up))
        self.assertIn('already-upstream', proc.stdout)
        saved = self.saved_refs('refs/nightly-saved/') + self.saved_refs('refs/nightly/')
        self.assertIn(night, saved)

    def night_of_two_document_commits(self):
        """Two night commits editing the same lines of a document."""
        self.commit(self.clone, 'queue.md', 'one\n')
        return self.commit(self.clone, 'queue.md', 'one\ntwo\n')

    def assertTakenByOwner(self, proc, night, upstream):
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('nightly_clone: taken-by-owner: reset to %s' % upstream, proc.stdout)
        self.assertNotIn('rebase-failed', proc.stdout)
        self.assertEqual(self.head(self.clone), upstream)
        self.assertIn(night, self.saved_refs('refs/nightly-saved/'))
        self.assertEqual(git(self.clone, 'status', '--porcelain').stdout, '')

    def test_owner_took_squashed_and_edited_the_night_resets_to_the_upstream(self):
        # The real case: the orchestrator fetches the night into the owner's
        # master, squashes it with a later edit of the same lines, and that
        # is pushed. Replaying the night conflicts; the owner holds the work.
        base = self.head(self.clone)
        night = self.night_of_two_document_commits()
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'merge', '-q', '--ff-only', 'FETCH_HEAD')
        git(self.owner, 'reset', '-q', '--soft', base)
        self.write(self.owner, 'queue.md', 'one, edited by day\ntwo, edited by day\n')
        git(self.owner, 'add', 'queue.md')
        git(self.owner, 'commit', '-q', '-m', 'the night, squashed and edited')
        upstream = self.upstream_commit('day.txt')
        proc = self.refresh()
        self.assertTakenByOwner(proc, night, upstream)
        self.assertIn('nightly_clone: upstream-commits: taken', proc.stdout)

    def test_owner_took_the_night_without_pushing_is_kept(self):
        # Taken but not pushed: the next night builds on it, or it would
        # run without it and might port the same units again.
        night = self.night_of_two_document_commits()
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'merge', '-q', '--ff-only', 'FETCH_HEAD')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('continuing from %s' % night[:12], proc.stdout)
        self.assertNotIn('taken-by-owner', proc.stdout)
        self.assertEqual(self.head(self.clone), night)
        self.assertEqual(self.saved_refs('refs/nightly-saved/'), [])

    def another_checkout_pushes(self, name, text=None):
        """Upstream moves without the night: another checkout pushes."""
        other = os.path.join(self.tmp, 'other')
        git(self.tmp, '-c', 'protocol.file.allow=always', 'clone', '-q',
            'file://' + self.up, other)
        self.commit(other, name, text)
        git(other, '-c', 'protocol.file.allow=always', 'push', '-q', 'origin', 'master')
        return self.head(other)

    def test_taken_night_whose_rebase_applies_is_rebased(self):
        self.night_of_two_document_commits()
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'merge', '-q', '--ff-only', 'FETCH_HEAD')
        upstream = self.another_checkout_pushes('day.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertNotIn('taken-by-owner', proc.stdout)
        self.assertIn('nightly_clone: rebased: 2 commits onto %s' % upstream, proc.stdout)
        self.assertEqual(git(self.clone, 'show', 'HEAD:queue.md').stdout, 'one\ntwo\n')

    def test_night_not_in_the_owners_checkout_that_conflicts_is_refused(self):
        night = self.night_of_two_document_commits()
        self.upstream_commit('queue.md', 'day version\n')
        before = (self.head(self.clone), self.tree_digest(self.clone),
                  git(self.clone, 'for-each-ref', 'refs/heads', 'refs/nightly-saved').stdout)
        proc = self.refresh()
        self.assertEqual(proc.returncode, 9, proc.stdout)
        self.assertIn('nightly_clone: rebase-failed:', proc.stdout)
        self.assertNotIn('taken-by-owner', proc.stdout)
        self.assertEqual(before, (self.head(self.clone), self.tree_digest(self.clone),
                                  git(self.clone, 'for-each-ref', 'refs/heads',
                                      'refs/nightly-saved').stdout))
        self.assertEqual(before[0], night)

    def test_owner_took_only_the_first_commit_is_not_taken(self):
        first = self.commit(self.clone, 'n1.txt')
        night = self.commit(self.clone, 'n2.txt')
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'merge', '-q', '--ff-only', first)
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertNotIn('taken-by-owner', proc.stdout)
        self.assertEqual(self.head(self.clone), night)
        # And when the owner pushes the first with a commit of his own, the
        # second is rebased as before.
        upstream = self.upstream_commit('day.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertNotIn('taken-by-owner', proc.stdout)
        self.assertIn('nightly_clone: rebased: 1 commits onto %s' % upstream, proc.stdout)
        self.assertEqual(git(self.clone, 'log', '--format=%s', upstream + '..HEAD').stdout,
                         'add n2.txt\n')

    def test_night_objects_in_the_owners_checkout_without_a_ref_are_not_taken(self):
        night = self.night_of_two_document_commits()
        self.upstream_commit('queue.md', 'day version\n')
        # Fetched into a ref that was then deleted (its reflog goes with
        # it), and fetched once more into FETCH_HEAD only: the objects are
        # there, no ref or reflog reaches them.
        git(self.owner, 'fetch', '-q', self.clone, 'master:refs/scratch/night')
        git(self.owner, 'update-ref', '-d', 'refs/scratch/night')
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        self.assertEqual(git(self.owner, 'cat-file', '-t', night).stdout.strip(), 'commit')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 9, proc.stdout)
        self.assertNotIn('taken-by-owner', proc.stdout)
        self.assertIn('nightly_clone: rebase-failed:', proc.stdout)
        self.assertEqual(self.head(self.clone), night)

    def test_status_says_a_taken_night_would_be_reset(self):
        base = self.head(self.clone)
        night = self.night_of_two_document_commits()
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'merge', '-q', '--ff-only', 'FETCH_HEAD')
        proc = self.run_tool('status', '--clone', self.clone)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        # Ahead: kept, whether taken or not.
        self.assertIn('refresh would continue from the clone', proc.stdout)
        self.assertNotIn('taken-by-owner', proc.stdout)
        # Diverged: the reset is the fallback for a conflicting rebase. A
        # refresh while the owner does not hold the night brings the
        # conflicting upstream into the mirror (and refuses); then he takes
        # the night again and status is asked.
        self.another_checkout_pushes('queue.md', 'day version\n')
        git(self.owner, 'reset', '-q', '--hard', base)
        git(self.owner, 'reflog', 'expire', '--expire=now', '--all')
        self.assertEqual(self.refresh().returncode, 9)
        git(self.owner, 'merge', '-q', '--ff-only', night)
        proc = self.run_tool('status', '--clone', self.clone)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('if the rebase conflicts, refresh would reset the clone to '
                      'origin/master (taken-by-owner:', proc.stdout)

    def test_failing_git_command_is_an_error_not_already_upstream(self):
        night = self.commit(self.clone, 'night.txt')
        self.upstream_commit('day.txt')
        shim = os.path.join(self.tmp, 'shim')
        os.mkdir(shim)
        real = shutil.which('git', path=base_env()['PATH'])
        with open(os.path.join(shim, 'git'), 'w') as fh:
            fh.write('#!/bin/sh\nfor a in "$@"; do [ "$a" = merge-tree ] && exit 2; done\n'
                     'exec %s "$@"\n' % real)
        os.chmod(os.path.join(shim, 'git'), 0o755)
        proc = self.run_tool('refresh', '--clone', self.clone,
                             PATH=shim + ':' + base_env()['PATH'])
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertIn('merge-tree', proc.stdout)
        self.assertEqual(self.head(self.clone), night)


class UntrustedCloneTest(CloneBase):
    """Nothing read from inside the clone is trusted: the session can write
    all of it, and refresh runs as the owner outside the session's limits."""

    def setUp(self):
        super().setUp()
        self.setup_clone()
        self.marker = os.path.join(self.tmp, 'CANARY-RAN')
        self.decoy = os.path.join(self.tmp, 'decoy')
        os.mkdir(self.decoy)
        self.write(self.decoy, 'precious.txt', 'x\n')

    def conf(self):
        return os.path.join(self.clone, '.git', 'swift-migration-nightly.conf')

    def decoy_writable(self):
        return bool(os.stat(os.path.join(self.decoy, 'precious.txt')).st_mode
                    & stat.S_IWUSR)

    def assertRefused(self, *expected, command='refresh'):
        clone_head = self.head(self.clone)
        owner_refs = git(self.owner, 'for-each-ref').stdout
        proc = self.run_tool(command, '--source', self.owner,
                             '--clone', self.clone)
        self.assertEqual(proc.returncode, 10, proc.stdout)
        for text in expected:
            self.assertIn(text, proc.stdout)
        self.assertEqual(self.head(self.clone), clone_head)
        self.assertEqual(git(self.owner, 'for-each-ref').stdout, owner_refs)
        self.assertTrue(self.decoy_writable())
        self.assertFalse(os.path.exists(self.marker))
        return proc

    def canary(self):
        path = os.path.join(self.tmp, 'canary.sh')
        with open(path, 'w') as fh:
            fh.write('#!/bin/sh\necho "$0 $*" >> %s\nexit 0\n' % self.marker)
        os.chmod(path, 0o755)
        return path

    def test_mirror_path_in_the_configuration_is_not_trusted(self):
        # The configuration names a directory to chmod -R, and origin
        # matches it so that a comparison of the two would pass.
        git(self.decoy, 'init', '-q', '--bare', '.')
        git(self.tmp, 'config', '-f', self.conf(), 'nightly.mirror', self.decoy)
        git(self.clone, 'config', 'remote.origin.url', self.decoy)
        self.commit(self.owner, 'b.txt')
        self.assertRefused('disagrees')

    def test_source_in_the_configuration_must_be_the_given_source(self):
        other = os.path.join(self.tmp, 'other')
        git(self.tmp, 'init', '-q', '-b', 'master', other)
        self.commit(other, 'o.txt')
        proc = self.run_tool('refresh', '--source', other, '--clone', self.clone)
        self.assertEqual(proc.returncode, 10, proc.stdout)
        self.assertIn('nightly.source', proc.stdout)

    def test_branch_in_the_configuration_must_be_master(self):
        git(self.tmp, 'config', '-f', self.conf(), 'nightly.branch', 'topic')
        self.assertRefused('nightly.branch')

    def test_mirror_replaced_by_a_symlink_is_refused(self):
        make_writable(self.mirror)
        shutil.rmtree(self.mirror)
        os.symlink(self.decoy, self.mirror)
        self.assertRefused('symbolic link')
        os.remove(self.mirror)

    def test_mirror_without_the_setup_marker_is_refused(self):
        make_writable(self.mirror)
        os.remove(os.path.join(self.mirror, 'nightly-mirror'))
        self.assertRefused('marker')

    def test_mirror_holding_a_hard_link_is_refused(self):
        make_writable(self.mirror)
        os.link(os.path.join(self.decoy, 'precious.txt'),
                os.path.join(self.mirror, 'linked'))
        self.assertRefused('hard-linked')

    def test_read_only_hard_link_outside_objects_is_refused(self):
        # Only data files under objects/ may have a second name: a read-only
        # hard link anywhere else, or as objects/info/alternates (which tells
        # git where else to read objects), is still refused.
        precious = os.path.join(self.decoy, 'precious.txt')
        os.chmod(precious, 0o444)
        info = os.path.join(self.mirror, 'objects', 'info')
        os.makedirs(info, exist_ok=True)
        for where, name in ((self.mirror, 'linked'),
                            (os.path.join(self.mirror, 'refs'), 'linked'),
                            (info, 'alternates')):
            os.chmod(where, 0o755)
            os.link(precious, os.path.join(where, name))
            os.chmod(where, 0o555)
            proc = self.run_tool('check', '--source', self.owner, '--clone', self.clone)
            self.assertEqual(proc.returncode, 10, proc.stdout)
            self.assertIn('hard-linked', proc.stdout)
            os.chmod(where, 0o755)
            os.remove(os.path.join(where, name))
            os.chmod(where, 0o555)
        os.chmod(precious, 0o644)

    def test_origin_must_be_exactly_the_mirror(self):
        git(self.clone, 'config', 'remote.origin.url', self.owner)
        self.assertRefused('not the mirror')

    def test_commondir_pointing_at_the_owner_is_refused(self):
        # A commondir file would send the refresh's ref updates into the
        # owner's repository.
        self.write(os.path.join(self.clone, '.git'), 'commondir',
                   os.path.join(self.owner, '.git') + '\n')
        self.commit(self.owner, 'b.txt')
        self.assertRefused('commondir')
        self.assertRefused('commondir', command='status')

    def test_config_that_runs_programs_is_refused_and_never_run(self):
        canary = self.canary()
        git(self.clone, 'config', 'core.fsmonitor', canary)
        git(self.clone, 'config', 'alias.status', '!' + canary)
        self.commit(self.owner, 'b.txt')
        self.assertRefused('core.fsmonitor', command='status')
        self.assertRefused('core.fsmonitor')
        self.assertRefused('core.fsmonitor', command='reset')

    def test_submodule_config_that_runs_programs_is_refused(self):
        canary = self.canary()
        sub_config = os.path.join(self.clone, '.git', 'modules', 'submodules',
                                  'sub', 'config')
        git(self.tmp, 'config', '-f', sub_config, 'core.fsmonitor', canary)
        self.assertRefused('core.fsmonitor')

    def test_submodule_update_command_is_refused(self):
        canary = self.canary()
        git(self.clone, 'config', 'submodule.submodules/sub.update', '!' + canary)
        self.assertRefused('submodule.submodules/sub.update')

    def test_hooks_in_the_clone_and_its_submodules_never_run(self):
        canary = self.canary()
        hook_dirs = [os.path.join(self.clone, '.git', 'hooks'),
                     os.path.join(self.clone, '.git', 'modules', 'submodules',
                                  'sub', 'hooks')]
        for directory in hook_dirs:
            for name in ('post-merge', 'post-checkout', 'reference-transaction',
                         'post-index-change', 'pre-auto-gc', 'post-rewrite',
                         'fsmonitor-watchman', 'pre-commit'):
                shutil.copy(canary, os.path.join(directory, name))
        # The owner moves on, including the submodule, so that refresh
        # fast-forwards, writes refs and checks out a new submodule commit.
        self.commit(self.sub_seed, 'two.txt')
        git(self.sub_seed, 'push', '-q', self.sub_up, 'main')
        owner_sub = os.path.join(self.owner, 'submodules', 'sub')
        git(owner_sub, 'fetch', '-q', 'origin')
        git(owner_sub, 'checkout', '-q', 'origin/main')
        git(self.owner, 'add', 'submodules/sub')
        git(self.owner, 'commit', '-q', '-m', 'bump sub')
        self.push_owner()
        for command in ('status', 'check', 'refresh'):
            proc = self.run_tool(command, '--source', self.owner,
                                 '--clone', self.clone)
            self.assertEqual(proc.returncode, 0, command + '\n' + proc.stdout)
        self.assertEqual(self.head(self.clone), self.head(self.owner))
        self.assertTrue(os.path.exists(os.path.join(
            self.clone, 'submodules', 'sub', 'two.txt')))
        # Then the clone gets commits the owner cherry-picks, so that
        # refresh saves a ref and resets.
        self.commit(self.clone, 'night.txt')
        self.commit(self.owner, 'day.txt')
        git(self.owner, 'fetch', '-q', self.clone, 'master')
        git(self.owner, 'cherry-pick', 'master..FETCH_HEAD')
        self.push_owner()
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.head(self.clone), self.head(self.owner))
        # Then the clone and the upstream diverge, so that refresh rebases
        # (and then, on a conflict, refuses and restores).
        self.commit(self.clone, 'night2.txt')
        self.upstream_commit('day2.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('rebased: 1 commits', proc.stdout)
        self.commit(self.clone, 'a.txt', 'night\n')
        self.upstream_commit('a.txt', 'day\n')
        self.assertEqual(self.refresh().returncode, 9)
        self.assertFalse(os.path.exists(self.marker), self.read_marker())

    def read_marker(self):
        if not os.path.exists(self.marker):
            return ''
        with open(self.marker) as fh:
            return fh.read()

    def test_submodule_path_from_the_clone_is_checked(self):
        git(self.clone, 'config', '-f', '.gitmodules',
            'submodule.submodules/sub.path', '../escape')
        git(self.clone, 'commit', '-q', '-am', 'move the submodule outside')
        proc = self.refresh()
        # The layout check finds the submodule's .git file without a name.
        self.assertEqual(proc.returncode, 10, proc.stdout)
        self.assertIn('no plain name', proc.stdout)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'escape')))

    def module_dir(self):
        return os.path.join(self.clone, '.git', 'modules', 'submodules', 'sub')

    def test_redirected_submodule_gitfile_runs_no_filter(self):
        # From the second review: a submodule .git file pointing at a copy
        # of its git directory outside .git/modules, whose configuration
        # names a clean filter and whose info/attributes applies it.
        # git status descending into the submodule would run it.
        evil = os.path.join(self.clone, '.git', 'evil')
        shutil.copytree(self.module_dir(), evil)
        git(self.tmp, 'config', '-f', os.path.join(evil, 'config'),
            'core.worktree', '../../submodules/sub')
        git(self.tmp, 'config', '-f', os.path.join(evil, 'config'),
            'filter.evil.clean', "sh -c 'touch %s; cat'" % self.marker)
        self.write(os.path.join(evil, 'info'), 'attributes', '* filter=evil\n')
        sub = os.path.join(self.clone, 'submodules', 'sub')
        self.write(sub, '.git', 'gitdir: ../../.git/evil\n')
        os.utime(os.path.join(sub, 'lib.txt'), (1, 1))
        for command in ('check', 'status', 'refresh'):
            self.assertRefused('evil', command=command)

    def test_commondir_in_a_module_without_objects_is_refused(self):
        # From the second review: a module git directory with a commondir
        # and no objects/ used to skip every check.
        module = self.module_dir()
        owner_module = os.path.join(self.owner, '.git', 'modules',
                                    'submodules', 'sub')
        head = self.head(owner_module, 'HEAD')
        make_writable(module)
        shutil.rmtree(module)
        os.makedirs(os.path.join(module, 'refs'))
        self.write(module, 'commondir', owner_module + '\n')
        self.write(module, 'HEAD', head + '\n')
        before = open(os.path.join(owner_module, 'config')).read()
        self.assertRefused('commondir', command='check')
        self.assertRefused('commondir')
        self.assertEqual(open(os.path.join(owner_module, 'config')).read(),
                         before)

    def test_embedded_repository_at_a_submodule_path_is_refused(self):
        sub = os.path.join(self.clone, 'submodules', 'sub')
        os.remove(os.path.join(sub, '.git'))
        shutil.copytree(self.module_dir(), os.path.join(sub, '.git'))
        git(self.tmp, 'config', '-f', os.path.join(sub, '.git', 'config'),
            '--unset', 'core.worktree')
        self.assertRefused('embedded', command='check')

    def test_info_attributes_in_the_clone_is_refused(self):
        self.write(os.path.join(self.clone, '.git', 'info'), 'attributes',
                   '* filter=x\n')
        self.assertRefused('info/attributes', command='check')

    def test_check_passes_on_a_fresh_clone(self):
        proc = self.run_tool('check', '--source', self.owner,
                             '--clone', self.clone)
        self.assertEqual(proc.returncode, 0, proc.stdout)


class MirrorLocalCloneTest(CloneBase):
    """The session may clone by local path, and origin is the mirror's path,
    so a plain `git clone <mirror>` happens. git links the mirror's object
    and pack files into the copy instead of copying them: that must not
    stop the nights, and the refresh must not change the copy's files."""

    def setUp(self):
        super().setUp()
        self.setup_clone()
        self.copy = os.path.join(self.tmp, 'copy')
        git(self.tmp, 'clone', '-q', '--bare', self.mirror, self.copy)
        self.linked = []
        for root, dirs, files in os.walk(os.path.join(self.copy, 'objects')):
            for name in files:
                path = os.path.join(root, name)
                if os.lstat(path).st_nlink > 1:
                    self.linked.append(path)
        # The premise: git did link them.
        self.assertTrue(self.linked)

    def check(self):
        return self.run_tool('check', '--source', self.owner, '--clone', self.clone)

    def test_a_plain_path_clone_of_the_mirror_passes_the_check(self):
        proc = self.check()
        self.assertEqual(proc.returncode, 0, proc.stdout)

    def test_refresh_leaves_the_linked_files_untouched(self):
        before = {p: os.lstat(p) for p in self.linked}
        self.upstream_commit('b.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.head(self.mirror), self.head(self.owner))
        self.assertEqual(writable_entries(self.mirror), [])
        for path, old in before.items():
            new = os.lstat(path)
            self.assertEqual(new.st_mode, old.st_mode, path)
            # Not even a chmod there and back: the file's change time is
            # the same, so it was never writable through the mirror's name.
            self.assertEqual(new.st_ctime_ns, old.st_ctime_ns, path)
        self.assertEqual(self.check().returncode, 0)

    def test_a_writable_linked_file_is_refused_and_named(self):
        path = self.linked[0]
        os.chmod(path, 0o644)
        ino = os.lstat(path).st_ino
        proc = self.check()
        self.assertEqual(proc.returncode, 10, proc.stdout)
        self.assertIn('hard-linked', proc.stdout)
        self.assertIn(self.mirror + '/objects/', proc.stdout)
        self.assertIn('-inum %d' % ino, proc.stdout)


class LaneRegistrationTest(CloneBase):
    """lane_clone.py makes the nightly orchestrator's build lanes as git
    worktrees of the clone in <clone>.lanes/, which registers each one in
    the clone's .git/worktrees/<name>/ with a commondir and a gitdir file.
    check allows exactly that shape (and Claude Code's own agent worktrees
    under <clone>/.claude/worktrees/) and refuses every other redirect."""

    def setUp(self):
        super().setUp()
        self.setup_clone()
        self.lanes = self.clone + '.lanes'

    def lane_tool(self, *args):
        env = base_env()
        proc = subprocess.run([sys.executable, '-B', LANE_TOOL, '--repo', self.clone] + list(args),
                              env=env, cwd=self.tmp, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, universal_newlines=True,
                              timeout=300)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        return proc

    def registration(self, name, *parts):
        return os.path.join(self.clone, '.git', 'worktrees', name, *parts)

    def check(self, command='check'):
        return self.run_tool(command, '--source', self.owner, '--clone', self.clone)

    def assertRefused(self, *expected):
        for command in ('check', 'refresh'):
            proc = self.check(command)
            self.assertEqual(proc.returncode, 10, command + '\n' + proc.stdout)
            for text in expected:
                self.assertIn(text, proc.stdout)

    def test_lanes_of_the_clone_pass_check_and_refresh(self):
        self.lane_tool('create', '--count', '2')
        lane = self.lane_tool('acquire', '--purpose', 'test').stdout.strip()
        self.assertEqual(lane, os.path.join(self.lanes, 'lane-1'))
        with open(self.registration('lane-1', 'commondir')) as fh:
            self.assertEqual(fh.read().strip(), '../..')
        with open(self.registration('lane-1', 'gitdir')) as fh:
            self.assertEqual(fh.read().strip(), os.path.join(lane, '.git'))
        proc = self.check()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        # The registrations live in .git, and the lanes outside the clone,
        # so the clone stays clean and a refresh works with lanes held.
        self.assertEqual(git(self.clone, 'status', '--porcelain').stdout, '')
        new = self.upstream_commit('b.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.head(self.clone), new)
        self.assertEqual(self.check().returncode, 0)

    def test_claude_code_agent_worktrees_pass_check(self):
        # Claude Code keeps its agent worktrees in .claude/worktrees/ of the
        # clone; check never refused them and must not start now.
        path = os.path.join(self.clone, '.claude', 'worktrees', 'agent-1')
        git(self.clone, 'worktree', 'add', '-q', '-b', 'worktree-agent-1', path)
        proc = self.check()
        self.assertEqual(proc.returncode, 0, proc.stdout)

    def test_registration_with_another_commondir_is_refused(self):
        # A commondir sends ref updates into another repository, here the
        # owner's.
        self.lane_tool('create', '--count', '2')
        self.write(self.registration('lane-1'), 'commondir',
                   os.path.join(self.owner, '.git') + '\n')
        self.assertRefused('commondir')

    def test_registration_whose_gitdir_is_not_its_lane_is_refused(self):
        self.lane_tool('create', '--count', '2')
        for target in (os.path.join(self.owner, '.git'),
                       os.path.join(self.lanes, 'lane-2', '.git'),
                       os.path.join(self.tmp, 'elsewhere.lanes', 'lane-1', '.git')):
            self.write(self.registration('lane-1'), 'gitdir', target + '\n')
            self.assertRefused('gitdir')

    def test_registration_with_a_worktree_config_is_refused(self):
        self.lane_tool('create', '--count', '2')
        self.write(self.registration('lane-1'), 'config.worktree',
                   '[core]\n\tfsmonitor = /bin/true\n')
        self.assertRefused('config.worktree')

    def test_registration_that_is_not_a_directory_is_refused(self):
        os.makedirs(os.path.join(self.clone, '.git', 'worktrees'))
        self.write(os.path.join(self.clone, '.git', 'worktrees'), 'stray', 'x\n')
        self.assertRefused('stray')

    def test_destroyed_lane_leaves_nothing_check_minds(self):
        self.lane_tool('create', '--count', '2')
        self.lane_tool('destroy', '1')
        self.assertFalse(os.path.exists(self.registration('lane-1')))
        self.assertEqual(self.check().returncode, 0)


class ReviewFixesTest(CloneBase):
    """Fixes from the review of the GitHub upstream: the morning advice when
    the owner's master lacks upstream commits, reset after a force-push, the
    setup warning about rule files, and stale locks after a kill."""

    def setUp(self):
        super().setUp()
        self.other = None

    def other_checkout_pushes(self, name):
        """A commit pushed to the upstream from another checkout of the
        owner's (his other agents push to GitHub too)."""
        if self.other is None:
            self.other = os.path.join(self.tmp, 'other')
            git(self.tmp, '-c', 'protocol.file.allow=always', 'clone', '-q',
                'file://' + self.up, self.other)
        git(self.other, '-c', 'protocol.file.allow=always', 'pull', '-q', '--ff-only')
        sha = self.commit(self.other, name)
        git(self.other, '-c', 'protocol.file.allow=always', 'push', '-q', 'origin', 'master')
        return sha

    def morning_lines(self, output):
        """The printed morning commands: the fast-forward and the rebase."""
        ff = [l.strip() for l in output.splitlines()
              if 'merge --ff-only FETCH_HEAD' in l and l.strip().startswith('[')]
        rb = [l.strip() for l in output.splitlines()
              if 'rebase FETCH_HEAD' in l and l.strip().startswith('[')]
        self.assertEqual(len(ff), 1, output)
        self.assertEqual(len(rb), 1, output)
        return ff[0], rb[0]

    def run_line(self, line):
        return subprocess.run(['/bin/bash', '-c', line], env=base_env(), cwd=self.tmp,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              universal_newlines=True)

    def test_morning_commands_when_the_owner_has_not_pushed(self):
        # The reviewer's scenario: night commits n1, n2; another checkout
        # pushes o1, o2; the owner fast-forwards to the night but does not
        # push; he commits L; night n4; another checkout pushes o3; the
        # refresh rebases; the morning fast-forward refuses.
        ff, rebase = self.morning_lines(self.setup_clone().stdout)
        self.commit(self.clone, 'n1.txt')
        self.commit(self.clone, 'n2.txt')
        self.other_checkout_pushes('o1.txt')
        self.other_checkout_pushes('o2.txt')
        run = self.run_line(ff)
        self.assertEqual(run.returncode, 0, run.stdout)
        self.assertEqual(git(self.owner, 'log', '-1', '--format=%s').stdout, 'add n2.txt\n')
        self.commit(self.owner, 'L.txt')
        self.commit(self.clone, 'n4.txt')
        self.other_checkout_pushes('o3.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('rebased:', proc.stdout)
        ff, rebase = self.morning_lines(proc.stdout)
        run = self.run_line(ff)
        self.assertNotEqual(run.returncode, 0, run.stdout)
        run = self.run_line(rebase)
        self.assertEqual(run.returncode, 0, run.stdout)
        git(self.owner, '-c', 'protocol.file.allow=always', 'fetch', '-q', 'origin')
        cherry = git(self.owner, 'cherry', '-v', 'origin/master', 'master').stdout
        subjects = [line.split(' ', 2)[2] for line in cherry.splitlines()]
        self.assertTrue(all(line.startswith('+ ') for line in cherry.splitlines()), cherry)
        self.assertEqual(sorted(subjects),
                         ['add L.txt', 'add n1.txt', 'add n2.txt', 'add n4.txt'], cherry)
        self.assertEqual(git(self.owner, 'status', '--porcelain').stdout, '')

    def test_morning_text_names_the_rebase(self):
        proc = self.setup_clone()
        ff, rebase = self.morning_lines(proc.stdout)
        self.assertIn('git -C %s rebase FETCH_HEAD' % self.owner, rebase)
        self.assertNotIn('cherry-pick', proc.stdout)

    def force_push(self):
        rewritten = git(self.owner, 'commit-tree', '-m', 'rewritten',
                        self.head(self.owner) + '^{tree}').stdout.strip()
        git(self.owner, '-c', 'protocol.file.allow=always', 'push', '-q', '-f', 'origin',
            rewritten + ':refs/heads/master')
        return rewritten

    def test_reset_accepts_a_rewritten_upstream_only_when_asked(self):
        self.setup_clone()
        old = self.head(self.mirror)
        rewritten = self.force_push()
        proc = self.refresh()
        self.assertEqual(proc.returncode, 9, proc.stdout)
        self.assertIn('reset --accept-rewritten-upstream', proc.stdout)
        proc = self.run_tool('reset', '--clone', self.clone)
        self.assertEqual(proc.returncode, 9, proc.stdout)
        self.assertEqual(self.head(self.mirror), old)
        proc = self.run_tool('reset', '--accept-rewritten-upstream', '--clone', self.clone)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.head(self.mirror), rewritten)
        self.assertEqual(self.head(self.clone), rewritten)
        kept = git(self.mirror, 'for-each-ref', '--format=%(objectname)',
                   'refs/nightly/rewritten/').stdout.split()
        self.assertEqual(kept, [old])
        self.assertEqual(writable_entries(self.mirror), [])
        # The option is for reset only.
        proc = self.run_tool('refresh', '--accept-rewritten-upstream', '--clone', self.clone)
        self.assertEqual(proc.returncode, 64, proc.stdout)

    def test_setup_says_when_every_night_will_be_refused(self):
        self.write(self.owner, 'CLAUDE.md', 'a rule\n')
        git(self.owner, 'add', 'CLAUDE.md')
        git(self.owner, 'commit', '-q', '-m', 'a new rule')
        rule = self.head(self.owner)
        self.commit(self.owner, 'plain.txt')
        proc = self.setup_clone()
        self.assertIn('EVERY NIGHT WILL BE REFUSED', proc.stdout)
        self.assertIn(rule[:12], proc.stdout)
        self.assertIn('a new rule', proc.stdout)
        warning = [l for l in proc.stdout.splitlines() if rule[:12] in l]
        self.assertNotIn('plain.txt', ' '.join(warning))

    def test_setup_does_not_warn_about_refusal_for_other_unpushed_commits(self):
        self.commit(self.owner, 'plain.txt')
        proc = self.setup_clone()
        self.assertIn('WARNING', proc.stdout)
        self.assertNotIn('EVERY NIGHT WILL BE REFUSED', proc.stdout)

    def test_rule_pathspecs_are_one_definition(self):
        proc = self.run_tool('rule-pathspecs')
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(proc.stdout.split('\n')[:-1],
                         [':(glob)**/CLAUDE.md', ':(glob)**/CLAUDE.local.md', '.claude',
                          '.mcp.json'])

    def holder(self, path):
        """A process whose command line names path, as a git command working
        on that repository would."""
        proc = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(600)', path])
        self.addCleanup(lambda: (proc.kill(), proc.wait()))
        return proc

    def test_stale_index_lock_is_removed_at_the_start_of_a_refresh(self):
        self.setup_clone()
        lock = os.path.join(self.clone, '.git', 'index.lock')
        self.write(os.path.join(self.clone, '.git'), 'index.lock', '')
        new = self.upstream_commit('b.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('removed a stale lock %s' % lock, proc.stdout)
        self.assertFalse(os.path.exists(lock))
        self.assertEqual(self.head(self.clone), new)

    def test_lock_held_by_a_running_process_is_refused_and_kept(self):
        self.setup_clone()
        lock = os.path.join(self.clone, '.git', 'index.lock')
        self.write(os.path.join(self.clone, '.git'), 'index.lock', '')
        holder = self.holder(self.clone)
        proc = self.refresh()
        self.assertEqual(proc.returncode, 8, proc.stdout)
        self.assertIn(lock, proc.stdout)
        self.assertIn(str(holder.pid), proc.stdout)
        self.assertTrue(os.path.exists(lock))

    def test_stale_ref_lock_in_the_mirror_is_removed(self):
        self.setup_clone()
        lock = os.path.join(self.mirror, 'refs', 'heads', 'master.lock')
        make_writable(self.mirror)
        self.write(os.path.join(self.mirror, 'refs', 'heads'), 'master.lock', 'x\n')
        new = self.upstream_commit('b.txt')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('removed a stale lock %s' % lock, proc.stdout)
        self.assertFalse(os.path.exists(lock))
        self.assertEqual(self.head(self.clone), new)
        self.assertEqual(writable_entries(self.mirror), [])

    def test_clear_locks_command_reports_both_branches(self):
        self.setup_clone()
        lock = os.path.join(self.clone, '.git', 'index.lock')
        self.write(os.path.join(self.clone, '.git'), 'index.lock', '')
        holder = self.holder(self.clone + '/.git')
        proc = self.run_tool('clear-locks', '--clone', self.clone)
        self.assertEqual(proc.returncode, 8, proc.stdout)
        self.assertTrue(os.path.exists(lock))
        holder.kill()
        holder.wait()
        proc = self.run_tool('clear-locks', '--clone', self.clone)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertFalse(os.path.exists(lock))


class OwnerRefsTest(CloneBase):
    def test_owner_refs_lists_refs_config_and_hooks_of_every_repository(self):
        proc = self.run_tool('owner-refs', '--source', self.owner)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('. %s refs/heads/master' % self.head(self.owner),
                      proc.stdout)
        self.assertIn('. HEAD refs/heads/master', proc.stdout)
        self.assertIn('modules/submodules/sub ', proc.stdout)
        self.assertIn('. file config ', proc.stdout)
        before = proc.stdout
        hook = os.path.join(self.owner, '.git', 'hooks', 'pre-commit')
        self.write(os.path.join(self.owner, '.git', 'hooks'), 'pre-commit',
                   '#!/bin/sh\n')
        os.chmod(hook, 0o755)
        after = self.run_tool('owner-refs', '--source', self.owner).stdout
        self.assertNotEqual(before, after)
        self.assertIn('. hook hooks/pre-commit ', after)


class StaleModuleOwnerRefsTest(CloneBase):
    def test_owner_refs_survives_a_stale_module_directory(self):
        # From the third review: the owner's .git/modules keeps the git
        # directory of a removed submodule whose core.worktree is gone (the
        # real checkout has submodules/adblock-rust).
        gone = os.path.join(self.owner, '.git', 'modules', 'gone')
        os.makedirs(gone)
        git(gone, 'init', '-q', '--bare', '.')
        git(gone, 'config', 'core.bare', 'false')
        git(gone, 'config', 'core.worktree', '../../../gone')
        proc = self.run_tool('owner-refs', '--source', self.owner)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn('modules/gone HEAD', proc.stdout)


class RefreshRaceTest(CloneBase):
    def test_upstream_moving_during_the_refresh_is_consistent(self):
        # The upstream gets a commit right after the mirror's fetch: the
        # clone ends at what the mirror fetched (origin/master agrees with
        # the mirror), and the next refresh takes the new commit.
        self.setup_clone()
        shim = os.path.join(self.tmp, 'shim')
        os.mkdir(shim)
        real = shutil.which('git', path=base_env()['PATH'])
        moved = os.path.join(self.tmp, 'moved')
        with open(os.path.join(shim, 'git'), 'w') as fh:
            fh.write('#!/bin/sh\n%s "$@"; rc=$?\n'
                     'case "$*" in *origin.git*fetch*)\n'
                     '  if [ ! -e %s ]; then touch %s; %s -C %s -c core.hooksPath=/dev/null '
                     'commit -q --allow-empty -m moved && %s -C %s -c protocol.file.allow=always '
                     'push -q origin master; fi ;; esac\n'
                     'exit $rc\n' % (real, moved, moved, real, self.owner, real, self.owner))
        os.chmod(os.path.join(shim, 'git'), 0o755)
        proc = self.run_tool('refresh', '--clone', self.clone,
                             PATH=shim + ':' + base_env()['PATH'])
        self.assertTrue(os.path.exists(moved))
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.head(self.clone), self.head(self.mirror))
        self.assertEqual(self.head(self.clone), self.head(self.owner, 'HEAD~1'))
        proc = self.refresh()
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertEqual(self.head(self.clone), self.head(self.up))


class SetupGuardTest(CloneBase):
    def assertSetupRefused(self, clone):
        proc = self.run_tool('setup', '--source', self.owner, '--clone', clone)
        self.assertEqual(proc.returncode, 64, proc.stdout)
        self.assertFalse(os.path.exists(clone + '.origin.git'))
        self.assertEqual(git(self.owner, 'status', '--porcelain').stdout, '')
        return proc

    def test_setup_refuses_the_source_itself(self):
        before = git(self.owner, 'for-each-ref').stdout
        self.assertSetupRefused(self.owner)
        self.assertEqual(git(self.owner, 'for-each-ref').stdout, before)

    def test_setup_refuses_a_clone_inside_the_working_tree(self):
        os.makedirs(os.path.join(self.owner, 'tmp', 'deep'))
        clone = os.path.join(self.owner, 'tmp', 'deep', 'night')
        self.assertSetupRefused(clone)
        self.assertFalse(os.path.exists(clone))

    def test_setup_refuses_a_clone_inside_the_git_directory(self):
        clone = os.path.join(self.owner, '.git', 'night')
        self.assertSetupRefused(clone)
        self.assertFalse(os.path.exists(clone))

    def test_printed_commands_are_quoted_and_work_with_spaces(self):
        clone = os.path.join(self.tmp, 'night clone')
        proc = self.run_tool('setup', '--source', self.owner, '--clone', clone)
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertIn("cd '%s' && claude" % clone, proc.stdout)
        line = [l for l in proc.stdout.splitlines() if 'merge --ff-only' in l][0]
        self.assertIn("'%s'" % clone, line)
        night = self.commit(clone, 'night.txt')
        run = subprocess.run(['/bin/bash', '-c', line.strip()], env=base_env(),
                             cwd=self.tmp, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, universal_newlines=True)
        self.assertEqual(run.returncode, 0, run.stdout)
        self.assertEqual(self.head(self.owner), night)

    def test_morning_command_does_nothing_unless_master_is_checked_out(self):
        proc = self.setup_clone()
        line = [l for l in proc.stdout.splitlines() if 'merge --ff-only' in l][0]
        self.commit(self.clone, 'night.txt')
        git(self.owner, 'checkout', '-q', '-b', 'topic')
        topic = self.head(self.owner, 'topic')
        master = self.head(self.owner, 'master')
        run = subprocess.run(['/bin/bash', '-c', line.strip()], env=base_env(),
                             cwd=self.tmp, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, universal_newlines=True)
        self.assertNotEqual(run.returncode, 0, run.stdout)
        self.assertEqual(self.head(self.owner, 'topic'), topic)
        self.assertEqual(self.head(self.owner, 'master'), master)


class SubmoduleRemovedUpstreamTest(CloneBase):
    """Upstream removes a submodule (2026-11-25: submodules/railroad_dsl).
    refresh removes its working directory, its .git/modules/<name> and its
    configuration in the clone, whether the leftover appeared before the
    move or appears with it, and initializes a submodule added at the same
    time; the lanes made from the clone keep working."""

    def setUp(self):
        super().setUp()
        self.setup_clone()
        self.lanes = self.clone + '.lanes'
        self.leftover = os.path.join(self.clone, 'submodules', 'sub')
        self.module = os.path.join(self.clone, '.git', 'modules', 'submodules', 'sub')

    def lane_tool(self, *args):
        proc = subprocess.run([sys.executable, '-B', LANE_TOOL, '--repo', self.clone] + list(args),
                              env=base_env(), cwd=self.tmp, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, universal_newlines=True, timeout=300)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        return proc

    def remove_sub_upstream(self):
        git(self.owner, 'rm', '-q', 'submodules/sub')
        git(self.owner, 'commit', '-q', '-m', 'remove sub')
        self.push_owner()

    def add_sub2_upstream(self):
        up = os.path.join(self.tmp, 'sub2-up.git')
        git(self.tmp, 'init', '-q', '--bare', '-b', 'main', up)
        seed = os.path.join(self.tmp, 'sub2-seed')
        git(self.tmp, 'init', '-q', '-b', 'main', seed)
        self.write(seed, 'two.txt', 'two\n')
        git(seed, 'add', 'two.txt')
        git(seed, 'commit', '-q', '-m', 'sub2 one')
        git(seed, 'push', '-q', up, 'main')
        git(self.owner, '-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', up, 'submodules/sub2')
        git(self.owner, 'config', '-f', '.gitmodules', 'submodule.submodules/sub2.url',
            'https://nightly-test.invalid/sub2.git')
        git(self.owner, 'add', '.gitmodules')
        git(self.owner, 'commit', '-q', '-m', 'add sub2')
        self.push_owner()

    def move_clone_by_hand(self):
        """What an older refresh did: the clone's master moved past the
        removal, and git left the submodule's directory behind."""
        git(self.clone, '-c', 'protocol.file.allow=always', 'fetch', '-q', 'file://' + self.up, 'master')
        git(self.clone, '-c', 'submodule.recurse=false', 'merge', '-q', '--ff-only', 'FETCH_HEAD')
        self.assertTrue(os.path.isfile(os.path.join(self.leftover, '.git')))
        self.assertIn('?? submodules/', git(self.clone, 'status', '--porcelain').stdout)

    def assert_gone(self, proc):
        self.assertEqual(proc.returncode, 0, proc.stdout)
        self.assertFalse(os.path.lexists(self.leftover), proc.stdout)
        self.assertFalse(os.path.lexists(self.module), proc.stdout)
        config = git(self.clone, 'config', '--list', '--name-only').stdout
        self.assertNotIn('submodule.submodules/sub.', config)
        self.assertEqual(git(self.clone, 'status', '--porcelain').stdout, '')
        self.assertIn('submodule-removed: submodules/sub', proc.stdout)
        self.assertEqual(self.run_tool('check', '--source', self.owner, '--clone', self.clone).returncode, 0)

    def test_removal_and_addition_with_lanes(self):
        self.lane_tool('create', '--count', '2')
        self.lane_tool('release', '1')
        self.remove_sub_upstream()
        self.add_sub2_upstream()
        self.assert_gone(self.refresh())
        self.assertTrue(os.path.exists(os.path.join(self.clone, 'submodules', 'sub2', 'two.txt')))
        self.assertEqual(self.refresh().returncode, 0)
        self.lane_tool('status')
        lane = self.lane_tool('acquire', '--purpose', 'test').stdout.strip()
        self.assertFalse(os.path.lexists(os.path.join(lane, 'submodules', 'sub')))
        self.assertTrue(os.path.exists(os.path.join(lane, 'submodules', 'sub2', 'two.txt')))
        self.assertEqual(git(lane, 'status', '--porcelain', '--ignore-submodules=none').stdout, '')
        self.lane_tool('release', '1')
        self.lane_tool('status')

    def test_leftover_from_before_the_move_is_removed(self):
        self.remove_sub_upstream()
        self.move_clone_by_hand()
        self.assert_gone(self.refresh())

    def test_module_whose_working_directory_was_removed_by_hand(self):
        self.remove_sub_upstream()
        self.move_clone_by_hand()
        shutil.rmtree(self.leftover)
        self.assert_gone(self.refresh())

    def test_leftover_holding_work_is_refused(self):
        self.remove_sub_upstream()
        self.move_clone_by_hand()
        self.write(self.leftover, 'lib.txt', 'precious\n')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 8, proc.stdout)
        with open(os.path.join(self.leftover, 'lib.txt')) as fh:
            self.assertEqual(fh.read(), 'precious\n')

    def test_local_commit_in_the_removed_submodule_is_refused(self):
        sub = os.path.join(self.clone, 'submodules', 'sub')
        self.commit(sub, 'local.txt')
        git(self.clone, 'add', 'submodules/sub')
        git(self.clone, 'commit', '-q', '-m', 'night moves sub')
        git(self.clone, 'reset', '-q', '--hard', 'HEAD~1')
        git(sub, 'checkout', '-q', '--detach', 'HEAD~1')
        git(sub, 'branch', 'keep', 'HEAD@{1}')
        self.remove_sub_upstream()
        proc = self.refresh()
        self.assertEqual(proc.returncode, 7, proc.stdout)
        self.assertIn('local commit', proc.stdout)
        self.assertTrue(os.path.isdir(self.module))

    def test_untracked_directory_that_is_not_a_former_submodule_is_refused(self):
        self.remove_sub_upstream()
        os.makedirs(os.path.join(self.clone, 'stray'))
        self.write(os.path.join(self.clone, 'stray'), 'f.txt', 'x\n')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 8, proc.stdout)
        self.assertIn('stray', proc.stdout)

    def test_module_not_explained_by_a_removed_submodule_is_refused(self):
        bogus = os.path.join(self.clone, '.git', 'modules', 'bogus')
        git(self.tmp, 'init', '-q', '--bare', bogus)
        git(bogus, 'config', 'core.bare', 'false')
        git(bogus, 'config', 'core.worktree', '../../../bogus')
        proc = self.refresh()
        self.assertEqual(proc.returncode, 10, proc.stdout)
        self.assertIn('core.worktree', proc.stdout)


if __name__ == '__main__':
    unittest.main()
