#!/bin/bash
# Hands-on QA of iTerm2 on a test VM: build, launch, drive the pointer and keyboard, inspect
# focus, and take screenshots, without touching this machine. See docs/vm-qa.md.
#
# Usage: tools/vm/qa.sh --host H COMMAND [ARG]...
#
# The developer hands out the VMs. Ask them which one to use; don't pick one yourself.
#
# Setup and builds
#   setup                 Build vmctl here, install it and guirun.sh on the VM, check permissions.
#   build                 Build this working tree on the VM (the candidate).
#   build-baseline [REF]  Build git REF (default origin/master) on the VM for comparison.
#
# Running the app
#   launch [candidate|baseline] [--frame X Y W H]
#                         Quit any QA app, then launch the chosen build with a fresh window.
#                         The candidate uses settings suite "qa", the baseline "qa-baseline".
#   quit                  Quit the QA apps and their session servers.
#   log                   Print the running app's stdout and stderr (NSFuckingLog output lands here).
#   pid                   Print the running QA app's process id.
#
# Driving it
#   ctl VMCTL-ARGS...     Run vmctl on the VM (see tools/vm/qa/vmctl.swift). An argument that
#                         is exactly PID is replaced by the running QA app's process id.
#   f                     One-line focus summary for the QA app (vmctl f PID).
#   menu TOP ITEM...      Press a menu item in the QA app.
#   shot [--crop X Y W H] [--size PIXELS]
#                         Screenshot to tmp/vm-qa/shot.png here. Crop is in screen points.
#                         Prints how image pixels map back to screen points.
#   sh COMMAND...         Run a shell command on the VM.
#   profiles SUITE ...    Edit profiles in a settings suite (tools/vm/qa/profiles.py on the VM).
#
# Cleaning up
#   clean                 Quit the apps and delete everything this script put on the VM:
#                         QA settings suites, the baseline checkout and its build, and the tools.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOCAL_DIR="$PROJECT_DIR/tmp/vm-qa"
REMOTE_DIR="iterm2-vm-test/qa"
BASELINE_CHECKOUT="iterm2-vm-test/baseline"
AGENT_LABEL="com.iterm2.vmqa.app"
SUITES=(qa qa-baseline)
# A local worktree of the baseline ref. It's kept until the next baseline build or clean so its
# build log stays readable.
BASELINE_WORKTREE="${TMPDIR:-/tmp}/iterm2-vm-qa-baseline-$(echo "$PROJECT_DIR" | shasum | cut -c1-8)"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

host=""
if [[ "${1:-}" == --host ]]; then
    host="${2:-}"
    shift 2
fi
if [[ -z "$host" ]]; then
    echo "Pass --host with the VM the developer gave you. Ask them which one to use." >&2
    exit 2
