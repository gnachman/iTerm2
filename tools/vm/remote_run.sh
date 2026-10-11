#!/bin/bash
# Runs on the test VM, invoked over ssh by tools/run_tests_vm.sh. Not meant to be run by hand.
#
# Runs a command from the synced checkout and streams its output to stdout. The command runs
# either as a LaunchAgent in the logged-in user's GUI (Aqua) session (--runner gui, the default),
# where an app-hosted XCTest can launch its test host, or directly in the ssh session
# (--runner direct). Either way the job's output goes to a log file in the job directory and
# this script tails it, so the job is unaffected by the ssh connection's lifetime until the
# caller cancels it.
#
# Usage:
#   tools/vm/remote_run.sh run --job ID [--runner gui|direct] [--developer-dir DIR]
#                          [--idle-timeout SECONDS] [--env NAME=VALUE]... -- COMMAND [ARG]...
#   tools/vm/remote_run.sh cancel --job ID
#
# Exits with the command's exit status (or 125 for an infrastructure failure here). With
# --idle-timeout, a job that writes no output for that long is cancelled and exits with 124: a
# test is probably hung, or waiting on a modal alert nobody can answer.

set -uo pipefail

STATE_DIR="$HOME/iterm2-vm-test"
JOBS_DIR="$STATE_DIR/jobs"
LABEL_PREFIX="com.iterm2.vmtest"

die() {
    echo "remote_run: $*" >&2
    exit 125
}

kill_tree() {
    local pid="$1" child
    for child in $(pgrep -P "$pid" 2>/dev/null); do
        kill_tree "$child"
    done
    kill -TERM "$pid" 2>/dev/null
}

# Test hosts, their XPC services, and the harnesses' private tmux servers are not in a job's
# process tree (testmanagerd launches the host, launchd its services, and tmux servers daemonize),
# so a cancelled or crashed run can leave them behind. A hung host's pidinfo service left running
# makes every later host stop at launch, so the next run waits forever.
kill_leftovers() {
    pkill -9 -f '/Build/Products/[^ ]*/iTerm2\.app/Contents/' 2>/dev/null
    pkill -f 'tmux -L iterm2wg' 2>/dev/null
}

cancel_job() {
    local job="$1"
    local dir="$JOBS_DIR/$job"
    [[ -d "$dir" ]] || return 0
    if [[ -f "$dir/runner" && "$(cat "$dir/runner")" == "gui" ]]; then
        launchctl bootout "gui/$(id -u)/$LABEL_PREFIX.$job" 2>/dev/null
    fi
    if [[ -f "$dir/pid" ]]; then
        kill_tree "$(cat "$dir/pid")"
    fi
    [[ -f "$dir/status" ]] || echo 130 > "$dir/status"
    kill_leftovers
}

mode="${1:-}"
shift || true
job=""
runner="gui"
developer_dir=""
idle_timeout=0
envs=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --job) job="$2"; shift 2 ;;
        --runner) runner="$2"; shift 2 ;;
        --developer-dir) developer_dir="$2"; shift 2 ;;
        --idle-timeout) idle_timeout="$2"; shift 2 ;;
        --env) envs+=("$2"); shift 2 ;;
        --) shift; break ;;
        *) die "unknown argument $1" ;;
    esac
done
[[ -n "$job" ]] || die "missing --job"
[[ "$job" =~ ^[A-Za-z0-9._-]+$ ]] || die "bad job id $job"

if [[ "$mode" == "cancel" ]]; then
    cancel_job "$job"
    exit 0
