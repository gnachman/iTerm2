#!/bin/bash
# Bring the code database and the unit classification up to date in one
# command, for the Objective-C to Swift migration
# (docs/swift-migration/orchestration.md section 1, step 4; lifecycle.md
# section 5, step 4). It is the only way the migration refreshes them, by
# day, at the start of a session and in the closing checks.
#
# Usage:
#   tools/swift_migration/codedb/refresh.sh [--root DIR] [--no-classify] [--jobs N]
#   tools/swift_migration/codedb/refresh.sh [--root DIR] --status
#
# A refresh runs three steps in the checkout, each only if the one before
# succeeded, each under `nice -n 15` in its own process group, with its
# output in tmp/codedb/refresh-<step>.log:
#   capture   tools/swift_migration/codedb/capture_compile_commands.sh, one
#             clean Development build that records every compile command;
#   update    codedb.py --root DIR update --accept-removals. When it fails
#             and the database records units with parse errors (table tu,
#             diagnostics_errors > 0, read directly and read-only; codedb.py
#             has no command that lists them all), each such file is
#             extracted again once with `update --file PATH --force`, and
#             the update runs once more. That is the remedy bugs.md gives
#             for "codedb.py update never re-extracts a unit recorded with
#             parse errors". Only a failure after that is a failure of the
#             step, and the verdict names the files still in error;
#   classify  qualify_unit.py --root DIR --classify --json, run once; its
#             document is written to tmp/classify.json and rendered by
#             qualify_unit.py's own text form into tmp/classify.txt.
#             Both are written under temporary names and moved into place
#             only when every step has succeeded and the checkout is
#             unchanged, so a failed refresh never leaves a classification
#             that looks new. The step fails when the document's
#             database_rows_incomplete list is not empty (the database's
#             own rows still are not current after a successful update), or,
#             for a qualify_unit.py that does not split its incomplete
#             lines, when database_incomplete is not empty. The lines of
#             registry_or_resources_incomplete (the reflective-site registry
#             is behind the code, or a resource file cannot be read) are
#             not something a refresh can change: they are printed as a
#             warning, stay in tmp/classify.txt, and the refresh succeeds.
#             --no-classify skips this step and leaves both files as they
#             were.
#
# No file the build or the classification reads may change while a
# refresh runs: the capture's file list, the database and the
# classification all describe those files as they were when it started,
# and a step that fails because of a change reports an error far from its
# cause. Those files are everything except docs/ and .claude/, plus
# docs/swift-migration/reflective-sites.md,
# docs/swift-migration/hot-paths.md and docs/swift-migration/reserved.md,
# which qualify_unit.py reads; one function (relevant() below) decides
# this for the change check and for --status. Editing claims.md or committing a change only to such
# documents during a refresh is therefore allowed. The script records at
# the start HEAD's commit and a SHA-256 digest of the content of every
# relevant file that differs from HEAD (tracked files, a changed submodule
# commit included but not a submodule's own working tree) and of every
# untracked, not ignored file under ModernTests/ and PerformanceTests/.
# Those two are file-system-synchronized groups in the Xcode project, so
# every file in them is compiled whether git tracks it or not; other
# untracked files are left out, since elsewhere the build compiles only
# files the tracked project file names. After every step it compares: HEAD
# may have moved, but only by commits that change no relevant file
# (`git diff --name-only START HEAD`), and the digest must be the same. If
# not, the script stops at once with status 3, and the first line it
# writes to stderr is
#   refresh.sh: the checkout changed during the refresh (HEAD was X, is Y):
#   its results are not trusted; run it again
# instead of whatever error the step produced, followed by the relevant
# files committed meanwhile. The comparison is made between steps, so a
# change made and undone again within one step is not seen. Git runs with
# GIT_OPTIONAL_LOCKS=0, so that reading the state never takes the index
# lock that a concurrent git command in the checkout needs.
# A refresh does not start while a rebase, merge, cherry-pick, revert or
# bisect is in progress in the checkout (status 5), as nightly_start.sh
# tells: the state files git keeps for them (rebase-merge, rebase-apply,
# MERGE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD, BISECT_LOG).
#
# On success the stamp tmp/codedb/refresh.stamp is written (key=value
# lines: commit, the commit at the end of the refresh, which the change
# check found to hold the same relevant files as the start; tree, date, and
# capture_seconds, update_seconds and classify_seconds, the last `skipped`
# with --no-classify; then one `dirty=CONTENT PATH` line for each tracked
# file that differed from HEAD and each untracked file in the two
# synchronized folders, CONTENT being its git blob hash, a submodule's
# checked-out commit, or `absent`). On any failure no stamp is written and
# the previous one is left, and tmp/codedb/refresh.incomplete says why (it
# is written when a refresh starts and removed when one succeeds, so a
# refresh killed outright also leaves it), so that --status reports the
# database as behind.
#
# Only one refresh runs in a checkout at a time. The lock is
# tmp/codedb/refresh.lock, an flock(2) taken without waiting by the code
# database's own lock code (codedb.py's Lock and hold_lock_and_exec: the
# script runs itself again through them with the lock held on fd 9). The
# kernel releases it when the holder dies in any way, so a dead holder
# leaves no lock. It is not the database's lock tmp/codedb/codedb.lock,
# which each step takes for itself. The steps do not inherit fd 9, so a
# step's process left running cannot hold the refresh lock. --status does
# not touch the lock: it reports a refresh as running when the lock file
# names a live process whose start time is the one recorded there, so
# asking can never make a refresh that is starting fail to take the lock.
#
# SIGINT, SIGTERM and SIGHUP send SIGTERM to the running step's process
# group (the capture and codedb.py stop their own children on it) and the
# script exits 128 plus the signal, writing no stamp. As for the capture: if
# the script is started in the background by a non-interactive shell,
# SIGINT is ignored from the start (the shell ignores it for background
# jobs, and an ignored signal cannot be trapped); use TERM or HUP.
#
# --status reads and changes nothing, builds nothing, and takes about a
# second. It prints whether a refresh is running now, then compares the
# stamp with the checkout. The stamp is current when its commit and digest
# are HEAD's and the current digest. Otherwise each file that may
# differ (`git diff --name-only STAMP HEAD`, the tracked files that now
# differ from HEAD, the untracked files of the two synchronized folders,
# and the stamp's dirty files) is listed when its content now differs from
# its content at the stamp (the stamp's dirty line, or else its blob in the
# stamp's commit) and the build or the classification reads it (the same
# relevant() as the change check). When nothing is listed, the database is still
# current. A stamp whose refresh skipped the classification says so on its
# own line; the status is about the database. A refresh that failed or did
# not finish since the stamp makes the status behind whatever the files.
#
#   --root DIR     The checkout to refresh (default: the one this script is
#                  in). The steps are that checkout's own tools; the lock
#                  helper and the text rendering of the classification are
#                  this script's checkout's codedb.py and qualify_unit.py.
#   --no-classify  Run the capture and the update only.
#   --jobs N       Passed to the capture: at most N build tasks at once.
#   --status       Print the state described above; run no step.
#   -h, --help     Print this text.
#
# Environment (the tests' stand-ins): REFRESH_CAPTURE, REFRESH_UPDATE and
# REFRESH_CLASSIFY each name one executable that replaces that step's
# command. It is called with the arguments the real command gets after its
# program (none for the capture, or `--jobs N`; `--root DIR update
# --accept-removals`, and `--root DIR update --file PATH --force` for a
# forced file; `--root DIR --classify --json`), in DIR, under nice, and the
# classify one prints the JSON document.
#
# The capture is a clean build, so a refresh is a heavy job
# (orchestration.md section 3, "Heavy jobs and the machine"). The script
# prints its pid first, so that a caller that runs it in the background can
# wait for it with a bound:
#   python3 tools/swift_migration/suite_guard.py wait --pid PID --seconds 540
# Its last line on standard output is always one verdict line beginning
# `refresh.sh: verdict:` (with --status, `refresh.sh: status:`), except
# after a usage error, which prints only to standard error.
#
# Exit status:
#   0    the refresh succeeded; with --status, the database is current
#   1    the stamp could not be written after every step succeeded
#   2    usage error, DIR is not the top of a git checkout, or git or
#        python3 cannot be run
#   3    the checkout changed during the refresh; nothing is trusted
#   4    --status only: the database is behind
#   5    a rebase, merge, cherry-pick, revert or bisect is in progress; the
#        refresh did not start
#   11   the capture failed; 12 the update failed; 13 the classification
#        failed or could not be moved into place (the verdict names the
#        step and its log)
#   75   another refresh holds the lock: the refresh did not start, or,
#        with --status, a refresh is running now
#   128 plus the signal, when the refresh was interrupted

