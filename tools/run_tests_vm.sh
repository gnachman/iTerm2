#!/bin/bash
# Run iTerm2's tests on a macOS test VM instead of this machine.
#
# The test host is the iTerm2 app, which opens windows and takes focus, so a local run takes
# over the computer. This script copies the current working tree (uncommitted changes and
# submodule contents included) to a persistent checkout on a VM, runs the tests there in the
# VM's GUI session, streams the output, saves the full log locally, and exits with the tests'
# exit status.
#
# Usage:
#   tools/run_tests_vm.sh --host H [options] [-parallel] TEST...
#       Same test arguments as tools/run_tests.expect, e.g.
#         tools/run_tests_vm.sh --host vm1 ModernTests/TmuxWorkgroupBindingTests
#         tools/run_tests_vm.sh --host vm1 ModernTests/iTermScriptFunctionCallTest/testSignature
#         tools/run_tests_vm.sh --host vm1 -parallel       # whole suite
#
#   tools/run_tests_vm.sh --host H [options] -- COMMAND [ARG]...
#       Run any command from the checkout on the VM, e.g. a live harness:
#         tools/run_tests_vm.sh --host vm1 -- tools/run_tmux_workgroup_live.sh
#         ITERM2_ONSCREEN_TESTS=1 tools/run_tests_vm.sh --host vm1 -- tools/run_tmux_workgroup_live.sh --e2e
#         ITERM2_ONSCREEN_TESTS=1 tools/run_tests_vm.sh --host vm1 -- tools/run_ssh_integration_live.sh
#         tools/run_tests_vm.sh --host vm1 -e OPENAI_API_KEY -e ANTHROPIC_API_KEY -- tools/run_ai_live.sh smoke
#
# Options:
#   --host H[,H...]   VM(s) to use. Required: there is no default, because the developer
#                     decides which agent gets which VM, so ask them. With several hosts the
#                     first one not busy with another run is used; if all are busy, it waits
#                     (unless --no-wait). Hosts are ssh destinations (ssh config names).
#   --no-wait         Fail instead of waiting when every host is busy.
#   -e NAME           Forward local environment variable NAME to the command on the VM.
#                     Repeatable. ITERM2_ONSCREEN_TESTS is forwarded automatically, but only
#                     when it is set to 1 here, so on-screen tests stay opt-in as they are
#                     locally.
#   --runner R        gui (default): run as a LaunchAgent in the VM user's GUI login session,
#                     which an app-hosted XCTest needs. direct: run in the ssh session.
#   --no-sync         Skip copying the tree (rerun what is already on the VM).
#   --idle-timeout S  Cancel the run if it prints nothing for S seconds (default 900; 0 never).
#                     A test hung, or waiting on a modal alert nobody on the VM can answer, would
#                     otherwise hold the VM forever. Exits 124 when it fires.
#   --allow-physical  Allow a host that is not a virtual machine. The script always refuses
#                     to run on this machine itself.
#
# Environment:
#   ITERM2_TEST_VM_CHECKOUT   Checkout path on the VM, relative to its home directory.
#                             Default iterm2-vm-test/checkout. One checkout is shared by every
#                             local worktree so its build products stay warm.
#
# The full log is saved in tmp/vm-tests/ in this repo. Prepare a new VM once with
# tools/vm/provision_test_vm.sh HOST.
#
# Only one run uses a VM at a time. A run holds a lock on the VM for as long as its ssh
# connection lives, so a killed or disconnected run releases it automatically.

set -uo pipefail