fi
[[ "$mode" == "run" ]] || die "mode must be run or cancel"
[[ $# -gt 0 ]] || die "no command given"

# The caller holds this VM's lock, so nothing else of ours should be running.
kill_leftovers

checkout="$(pwd)"
dir="$JOBS_DIR/$job"
mkdir -p "$dir" || die "cannot create $dir"
# Keep the last 20 job directories.
ls -1t "$JOBS_DIR" | tail -n +21 | while read -r old; do rm -rf "${JOBS_DIR:?}/$old"; done

log="$dir/log"
: > "$log"
echo "$runner" > "$dir/runner"

# The job script. It records its pid so cancel can kill its process tree (expect gives
# xcodebuild its own session, so the tree has to be walked rather than signalled as a group),
# and writes the exit status last, which is what the tail loop below waits for.
{
    echo '#!/bin/bash'
    echo "echo \$\$ > $(printf %q "$dir/pid")"
    echo 'kill_tree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done; kill -TERM "$1" 2>/dev/null; }'
    echo "trap 'for c in \$(pgrep -P \$\$); do kill_tree \$c; done; echo 130 > $(printf %q "$dir/status"); exit 130' TERM INT HUP"
    echo 'export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"'
    echo 'export LANG="${LANG:-en_US.UTF-8}"'
    if [[ -n "$developer_dir" ]]; then
        echo "export DEVELOPER_DIR=$(printf %q "$developer_dir")"
    fi
    for kv in ${envs[@]+"${envs[@]}"}; do
        name="${kv%%=*}"
        [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "bad env name $name"
        echo "export $name=$(printf %q "${kv#*=}")"
    done
    echo "cd $(printf %q "$checkout") || exit 125"
    printf '%q ' "$@"
    echo '< /dev/null &'
    echo 'child=$!'
    echo 'wait $child'
    echo 'rc=$?'
    echo "echo \$rc > $(printf %q "$dir/status.tmp") && mv $(printf %q "$dir/status.tmp") $(printf %q "$dir/status")"
} > "$dir/job.sh"
chmod +x "$dir/job.sh"

trap 'cancel_job "$job"; exit 130' INT TERM HUP PIPE

case "$runner" in
    direct)
        "$dir/job.sh" >> "$log" 2>&1 &
        ;;
    gui)
        console_user="$(stat -f %Su /dev/console)"
        if [[ "$console_user" != "$(id -un)" ]]; then
            die "$(id -un) is not logged in to the GUI (console user is $console_user). Turn on automatic login for $(id -un) in the VM and reboot it, or pass --runner direct."
        fi
        plist="$dir/job.plist"
        cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL_PREFIX.$job</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$dir/job.sh</string></array>
    <key>StandardOutPath</key><string>$log</string>
    <key>StandardErrorPath</key><string>$log</string>
    <key>WorkingDirectory</key><string>$checkout</string>
    <key>RunAtLoad</key><true/>
    <key>ProcessType</key><string>Interactive</string>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
EOF
        if ! launchctl bootstrap "gui/$(id -u)" "$plist"; then
            die "launchctl bootstrap gui/$(id -u) failed. Is $(id -un) logged in to the GUI?"
        fi
        ;;
    *)
        die "unknown runner $runner"
        ;;
esac

# Stream the log until the job writes its status. Polling for the status file is how this
# side learns the job ended; launchd gives no other completion signal to an ssh session.
tail -n +1 -f "$log" &
tail_pid=$!
last_size=-1
last_change=$(date +%s)
while [[ ! -f "$dir/status" ]]; do
    size=$(stat -f %z "$log" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [[ "$size" != "$last_size" ]]; then
        last_size=$size
        last_change=$now
    elif [[ "$idle_timeout" -gt 0 && $(( now - last_change )) -ge "$idle_timeout" ]]; then
        echo "remote_run: no output for ${idle_timeout}s; cancelling. A test is probably hung or waiting on a modal alert." >> "$log"
        # Where the test host is stuck: the main thread's stack, with the full samples kept in the
        # job directory.
        for host_pid in $(pgrep -x iTerm2); do
            sample "$host_pid" 3 -file "$dir/sample-$host_pid.txt" >/dev/null 2>&1
            echo "remote_run: main thread of iTerm2 $host_pid (full sample in $dir/sample-$host_pid.txt):" >> "$log"
            awk '/^Call graph:/{on=1} on&&/^ *[0-9]+ Thread_/{n++} on&&n<=1' "$dir/sample-$host_pid.txt" | head -150 >> "$log"
        done
        cancel_job "$job"
        # The job's own trap records 130 as it dies; record why instead, once it is gone.
        for _ in $(seq 10); do
            [[ -f "$dir/pid" ]] && kill -0 "$(cat "$dir/pid")" 2>/dev/null || break
            sleep 1
        done
        echo 124 > "$dir/status"
        break
    fi
    if [[ -f "$dir/pid" ]] && ! kill -0 "$(cat "$dir/pid")" 2>/dev/null; then
        # The job script is gone. Give a status written at the last moment a chance to land.
        sleep 1
        [[ -f "$dir/status" ]] || { echo 125 > "$dir/status"; echo "remote_run: job exited without a status" >> "$log"; }
        break
    fi
    sleep 1
done
# Let tail print the last lines before stopping it.
sleep 1
kill "$tail_pid" 2>/dev/null
wait "$tail_pid" 2>/dev/null
if [[ "$runner" == "gui" ]]; then
    launchctl bootout "gui/$(id -u)/$LABEL_PREFIX.$job" 2>/dev/null
fi
exit "$(cat "$dir/status")"
