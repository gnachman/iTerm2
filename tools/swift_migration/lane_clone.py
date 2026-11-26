#!/usr/bin/env python3
"""Build lanes: separate checkouts in which author and reviewer agents build
and test, so that agents neither wait on one shared Build/ nor overwrite each
other's working tree.

Part of the Objective-C to Swift migration tooling. See
docs/swift-migration/decisions.md, 2026-11-20 ("Agents that change code or
run builds each work in their own clone").

Who runs it. The orchestrator, from its own checkout (the owner's checkout in
the day, the nightly clone at night). Agents do not run it: they are handed
a lane path and work there. Running it from inside a lane is refused.

Layout. LANES defaults to <repository>.lanes, beside the repository (for the
nightly clone, <clone>.lanes, which nightly_start.sh creates and lets the
session edit with claude --add-dir; nightly_clone.sh check allows the
lanes' registrations in the clone's .git/worktrees/):
  LANES/lanes.json       the repository the lanes belong to and the number
                         of lanes (default 3). A lanes directory made for one
                         repository is refused for another.
  LANES/lane-N           lane N: a `git worktree add --detach` of the
                         repository, so it shares the repository's objects
                         and sees its commits with no fetch. Its own Build/
                         and tmp/ (tools/build.sh and run_tests.expect write
                         under the checkout they run in).
  LANES/locks/lane-N/    present while lane N is held; holder.json inside
                         records the holder's pid, its start time, the
                         purpose, the base commit and when.
  LANES/state/lane-N.json the commit lane N was last reset to (its base),
                         and at acquire the stash count and the branch tips,
                         to warn when they change while the lane is held.
  LANES/saved/           patches of work that would otherwise be lost, made
                         when a dirty lane is released, destroyed or
                         re-acquired: one patch of the lane itself (tracked
                         changes, new files whether added or not, commits
                         since the base; ignored files are not saved), and
                         one more for each submodule with changes of its own
                         (edits, untracked files, commits), named
                         ...-submodule-<path>.patch. Each is announced with
                         its path. If something cannot be saved (git add -A
                         fails, for example on a nested repository with no
                         commit), the lane is left untouched instead of
                         being reset.
The highest-numbered lane is reserved for full-suite runs and is handed out
only to `acquire --full-suite` (when there are two lanes or more).

Submodules. Each submodule the repository has initialized is made in the
lane as a repository of its own (an embedded .git directory) that borrows
the repository's submodule objects through objects/info/alternates, then is
checked out at the commit the lane's tree records. No transport is used, so
this works offline. The repository's submodule working trees, its submodule
repositories and its configuration are only read. A submodule added upstream
is made the same way once the repository has initialized it.

Submodules also go away. When a lane is acquired, reset or released, what
is left of a removed submodule is cleared from the lane if it holds no work
(an embedded .git directory with no objects of its own, no changed tracked
file, no untracked file that is not ignored): a submodule the lane's commit
still records whose borrowed objects are gone (the repository deleted its
copy) is emptied, as an uninitialized submodule is, and a nested repository
the lane's commit records neither as a gitlink nor in .gitmodules, that was
a gitlink in an earlier commit or is named by the repository's submodule
configuration or modules/ directory, is removed. One holding work is left
for the usual saving, which saves it or refuses and leaves the lane as it
was. status only reads: it judges such a submodule without asking git to
look inside it, and lists it as stale.

Commands:
  create [N...] [--count C]  make lanes (default: every lane not yet made)
  acquire [--purpose TEXT] [--full-suite] [--holder-pid PID]
          [--apply-staged PATHSPEC...] [--apply-patch FILE]
                             claim a free lane, reset it to the repository's
                             HEAD (keeping ignored build products), optionally
                             apply the repository's staged changes for
                             PATHSPEC or a patch file, and print its path
  release N | --stale        free lane N (or every lane whose holder is dead),
                             saving uncollected work under saved/ as
                             described above and cleaning the lane
  status [--json]            every lane: state, holder, age, commit, clean,
                             dirty, or dirty (submodule <path>). Inspects
                             lanes without taking their index lock
  collect N [--to-index] [--allow-project]
                             print the lane's change since its base as a
                             binary patch, or apply it to the repository's
                             index and working tree with a three-way merge,
                             refusing anything that does not apply cleanly,
                             any submodule change, and (unless
                             --allow-project) any *.xcodeproj/project.pbxproj
  destroy N [--force]        remove lane N and its worktree registration,
                             saving uncollected work first; prints the lane's
                             Xcode DerivedData folder, which is left for
                             removal by hand

collect and release warn when the shared stash list grew, or a branch was
created, moved or deleted, while the lane was held. A lane shares refs with
the repository, so this may be the lane's agent or anyone else.

Briefing an agent. The orchestrator runs `acquire --purpose "<unit> <role>"`
(adding `--apply-staged <unit files>` for a reviewer or a later round), and
pastes this into the brief with LANE replaced by the printed path:

  Your working copy is LANE (an absolute path). Do all editing, building and
  testing there, never in the main checkout: start every shell command with
  `cd LANE &&` and give every file path as LANE/... . Read the process
  documents (CLAUDE.md, docs/swift-migration/) from the main checkout. The
  build lane is yours: `cd LANE && tools/build.sh` and
  `cd LANE && tools/run_tests.expect <tests>` (no -parallel unless told).
  LANE has no tmp/codedb: query the main checkout's code database read-only
  by its absolute path, with the main checkout's codedb.py (a codedb.py of
  another schema version refuses to query it, and its `update` would
  rebuild it), unless you are told to build one. Put scratch files
  and fixtures under LANE/tmp/. `git add` each new file immediately: files
  that are not added are not collected. Do not commit, stash, create or move
  branches, or run git submodule commands. Do not create git repositories
  inside LANE except under LANE/tmp/. Leave the submodules and
  iTerm2.xcodeproj/project.pbxproj alone unless the brief says to add a file
  to the project; edits inside a submodule are saved aside but never
  collected. Before you hand back, make sure no build or test you started is
  still running: the lane is reset after you finish.

Afterwards: `collect N` to review, `collect N --to-index` (with
--allow-project only after reading the project diff), then `release N`.

Guards are against accidents (two agents in one lane, a lane built from
stale code, lost work, a clobbered project file), not against an agent that
sets out to defeat them.

Exit status: 0 success; 1 error; 2 usage; 3 no free lane; 4 refused (a held
lane, or a collect that would not apply cleanly or touches what it must not).

Every git command runs with hooks, fsmonitor, submodule recursion and rerere
turned off on its command line, and without inherited GIT_DIR, GIT_INDEX_FILE
and similar variables.
"""

