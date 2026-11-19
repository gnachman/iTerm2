#!/bin/bash
# Memory watchdog for the code database tools.
#
# usage: guard.sh [--limit-kb N] [--peak-file FILE] -- <command...>
#
# Runs the command and polls the resident memory of its whole process tree.
# If the total exceeds the limit (default 4 GB) the tree is killed with
# SIGKILL and guard.sh exits 137. Otherwise it exits with the command's
# status. With --peak-file, the highest total seen (in KB) is written there.
# `ulimit -d` and `ulimit -v` do not work on this macOS, hence the polling.
#
# If guard.sh itself gets SIGINT, SIGTERM or SIGHUP, it kills the whole tree
# it started and exits 130, 143 or 129.
#
# SIGINT is ignored when guard.sh is started in the background by a
# non-interactive shell (`guard.sh -- cmd &` in a script): that shell starts
# background jobs with SIGINT ignored, and a signal ignored on entry cannot be
# trapped. Ctrl-C then reaches neither guard.sh nor its command. Send TERM or
# HUP instead; those always work.

LIMIT_KB=4000000
PEAK_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --limit-kb) LIMIT_KB="$2"; shift 2 ;;
        --peak-file) PEAK_FILE="$2"; shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
done
if [ $# -eq 0 ]; then
    echo "usage: guard.sh [--limit-kb N] [--peak-file FILE] -- <command...>" >&2
    exit 2
fi

# Sum the RSS of PID and all its descendants from one `ps` snapshot.
tree_rss() {
    ps -A -o pid=,ppid=,rss= | awk -v root="$1" '
        { parent[$1] = $2; rss[$1] = $3 }
        END {
            total = 0
            for (p in rss) {
                q = p
                while (q != "" && q != 0 && q != 1) {
                    if (q == root) { total += rss[p]; break }
                    q = parent[q]
                }
            }
            print total
        }'
}

# Stop each process before listing its children, so that none can start a new
# one between the listing and the kill.
kill_tree() {
    local p
    kill -STOP "$1" 2>/dev/null
    for p in $(pgrep -P "$1"); do kill_tree "$p"; done
    kill -9 "$1" 2>/dev/null
}

PID=""
on_signal() {
    trap '' INT TERM HUP
    if [ -n "$PID" ]; then
        echo "guard: signal received; killing $CMD (pid $PID) and its children" >&2
        kill_tree "$PID"
        wait "$PID" 2>/dev/null
    fi
    exit "$1"
}
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap 'on_signal 129' HUP

CMD="$*"
"$@" &
PID=$!
PEAK=0
KILLED=0

while kill -0 "$PID" 2>/dev/null; do
    total=$(tree_rss "$PID")
    [ "${total:-0}" -gt "$PEAK" ] && PEAK=$total
    if [ "${total:-0}" -gt "$LIMIT_KB" ]; then
        echo "guard: killing $CMD (pid $PID): process tree RSS ${total} KB exceeds ${LIMIT_KB} KB" >&2
        kill_tree "$PID"
        KILLED=1
        break
    fi
    sleep 0.1
done
wait "$PID"
STATUS=$?
[ -n "$PEAK_FILE" ] && echo "$PEAK" > "$PEAK_FILE"
if [ $KILLED -eq 1 ]; then
    exit 137
fi
exit $STATUS