# Everything below is one compound command, so bash reads the whole file before running any of
# it: editing this script while a run is in progress can't change what that run does.
{

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SSH_OPTS=(-T -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=6)

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

hosts=""
wait_for_host=1
runner=gui
sync=1
allow_physical=0
idle_timeout=900
forward_names=()
explicit_command=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host) hosts="$2"; shift 2 ;;
        --host=*) hosts="${1#--host=}"; shift ;;
        --no-wait) wait_for_host=0; shift ;;
        -e) forward_names+=("$2"); shift 2 ;;
        --runner) runner="$2"; shift 2 ;;
        --no-sync) sync=0; shift ;;
        --idle-timeout) idle_timeout="$2"; shift 2 ;;
        --allow-physical) allow_physical=1; shift ;;
        -h|--help) usage ;;
        --) explicit_command=1; shift; break ;;
        *) break ;;
    esac
done

# The command to run on the VM.
if [[ "${1:-}" == "--" ]]; then
    explicit_command=1
    shift
fi
if [[ $# -eq 0 ]]; then
    usage
fi
if [[ -z "$hosts" ]]; then
    echo "Pass --host with the VM the developer gave you. Ask them which one to use." >&2
    exit 2
fi
if [[ $explicit_command == 1 ]] ||
   [[ "$1" == */* && "$1" != ModernTests/* && "$1" != iTerm2XCTests/* && -e "$PROJECT_DIR/$1" ]]; then
    command=("$@")
else
    command=(tools/run_tests.expect "$@")
fi

if [[ "${ITERM2_ONSCREEN_TESTS:-}" == "1" ]]; then
    forward_names+=(ITERM2_ONSCREEN_TESTS)
fi
env_args=()
for name in ${forward_names[@]+"${forward_names[@]}"}; do
    if [[ -z "${!name+x}" ]]; then
        echo "Not forwarding $name: it is not set." >&2
        continue
    fi
    env_args+=(--env "$name=${!name}")
done

checkout="${ITERM2_TEST_VM_CHECKOUT:-iterm2-vm-test/checkout}"
local_uuid="$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')"
local_xcode="$(xcodebuild -version 2>/dev/null)"

tmp_dir="$PROJECT_DIR/tmp/vm-tests"
mkdir -p "$tmp_dir"
stamp="$(date +%Y%m%d-%H%M%S)"
job="$stamp-$$"

lock_pid=""
lock_fifo=""
heartbeat_pid=""
host=""
cleanup() {
    [[ -n "$heartbeat_pid" ]] && kill "$heartbeat_pid" 2>/dev/null
    if [[ -n "$lock_pid" ]]; then
        exec 9>&- 2>/dev/null
        kill "$lock_pid" 2>/dev/null
        wait "$lock_pid" 2>/dev/null
    fi
    [[ -n "$lock_fifo" ]] && rm -f "$lock_fifo" "$lock_fifo.out"
}
trap cleanup EXIT

# Holds the per-host lock for as long as the ssh connection lives: the remote shell takes the
# lock with mkdir (atomic), then reads stdin, and removes the lock when stdin closes, which
# happens when this script exits for any reason. This side sends a line every 30 seconds; a
# connection that died without the VM noticing (sshd can take hours) sends none, so after two
# minutes of silence the lock is released anyway. A lock whose holder process is gone is stale
# and is taken over.
LOCK_SCRIPT='
d="$HOME/iterm2-vm-test"; l="$d/lock"; mkdir -p "$d"
if ! mkdir "$l" 2>/dev/null; then
    if [ -f "$l/pid" ] && ! kill -0 "$(cat "$l/pid")" 2>/dev/null; then
        rm -rf "$l"; mkdir "$l" 2>/dev/null || { echo "BUSY lock race"; exit 0; }
    else
        echo "BUSY $(cat "$l/owner" 2>/dev/null)"; exit 0
    fi
fi
echo $$ > "$l/pid"; echo "$OWNER" > "$l/owner"
trap "rm -rf \"$l\"" EXIT HUP TERM INT
echo LOCKED
while IFS= read -r -t 120 _; do :; done
'

# Returns 0 and leaves the lock held if this host was free.
try_lock() {
    local h="$1" owner line
    owner="$(hostname -s):$PROJECT_DIR pid $$ since $(date '+%H:%M:%S')"
    lock_fifo="$tmp_dir/lock-$job.fifo"
    rm -f "$lock_fifo" "$lock_fifo.out"
    mkfifo "$lock_fifo"
    ssh "${SSH_OPTS[@]}" "$h" "OWNER=$(printf %q "$owner") /bin/sh -c $(printf %q "$LOCK_SCRIPT")" \
        < "$lock_fifo" > "$lock_fifo.out" 2>&1 &
    lock_pid=$!
    exec 9> "$lock_fifo"
    # Wait for the remote side's verdict. This polls a file the ssh process writes; it is
    # not timing-dependent: it ends on output or on ssh exiting.
    while :; do
        line="$(head -n 1 "$lock_fifo.out" 2>/dev/null)"
        if [[ "$line" == LOCKED ]]; then
            ( while sleep 30; do echo >&9 || exit 0; done ) &
            heartbeat_pid=$!
            return 0
        fi
        if [[ -n "$line" ]] || ! kill -0 "$lock_pid" 2>/dev/null; then
            wait "$lock_pid" 2>/dev/null
            last_lock_message="$(cat "$lock_fifo.out")"
            exec 9>&-
            lock_pid=""
            return 1
        fi
        sleep 0.2
    done
}

# Refuse to run on this machine (an ssh alias that points back here would defeat the purpose)
# and, unless allowed, on anything that is not a VM.
check_host() {
    local h="$1" info uuid vmm
    info="$(ssh "${SSH_OPTS[@]}" "$h" 'ioreg -rd1 -c IOPlatformExpertDevice | awk -F\" "/IOPlatformUUID/{print \$4}"; sysctl -n kern.hv_vmm_present' 2>&1)" || {
        echo "Cannot reach $h: $info" >&2
        return 1
    }
    uuid="$(echo "$info" | sed -n 1p)"
    vmm="$(echo "$info" | sed -n 2p)"
    if [[ "$uuid" == "$local_uuid" ]]; then
        echo "Refusing to use $h: it is this machine ($(ssh -G "$h" | awk '/^hostname /{print $2}')). Check its HostName in ~/.ssh/config." >&2
        return 1
    fi
    if [[ "$vmm" != "1" && "$allow_physical" != 1 ]]; then
        echo "Refusing to use $h: it is not a virtual machine. Pass --allow-physical to use it anyway." >&2
        return 1
    fi
    return 0
}

IFS=',' read -r -a host_list <<< "$hosts"
usable=()
for h in "${host_list[@]}"; do
    h="${h// /}"
    [[ -n "$h" ]] || continue
    check_host "$h" && usable+=("$h")
done
if [[ ${#usable[@]} -eq 0 ]]; then
    echo "No usable test VM." >&2
    exit 125
fi

announced_wait=0
while [[ -z "$host" ]]; do
    for h in "${usable[@]}"; do
        if try_lock "$h"; then
            host="$h"
            break
        fi
        if [[ "$last_lock_message" != BUSY* ]]; then
            echo "Could not take the lock on $h: $last_lock_message" >&2
        elif [[ $wait_for_host == 0 || $announced_wait == 0 ]]; then
            echo "$h is busy: ${last_lock_message#BUSY }" >&2
        fi
    done
    if [[ -z "$host" ]]; then
        if [[ $wait_for_host == 0 ]]; then
            exit 125
        fi
        if [[ $announced_wait == 0 ]]; then
            echo "Waiting for a free host..." >&2
            announced_wait=1
        fi
        sleep 15
    fi
done

log="$tmp_dir/$stamp-$host.log"
echo "Using $host. Log: $log"

# Pick the VM's Xcode whose version matches this machine's, since the build refuses to run
# against prebuilt dependencies from a different Xcode (see last-xcode-version).
find_xcode='for x in /Applications/Xcode*.app; do d="$x/Contents/Developer"; [ -d "$d" ] || continue; [ "$(DEVELOPER_DIR="$d" xcodebuild -version 2>/dev/null)" = "$WANT" ] && { echo "$d"; break; }; done'
developer_dir="$(ssh "${SSH_OPTS[@]}" "$host" "WANT=$(printf %q "$local_xcode") /bin/sh -c $(printf %q "$find_xcode")")"
if [[ -z "$developer_dir" ]]; then
    echo "$host has no Xcode matching this machine's:" >&2
    echo "$local_xcode" >&2
    echo "Run tools/vm/provision_test_vm.sh $host" >&2
    exit 125
fi

if [[ $sync == 1 ]]; then
    start=$(date +%s)
    echo "Syncing working tree to $host:$checkout ..."
    ssh "${SSH_OPTS[@]}" "$host" "mkdir -p $(printf %q "$checkout")" || exit 125
    # Excluded paths are build products, caches, VCS metadata and local junk. Excluded paths
    # are also protected from --delete, so the VM's own build products survive.
    # One retry: a dropped connection mid-copy is not worth failing a run over.
    for attempt in 1 2; do
    if rsync -a --delete \
        --exclude='/.git' --exclude='.git' \
        --exclude='/Build/' --exclude='/Companion/Build/' --exclude='DerivedData/' \
        --exclude='.build/' --exclude='.build-arm64/' --exclude='.build-x86_64/' \
        --exclude='node_modules/' --exclude='.wrangler/' --exclude='.swiftpm/' \
        --exclude='xcuserdata/' --exclude='*.xcuserstate' --exclude='.DS_Store' \
        --exclude='__pycache__/' --exclude='/tmp/' --exclude='/.claude/' \
        --exclude='/[0-9]*/' --exclude='/debuglog*.txt' --exclude='/.iterm2-ai-live.json' \
        --exclude='/WebExtensionsFramework/build/' --exclude='/api/library/python/iterm2/build/' \
        -e "ssh ${SSH_OPTS[*]}" \
        "$PROJECT_DIR/" "$host:$checkout/"; then
        break
    fi
    if [[ $attempt == 2 ]]; then
        echo "rsync to $host failed." >&2
        exit 125
    fi
    echo "rsync to $host failed; retrying." >&2
    done
    echo "Synced in $(( $(date +%s) - start ))s."
fi

cancel_remote() {
    echo "" >&2
    echo "*** Interrupted, cancelling the run on $host ***" >&2
    ssh "${SSH_OPTS[@]}" "$host" "cd $(printf %q "$checkout") && tools/vm/remote_run.sh cancel --job $job" >&2
    exit 130
}
trap cancel_remote INT TERM

remote_cmd="cd $(printf %q "$checkout") && tools/vm/remote_run.sh run --job $job --runner $runner --idle-timeout $(printf %q "$idle_timeout") --developer-dir $(printf %q "$developer_dir")"
for a in ${env_args[@]+"${env_args[@]}"}; do
    remote_cmd+=" $(printf %q "$a")"
done
remote_cmd+=" --"
for a in "${command[@]}"; do
    remote_cmd+=" $(printf %q "$a")"
done

echo "Running on $host: ${command[*]}"
start=$(date +%s)
ssh "${SSH_OPTS[@]}" "$host" "$remote_cmd" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
elapsed=$(( $(date +%s) - start ))
trap - INT TERM

echo ""
echo "=== $host: exit status $rc after ${elapsed}s. Full log: $log"
if [[ $rc != 0 ]]; then
    # xcodebuild's own summary names failing tests; the assertion lines carry file:line.
    failures="$(grep -E '(error: -\[|: error: |Test Case .* failed|Failing tests:|^\s+[A-Za-z0-9_]+\.[A-Za-z0-9_]+\(\)|\*\* TEST FAILED|\*\* BUILD FAILED)' "$log" | head -100)"
    if [[ -n "$failures" ]]; then
        echo "=== Failures:"
        echo "$failures"
    fi
fi
exit "$rc"
}
