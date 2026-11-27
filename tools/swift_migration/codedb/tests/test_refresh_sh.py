#!/usr/bin/env python3
"""Tests for tools/swift_migration/codedb/refresh.sh, the one command that
brings the code database and the classification up to date, and its
--status.

Run with:
  python3 -B -m unittest discover -s tools/swift_migration/codedb/tests -p 'test_refresh_sh.py'

Every test builds its own scratch repository in the system temporary
directory and runs the script on it with --root. The three steps (the
capture, codedb.py update and qualify_unit.py --classify) are stand-ins
named by REFRESH_CAPTURE, REFRESH_UPDATE and REFRESH_CLASSIFY: one shell
script that records its call, its arguments, its working directory and
its niceness, and then does what the test's STUB_<STEP>_ACTION says
(commit to the scratch repository, edit a tracked file, create an
untracked file, or hold until released) before it exits with
STUB_<STEP>_STATUS. The classify stand-in prints the JSON document the
test wrote. The update stand-in's action parse_errors writes a database
with the one table refresh.sh reads, tu (main_file, diagnostics_errors),
listing two units with parse errors, and fails as codedb.py update does
while any unit has them; called with --file P --force it clears P's
errors when STUB_FORCE_FIXES is set. Nothing is built, the real database is never touched, and the
test's git commands use no global configuration and no hooks.
"""

import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
CODEDB_DIR = os.path.dirname(HERE)
SCRIPT = os.path.join(CODEDB_DIR, 'refresh.sh')

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_CHANGED = 3
EXIT_BEHIND = 4
EXIT_GIT_BUSY = 5
EXIT_CAPTURE = 11
EXIT_UPDATE = 12
EXIT_CLASSIFY = 13
EXIT_RUNNING = 75

IDENTITY = {
    'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@example.invalid',
    'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@example.invalid',
}

STUB = r'''#!/bin/bash
# A stand-in for one step of refresh.sh. Its name (capture, update or
# classify) selects the STUB_<NAME>_ACTION and STUB_<NAME>_STATUS it obeys.
name=$(basename "$0")
upper=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')
echo "$name" >> "$STUB_DIR/calls"
printf '%s\n' "$@" > "$STUB_DIR/$name.args"
pwd > "$STUB_DIR/$name.pwd"
ps -o nice= -p $$ | tr -d ' ' > "$STUB_DIR/$name.nice"
echo "$name: stand-in output" >&2
eval "action=\${STUB_${upper}_ACTION:-}"
eval "status=\${STUB_${upper}_STATUS:-0}"
case "$action" in
    commit)
        echo during >> sources/Foo.m
        git add sources/Foo.m
        git commit -q -m 'committed during the refresh' ;;
    edit)
        echo edited >> sources/Foo.m ;;
    untracked)
        echo new > sources/Untracked.m ;;
    untracked-test)
        echo new > ModernTests/UntrackedTests.swift ;;
    edit-docs)
        echo more >> docs/swift-migration/claims.md ;;
    commit-docs)
        echo more >> docs/swift-migration/claims.md
        git add docs/swift-migration/claims.md
        git commit -q -m 'claims changed during the refresh' ;;
    mv-docs-staged)
        mkdir -p docs/moved
        git mv sources/Foo.m docs/moved/Foo.m ;;
    mv-docs-commit)
        mkdir -p docs/moved
        git mv sources/Foo.m docs/moved/Foo.m
        git commit -q -m 'moved a source file into docs' ;;
    commit-registry)
        echo more >> docs/swift-migration/reflective-sites.md
        git add docs/swift-migration/reflective-sites.md
        git commit -q -m 'registry changed during the refresh' ;;
    hold)
        echo $$ > "$STUB_DIR/$name.started"
        # The loop also ends when the test's directory is gone, so that a
        # stand-in whose test failed never runs on.
        while [ ! -e "$STUB_DIR/release" ] && [ -d "$STUB_DIR" ]; do sleep 0.05; done ;;
    parse_errors)
        echo "$*" >> "$STUB_DIR/update.calls"
        exec python3 -B - "$@" <<'EOF'
import os, sqlite3, sys
db = os.path.join('tmp', 'codedb', 'codedb.sqlite')
args = sys.argv[1:]
if '--file' in args:
    path = args[args.index('--file') + 1]
    if os.environ.get('STUB_FORCE_FIXES'):
        con = sqlite3.connect(db)
        con.execute('UPDATE tu SET diagnostics_errors = 0 WHERE main_file = ?', (path,))
        con.commit()
    sys.exit(0)
if not os.path.exists(db):
    os.makedirs(os.path.dirname(db), exist_ok=True)
    con = sqlite3.connect(db)
    con.execute('CREATE TABLE tu (target TEXT, main_file TEXT, diagnostics_errors INTEGER)')
    con.executemany('INSERT INTO tu VALUES (?, ?, ?)', [('iTerm2', 'sources/A.m', 2), ('ModernTests', 'sources/A.m', 1),
                                                       ('iTerm2', 'sources/B.m', 1), ('iTerm2', 'sources/C.m', 0)])
    con.commit()
con = sqlite3.connect(db)
errors = con.execute('SELECT count(*) FROM tu WHERE diagnostics_errors > 0').fetchone()[0]
if errors:
    print('%d units in the database have parse errors; their rows are incomplete' % errors, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
EOF
        ;;
esac
if [ "$status" != 0 ]; then
    echo "$name: error: the stand-in fails with status $status" >&2
    exit "$status"
fi
if [ "$name" = classify ]; then
    cat "$STUB_DIR/classify.json"
fi
exit 0
'''