import argparse
import datetime
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time

DEFAULT_COUNT = 3
CONF_NAME = 'lanes.json'
HOLDER_NAME = 'holder.json'
MARKER_NAME = 'swift-migration-lane.json'

EXIT_ERROR = 1
EXIT_NO_LANE = 3
EXIT_REFUSED = 4

SAFE = ['-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
        '-c', 'submodule.recurse=false', '-c', 'rerere.enabled=false',
        '-c', 'core.pager=cat', '-c', 'advice.detachedHead=false']
DIFF_FLAGS = ['--binary', '--no-color', '--no-ext-diff', '--no-textconv', '--no-renames',
              '--src-prefix=a/', '--dst-prefix=b/']
INHERITED_GIT_VARS = ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_PREFIX',
                      'GIT_COMMON_DIR', 'GIT_OBJECT_DIRECTORY',
                      'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_NAMESPACE']
# Process names skipped when looking for the long-lived process that holds a
# lane (the Claude Code session): shells and wrappers that end with the
# command.
WRAPPERS = {'sh', 'bash', 'zsh', 'dash', 'ksh', 'fish', 'env', 'time', 'timeout', 'gtimeout',
            'expect', 'make', 'xargs', 'nohup', 'nice', 'caffeinate', 'perl', 'ruby', 'tclsh',
            'login'}
PROJECT_SUFFIX = '.xcodeproj/project.pbxproj'


class Fail(Exception):
    def __init__(self, message, code=EXIT_ERROR):
        Exception.__init__(self, message)
        self.code = code


def say(message):
    sys.stderr.write('lane_clone: %s\n' % message)


def git_env(extra=None):
    env = dict(os.environ)
    for name in INHERITED_GIT_VARS:
        env.pop(name, None)
    env.update(extra or {})
    return env


def git(cwd, *args, check=True, data=None, env=None, binary=False):
    """Runs git in cwd. Returns the CompletedProcess; raises Fail on error when check."""
    # --no-optional-locks: inspecting a lane someone else holds (status)
    # must never take its index.lock and make that holder's git fail.
    proc = subprocess.run(['git', '--no-optional-locks'] + SAFE + list(args), cwd=cwd,
                          env=git_env(env),
                          input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          universal_newlines=not binary)
    if check and proc.returncode != 0:
        err = proc.stderr if not binary else proc.stderr.decode('utf-8', 'replace')
        raise Fail('git %s (in %s) failed: %s' % (' '.join(args), cwd, err.strip()))
    return proc


def out(cwd, *args):
    return git(cwd, *args).stdout.strip()


def inside(path, top):
    path, top = os.path.realpath(path), os.path.realpath(top)
    return path == top or path.startswith(top.rstrip('/') + '/')


def write_json_atomically(path, value):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix='.tmp.')
    with os.fdopen(fd, 'w') as f:
        json.dump(value, f, indent=1, sort_keys=True)
        f.write('\n')
    os.rename(tmp, path)


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def process_info(pid):
    """(parent pid, start time text, command name) of pid, or None."""
    try:
        proc = subprocess.run(['ps', '-o', 'ppid=,lstart=,comm=', '-p', str(pid)],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              universal_newlines=True)
    except OSError:
        return None
    fields = proc.stdout.split()
    if proc.returncode != 0 or len(fields) < 7:
        return None
    return int(fields[0]), ' '.join(fields[1:6]), ' '.join(fields[6:])


def default_holder_pid():
    """The nearest ancestor that is not a shell, wrapper or Python: normally
    the Claude Code process whose session asked for the lane."""
    pid = os.getppid()
    for _ in range(30):
        info = process_info(pid)
        if info is None:
            break
        name = os.path.basename(info[2]).lstrip('-')
        if name in WRAPPERS or name.startswith('python'):
            if info[0] <= 1:
                break
            pid = info[0]
            continue
        return pid
    return os.getppid()


def holder_is_dead(holder):
    pid = holder.get('pid')
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    started = holder.get('pid_start')
    info = process_info(pid)
    if started and info is not None and info[1] != started:
        return True  # the pid has been reused by another process
    return False