fi
[[ $# -gt 0 ]] || usage
command="$1"
shift

mkdir -p "$LOCAL_DIR"
# Reuse one ssh connection; most commands are many quick round trips.
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o ControlMaster=auto
          -o "ControlPath=/tmp/vmqa-%C" -o ControlPersist=600)

remote() {
    ssh "${SSH_OPTS[@]}" "$host" "$@"
}

# Prints the process id of the running QA app, if any.
REMOTE_PID='pgrep -f "/Contents/MacOS/iTerm2 -suite (qa|qa-baseline)$" | head -1'

# Quits the QA apps and their session servers (sessions survive the app otherwise).
REMOTE_QUIT="launchctl bootout gui/\$(id -u)/$AGENT_LABEL 2>/dev/null
pkill -f '/Contents/MacOS/iTerm2 -suite (qa|qa-baseline)\$'
pkill -f 'Application Support/(qa|qa-baseline)/iTermServer'
sleep 1"

require_setup() {
    remote "test -x $REMOTE_DIR/vmctl" || {
        echo "Run tools/vm/qa.sh --host $host setup first." >&2
        exit 1
    }
}

# Finds the Development iTerm2.app that Xcode built from a checkout on the VM. Each DerivedData
# folder records the workspace it belongs to.
remote_app_for_checkout() {
    local checkout="$1"
    remote "for d in ~/Library/Developer/Xcode/DerivedData/iTerm2-*; do
        if [ \"\$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' \"\$d/info.plist\" 2>/dev/null)\" = \"\$HOME/$checkout/iTerm2.xcodeproj\" ]; then
            echo \"\$d/Build/Products/Development/iTerm2.app\"
        fi
    done" | head -1
}

case "$command" in
setup)
    signing_identity="${ITERM2_VM_QA_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"')}"
    echo "Building vmctl ..."
    swiftc -O "$SCRIPT_DIR/qa/vmctl.swift" -o "$LOCAL_DIR/vmctl" || exit 1
    # A stable signature keeps the VM's privacy grants for vmctl across rebuilds.
    if [[ -n "$signing_identity" ]]; then
        codesign -f -s "$signing_identity" -i com.iterm2.vmqa.vmctl "$LOCAL_DIR/vmctl" || exit 1
    else
        echo "WARNING: no Apple Development identity; vmctl is ad hoc signed, so its Screen Recording grant won't survive a rebuild." >&2
    fi
    remote "mkdir -p $REMOTE_DIR" || exit 1
    scp -q -o "ControlPath=/tmp/vmqa-%C" "$LOCAL_DIR/vmctl" "$SCRIPT_DIR/qa/guirun.sh" \
        "$SCRIPT_DIR/qa/profiles.py" "$host:$REMOTE_DIR/" || exit 1
    echo "Installed in ~/$REMOTE_DIR on $host."
    echo "From ssh (input and accessibility): $(remote "$REMOTE_DIR/vmctl trusted")"
    echo "From the GUI session (screenshots): $(remote "$REMOTE_DIR/guirun.sh \$HOME/$REMOTE_DIR/vmctl trusted")"
    echo "Input needs accessibility and postEvent from ssh; screenshots need screenRecording from the GUI session."
    echo "See docs/vm-qa.md for granting what's missing."
    ;;

build)
    "$PROJECT_DIR/tools/run_tests_vm.sh" --host "$host" -- tools/build.sh || exit $?
    app="$(remote_app_for_checkout "${ITERM2_TEST_VM_CHECKOUT:-iterm2-vm-test/checkout}")"
    [[ -n "$app" ]] || { echo "Couldn't find the built app on $host." >&2; exit 1; }
    remote "mkdir -p $REMOTE_DIR && echo $(printf %q "$app") > $REMOTE_DIR/app-candidate"
    echo "Candidate: $app"
    ;;

build-baseline)
    ref="${1:-origin/master}"
    git -C "$PROJECT_DIR" fetch -q origin 2>/dev/null
    sha="$(git -C "$PROJECT_DIR" rev-parse --verify "$ref^{commit}")" || exit 1
    git -C "$PROJECT_DIR" worktree remove --force "$BASELINE_WORKTREE" 2>/dev/null
    rm -rf "$BASELINE_WORKTREE"
    git -C "$PROJECT_DIR" worktree add -q --detach "$BASELINE_WORKTREE" "$sha" || exit 1
    # Copy submodule contents from this tree (APFS clones, so it's quick) instead of fetching.
    git -C "$PROJECT_DIR" submodule --quiet foreach --recursive 'echo "$displaypath"' |
    while read -r path; do
        rm -rf "${BASELINE_WORKTREE:?}/$path"
        mkdir -p "$(dirname "$BASELINE_WORKTREE/$path")"
        cp -Rc "$PROJECT_DIR/$path" "$BASELINE_WORKTREE/$path"
    done
    if ! diff <(git -C "$PROJECT_DIR" ls-tree -r "$sha" | awk '$2 == "commit"') \
              <(git -C "$PROJECT_DIR" ls-tree -r HEAD | awk '$2 == "commit"') > /dev/null; then
        echo "WARNING: submodule commits differ between $ref and HEAD; the baseline uses HEAD's." >&2
    fi
    # Use this tree's VM runner, which REF may predate.
    mkdir -p "$BASELINE_WORKTREE/tools/vm"
    cp "$PROJECT_DIR/tools/run_tests_vm.sh" "$BASELINE_WORKTREE/tools/"
    cp "$PROJECT_DIR/tools/vm/remote_run.sh" "$BASELINE_WORKTREE/tools/vm/"
    # Start from a clone of the candidate checkout so the copy is a small delta.
    remote "test -d ~/$BASELINE_CHECKOUT || cp -Rc ~/iterm2-vm-test/checkout ~/$BASELINE_CHECKOUT 2>/dev/null; rm -rf ~/$BASELINE_CHECKOUT/Build"
    echo "Building $ref ($sha) on $host. The first baseline build is a full build."
    ITERM2_TEST_VM_CHECKOUT="$BASELINE_CHECKOUT" "$BASELINE_WORKTREE/tools/run_tests_vm.sh" --host "$host" -- tools/build.sh
    status=$?
    [[ $status == 0 ]] || exit $status
    app="$(remote_app_for_checkout "$BASELINE_CHECKOUT")"
    [[ -n "$app" ]] || { echo "Couldn't find the built app on $host." >&2; exit 1; }
    remote "mkdir -p $REMOTE_DIR && echo $(printf %q "$app") > $REMOTE_DIR/app-baseline"
    echo "Baseline ($sha): $app"
    ;;