def classify_document(trivial_unit='iTermFoo', incomplete=(), other=(), split=True):
    """A document in the shape qualify_unit.py --classify --json prints:
    incomplete lines about the database's own rows, and other lines (the
    registry and the resource files). Without split, only the combined key
    of qualify_unit.py versions before the split."""
    unit = {'unit': trivial_unit, 'classes': [trivial_unit], 'file': 'sources/%s.m' % trivial_unit,
            'path': 'trivial', 'part_of': None, 'body_lines': 3, 'implementation_lines': 20,
            'not_trivial_because': [], 'stop_status': None}
    d = {'units': 1, 'counts': {'trivial': 1, 'light': 0, 'full': 0},
         'split_counts': {'trivial': 0, 'light': 0, 'full': 0},
         'database_incomplete': list(incomplete) + list(other), 'classified': [unit], 'exit_status': 0}
    if split:
        d['database_rows_incomplete'] = list(incomplete)
        d['registry_or_resources_incomplete'] = list(other)
    return d


class RefreshTests(unittest.TestCase):
    def setUp(self):
        self.tmp = os.path.realpath(tempfile.mkdtemp(prefix='codedb_refresh_test.'))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = os.path.join(self.tmp, 'repo')
        self.stubs = os.path.join(self.tmp, 'stubs')
        os.makedirs(self.stubs)
        for name in ('capture', 'update', 'classify'):
            path = os.path.join(self.stubs, name)
            with open(path, 'w') as f:
                f.write(STUB)
            os.chmod(path, 0o755)
        self.write_classify(classify_document())
        self.git(self.tmp, 'init', '-q', '-b', 'master', self.repo)
        self.git(self.repo, 'config', 'core.hooksPath', '/dev/null')
        self.write_file('sources/Foo.m', 'one\n')
        self.write_file('sources/Foo.h', 'header\n')
        self.write_file('docs/swift-migration/claims.md', 'claims\n')
        self.write_file('docs/swift-migration/reflective-sites.md', 'registry\n')
        self.write_file('ModernTests/FooTests.swift', 'tests\n')
        self.write_file('.gitignore', 'tmp/\n')
        self.git(self.repo, 'add', '-A')
        self.git(self.repo, 'commit', '-q', '-m', 'init')
        self.procs = []
        self.addCleanup(self.stop_procs)

    # Helpers.

    def env(self, **extra):
        env = {
            'PATH': '/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
            'HOME': os.environ.get('HOME', '/nonexistent'),
            'GIT_CONFIG_GLOBAL': '/dev/null',
            'GIT_CONFIG_NOSYSTEM': '1',
            'LANG': 'en_US.UTF-8',
            'STUB_DIR': self.stubs,
            'REFRESH_CAPTURE': os.path.join(self.stubs, 'capture'),
            'REFRESH_UPDATE': os.path.join(self.stubs, 'update'),
            'REFRESH_CLASSIFY': os.path.join(self.stubs, 'classify'),
        }
        env.update(IDENTITY)
        env.update(extra)
        return env

    def git(self, cwd, *args):
        proc = subprocess.run(['git'] + list(args), cwd=cwd, env=self.env(), stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, universal_newlines=True)
        if proc.returncode != 0:
            raise AssertionError('git %s failed: %s' % (' '.join(args), proc.stderr))
        return proc.stdout.strip()

    def head(self):
        return self.git(self.repo, 'rev-parse', 'HEAD')

    def write_file(self, rel, text, mode='w'):
        path = os.path.join(self.repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, mode) as f:
            f.write(text)

    def commit_file(self, rel, text):
        self.write_file(rel, text, mode='a')
        self.git(self.repo, 'add', rel)
        self.git(self.repo, 'commit', '-q', '-m', 'change ' + rel)

    def write_classify(self, document):
        with open(os.path.join(self.stubs, 'classify.json'), 'w') as f:
            json.dump(document, f)

    def run_script(self, *args, **extra):
        return self.run_raw(['--root', self.repo] + list(args), **extra)

    def run_raw(self, args, cwd=None, **extra):
        p = subprocess.run(['bash', SCRIPT] + list(args), env=self.env(**extra), cwd=cwd,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, timeout=120)
        return p.returncode, p.stdout, p.stderr

    def start_script(self, *args, **extra):
        out = open(os.path.join(self.tmp, 'background.out'), 'w')
        p = subprocess.Popen(['bash', SCRIPT, '--root', self.repo] + list(args), env=self.env(**extra),
                             stdout=out, stderr=subprocess.STDOUT)
        out.close()
        self.procs.append(p)
        return p

    def stop_procs(self):
        open(os.path.join(self.stubs, 'release'), 'w').close()
        for p in self.procs:
            try:
                p.wait(timeout=30)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()

    def wait_for(self, path):
        end = time.monotonic() + 60
        while not os.path.exists(path) and time.monotonic() < end:
            time.sleep(0.05)
        self.assertTrue(os.path.exists(path), path)

    def calls(self):
        try:
            with open(os.path.join(self.stubs, 'calls')) as f:
                return f.read().split()
        except FileNotFoundError:
            return []

    def read(self, *parts):
        with open(os.path.join(*parts)) as f:
            return f.read()

    def stamp_path(self):
        return os.path.join(self.repo, 'tmp', 'codedb', 'refresh.stamp')

    def stamp(self):
        fields = {}
        for line in self.read(self.stamp_path()).splitlines():
            key, _, value = line.partition('=')
            fields[key] = value
        return fields

    def classify_paths(self):
        return (os.path.join(self.repo, 'tmp', 'classify.txt'), os.path.join(self.repo, 'tmp', 'classify.json'))

    def last_line(self, text):
        lines = [x for x in text.splitlines() if x.strip()]
        return lines[-1] if lines else ''

    # The refresh.

    def test_success_runs_the_three_steps_and_writes_the_stamp_and_both_classify_files(self):
        status, out, err = self.run_script()
        self.assertEqual(status, EXIT_OK, out + err)
        self.assertEqual(self.calls(), ['capture', 'update', 'classify'])
        self.assertEqual(self.read(self.stubs, 'capture.args').strip(), '')
        self.assertEqual(self.read(self.stubs, 'update.args').split(),
                         ['--root', self.repo, 'update', '--accept-removals'])
        self.assertEqual(self.read(self.stubs, 'classify.args').split(),
                         ['--root', self.repo, '--classify', '--json'])
        for name in ('capture', 'update', 'classify'):
            self.assertEqual(self.read(self.stubs, name + '.pwd').strip(), self.repo)
            self.assertGreaterEqual(int(self.read(self.stubs, name + '.nice')), 15)
        stamp = self.stamp()
        self.assertEqual(stamp['commit'], self.head())
        self.assertTrue(stamp['tree'])
        self.assertRegex(stamp['date'], r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$')
        for name in ('capture', 'update', 'classify'):
            self.assertRegex(stamp[name + '_seconds'], r'^\d+$')
        text, js = self.classify_paths()
        self.assertEqual(json.loads(self.read(js)), classify_document())
        # The text is qualify_unit.py's own rendering of the same document.
        self.assertIn('Paths of 1 units under sources/', self.read(text))
        self.assertIn('iTermFoo', self.read(text))
        self.assertEqual([n for n in os.listdir(os.path.join(self.repo, 'tmp')) if 'partial' in n], [])
        self.assertFalse(os.path.exists(os.path.join(self.repo, 'tmp', 'codedb', 'refresh.incomplete')))
        self.assertIn('SUCCEEDED', self.last_line(out))
        self.assertIn(self.head(), self.last_line(out))
        # Refreshing leaves the tree clean: everything it writes is ignored.
        self.assertEqual(self.git(self.repo, 'status', '--porcelain'), '')

    def test_no_classify_skips_the_classification(self):
        status, out, err = self.run_script('--no-classify')
        self.assertEqual(status, EXIT_OK, out + err)
        self.assertEqual(self.calls(), ['capture', 'update'])
        self.assertEqual(self.stamp()['classify_seconds'], 'skipped')
        for path in self.classify_paths():
            self.assertFalse(os.path.exists(path))

    def test_jobs_limits_the_capture(self):
        status, out, err = self.run_script('--jobs', '4')
        self.assertEqual(status, EXIT_OK, out + err)
        self.assertEqual(self.read(self.stubs, 'capture.args').split(), ['--jobs', '4'])
        status, out, err = self.run_script('--jobs', 'many')
        self.assertEqual(status, EXIT_USAGE, out + err)

    def test_a_failing_capture_stops_the_chain_and_writes_no_stamp(self):
        status, out, err = self.run_script(STUB_CAPTURE_STATUS='1')
        self.assertEqual(status, EXIT_CAPTURE, out + err)
        self.assertEqual(self.calls(), ['capture'])
        self.assertFalse(os.path.exists(self.stamp_path()))
        for path in self.classify_paths():
            self.assertFalse(os.path.exists(path))
        log = os.path.join(self.repo, 'tmp', 'codedb', 'refresh-capture.log')
        self.assertIn('the stand-in fails with status 1', self.read(log))
        verdict = self.last_line(out)
        self.assertIn('FAILED', verdict)
        self.assertIn('capture', verdict)
        self.assertIn(log, verdict)
        # The end of the step's log is shown, so that the error is seen
        # without opening the log.
        self.assertIn('the stand-in fails with status 1', err)

    def test_a_failing_update_leaves_the_previous_stamp_and_classify_files_untouched(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        before = [self.read(p) for p in self.classify_paths()]
        old_stamp = self.read(self.stamp_path())
        self.commit_file('sources/Foo.m', 'two\n')
        self.write_classify(classify_document(trivial_unit='iTermBar'))
        open(os.path.join(self.stubs, 'calls'), 'w').close()
        status, out, err = self.run_script(STUB_UPDATE_STATUS='1')
        self.assertEqual(status, EXIT_UPDATE, out + err)
        self.assertEqual(self.calls(), ['capture', 'update'])
        self.assertEqual([self.read(p) for p in self.classify_paths()], before)
        self.assertEqual(self.read(self.stamp_path()), old_stamp)
        self.assertIn('update', self.last_line(out))
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('update', out)

    def test_a_failed_update_on_an_unchanged_checkout_still_shows_behind(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.assertEqual(self.run_script(STUB_UPDATE_STATUS='1')[0], EXIT_UPDATE)
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('the last refresh failed', out)

    def test_a_failing_classification_replaces_neither_classify_file(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        before = [self.read(p) for p in self.classify_paths()]
        self.write_classify(classify_document(trivial_unit='iTermBar'))
        status, out, err = self.run_script(STUB_CLASSIFY_STATUS='2')
        self.assertEqual(status, EXIT_CLASSIFY, out + err)
        self.assertEqual([self.read(p) for p in self.classify_paths()], before)
        self.assertEqual([n for n in os.listdir(os.path.join(self.repo, 'tmp')) if 'partial' in n], [])

    def test_registry_and_resource_lines_are_a_warning_and_the_refresh_succeeds(self):
        line = 'INCOMPLETE: 2 dynamic reflective call sites in the migration\'s scope are in the database but not in the registry'
        self.write_classify(classify_document(other=[line]))
        status, out, err = self.run_script()
        self.assertEqual(status, EXIT_OK, out + err)
        self.assertTrue(os.path.exists(self.stamp_path()))
        self.assertIn('warning', self.last_line(out))
        self.assertIn(line, out + err)
        self.assertIn(line, self.read(self.classify_paths()[0]))

    def test_an_older_classification_without_the_split_fails_on_any_incomplete_line(self):
        line = 'INCOMPLETE: something'
        self.write_classify(classify_document(other=[line], split=False))
        status, out, err = self.run_script()
        self.assertEqual(status, EXIT_CLASSIFY, out + err)
        self.assertFalse(os.path.exists(self.stamp_path()))

    def test_a_classification_of_an_incomplete_database_is_a_failure(self):
        line = 'INCOMPLETE: 3 of 10 units are not current'
        self.write_classify(classify_document(incomplete=[line]))
        status, out, err = self.run_script()
        self.assertEqual(status, EXIT_CLASSIFY, out + err)
        self.assertIn(line, err)
        self.assertFalse(os.path.exists(self.stamp_path()))
        for path in self.classify_paths():
            self.assertFalse(os.path.exists(path))

    def test_a_commit_during_a_step_is_reported_as_a_changed_checkout(self):
        start = self.head()
        # The step also fails, as the update did when the capture's file
        # list no longer matched the tree; the change is what is reported.
        status, out, err = self.run_script(STUB_UPDATE_ACTION='commit', STUB_UPDATE_STATUS='1')
        self.assertEqual(status, EXIT_CHANGED, out + err)
        now = self.head()
        self.assertNotEqual(start, now)
        self.assertEqual(err.splitlines()[0],
                         'refresh.sh: the checkout changed during the refresh (HEAD was %s, is %s): its results are '
                         'not trusted; run it again' % (start, now))
        self.assertNotIn('the stand-in fails', err)
        self.assertEqual(self.calls(), ['capture', 'update'])
        self.assertFalse(os.path.exists(self.stamp_path()))
        self.assertIn('changed', self.last_line(out))

    def test_a_tracked_file_edited_during_a_step_is_reported_as_a_changed_checkout(self):
        start = self.head()
        status, out, err = self.run_script(STUB_CAPTURE_ACTION='edit')
        self.assertEqual(status, EXIT_CHANGED, out + err)
        self.assertEqual(err.splitlines()[0],
                         'refresh.sh: the checkout changed during the refresh (HEAD was %s, is %s, and files the build '
                         'or the classification reads were edited): its results are not trusted; run it again'
                         % (start, start))
        self.assertEqual(self.calls(), ['capture'])
        self.assertFalse(os.path.exists(self.stamp_path()))

    def test_a_claims_edit_during_a_step_is_not_a_change(self):
        status, out, err = self.run_script(STUB_UPDATE_ACTION='edit-docs')
        self.assertEqual(status, EXIT_OK, out + err)
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_OK, out + err)

    def test_a_docs_only_commit_during_a_step_is_not_a_change_and_the_stamp_has_the_new_head(self):
        start = self.head()
        status, out, err = self.run_script(STUB_UPDATE_ACTION='commit-docs')
        self.assertEqual(status, EXIT_OK, out + err)
        self.assertNotEqual(self.head(), start)
        self.assertEqual(self.stamp()['commit'], self.head())
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_OK, out + err)
        self.assertIn('the stamp matches HEAD', out)

    def test_a_commit_to_a_document_the_classification_reads_during_a_step_is_a_change(self):
        status, out, err = self.run_script(STUB_UPDATE_ACTION='commit-registry')
        self.assertEqual(status, EXIT_CHANGED, out + err)
        self.assertIn('docs/swift-migration/reflective-sites.md', err)

    def test_a_source_file_moved_into_docs_and_committed_during_a_step_is_a_change(self):
        status, out, err = self.run_script(STUB_UPDATE_ACTION='mv-docs-commit')
        self.assertEqual(status, EXIT_CHANGED, out + err)
        self.assertIn('sources/Foo.m', err)

    def test_a_source_file_moved_into_docs_and_staged_during_a_step_is_a_change(self):
        status, out, err = self.run_script(STUB_UPDATE_ACTION='mv-docs-staged')
        self.assertEqual(status, EXIT_CHANGED, out + err)

    def test_an_untracked_file_created_during_a_step_is_not_a_change(self):
        status, out, err = self.run_script(STUB_CLASSIFY_ACTION='untracked')
        self.assertEqual(status, EXIT_OK, out + err)

    def test_a_second_refresh_is_refused_while_one_runs(self):
        first = self.start_script(STUB_CAPTURE_ACTION='hold')
        self.wait_for(os.path.join(self.stubs, 'capture.started'))
        status, out, err = self.run_script()
        self.assertEqual(status, EXIT_RUNNING, out + err)
        self.assertIn('another refresh is running in this checkout', out + err)
        self.assertIn(str(first.pid), out + err)
        self.assertIn('NOT STARTED', self.last_line(out))
        self.assertEqual(self.calls(), ['capture'])
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_RUNNING, out + err)
        self.assertIn('running', self.last_line(out))
        open(os.path.join(self.stubs, 'release'), 'w').close()
        self.assertEqual(first.wait(timeout=60), EXIT_OK, self.read(self.tmp, 'background.out'))
        self.assertEqual(self.run_script('--status')[0], EXIT_OK)

    def test_a_killed_refresh_leaves_no_lock_and_shows_behind(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        first = self.start_script(STUB_CAPTURE_ACTION='hold')
        self.wait_for(os.path.join(self.stubs, 'capture.started'))
        stub_pid = int(self.read(self.stubs, 'capture.started'))
        first.send_signal(signal.SIGKILL)
        first.wait(timeout=30)
        # The stand-in runs in its own process group and outlives the
        # script; it is stopped here so that it cannot run on.
        try:
            os.kill(stub_pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('did not finish', out)
        os.remove(os.path.join(self.stubs, 'capture.started'))
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.assertEqual(self.run_script('--status')[0], EXIT_OK)

    def test_sigterm_stops_the_running_step(self):
        first = self.start_script(STUB_CAPTURE_ACTION='hold')
        started = os.path.join(self.stubs, 'capture.started')
        self.wait_for(started)
        stub_pid = int(self.read(started))
        first.send_signal(signal.SIGTERM)
        self.assertEqual(first.wait(timeout=30), 128 + signal.SIGTERM)
        end = time.monotonic() + 30
        alive = True
        while alive and time.monotonic() < end:
            try:
                os.kill(stub_pid, 0)
                time.sleep(0.05)
            except ProcessLookupError:
                alive = False
        self.assertFalse(alive, 'the step is still running')
        self.assertFalse(os.path.exists(self.stamp_path()))

    def test_an_update_failing_on_parse_errors_forces_those_units_once_and_runs_again(self):
        status, out, err = self.run_script(STUB_UPDATE_ACTION='parse_errors', STUB_FORCE_FIXES='1')
        self.assertEqual(status, EXIT_OK, out + err)
        self.assertEqual(self.read(self.stubs, 'update.calls').splitlines(), [
            '--root %s update --accept-removals' % self.repo,
            '--root %s update --file sources/A.m --force' % self.repo,
            '--root %s update --file sources/B.m --force' % self.repo,
            '--root %s update --accept-removals' % self.repo])
        self.assertEqual(self.calls(), ['capture', 'update', 'update', 'update', 'update', 'classify'])
        self.assertTrue(os.path.exists(self.stamp_path()))

    def test_parse_errors_that_forcing_does_not_clear_fail_the_update_naming_the_units(self):
        status, out, err = self.run_script(STUB_UPDATE_ACTION='parse_errors')
        self.assertEqual(status, EXIT_UPDATE, out + err)
        verdict = self.last_line(out)
        self.assertIn('sources/A.m', verdict)
        self.assertIn('sources/B.m', verdict)
        self.assertNotIn('sources/C.m', verdict)
        self.assertEqual(len(self.read(self.stubs, 'update.calls').splitlines()), 4)
        self.assertFalse(os.path.exists(self.stamp_path()))

    def test_an_update_failing_without_parse_errors_is_not_retried(self):
        status, out, err = self.run_script(STUB_UPDATE_STATUS='1')
        self.assertEqual(status, EXIT_UPDATE, out + err)
        self.assertEqual(self.calls(), ['capture', 'update'])

    def test_a_relative_root_works(self):
        status, out, err = self.run_raw(['--root', 'repo'], cwd=self.tmp)
        self.assertEqual(status, EXIT_OK, out + err)
        self.assertEqual(self.stamp()['commit'], self.head())

    def test_a_missing_root_is_named(self):
        status, out, err = self.run_raw(['--root', os.path.join(self.tmp, 'nowhere')])
        self.assertEqual(status, EXIT_USAGE, out + err)
        self.assertIn(os.path.join(self.tmp, 'nowhere'), err)

    def test_a_git_operation_in_progress_refuses_to_start(self):
        with open(os.path.join(self.repo, '.git', 'MERGE_HEAD'), 'w') as f:
            f.write(self.head() + '\n')
        status, out, err = self.run_script()
        self.assertEqual(status, EXIT_GIT_BUSY, out + err)
        self.assertIn('a merge is in progress', out + err)
        self.assertEqual(self.calls(), [])
        os.remove(os.path.join(self.repo, '.git', 'MERGE_HEAD'))
        os.makedirs(os.path.join(self.repo, '.git', 'rebase-merge'))
        status, out, err = self.run_script()
        self.assertEqual(status, EXIT_GIT_BUSY, out + err)
        self.assertIn('a rebase is in progress', out + err)

    def test_an_untracked_file_in_a_synchronized_test_folder_during_a_step_is_a_change(self):
        status, out, err = self.run_script(STUB_CAPTURE_ACTION='untracked-test')
        self.assertEqual(status, EXIT_CHANGED, out + err)

    def test_unknown_options_are_a_usage_error(self):
        status, out, err = self.run_script('--bogus')
        self.assertEqual(status, EXIT_USAGE, out + err)
        self.assertEqual(self.calls(), [])

    # --status.

    def test_status_without_a_stamp_is_behind(self):
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('no database refresh has succeeded', out)
        self.assertEqual(self.calls(), [])

    def test_status_is_current_after_a_refresh(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_OK, out + err)
        self.assertIn('current', self.last_line(out))
        self.assertEqual(self.calls(), ['capture', 'update', 'classify'])

    def test_status_is_behind_after_a_commit_touching_a_source_file(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.commit_file('sources/Foo.m', 'two\n')
        self.commit_file('sources/Foo.h', 'two\n')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('2 files', out)
        self.assertIn('sources/Foo.m', out)
        self.assertIn('behind', self.last_line(out))

    def test_status_is_not_behind_after_a_commit_touching_only_migration_records(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.commit_file('docs/swift-migration/claims.md', 'more\n')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_OK, out + err)
        self.assertIn('current', self.last_line(out))

    def test_status_is_behind_after_a_change_to_a_document_the_classification_reads(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.commit_file('docs/swift-migration/reflective-sites.md', 'more\n')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('docs/swift-migration/reflective-sites.md', out)

    def test_status_is_behind_after_a_change_to_the_reserved_paths(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.commit_file('docs/swift-migration/reserved.md', 'reserved\n')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('docs/swift-migration/reserved.md', out)

    def test_status_is_behind_after_a_source_file_is_moved_into_docs(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        os.makedirs(os.path.join(self.repo, 'docs', 'moved'))
        self.git(self.repo, 'mv', 'sources/Foo.m', 'docs/moved/Foo.m')
        self.git(self.repo, 'commit', '-q', '-m', 'move')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('sources/Foo.m', out)

    def test_status_in_another_locale_and_time_zone_still_sees_a_running_refresh(self):
        first = self.start_script(STUB_CAPTURE_ACTION='hold', LC_ALL='C', TZ='UTC0')
        self.wait_for(os.path.join(self.stubs, 'capture.started'))
        status, out, err = self.run_script('--status', LC_ALL='fr_FR.UTF-8', TZ='Asia/Tokyo')
        self.assertEqual(status, EXIT_RUNNING, out + err)
        open(os.path.join(self.stubs, 'release'), 'w').close()
        self.assertEqual(first.wait(timeout=60), EXIT_OK, self.read(self.tmp, 'background.out'))

    def test_status_is_behind_for_an_uncommitted_edit_of_a_source_file(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.write_file('sources/Foo.m', 'edited\n', mode='a')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('sources/Foo.m', out)

    def test_status_is_behind_when_an_edit_present_at_the_stamp_was_reverted(self):
        self.write_file('sources/Foo.m', 'edited\n', mode='a')
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.git(self.repo, 'checkout', '--', 'sources/Foo.m')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('sources/Foo.m', out)

    def test_status_is_current_after_an_unrelated_commit_when_a_file_was_edited_at_the_stamp(self):
        self.write_file('sources/Foo.m', 'edited\n', mode='a')
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.commit_file('docs/swift-migration/claims.md', 'more\n')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_OK, out + err)

    def test_status_is_behind_when_a_file_edited_at_the_stamp_is_edited_again(self):
        self.write_file('sources/Foo.m', 'edited\n', mode='a')
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.write_file('sources/Foo.m', 'again\n', mode='a')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('sources/Foo.m', out)

    def test_status_is_current_when_an_edit_at_the_stamp_was_committed_unchanged(self):
        self.write_file('sources/Foo.m', 'edited\n', mode='a')
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.git(self.repo, 'commit', '-q', '-am', 'commit the edit')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_OK, out + err)

    def test_status_is_behind_for_an_untracked_file_in_a_synchronized_test_folder(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        self.write_file('ModernTests/NewTests.swift', 'new\n')
        self.write_file('sources/Untracked.m', 'new\n')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_BEHIND, out + err)
        self.assertIn('ModernTests/NewTests.swift', out)
        self.assertNotIn('sources/Untracked.m', out)

    def test_status_ignores_a_lock_file_left_by_a_dead_holder(self):
        self.assertEqual(self.run_script()[0], EXIT_OK)
        with open(os.path.join(self.repo, 'tmp', 'codedb', 'refresh.lock'), 'w') as f:
            f.write('99999\nrefresh.sh\nMon Jan  1 00:00:00 2024\n')
        status, out, err = self.run_script('--status')
        self.assertEqual(status, EXIT_OK, out + err)
        self.assertEqual(self.run_script()[0], EXIT_OK)


if __name__ == '__main__':
    unittest.main()