def format_age(seconds):
    seconds = max(0, int(seconds))
    if seconds < 3600:
        return '%dm%02ds' % (seconds // 60, seconds % 60)
    return '%dh%02dm' % (seconds // 3600, (seconds % 3600) // 60)


class Lanes(object):
    def __init__(self, repo_arg, lanes_arg):
        start = os.path.abspath(repo_arg or os.getcwd())
        proc = git(start, 'rev-parse', '--show-toplevel', check=False)
        if proc.returncode != 0:
            raise Fail('%s is not in a git working tree' % start)
        self.repo = os.path.realpath(proc.stdout.strip())
        gitdir = out(self.repo, 'rev-parse', '--path-format=absolute', '--absolute-git-dir')
        if os.path.exists(os.path.join(gitdir, MARKER_NAME)):
            raise Fail('%s is inside a lane; run lane_clone.py from the orchestrator\'s '
                       'checkout, not from a lane' % self.repo)
        self.common = os.path.realpath(out(self.repo, 'rev-parse', '--path-format=absolute',
                                           '--git-common-dir'))
        self.dir = os.path.realpath(os.path.abspath(lanes_arg or self.repo + '.lanes'))
        if inside(self.dir, self.repo):
            ignored = git(self.repo, 'check-ignore', '-q', '--no-index', self.dir, check=False)
            if ignored.returncode != 0:
                raise Fail('the lanes directory %s is inside the working tree of %s and not '
                           'ignored by git; choose a directory outside it or under an ignored '
                           'one such as tmp/' % (self.dir, self.repo))
        self.conf = read_json(os.path.join(self.dir, CONF_NAME))
        if self.conf is not None and os.path.realpath(self.conf.get('repo', '')) != self.repo:
            raise Fail('the lanes directory %s belongs to %s, not %s'
                       % (self.dir, self.conf.get('repo'), self.repo))

    # Configuration and paths.

    @property
    def count(self):
        return int(self.conf['count']) if self.conf else DEFAULT_COUNT

    @property
    def reserved(self):
        return self.count if self.count >= 2 else None

    def ensure_conf(self, count=None):
        wanted = count or self.count
        if self.conf is not None and int(self.conf['count']) == wanted:
            return
        if self.conf is not None and wanted < self.count:
            extra = [n for n in range(wanted + 1, self.count + 1) if self.exists(n)]
            if extra:
                raise Fail('lanes %s exist beyond the new count %d; destroy them first'
                           % (', '.join(map(str, extra)), wanted))
        self.conf = {'repo': self.repo, 'count': wanted}
        write_json_atomically(os.path.join(self.dir, CONF_NAME), self.conf)

    def path(self, n):
        return os.path.join(self.dir, 'lane-%d' % n)

    def lock_dir(self, n):
        return os.path.join(self.dir, 'locks', 'lane-%d' % n)

    def state_path(self, n):
        return os.path.join(self.dir, 'state', 'lane-%d.json' % n)

    def parse(self, text):
        name = os.path.basename(text.rstrip('/'))
        if name.startswith('lane-'):
            name = name[len('lane-'):]
        try:
            n = int(name)
        except ValueError:
            raise Fail('%s does not name a lane (give a number, lane-N or its path)' % text)
        if n < 1 or n > self.count:
            raise Fail('there is no lane %d (lanes are 1 to %d)' % (n, self.count))
        return n

    def exists(self, n):
        """Whether lane n is a worktree made by this tool."""
        path = self.path(n)
        if not os.path.isfile(os.path.join(path, '.git')):
            return False
        proc = git(path, 'rev-parse', '--path-format=absolute', '--absolute-git-dir', check=False)
        if proc.returncode != 0:
            return False
        marker = read_json(os.path.join(proc.stdout.strip(), MARKER_NAME))
        return bool(marker) and os.path.realpath(marker.get('path', '')) == path

    # Locks.

    def holder(self, n):
        if not os.path.isdir(self.lock_dir(n)):
            return None
        return read_json(os.path.join(self.lock_dir(n), HOLDER_NAME)) or {}

    def try_lock(self, n, holder):
        os.makedirs(os.path.dirname(self.lock_dir(n)), exist_ok=True)
        try:
            os.mkdir(self.lock_dir(n))
        except FileExistsError:
            return False
        write_json_atomically(os.path.join(self.lock_dir(n), HOLDER_NAME), holder)
        return True

    def unlock(self, n):
        shutil.rmtree(self.lock_dir(n), ignore_errors=True)

    def state(self, n):
        return read_json(self.state_path(n)) or {}

    def write_state(self, n, **values):
        state = self.state(n)
        state.update(values)
        write_json_atomically(self.state_path(n), state)

    def base(self, n):
        return self.state(n).get('base') or out(self.path(n), 'rev-parse', 'HEAD')

    # Making and resetting lanes.

    def create(self, n, sha):
        path = self.path(n)
        if self.exists(n):
            return False
        if os.path.exists(path):
            raise Fail('%s exists but is not a lane made by this tool; remove it with '
                       '`destroy %d`' % (path, n))
        os.makedirs(self.dir, exist_ok=True)
        git(self.repo, 'worktree', 'add', '--quiet', '--detach', path, sha)
        try:
            gitdir = out(path, 'rev-parse', '--path-format=absolute', '--absolute-git-dir')
            write_json_atomically(os.path.join(gitdir, MARKER_NAME),
                                  {'path': path, 'lanes': self.dir, 'repo': self.repo})
            sync_submodules(path, self.common, sha)
        except BaseException:
            self.remove_worktree(n)
            raise
        write_json_atomically(self.state_path(n), {'base': sha})
        return True

    def reset(self, n, sha):
        path = self.path(n)
        self.remove_former_submodules(n)
        git(path, 'checkout', '-q', '--detach', '--force', sha)
        git(path, 'reset', '-q', '--hard', sha)
        # Without -x: ignored files (Build/, tmp/, products) stay, so builds
        # stay incremental. -ff also removes an untracked nested repository,
        # such as a submodule the new commit no longer has; an ignored one
        # is removed by remove_former_submodules.
        git(path, 'clean', '-ffdq')
        self.remove_former_submodules(n)
        sync_submodules(path, self.common, sha)
        write_json_atomically(self.state_path(n), {'base': sha})

    # Shared refs. A lane shares refs/stash and refs/heads with the
    # repository, so a stash or a branch made in it lands there.

    def ref_snapshot(self):
        heads = {}
        for line in out(self.repo, 'for-each-ref', '--format=%(refname) %(objectname)',
                        'refs/heads').splitlines():
            name, sha = line.rsplit(' ', 1)
            heads[name[len('refs/heads/'):]] = sha
        stash = 0
        if git(self.repo, 'rev-parse', '-q', '--verify', 'refs/stash',
               check=False).returncode == 0:
            stash = int(out(self.repo, 'rev-list', '--walk-reflogs', '--count', 'refs/stash'))
        return {'stash': stash, 'heads': heads}

    def warn_ref_changes(self, n):
        before = self.state(n).get('refs')
        if not before:
            return
        now = self.ref_snapshot()
        changes = []
        if now['stash'] > before['stash']:
            changes.append('the stash list grew from %d to %d entries'
                           % (before['stash'], now['stash']))
        old, new = before['heads'], now['heads']
        made = sorted(set(new) - set(old))
        moved = sorted(b for b in set(new) & set(old) if new[b] != old[b])
        gone = sorted(set(old) - set(new))
        if made:
            changes.append('branches created: %s' % ' '.join(made))
        if moved:
            changes.append('branches moved: %s' % ' '.join(moved))
        if gone:
            changes.append('branches deleted: %s' % ' '.join(gone))
        if changes:
            say('shared refs changed while the lane was held (by the lane\'s agent or '
                'someone else; refs are shared with %s): %s'
                % (self.repo, '; '.join(changes)))

    # Dirtiness and saving work.

    def dirty_submodules(self, n):
        """Paths (relative to lane n) of submodules with changes of their own:
        edits, untracked files, or a checkout other than the recorded commit."""
        return [p for p, _ in self._dirty_submodules(n)]

    def _dirty_submodules(self, n):
        """[(path relative to lane n, commit its parent records)]."""
        found = []

        def walk(work, commit, prefix):
            for path, sha in gitlinks(work, commit):
                dst = os.path.join(work, path)
                if not os.path.isdir(os.path.join(dst, '.git')):
                    continue
                if alternates_missing(dst):
                    # Its objects are gone, so git cannot inspect it.
                    if not disposable_nested_repo(dst):
                        found.append((prefix + path, sha))
                    continue
                head = sub_git(dst, 'rev-parse', '-q', '--verify', 'HEAD',
                               check=False).stdout.strip()
                if not head:
                    continue
                status = sub_git(dst, 'status', '--porcelain', '--ignore-submodules=all').stdout
                if status.strip() or head != sha:
                    found.append((prefix + path, sha))
                walk(dst, head, prefix + path + '/')

        walk(self.path(n), 'HEAD', '')
        return found

    def is_dirty(self, n):
        path = self.path(n)
        stale = stale_submodules(path)
        # A submodule whose borrowed objects are gone makes git status fail,
        # so it is left out and judged by stale_submodule_is_disposable.
        excludes = [':(exclude,literal)' + p for p in stale]
        status = git(path, 'status', '--porcelain', '--ignore-submodules=none',
                     *(['--', '.'] + excludes if excludes else [])).stdout
        if any(not disposable_nested_repo(os.path.join(path, p)) for p in stale):
            return True
        return bool(status.strip()) or out(path, 'rev-parse', 'HEAD') != self.base(n)

    def remove_former_submodules(self, n):
        """Removes from lane n what is left of submodules that are gone, when
        it holds no work (see disposable_nested_repo): a submodule the lane's
        HEAD records whose borrowed objects no longer exist (emptied, as an
        uninitialized submodule is), and a nested repository the lane's HEAD
        does not record that was a submodule (removed). Anything holding
        work is left for save_work, which saves it or refuses."""
        path = self.path(n)
        for sub in stale_submodules(path):
            dst = os.path.join(path, sub)
            if disposable_nested_repo(dst):
                shutil.rmtree(dst)
                os.makedirs(dst)
                say('lane %d: emptied submodule %s, whose objects in the repository are gone'
                    % (n, sub))
        for sub in former_submodule_leftovers(path, self.common):
            dst = os.path.join(path, sub)
            if disposable_nested_repo(dst):
                shutil.rmtree(dst)
                say('lane %d: removed %s, left over from a submodule the lane\'s commit no '
                    'longer has' % (n, sub))

    def _patch_with_untracked(self, work, base, sub=False):
        """A binary patch of everything in work that differs from base,
        untracked files included, made with a copy of the index."""
        if sub:
            run = lambda *a, **k: sub_git(work, *a, **k)
            index = os.path.join(work, '.git', 'index')
        else:
            run = lambda *a, **k: git(work, *a, **k)
            index = out(work, 'rev-parse', '--path-format=absolute', '--git-path', 'index')
        with tempfile.TemporaryDirectory(dir=self.dir) as scratch:
            tmp_index = os.path.join(scratch, 'index')
            if os.path.exists(index):
                shutil.copyfile(index, tmp_index)
            env = {'GIT_INDEX_FILE': tmp_index}
            proc = run('add', '-A', env=env, check=False)
            if proc.returncode != 0:
                raise Fail('cannot save the changes in %s: git add -A failed: %s'
                           % (work, proc.stderr.strip()))
            return run('diff', '--cached', *(DIFF_FLAGS + [base]), env=env,
                       binary=True).stdout

    def _write_saved(self, n, why, suffix, patch):
        saved_dir = os.path.join(self.dir, 'saved')
        os.makedirs(saved_dir, exist_ok=True)
        stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
        name = 'lane-%d-%s-%s-%d%s.patch' % (n, stamp, why, os.getpid(), suffix)
        target = os.path.join(saved_dir, name)
        with open(target, 'wb') as f:
            f.write(patch)
        return target

    def save_work(self, n, why):
        """Saves what lane n holds that its base does not, as patches under
        saved/: one for the lane (tracked changes, new files whether added or
        not, commits since the base), and one per submodule with changes of
        its own (against the commit the lane records for it). Returns
        [(saved path, submodule path or None)]. Raises Fail when something
        cannot be saved."""
        path = self.path(n)
        if not self.exists(n):
            return []
        self.remove_former_submodules(n)
        if not self.is_dirty(n):
            return []
        saved = []
        patch = self._patch_with_untracked(path, self.base(n))
        if patch:
            saved.append((self._write_saved(n, why, '', patch), None))
        for sub, recorded in self._dirty_submodules(n):
            patch = self._patch_with_untracked(os.path.join(path, sub), recorded, sub=True)
            if patch:
                suffix = '-submodule-' + sub.replace('/', '_')
                saved.append((self._write_saved(n, why, suffix, patch), sub))
        return saved

    def report_saved(self, n, saved):
        for target, sub in saved:
            if sub is None:
                say('lane %d had uncollected work; saved it to %s' % (n, target))
            else:
                say('lane %d had changes inside submodule %s, which are never collected; '
                    'saved them to %s' % (n, sub, target))

    def remove_worktree(self, n):
        path = self.path(n)
        git(self.repo, 'worktree', 'remove', '--force', '--force', path, check=False)
        if os.path.lexists(path):
            shutil.rmtree(path, ignore_errors=True)
        # Remove this lane's registration only; a global `git worktree prune`
        # would also act on other people's worktrees.
        registry = os.path.join(self.common, 'worktrees')
        if os.path.isdir(registry):
            for entry in os.listdir(registry):
                gitdir_file = os.path.join(registry, entry, 'gitdir')
                try:
                    with open(gitdir_file) as f:
                        target = f.read().strip()
                except OSError:
                    continue
                if os.path.realpath(os.path.dirname(target)) == path or \
                        os.path.dirname(target) == path:
                    shutil.rmtree(os.path.join(registry, entry), ignore_errors=True)

    def describe(self, n):
        path = self.path(n)
        entry = {'lane': n, 'path': path, 'reserved': n == self.reserved,
                 'exists': self.exists(n), 'commit': None, 'dirty': None,
                 'dirty_submodules': [], 'pid': None, 'purpose': None,
                 'age_seconds': None}
        holder = self.holder(n)
        if holder is None:
            entry['state'] = 'free' if entry['exists'] else 'missing'
        else:
            entry['state'] = 'stale' if holder_is_dead(holder) else 'held'
            entry['pid'] = holder.get('pid')
            entry['purpose'] = holder.get('purpose')
            if isinstance(holder.get('acquired'), (int, float)):
                entry['age_seconds'] = int(time.time() - holder['acquired'])
        if entry['exists']:
            entry['commit'] = out(path, 'rev-parse', 'HEAD')
            entry['dirty'] = self.is_dirty(n)
            entry['dirty_submodules'] = self.dirty_submodules(n) if entry['dirty'] else []
            # Read only: the next acquire or release removes them.
            entry['stale_submodules'] = sorted(set(stale_submodules(path)) |
                                               set(former_submodule_leftovers(path, self.common)))
        return entry


# Submodules.

def gitlinks(work, commit):
    """[(path, sha)] for every submodule entry in commit's tree."""
    listing = git(work, 'ls-tree', '-r', '-z', commit).stdout
    found = []
    for record in listing.split('\0'):
        if not record:
            continue
        meta, path = record.split('\t', 1)
        mode, _, sha = meta.split(' ')
        if mode == '160000':
            found.append((path, sha))
    return found


def submodule_names(work, commit):
    """{path: name} from the .gitmodules in commit."""
    proc = git(work, 'config', '--blob', commit + ':.gitmodules', '-z', '--get-regexp',
               r'^submodule\..*\.path$', check=False)
    names = {}
    for record in proc.stdout.split('\0'):
        if '\n' not in record:
            continue
        key, value = record.split('\n', 1)
        names[value] = key[len('submodule.'):-len('.path')]
    return names


def alternates_missing(dst):
    """Whether the repository embedded at dst borrows objects from a
    directory that no longer exists."""
    try:
        with open(os.path.join(dst, '.git', 'objects', 'info', 'alternates')) as f:
            lines = [line.strip() for line in f]
    except OSError:
        return False
    return any(line and not line.startswith('#') and not os.path.isdir(line) for line in lines)


def stale_submodules(work):
    """Paths of the submodules work's HEAD records whose embedded repository
    borrows from a submodule repository that is gone (upstream removed the
    submodule and the repository's copy was deleted)."""
    return [p for p, _ in gitlinks(work, 'HEAD') if alternates_missing(os.path.join(work, p))]


def former_submodule_leftovers(work, common):
    """Untracked or ignored directories in work holding a repository of their
    own (.git) that work's HEAD records neither as a gitlink nor in
    .gitmodules, and that were a submodule: a gitlink in an earlier commit of
    HEAD's history, or named by the repository's submodule configuration or
    its modules/ directory."""
    listing = git(work, 'ls-files', '--others', '--directory', '-z').stdout
    candidates = [p.rstrip('/') for p in listing.split('\0')
                  if p.endswith('/') and os.path.lexists(os.path.join(work, p, '.git'))]
    if not candidates:
        return []
    recorded = set(p for p, _ in gitlinks(work, 'HEAD')) | set(submodule_names(work, 'HEAD'))
    found = []
    for path in candidates:
        if path in recorded:
            continue
        last = git(work, 'rev-list', '-1', 'HEAD', '--', path, check=False).stdout.strip()
        was_gitlink = False
        if last:
            for commit in (last, last + '^'):
                if any(p == path for p, _ in gitlinks_at(work, commit, path)):
                    was_gitlink = True
        configured = git(work, 'config', '--get-regexp', r'^submodule\..*\.(path|url)$',
                         check=False).stdout
        named = ('submodule.%s.' % path) in configured or \
            os.path.isdir(os.path.join(common, 'modules', path))
        if was_gitlink or named:
            found.append(path)
    return found


def gitlinks_at(work, commit, path):
    """gitlinks(work, commit) limited to path; empty when commit does not exist."""
    proc = git(work, 'ls-tree', '-z', commit, '--', path, check=False)
    found = []
    for record in proc.stdout.split('\0'):
        if record and '\t' in record:
            meta, name = record.split('\t', 1)
            if meta.split(' ')[0] == '160000':
                found.append((name, meta.split(' ')[2]))
    return found


def disposable_nested_repo(dst):
    """Whether the repository embedded at dst holds nothing the lane tool
    would save: an embedded .git directory with no objects of its own (so no
    commit and nothing staged; a lane's submodule borrows every object), no
    tracked file changed, and no untracked file that is not ignored (ignored
    files are never saved). Answered from the index and the working tree
    only, so it works when the borrowed objects are gone; anything git
    cannot answer counts as work."""
    dotgit = os.path.join(dst, '.git')
    if not os.path.isdir(dotgit) or os.path.islink(dotgit):
        return False
    objects = os.path.join(dotgit, 'objects')
    for root, dirs, files in os.walk(objects):
        if root == objects and 'info' in dirs:
            dirs.remove('info')
        if files:
            return False
    if sub_git(dst, 'diff-files', '--quiet', check=False).returncode != 0:
        return False
    others = sub_git(dst, 'ls-files', '--others', '--exclude-standard', '-z', check=False)
    return others.returncode == 0 and not others.stdout


def sub_git(path, *args, **kwargs):
    # The submodule's git directory and working tree are named explicitly so
    # that a missing .git can never make git find the lane itself.
    return git(path, '--git-dir=' + os.path.join(path, '.git'), '--work-tree=' + path,
               *args, **kwargs)


def sync_submodules(work, source_gitdir, commit):
    """Makes every submodule of commit (in working tree work) that the source
    repository has initialized, at the recorded commit, recursively."""
    links = gitlinks(work, commit)
    if not links:
        return
    names = submodule_names(work, commit)
    for path, sha in links:
        name = names.get(path)
        if not name:
            say('submodule %s in %s has no entry in .gitmodules; left empty' % (path, work))
            continue
        source = os.path.join(source_gitdir, 'modules', name)
        if not os.path.isdir(os.path.join(source, 'objects')):
            continue  # not initialized in the source either
        dst = os.path.join(work, path)
        dotgit = os.path.join(dst, '.git')
        if not os.path.lexists(dotgit):
            os.makedirs(dst, exist_ok=True)
            git(dst, 'init', '-q', '--template=', dst)
            info = os.path.join(dotgit, 'objects', 'info')
            os.makedirs(info, exist_ok=True)
            with open(os.path.join(info, 'alternates'), 'w') as f:
                f.write(os.path.join(os.path.realpath(source), 'objects') + '\n')
        if sub_git(dst, 'cat-file', '-e', sha + '^{commit}', check=False).returncode != 0:
            raise Fail('submodule %s needs commit %s, which %s does not have: update the '
                       'submodule in the orchestrator\'s checkout first' % (path, sha, source))
        head = sub_git(dst, 'rev-parse', '-q', '--verify', 'HEAD', check=False).stdout.strip()
        dirty = head and sub_git(dst, 'status', '--porcelain',
                                 '--ignore-submodules=all').stdout.strip()
        if head != sha or dirty:
            sub_git(dst, 'checkout', '-q', '--detach', '--force', sha)
            sub_git(dst, 'reset', '-q', '--hard', sha)
            sub_git(dst, 'clean', '-ffdq')
        sync_submodules(dst, source, sha)


def derived_data_folders(lane_path):
    """Xcode's DerivedData folders whose workspace is inside lane_path."""
    root = os.path.join(os.path.expanduser('~'), 'Library', 'Developer', 'Xcode', 'DerivedData')
    found = []
    try:
        names = sorted(os.listdir(root))
    except OSError:
        return found
    for name in names:
        try:
            with open(os.path.join(root, name, 'info.plist'), 'rb') as f:
                workspace = plistlib.load(f).get('WorkspacePath', '')
        except Exception:
            continue
        if isinstance(workspace, str) and inside(workspace, lane_path):
            found.append(os.path.join(root, name))
    return found


# Commands.

def cmd_create(lanes, args):
    lanes.ensure_conf(args.count)
    numbers = [lanes.parse(t) for t in args.lanes] or list(range(1, lanes.count + 1))
    sha = out(lanes.repo, 'rev-parse', '--verify', 'HEAD^{commit}')
    holder = {'pid': os.getpid(), 'purpose': 'create', 'acquired': time.time()}
    for n in numbers:
        if lanes.exists(n):
            say('lane %d already exists at %s' % (n, lanes.path(n)))
            continue
        if not lanes.try_lock(n, holder):
            say('lane %d is locked; not made' % n)
            continue
        try:
            started = time.time()
            lanes.create(n, sha)
            say('made lane %d at %s (%s) in %.1fs' % (n, lanes.path(n), sha[:12],
                                                       time.time() - started))
        finally:
            lanes.unlock(n)
    return 0


def cmd_acquire(lanes, args):
    patch_file = None
    if args.apply_patch:
        try:
            with open(args.apply_patch, 'rb') as f:
                patch_file = f.read()
        except OSError as e:
            raise Fail('cannot read the patch %s: %s' % (args.apply_patch, e.strerror))
    lanes.ensure_conf()
    sha = out(lanes.repo, 'rev-parse', '--verify', 'HEAD^{commit}')
    if args.full_suite:
        candidates = [lanes.reserved or 1]
    else:
        candidates = [n for n in range(1, lanes.count + 1) if n != lanes.reserved]
    candidates.sort(key=lambda n: (not lanes.exists(n), n))
    pid = args.holder_pid or default_holder_pid()
    info = process_info(pid)
    holder = {'pid': pid, 'pid_start': info[1] if info else None,
              'purpose': args.purpose or '', 'acquired': time.time(),
              'acquired_at': datetime.datetime.now().isoformat(timespec='seconds'),
              'base': sha, 'full_suite': bool(args.full_suite)}
    chosen = None
    for n in candidates:
        if lanes.try_lock(n, holder):
            chosen = n
            break
    if chosen is None:
        lines = ['no free lane%s among %s:' % (' for a full-suite run' if args.full_suite else '',
                                              ', '.join('lane-%d' % n for n in candidates))]
        # Only the lock files are read: a lane someone holds is not inspected.
        for n in candidates:
            h = lanes.holder(n) or {}
            state = 'stale' if h and holder_is_dead(h) else 'held'
            lines.append('  lane-%d %s pid %s %s' % (n, state, h.get('pid'), h.get('purpose') or ''))
        lines.append('release a lane (`release N`, or `release --stale` for dead holders) '
                     'or wait for one')
        raise Fail('\n'.join(lines), EXIT_NO_LANE)
    may_reset = False
    try:
        if lanes.create(chosen, sha):
            may_reset = True
        else:
            try:
                saved = lanes.save_work(chosen, 'acquire')
            except Fail as e:
                raise Fail('%s\nlane %d was not reset and is left as it was (free); save or '
                           'remove its changes by hand, then acquire again' % (e, chosen))
            lanes.report_saved(chosen, saved)
            may_reset = True
            lanes.reset(chosen, sha)
        lanes.write_state(chosen, refs=lanes.ref_snapshot())
        path = lanes.path(chosen)
        if args.apply_staged:
            patch = git(lanes.repo, 'diff', '--cached', *(DIFF_FLAGS + ['--'] + args.apply_staged),
                        binary=True).stdout
            if not patch:
                raise Fail('nothing staged in %s for %s' % (lanes.repo, ' '.join(args.apply_staged)))
            git(path, 'apply', '--index', '-', data=patch, binary=True)
        if patch_file is not None:
            git(path, 'apply', '--index', '-', data=patch_file, binary=True)
    except BaseException:
        if may_reset and lanes.exists(chosen):
            try:
                lanes.reset(chosen, sha)
            except Fail:
                pass
        lanes.unlock(chosen)
        raise
    say('acquired lane %d at %s for %s' % (chosen, sha[:12], args.purpose or '(no purpose given)'))
    print(lanes.path(chosen))
    return 0


def release_one(lanes, n):
    if lanes.exists(n):
        lanes.warn_ref_changes(n)
        lanes.report_saved(n, lanes.save_work(n, 'release'))
        if lanes.is_dirty(n):
            lanes.reset(n, lanes.base(n))
    lanes.unlock(n)
    say('released lane %d' % n)


def cmd_release(lanes, args):
    if args.stale:
        if args.lane:
            raise Fail('give a lane or --stale, not both')
        for n in range(1, lanes.count + 1):
            holder = lanes.holder(n)
            if holder is not None and holder_is_dead(holder):
                release_one(lanes, n)
        return 0
    if not args.lane:
        raise Fail('give a lane to release, or --stale')
    n = lanes.parse(args.lane)
    if lanes.holder(n) is None:
        say('lane %d was not held' % n)
    release_one(lanes, n)
    return 0


def cmd_status(lanes, args):
    entries = [lanes.describe(n) for n in range(1, lanes.count + 1)]
    if args.json:
        print(json.dumps({'repo': lanes.repo, 'lanes_dir': lanes.dir, 'lanes': entries},
                         indent=1, sort_keys=True))
        return 0
    print('lanes of %s in %s' % (lanes.repo, lanes.dir))
    for e in entries:
        parts = ['lane-%d' % e['lane'], e['state']]
        if e['reserved']:
            parts.append('(full suite)')
        if e['pid'] is not None:
            parts.append('pid %s' % e['pid'])
        if e['age_seconds'] is not None:
            parts.append('for %s' % format_age(e['age_seconds']))
        if e['commit']:
            parts.append(e['commit'][:12])
            if e['dirty_submodules']:
                parts.append('dirty (submodule %s)' % ', '.join(e['dirty_submodules']))
            else:
                parts.append('dirty' if e['dirty'] else 'clean')
        if e['purpose']:
            parts.append('"%s"' % e['purpose'])
        print('  ' + '  '.join(parts))
    return 0


def cmd_collect(lanes, args):
    n = lanes.parse(args.lane)
    if not lanes.exists(n):
        raise Fail('lane %d does not exist' % n)
    path = lanes.path(n)
    base = lanes.base(n)
    lanes.warn_ref_changes(n)
    if out(path, 'rev-parse', 'HEAD') != base:
        say('lane %d has commits since its base %s; collecting everything since the base '
            '(agents must not commit)' % (n, base[:12]))
    untracked = [p for p in git(path, 'ls-files', '--others', '--exclude-standard',
                                '-z').stdout.split('\0') if p]
    if untracked:
        say('lane %d has files that were not added with `git add` and are NOT collected: %s'
            % (n, ' '.join(untracked)))
    raw = git(path, 'diff', '--raw', '-z', '--no-renames', '--ignore-submodules=none',
              base).stdout.split('\0')
    submodules = []
    for i, field in enumerate(raw):
        if field.startswith(':') and ('160000' in field.split(' ')[:2]) and i + 1 < len(raw):
            submodules.append(raw[i + 1])
    if submodules:
        say('lane %d changed submodules %s; submodule changes are never collected'
            % (n, ' '.join(submodules)))
    patch = git(path, 'diff', '--ignore-submodules=all', *(DIFF_FLAGS + [base]),
                binary=True).stdout
    names = [p for p in git(path, 'diff', '--name-only', '-z', '--no-renames',
                            '--ignore-submodules=all', base).stdout.split('\0') if p]
    projects = [p for p in names if p.endswith(PROJECT_SUFFIX)]
    if not args.to_index:
        if projects:
            say('the patch touches %s' % ' '.join(projects))
        sys.stdout.flush()
        sys.stdout.buffer.write(patch)
        sys.stdout.flush()
        return 0
    if not patch:
        say('nothing to collect from lane %d' % n)
        return 0
    if submodules:
        raise Fail('refusing: lane %d changed submodule %s; reset the submodule in the lane '
                   'and collect again' % (n, ' '.join(submodules)), EXIT_REFUSED)
    if projects and not args.allow_project:
        raise Fail('refusing: the patch touches %s, which stray tools have clobbered before; '
                   'look at `collect %d` and pass --allow-project if the change is intended'
                   % (' '.join(projects), n), EXIT_REFUSED)
    # Trial run of the three-way apply on a copy of the index, so that a
    # conflict leaves the orchestrator's index and working tree untouched.
    index = out(lanes.repo, 'rev-parse', '--path-format=absolute', '--git-path', 'index')
    with tempfile.TemporaryDirectory(dir=lanes.dir) as scratch:
        tmp_index = os.path.join(scratch, 'index')
        if os.path.exists(index):
            shutil.copyfile(index, tmp_index)
        env = {'GIT_INDEX_FILE': tmp_index}
        trial = git(lanes.repo, 'apply', '--cached', '--3way', '-', data=patch, env=env,
                    binary=True, check=False)
        unmerged = git(lanes.repo, 'ls-files', '-u', env=env).stdout.strip()
    if trial.returncode != 0 or unmerged:
        raise Fail('refusing: lane %d\'s change does not apply cleanly to %s:\n%s'
                   % (n, lanes.repo, trial.stderr.decode('utf-8', 'replace').strip()),
                   EXIT_REFUSED)
    real = git(lanes.repo, 'apply', '--index', '--3way', '-', data=patch, binary=True,
               check=False)
    if real.returncode != 0:
        raise Fail('applying lane %d\'s change to %s failed (check `git status` there; the '
                   'working tree may differ from the index): %s'
                   % (n, lanes.repo, real.stderr.decode('utf-8', 'replace').strip()),
                   EXIT_REFUSED)
    say('applied lane %d\'s change to the index and working tree of %s: %s'
        % (n, lanes.repo, ' '.join(names)))
    return 0


def cmd_destroy(lanes, args):
    n = lanes.parse(args.lane)
    holder = lanes.holder(n)
    if holder is not None and not args.force:
        state = 'held (stale)' if holder_is_dead(holder) else 'held'
        raise Fail('lane %d is %s by pid %s (%s); release it first or pass --force'
                   % (n, state, holder.get('pid'), holder.get('purpose') or ''), EXIT_REFUSED)
    lanes.report_saved(n, lanes.save_work(n, 'destroy'))
    derived = derived_data_folders(lanes.path(n))
    lanes.remove_worktree(n)
    try:
        os.remove(lanes.state_path(n))
    except OSError:
        pass
    lanes.unlock(n)
    listed = out(lanes.repo, 'worktree', 'list', '--porcelain')
    if os.path.exists(lanes.path(n)) or ('worktree %s\n' % lanes.path(n)) in listed + '\n':
        raise Fail('lane %d was not removed completely: %s' % (n, lanes.path(n)))
    say('destroyed lane %d' % n)
    for folder in derived:
        say('lane %d\'s Xcode DerivedData folder is %s; remove it by hand if it is no '
            'longer wanted' % (n, folder))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description='Build lanes for migration agents. See the header of this file.')
    parser.add_argument('--repo', help='the orchestrator\'s checkout (default: the one the '
                        'current directory is in)')
    parser.add_argument('--lanes-dir', help='where lanes live (default: <repo>.lanes)')
    sub = parser.add_subparsers(dest='command')
    sub.required = True

    p = sub.add_parser('create', help='make lanes')
    p.add_argument('lanes', nargs='*')
    p.add_argument('--count', type=int, help='number of lanes (default 3, or as recorded)')
    p.set_defaults(func=cmd_create)

    p = sub.add_parser('acquire', help='claim a free lane and print its path')
    p.add_argument('--purpose', help='what the lane is for, shown by status')
    p.add_argument('--full-suite', action='store_true', help='claim the lane reserved for '
                   'full-suite runs')
    p.add_argument('--holder-pid', type=int, help='the process whose death makes the lock '
                   'stale (default: the nearest ancestor that is not a shell or wrapper)')
    p.add_argument('--apply-staged', nargs='+', metavar='PATHSPEC', help='apply the '
                   'repository\'s staged changes for these paths to the lane\'s index')
    p.add_argument('--apply-patch', metavar='FILE', help='apply this patch to the lane\'s index')
    p.set_defaults(func=cmd_acquire)

    p = sub.add_parser('release', help='free a lane')
    p.add_argument('lane', nargs='?')
    p.add_argument('--stale', action='store_true', help='free every lane whose holder is dead')
    p.set_defaults(func=cmd_release)

    p = sub.add_parser('status', help='list lanes')
    p.add_argument('--json', action='store_true')
    p.set_defaults(func=cmd_status)

    p = sub.add_parser('collect', help='print or apply a lane\'s change')
    p.add_argument('lane')
    p.add_argument('--to-index', action='store_true', help='apply it to the repository\'s '
                   'index and working tree')
    p.add_argument('--allow-project', action='store_true', help='allow a change to an Xcode '
                   'project file')
    p.set_defaults(func=cmd_collect)

    p = sub.add_parser('destroy', help='remove a lane completely')
    p.add_argument('lane')
    p.add_argument('--force', action='store_true', help='destroy even if held')
    p.set_defaults(func=cmd_destroy)

    args = parser.parse_args(argv)
    try:
        if args.command == 'create' and args.count is not None and args.count < 1:
            raise Fail('--count must be at least 1')
        lanes = Lanes(args.repo, args.lanes_dir)
        return args.func(lanes, args)
    except Fail as e:
        say(str(e))
        return e.code
    except OSError as e:
        say('error: %s' % e)
        return EXIT_ERROR


if __name__ == '__main__':
    sys.exit(main())