launch)
    which=candidate
    suite=qa
    frame=(100 80 1400 800)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            candidate) which=candidate; suite=qa; shift ;;
            baseline) which=baseline; suite=qa-baseline; shift ;;
            --frame) frame=("$2" "$3" "$4" "$5"); shift 5 ;;
            *) usage ;;
        esac
    done
    require_setup
    app="$(remote "cat $REMOTE_DIR/app-$which 2>/dev/null")"
    if [[ -z "$app" ]]; then
        [[ $which == baseline ]] && echo "No baseline build. Run tools/vm/qa.sh --host $host build-baseline first." >&2
        [[ $which == candidate ]] && echo "No candidate build. Run tools/vm/qa.sh --host $host build first." >&2
        exit 1
    fi
    remote "$REMOTE_QUIT
defaults write $suite NSQuitAlwaysKeepsWindows -bool false
defaults write $suite SUEnableAutomaticChecks -bool false
cat > /tmp/$AGENT_LABEL.plist <<PLIST
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict>
<key>Label</key><string>$AGENT_LABEL</string>
<key>ProgramArguments</key><array><string>$app/Contents/MacOS/iTerm2</string><string>-suite</string><string>$suite</string></array>
<key>StandardOutPath</key><string>\$HOME/$REMOTE_DIR/app.log</string>
<key>StandardErrorPath</key><string>\$HOME/$REMOTE_DIR/app.log</string>
<key>RunAtLoad</key><true/>
</dict></plist>
PLIST
: > $REMOTE_DIR/app.log
launchctl bootstrap gui/\$(id -u) /tmp/$AGENT_LABEL.plist" || exit 1
    # Wait for the app to finish launching, then give it a window of a known size in front.
    pid=""
    for _ in $(seq 1 60); do
        pid="$(remote "$REMOTE_PID")"
        [[ -n "$pid" ]] && remote "$REMOTE_DIR/vmctl wins $pid | grep -q ." && break
        sleep 0.5
    done
    [[ -n "$pid" ]] || { echo "The app didn't start. tools/vm/qa.sh --host $host log may say why." >&2; exit 1; }
    remote "$REMOTE_DIR/vmctl hideothers $pid; $REMOTE_DIR/vmctl activate $pid"
    sleep 1
    if ! remote "$REMOTE_DIR/vmctl wins $pid | grep -q ."; then
        remote "$REMOTE_DIR/vmctl key 45 cmd"
        sleep 2
    fi
    remote "$REMOTE_DIR/vmctl setframe $pid f ${frame[*]}; $REMOTE_DIR/vmctl wins $pid"
    echo "Launched $which (pid $pid, suite $suite)."
    ;;