set -u

HERE="$(cd "$(dirname "$0")" && pwd)" || exit 2
SELF="$HERE/$(basename "$0")"
TOOLS="$(cd "$HERE/.." && pwd)" || exit 2
DEFAULT_ROOT="$(cd "$HERE/../../.." && pwd)" || exit 2

EXIT_OK=0
EXIT_STAMP=1
EXIT_USAGE=2
EXIT_CHANGED=3
EXIT_BEHIND=4
EXIT_GIT_BUSY=5
EXIT_CAPTURE=11
EXIT_UPDATE=12
EXIT_CLASSIFY=13
EXIT_RUNNING=75

usage() {
    sed -n '2,/^$/s/^# \{0,1\}//p' "$SELF"
}

GIVEN_ROOT="$DEFAULT_ROOT"
MODE=refresh
CLASSIFY=1
JOBS_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --root)
            [ $# -ge 2 ] || { echo "refresh.sh: --root needs a directory" >&2; exit $EXIT_USAGE; }
            GIVEN_ROOT="$2"
            shift ;;
        --no-classify) CLASSIFY=0 ;;
        --jobs)
            case "${2:-}" in
                ''|*[!0-9]*|0*) echo "refresh.sh: --jobs takes a whole number of at least 1, not '${2:-}'" >&2
                                exit $EXIT_USAGE ;;
            esac
            JOBS_ARGS=(--jobs "$2")
            shift ;;
        --status) MODE=status ;;
        *) echo "refresh.sh: unknown argument: $1 (see --help)" >&2; exit $EXIT_USAGE ;;
    esac
    shift