quit)
    remote "$REMOTE_QUIT"
    ;;

log)
    remote "cat $REMOTE_DIR/app.log"
    ;;

pid)
    remote "$REMOTE_PID"
    ;;

ctl)
    require_setup
    pid="$(remote "$REMOTE_PID")"
    args=()
    for a in "$@"; do
        [[ "$a" == PID ]] && a="$pid"
        args+=("$(printf %q "$a")")
    done
    remote "$REMOTE_DIR/vmctl ${args[*]}"
    ;;

f)
    require_setup
    # Accessibility notifications lag focus changes slightly.
    sleep 0.4
    remote "$REMOTE_DIR/vmctl f $(remote "$REMOTE_PID")"
    ;;

menu)
    exec "$0" --host "$host" ctl menu PID "$@"
    ;;

shot)
    require_setup
    crop=()
    size=1400
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --crop) crop=("$2" "$3" "$4" "$5"); shift 5 ;;
            --size) size="$2"; shift 2 ;;
            *) usage ;;
        esac
    done
    out="$LOCAL_DIR/shot.png"
    remote "$REMOTE_DIR/guirun.sh \$HOME/$REMOTE_DIR/vmctl shot /tmp/vmqa-shot.png" >/dev/null
    scp -q -o "ControlPath=/tmp/vmqa-%C" "$host:/tmp/vmqa-shot.png" "$out" || exit 1
    remote "rm -f /tmp/vmqa-shot.png"
    screen_width="$(remote "$REMOTE_DIR/vmctl screen" | cut -dx -f1)"
    pixel_width="$(sips -g pixelWidth "$out" | awk '/pixelWidth/ {print $2}')"
    # Backing pixels per screen point, usually 2.
    density=$(( pixel_width / screen_width ))
    origin_x=0
    origin_y=0
    if [[ ${#crop[@]} == 4 ]]; then
        origin_x=${crop[0]}
        origin_y=${crop[1]}
        sips -c $(( crop[3] * density )) $(( crop[2] * density )) \
            --cropOffset $(( crop[1] * density )) $(( crop[0] * density )) "$out" >/dev/null
    fi
    sips -Z "$size" "$out" >/dev/null
    final_width="$(sips -g pixelWidth "$out" | awk '/pixelWidth/ {print $2}')"
    covered=$(( ${#crop[@]} == 4 ? crop[2] : screen_width ))
    echo "$out"
    echo "Screen point = ($origin_x + px * $covered / $final_width, $origin_y + py * $covered / $final_width) for image pixel (px, py)."
    ;;

sh)
    remote "$@"
    ;;

profiles)
    require_setup
    args=()
    for a in "$@"; do
        args+=("$(printf %q "$a")")
    done
    remote "python3 $REMOTE_DIR/profiles.py ${args[*]}"
    ;;

clean)
    remote "$REMOTE_QUIT
rm -f /tmp/$AGENT_LABEL.plist /tmp/vmqa-shot.png
for s in ${SUITES[*]}; do
    defaults delete \$s 2>/dev/null
    defaults delete \$s.private 2>/dev/null
    rm -f ~/Library/Preferences/\$s.plist ~/Library/Preferences/\$s.private.plist
    rm -rf ~/Library/Application\\ Support/\$s
done"
    baseline_app="$(remote_app_for_checkout "$BASELINE_CHECKOUT")"
    if [[ -n "$baseline_app" ]]; then
        remote "rm -rf $(printf %q "${baseline_app%/Build/Products/Development/iTerm2.app}")"
    fi
    remote "rm -rf ~/$BASELINE_CHECKOUT ~/$REMOTE_DIR"
    git -C "$PROJECT_DIR" worktree remove --force "$BASELINE_WORKTREE" 2>/dev/null
    rm -rf "$BASELINE_WORKTREE"
    echo "Cleaned up $host. Extra Spaces, if you made any, have to be removed in Mission Control."
    ;;

*)
    usage
    ;;
esac