done
if [ "$MODE" = status ] && { [ "$CLASSIFY" = 0 ] || [ ${#JOBS_ARGS[@]} -gt 0 ]; }; then
    echo "refresh.sh: --status takes neither --no-classify nor --jobs" >&2
    exit $EXIT_USAGE
fi
for tool in git python3; do
    command -v "$tool" > /dev/null 2>&1 || { echo "refresh.sh: $tool cannot be found" >&2; exit $EXIT_USAGE; }
done
if ! ROOT="$(cd "$GIVEN_ROOT" 2>/dev/null && pwd -P)"; then
    echo "refresh.sh: no such directory: $GIVEN_ROOT" >&2
    exit $EXIT_USAGE
fi
cd "$ROOT" || exit $EXIT_USAGE
if [ "$(git rev-parse --show-toplevel 2>/dev/null)" != "$ROOT" ]; then
    echo "refresh.sh: $ROOT is not the top of a git checkout" >&2
    exit $EXIT_USAGE
fi

export GIT_OPTIONAL_LOCKS=0
OUT="$ROOT/tmp/codedb"
STAMP="$OUT/refresh.stamp"
INCOMPLETE="$OUT/refresh.incomplete"
LOCK="$OUT/refresh.lock"
DB="$OUT/codedb.sqlite"
CLASSIFY_TXT="$ROOT/tmp/classify.txt"
CLASSIFY_JSON="$ROOT/tmp/classify.json"

# The checkout's state and the other questions this script asks, in one
# Python program run with a command: digest, dirty, changed STAMP_COMMIT
# STAMP_FILE, holder LOCK, parse-errors DB, check-classify TOOLS JSON TXT.
read -r -d '' STATE_PY <<'EOF'
import hashlib, json, os, sqlite3, subprocess, sys

# The file-system-synchronized groups of the Xcode project: every file in
# them is compiled, tracked or not.
SYNCED = ('ModernTests', 'PerformanceTests')
# The documents qualify_unit.py reads.
READ_DOCUMENTS = ('docs/swift-migration/reflective-sites.md', 'docs/swift-migration/hot-paths.md',
                  'docs/swift-migration/reserved.md')


def relevant(path):
    """Whether the build or the classification reads path: everything but
    docs/ and .claude/, and the three documents qualify_unit.py reads. The
    change check during a refresh and --status both decide with this."""
    if path in READ_DOCUMENTS:
        return True
    return not (path.startswith('docs/') or path.startswith('.claude/'))


def git(*args, data=None):
    return subprocess.run(['git'] + list(args), input=data, stdout=subprocess.PIPE, check=True).stdout


def names(raw):
    return [x.decode('utf-8', 'surrogateescape') for x in raw.split(b'\0') if x]


def tracked_dirty():
    return names(git('diff', 'HEAD', '--name-only', '-z', '--no-renames', '--no-ext-diff',
                     '--ignore-submodules=dirty'))


def untracked():
    return names(git('ls-files', '--others', '--exclude-standard', '-z', '--', *SYNCED))


def contents(paths):
    """The content of each path in the working tree: its blob hash, a
    submodule's checked-out commit, or 'absent'."""
    out = {}
    files = []
    for p in paths:
        if os.path.islink(p) or os.path.isfile(p):
            files.append(p)
        elif os.path.isdir(p) and os.path.exists(os.path.join(p, '.git')):
            r = subprocess.run(['git', '-C', p, 'rev-parse', 'HEAD'], stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL)
            out[p] = r.stdout.decode().strip() or 'absent'
        else:
            out[p] = 'absent'
    if files:
        hashes = git('hash-object', '--stdin-paths', data=''.join(f + '\n' for f in files).encode()).split()
        out.update(zip(files, (h.decode() for h in hashes)))
    return out


def stamp_dirty(path):
    found = {}
    with open(path) as f:
        for line in f:
            if line.startswith('dirty='):
                content, _, name = line[len('dirty='):].rstrip('\n').partition(' ')
                found[name] = content
    return found


def in_commit(commit, paths):
    """The blob or submodule commit of each path in commit, or 'absent'."""
    if not paths:
        return {}
    raw = git('cat-file', '--batch-check=%(objectname) %(objecttype)',
              data=''.join('%s:%s\n' % (commit, p) for p in paths).encode()).decode().splitlines()
    out = {}
    for p, line in zip(paths, raw):
        parts = line.split()
        out[p] = parts[0] if len(parts) == 2 and parts[1] in ('blob', 'commit') else 'absent'
    return out


cmd, args = sys.argv[1], sys.argv[2:]
if cmd == 'digest':
    # The content of every file the build or the classification reads that
    # differs from HEAD (tracked) or that git does not track (in the
    # synchronized folders).
    h = hashlib.sha256()
    paths = [p for p in set(tracked_dirty()) | set(untracked()) if relevant(p)]
    for p, c in sorted(contents(paths).items()):
        h.update(('%s %s\0' % (c, p)).encode('utf-8', 'surrogateescape'))
    print(h.hexdigest())
elif cmd == 'moved':
    # The files the build or the classification reads that differ between
    # two commits.
    for p in names(git('diff', '--name-only', '-z', '--no-renames', '--no-ext-diff', args[0], args[1], '--')):
        if relevant(p):
            print(p)
elif cmd == 'dirty':
    for p, c in sorted(contents(tracked_dirty() + untracked()).items()):
        print('%s %s' % (c, p))
elif cmd == 'changed':
    commit, stamp = args
    before = stamp_dirty(stamp)
    candidates = sorted(set(names(git('diff', '--name-only', '-z', '--no-renames', '--no-ext-diff', commit,
                                      'HEAD', '--')))
                        | set(tracked_dirty()) | set(untracked()) | set(before))
    at_stamp = in_commit(commit, [p for p in candidates if p not in before])
    at_stamp.update(before)
    now = contents(candidates)
    for p in candidates:
        if relevant(p) and now[p] != at_stamp[p]:
            print(p)
elif cmd == 'holder':
    # A refresh is running when the lock file names a live process with the
    # start time it recorded, or a live process whose command is refresh.sh
    # (so that a start time written in another form never hides a running
    # refresh; the worst case is waiting for nothing). The lock itself is
    # not touched, so asking can never make a refresh that is starting fail
    # to take it. The file of a holder that died stays behind, but names a
    # process that is gone or started at another time. ps runs in the C
    # locale and UTC, as codedb.py's PS_ENV, which wrote the start time.
    ps_env = dict(os.environ, LC_ALL='C', TZ='UTC0')
    try:
        with open(args[0]) as f:
            lines = f.read().splitlines()
        pid = int(lines[0])
        start = lines[2] if len(lines) > 2 else ''
    except (OSError, ValueError, IndexError):
        sys.exit(1)
    now = ' '.join(subprocess.run(['ps', '-o', 'lstart=', '-p', str(pid)], stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, env=ps_env).stdout.decode().split())
    if not now:
        sys.exit(1)
    if now != ' '.join(start.split()):
        command = subprocess.run(['ps', '-o', 'command=', '-p', str(pid)], stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, env=ps_env).stdout.decode()
        if 'refresh.sh' not in command:
            sys.exit(1)
    print('pid %d, started %s' % (pid, now))
    sys.exit(0)
elif cmd == 'parse-errors':
    if not os.path.exists(args[0]):
        sys.exit(0)
    try:
        con = sqlite3.connect('file:%s?mode=ro' % args[0], uri=True)
        rows = con.execute('SELECT DISTINCT main_file FROM tu WHERE diagnostics_errors > 0 ORDER BY main_file')
        for (f,) in rows:
            print(f)
    except sqlite3.Error as e:
        print('refresh.sh: cannot list the units with parse errors in %s: %s' % (args[0], e), file=sys.stderr)
elif cmd == 'check-classify':
    # Exit 1 with the reason when the document is refused; otherwise write
    # its text form and print the warning lines, if any.
    tools, json_path, txt_path = args
    try:
        with open(json_path) as f:
            d = json.load(f)
    except (OSError, ValueError) as e:
        print('its output is not a JSON document: %s' % e)
        sys.exit(1)
    if 'database_rows_incomplete' in d:
        refused, warnings = d['database_rows_incomplete'], d.get('registry_or_resources_incomplete', [])
    else:
        refused, warnings = d.get('database_incomplete', []), []
    if refused:
        print('it says the database is incomplete after a successful update:')
        for line in refused:
            print('  ' + line)
        sys.exit(1)
    sys.path.insert(0, tools)
    import qualify_unit
    with open(txt_path, 'w') as out:
        qualify_unit.write_classify(d, out)
    for line in warnings:
        print(line)
EOF

state() {
    python3 -B -c "$STATE_PY" "$@"
}

head_commit() {
    git rev-parse --verify -q HEAD 2>/dev/null || echo none
}

# Names the git operation in progress in the checkout, if any.
git_operation() {
    local p
    for p in rebase-merge rebase-apply; do
        if [ -d "$(git rev-parse --git-path "$p")" ]; then echo "a rebase is in progress"; return; fi
    done
    [ ! -e "$(git rev-parse --git-path MERGE_HEAD)" ] || { echo "a merge is in progress"; return; }
    [ ! -e "$(git rev-parse --git-path CHERRY_PICK_HEAD)" ] || { echo "a cherry-pick is in progress"; return; }
    [ ! -e "$(git rev-parse --git-path REVERT_HEAD)" ] || { echo "a revert is in progress"; return; }
    [ ! -e "$(git rev-parse --git-path BISECT_LOG)" ] || { echo "a bisect is in progress"; return; }
}

stamp_field() {
    sed -n "s/^$1=//p" "$STAMP" | head -1
}

if [ "$MODE" = status ]; then
    if holder="$(state holder "$LOCK")"; then
        echo "refresh.sh: a database refresh is running now in $ROOT ($holder); wait for it before qualifying or briefing units, querying the database, landing or rebasing"
        echo "refresh.sh: status: running"
        exit $EXIT_RUNNING
    fi
    busy="$(git_operation)"
    [ -z "$busy" ] || echo "refresh.sh: note: $busy in $ROOT, so a refresh would not start"
    if [ ! -f "$STAMP" ]; then
        echo "refresh.sh: no database refresh has succeeded in $ROOT (no stamp $STAMP)"
        echo "refresh.sh: status: behind"
        exit $EXIT_BEHIND
    fi
    s_commit="$(stamp_field commit)"
    s_tree="$(stamp_field tree)"
    s_classify="$(stamp_field classify_seconds)"
    [ "$s_classify" = skipped ] || s_classify="$s_classify s"
    echo "refresh.sh: the last successful database refresh: commit $s_commit, $(stamp_field date) (capture $(stamp_field capture_seconds) s, update $(stamp_field update_seconds) s, classify $s_classify)"
    if [ "$s_classify" = skipped ]; then
        echo "refresh.sh: that refresh skipped the classification, so tmp/classify.txt and tmp/classify.json are older than the database"
    fi
    if [ -f "$INCOMPLETE" ]; then
        echo "refresh.sh: $(head -1 "$INCOMPLETE")"
        echo "refresh.sh: status: behind (since the stamp a database refresh failed or did not finish)"
        exit $EXIT_BEHIND
    fi
    head_now="$(head_commit)"
    if [ "$s_commit" = "$head_now" ] && [ "$s_tree" = "$(state digest)" ]; then
        echo "refresh.sh: status: current (the stamp matches HEAD $head_now and the files the build and the classification read)"
        exit $EXIT_OK
    fi
    if ! git cat-file -e "$s_commit^{commit}" 2>/dev/null; then
        echo "refresh.sh: the stamp's commit $s_commit is no longer in the repository, so what changed since cannot be listed"
        echo "refresh.sh: status: behind"
        exit $EXIT_BEHIND
    fi
    if ! changed="$(state changed "$s_commit" "$STAMP")"; then
        echo "refresh.sh: what changed since the stamp could not be listed"
        echo "refresh.sh: status: behind"
        exit $EXIT_BEHIND
    fi
    if [ -z "$changed" ]; then
        echo "refresh.sh: status: current (since the stamp's commit $s_commit no file that the build or the classification reads changed; HEAD is $head_now)"
        exit $EXIT_OK
    fi
    count=$(printf '%s\n' "$changed" | wc -l | tr -d ' ')
    files=files
    [ "$count" != 1 ] || files=file
    echo "refresh.sh: $count $files that the build or the classification reads changed since the stamp ($s_commit..HEAD $head_now, and the working tree):"
    printf '%s\n' "$changed" | head -20 | sed 's/^/  /'
    [ "$count" -le 20 ] || echo "  (and $((count - 20)) more)"
    echo "refresh.sh: status: behind ($count $files changed since the stamp)"
    exit $EXIT_BEHIND
fi

busy="$(git_operation)"
if [ -n "$busy" ]; then
    echo "refresh.sh: $busy in $ROOT; finish or abort it first" >&2
    echo "refresh.sh: verdict: NOT STARTED: $busy"
    exit $EXIT_GIT_BUSY
fi
mkdir -p "$OUT" || exit $EXIT_USAGE

# Take the refresh lock by running this script again through the code
# database's lock code (see the header), with the root made absolute.
# hold_lock_and_exec sets CODEDB_LOCK_TOKEN to the pid it keeps; the token
# is removed again so that no step mistakes it for its own.
if [ "${REFRESH_LOCK_TOKEN:-}" != "$$" ]; then
    OPTS=(--root "$ROOT" ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"})
    [ "$CLASSIFY" = 1 ] || OPTS+=(--no-classify)
    exec python3 -B - "$HERE" "$LOCK" "$SELF" "${OPTS[@]}" <<'EOF'
import os, sys
here, lock_path, program = sys.argv[1], sys.argv[2], sys.argv[3:]
sys.path.insert(0, here)
import codedb
os.environ['REFRESH_LOCK_TOKEN'] = str(os.getpid())
try:
    codedb.hold_lock_and_exec(codedb.Paths(os.getcwd(), lock=lock_path), 'refresh.sh',
                              ['/bin/bash'] + program)
except codedb.CodeDBLocked as e:
    print('refresh.sh: another refresh is running in this checkout: %s' % e, file=sys.stderr)
    print('refresh.sh: verdict: NOT STARTED: another refresh is running in this checkout')
    sys.exit(75)
except (codedb.CodeDBError, OSError) as e:
    print('refresh.sh: cannot take the lock %s: %s' % (lock_path, e), file=sys.stderr)
    print('refresh.sh: verdict: NOT STARTED: the lock could not be taken')
    sys.exit(2)
EOF
fi
unset REFRESH_LOCK_TOKEN CODEDB_LOCK_TOKEN

echo "refresh.sh: pid $$"

START_HEAD="$(head_commit)"
END_HEAD="$START_HEAD"
if ! START_TREE="$(state digest)"; then
    echo "refresh.sh: verdict: NOT STARTED: the checkout's state could not be read"
    exit $EXIT_USAGE
fi
echo "refresh.sh: refreshing $ROOT at $START_HEAD (tree digest $START_TREE)"
printf 'the last refresh did not finish: it started at %s on %s and was stopped before writing a verdict\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$START_HEAD" > "$INCOMPLETE"

PARTIAL_JSON="$CLASSIFY_JSON.partial-$$"
PARTIAL_TXT="$CLASSIFY_TXT.partial-$$"
STEP_PID=""
cleanup() {
    rm -f "$PARTIAL_JSON" "$PARTIAL_TXT" "$STAMP.partial-$$"
}
trap cleanup EXIT
on_signal() {
    trap '' INT TERM HUP
    if [ -n "$STEP_PID" ]; then
        echo "refresh.sh: signal received; stopping the running step (process group $STEP_PID)" >&2
        kill -TERM -- "-$STEP_PID" 2>/dev/null
        wait "$STEP_PID" 2>/dev/null
    fi
    printf 'the last refresh was interrupted by a signal at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$INCOMPLETE"
    echo "refresh.sh: verdict: INTERRUPTED: no stamp written; the database is behind"
    exit "$1"
}
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap 'on_signal 129' HUP

# Ends the refresh as failed: the exit status, the reason for the
# incomplete marker, and the verdict.
fail() {
    printf 'the last refresh failed: %s\n' "$2" > "$INCOMPLETE"
    echo "refresh.sh: verdict: FAILED: $3"
    exit "$1"
}

fail_changed() {
    local step="$1" status="$2" head_now="$3" moved="$4" how
    if [ -z "$moved" ]; then
        how="HEAD was $START_HEAD, is $head_now, and files the build or the classification reads were edited"
    else
        how="HEAD was $START_HEAD, is $head_now"
    fi
    local message="the checkout changed during the refresh ($how): its results are not trusted; run it again"
    echo "refresh.sh: $message" >&2
    echo "refresh.sh: (noticed after the $step step, which exited with status $status; its log is $OUT/refresh-$step.log)" >&2
    [ -z "$moved" ] || printf '%s\n' "$moved" | head -20 | sed 's/^/refresh.sh:   committed meanwhile: /' >&2
    fail $EXIT_CHANGED "$message" "the checkout changed during the refresh; no stamp written"
}

# Runs one command of a step: the step's name, then the command. Its output
# goes to the step's log (appended to with APPEND=1), its standard output
# to the partial classification for the classify step. Sets STEP_STATUS
# and adds the seconds to STEP_SECONDS. Stops the refresh if the checkout
# changed meanwhile.
APPEND=0
STEP_SECONDS=0
run_cmd() {
    local name="$1"
    shift
    local log="$OUT/refresh-$name.log" started=$SECONDS
    [ "$APPEND" = 1 ] || : > "$log"
    # Job control puts the command in its own process group, which the
    # signal handler stops as a whole. A trapped signal interrupts wait at
    # once.
    set -m
    if [ "$name" = classify ]; then
        nice -n 15 "$@" 9>&- < /dev/null > "$PARTIAL_JSON" 2>> "$log" &
    else
        nice -n 15 "$@" 9>&- < /dev/null >> "$log" 2>&1 &
    fi
    STEP_PID=$!
    set +m
    wait "$STEP_PID"
    STEP_STATUS=$?
    STEP_PID=""
    STEP_SECONDS=$((STEP_SECONDS + SECONDS - started))
    check_unchanged "$name"
}

# Stops the refresh when a file the build or the classification reads
# changed since the start: through a commit (HEAD may move, but only by
# commits that change no such file) or in the working tree.
check_unchanged() {
    local name="$1" head_now moved="" tree_now
    head_now="$(head_commit)"
    if [ "$head_now" != "$START_HEAD" ]; then
        moved="$(state moved "$START_HEAD" "$head_now")" || moved="(the commits could not be compared)"
    fi
    tree_now="$(state digest)" || tree_now=unreadable
    if [ -n "$moved" ] || [ "$tree_now" != "$START_TREE" ]; then
        fail_changed "$name" "$STEP_STATUS" "$head_now" "$moved"
    fi
    END_HEAD="$head_now"
}

# Shows the end of a failed step's log and fails the refresh: the step's
# name, its exit status for the refresh, and an optional note for the
# verdict.
fail_step() {
    local name="$1" failure="$2" note="${3:-}"
    local log="$OUT/refresh-$name.log"
    echo "refresh.sh: $name: FAILED with exit status $STEP_STATUS after $STEP_SECONDS s; the end of its log $log:" >&2
    tail -n 20 "$log" | sed 's/^/  /' >&2
    fail "$failure" "the $name step exited with status $STEP_STATUS (log: $log)${note:+; $note}" \
        "at the $name step (exit status $STEP_STATUS; log: $log${note:+; $note}); no stamp written, the database is behind and tmp/classify.* are unchanged"
}

DURATIONS=()
started_step() {
    echo "refresh.sh: $1: started (log: $OUT/refresh-$1.log)"
    APPEND=0
    STEP_SECONDS=0
}
succeeded_step() {
    echo "refresh.sh: $1: succeeded in $STEP_SECONDS s"
    DURATIONS+=("${1}_seconds=$STEP_SECONDS")
}

started_step capture
run_cmd capture "${REFRESH_CAPTURE:-$ROOT/tools/swift_migration/codedb/capture_compile_commands.sh}" \
    ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"}
[ "$STEP_STATUS" = 0 ] || fail_step capture $EXIT_CAPTURE
succeeded_step capture

if [ -n "${REFRESH_UPDATE:-}" ]; then
    UPDATE=("$REFRESH_UPDATE")
else
    UPDATE=(python3 -B "$ROOT/tools/swift_migration/codedb/codedb.py")
fi
started_step update
run_cmd update "${UPDATE[@]}" --root "$ROOT" update --accept-removals
if [ "$STEP_STATUS" != 0 ]; then
    ERROR_UNITS="$(state parse-errors "$DB")"
    if [ -n "$ERROR_UNITS" ]; then
        echo "refresh.sh: update: exited with status $STEP_STATUS with $(printf '%s\n' "$ERROR_UNITS" | wc -l | tr -d ' ') files recorded with parse errors; extracting each again once (update --file PATH --force), then updating once more"
        APPEND=1
        while IFS= read -r unit; do
            run_cmd update "${UPDATE[@]}" --root "$ROOT" update --file "$unit" --force
        done <<< "$ERROR_UNITS"
        run_cmd update "${UPDATE[@]}" --root "$ROOT" update --accept-removals
        if [ "$STEP_STATUS" != 0 ]; then
            LEFT="$(state parse-errors "$DB")"
            if [ -n "$LEFT" ]; then
                n=$(printf '%s\n' "$LEFT" | wc -l | tr -d ' ')
                shown="$(printf '%s\n' "$LEFT" | head -10 | tr '\n' ' ' | sed 's/ $//')"
                [ "$n" -le 10 ] || shown="$shown and $((n - 10)) more"
                fail_step update $EXIT_UPDATE "files still recorded with parse errors after forcing each once: $shown"
            fi
            fail_step update $EXIT_UPDATE "after forcing the files recorded with parse errors once"
        fi
    else
        fail_step update $EXIT_UPDATE
    fi
fi
succeeded_step update

if [ "$CLASSIFY" = 1 ]; then
    started_step classify
    if [ -n "${REFRESH_CLASSIFY:-}" ]; then
        run_cmd classify "$REFRESH_CLASSIFY" --root "$ROOT" --classify --json
    else
        run_cmd classify python3 -B "$ROOT/tools/swift_migration/qualify_unit.py" --root "$ROOT" --classify --json
    fi
    [ "$STEP_STATUS" = 0 ] || fail_step classify $EXIT_CLASSIFY
    log="$OUT/refresh-classify.log"
    # The document must say the database's own rows are complete; its text
    # form is qualify_unit.py's own rendering of it.
    if ! checked="$(state check-classify "$TOOLS" "$PARTIAL_JSON" "$PARTIAL_TXT")"; then
        echo "refresh.sh: classify: FAILED: $checked" >&2
        fail $EXIT_CLASSIFY "the classification was refused ($(printf '%s\n' "$checked" | head -1))" \
            "at the classify step (its document was refused: see above; log: $log); no stamp written, the database is behind and tmp/classify.* are unchanged"
    fi
    WARNINGS="$checked"
    if ! mv -f "$PARTIAL_JSON" "$CLASSIFY_JSON" || ! mv -f "$PARTIAL_TXT" "$CLASSIFY_TXT"; then
        fail $EXIT_CLASSIFY "the classification could not be moved into place" \
            "at the classify step (its output could not be moved into place); no stamp written"
    fi
    succeeded_step classify
    echo "refresh.sh: wrote $CLASSIFY_TXT and $CLASSIFY_JSON"
else
    WARNINGS=""
    DURATIONS+=("classify_seconds=skipped")
fi

# The stamp names the commit at the end, whose files the build and the
# classification read were checked to be the ones at the start.
if ! END_DIRTY="$(state dirty)"; then
    fail $EXIT_STAMP "the working tree could not be read for the stamp" "the stamp could not be written"
fi
if ! {
    echo "commit=$END_HEAD"
    echo "tree=$START_TREE"
    echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\n' "${DURATIONS[@]}"
    [ -z "$END_DIRTY" ] || printf '%s\n' "$END_DIRTY" | sed 's/^/dirty=/'
} > "$STAMP.partial-$$" || ! mv -f "$STAMP.partial-$$" "$STAMP"; then
    fail $EXIT_STAMP "the stamp $STAMP could not be written" "the stamp $STAMP could not be written"
fi
rm -f "$INCOMPLETE"
if [ -n "$WARNINGS" ]; then
    n=$(printf '%s\n' "$WARNINGS" | wc -l | tr -d ' ')
    echo "refresh.sh: warning: the classification lists $n incomplete lines that a database refresh cannot change (the reflective-site registry or the resource files); they stay in $CLASSIFY_TXT:"
    printf '%s\n' "$WARNINGS" | sed 's/^/  /'
    echo "refresh.sh: verdict: SUCCEEDED, with a warning ($n registry or resource lines in tmp/classify.txt): the code database is current with $END_HEAD; stamp $STAMP"
else
    echo "refresh.sh: verdict: SUCCEEDED: the code database is current with $END_HEAD; stamp $STAMP"
fi
exit $EXIT_OK
