#!/bin/bash
# Capture the compile commands that the real Development build runs, for the
# code database.
#
# This runs one clean Development build of the ModernTests scheme
# (`xcodebuild clean build-for-testing`), which compiles the app, every
# framework it embeds and the ModernTests bundle. The build must be clean:
# clang writes a fragment only for a file it compiles, so an incremental build
# would capture only the files it recompiled. The clean action removes the
# scheme's Development products and intermediates in Build/ first. It adds one standard clang driver flag to every C,
# Objective-C, C++ and Objective-C++ compile through the command line:
#
#     OTHER_CFLAGS='$(inherited) -gen-cdb-fragment-path <dir>'
#
# `$(inherited)` keeps each target's own OTHER_CFLAGS, and the project's
# OTHER_CPLUSPLUSFLAGS inherit $(OTHER_CFLAGS), so per-target flags survive.
# Clang then writes one JSON fragment per compiled file into <dir>.
#
# What this build does to the tree:
#
# - It builds into Build/ (SYMROOT), the same place `make Development` builds,
#   cleans the Development build there, and replaces it with an unsigned one
#   (code signing is turned off). Run `make Development` afterwards to get a
#   signed build back.
# - The sanitizer options below are passed, but the ModernTests scheme's test
#   plan still has xcodebuild compile an address-sanitizer variant of every
#   file as well (Build/Intermediates.noindex/Variant-ASan). The earlier
#   capture wrote 1,086 such fragments. `codedb.py cdb` discards them; the
#   normal variant (Variant-NoSanitizers) is what the database is built from.
# - Index-while-building is turned off, so this build does not write to
#   Xcode's index store.
#
# The fragments are written to tmp/codedb/cdb-fragments.partial, which is
# emptied first. Only when the build succeeds is it moved to
# tmp/codedb/cdb-fragments (replacing the previous capture) with a .captured
# stamp and a .capture-record: the digest of the project's build settings,
# the SDK and the date, all computed by `codedb.py capture-record` before
# the build starts. `codedb.py cdb` takes the build settings digest from that
# record, so a flag change made after the capture is reported however often
# the compile database is rebuilt from these fragments. If the build fails,
# nothing is recorded, the previous capture and the compile database built
# from it are left untouched, and the script exits non-zero.
#
# It takes the code database lock (tmp/codedb/codedb.lock), shared with
# `codedb.py update` and `codedb.py cdb`, and exits 2 if one of them holds it.
# The lock is an flock(2) on that file, taken by the same code as theirs: the
# script first runs `codedb.py hold-lock`, which takes the lock and then execs
# this script again (same pid) with the locked file open on fd 9 and
# CODEDB_LOCK_TOKEN set to that pid. The kernel releases the lock when this
# process dies in any way. The build does not inherit fd 9. While the build
# runs, its process group is recorded in the lock file (`child <pgid>
# <start>`), so that if this script is killed with SIGKILL, the next taker of
# the lock kills the build before it proceeds.
#
# The build runs as a background job in its own process group, and the script
# waits for it, so that SIGTERM or SIGHUP stops the script at once and kills
# the build's whole process group. If the script is started in the background
# by a non-interactive shell, SIGINT is ignored (the shell ignores it for
# background jobs, and an ignored signal cannot be trapped); use TERM or HUP.
#
# Run it again whenever source files are added or removed, or compile flags
# change. `codedb.py update` reports when the compile database no longer
# matches the project.
#
# After the build succeeds, `codedb.py swift-capture` keeps what the Swift
# side needs in tmp/codedb/cdb-fragments/swift: the log's SwiftDriver
# commands of the Variant-NoSanitizers variant (drivers.jsonl) and a copy of
# each module's .SwiftFileList (filelists/), which the next build of the tree
# overwrites. If that fails, nothing is recorded, as for a failed build.
#
# With --other-projects it captures, instead of the main build, each other
# Xcode project listed in other_projects.json that is in the tree (projects
# whose frameworks the app embeds prebuilt, or whose command line tools the
# app's build does not compile; `codedb.py other-projects` prints the list).
# For each, under the same lock: its build directory
# tmp/codedb/other-build/NAME is deleted, so that the build is clean (no
# `clean` action: xcodebuild refuses to clean a directory it did not create),
# then `xcodebuild -project P -scheme T -configuration C -derivedDataPath
# DIR/dd build` runs once per kept target T (scheme of the same name) with
# the project's own settings plus the spec's, SYMROOT and OBJROOT in that
# directory and SHARED_PRECOMPS_DIR in it too (never the project's own build
# directory, Build/ or ~/Library/Developer/Xcode/DerivedData), signing and
# indexing off, the
# native architecture, and the same OTHER_CFLAGS fragment
# flag pointing at tmp/codedb/other-fragments/NAME.partial. Only when that
# build succeeds is the partial directory moved to
# tmp/codedb/other-fragments/NAME with a .captured stamp and a
# .capture-record (`codedb.py capture-record --project NAME`: the project,
# the digest of its other_projects.json entry, its own build settings digest,
# the SDK and the date, computed before the build). A project whose build
# fails keeps its previous capture; the others proceed, and the script exits
# 1. A project whose project file is absent although its directory exists (a
# submodule that is not checked out, as in a lane) is named ("NAME: not
# captured: DIR is not checked out here") and skipped, which is not an
# error; CoreParse is captured from submodules/CoreParse, so run this in a
# checkout where that submodule is checked out. xcodebuild creates the empty
# directory project.xcworkspace/xcshareddata/swiftpm/configuration in a
# project that lacks it; for a project under submodules/ the capture is
# skipped, with a message, when that directory is missing (in the main
# checkout it exists), so that nothing is written inside a submodule. The build log is tmp/codedb/other-build-NAME.log. The build directory is
# kept: the captured commands name the header maps in it. `codedb.py cdb`
# (or update) merges these captures into the compile database. Only Clang
# units are captured: a project's Swift (BetterFontPicker,
# SearchableComboListView) is not.
#
# With --jobs N, at most N build tasks run at once (xcodebuild -jobs N, on
# the main build and on each build of --other-projects); without it
# xcodebuild chooses (about one per core). The capture is a clean build, so
# it is a heavy job (docs/swift-migration/orchestration.md section 3): a
# limit lowers the load it puts on the machine, not the work, and the build
# takes longer. Priority is a separate matter: started under `nice -n 15`,
# xcodebuild, its build service (SWBBuildService, a child of xcodebuild) and
# the compilers all run at that priority.
#
# Usage: tools/swift_migration/codedb/capture_compile_commands.sh [--other-projects] [--jobs N]
# Writes: tmp/codedb/cdb-fragments/*.json, tmp/codedb/cdb-fragments/swift/
# and tmp/codedb/capture-build.log; with --other-projects,
# tmp/codedb/other-fragments/NAME/, tmp/codedb/other-build/NAME/ and
# tmp/codedb/other-build-NAME.log

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="$ROOT/tmp/codedb"
FRAG="$OUT/cdb-fragments"
PARTIAL="$OUT/cdb-fragments.partial"
LOG="$OUT/capture-build.log"
LOCK="$OUT/codedb.lock"

MODE=main
JOBS_ARGS=()
usage_error() {
    echo "usage: $(basename "$0") [--other-projects] [--jobs N]" >&2
    exit 2
}
ARGV=("$@")
while [ $# -gt 0 ]; do
    case "$1" in
        --other-projects) MODE=other ;;
        --jobs)
            case "${2:-}" in
                ''|*[!0-9]*|0*) echo "error: --jobs takes a whole number of at least 1, not '${2:-}'" >&2; usage_error ;;
            esac
            JOBS_ARGS=(-jobs "$2")
            shift ;;
        *) usage_error ;;
    esac
    shift
done
set -- ${ARGV[@]+"${ARGV[@]}"}

cd "$ROOT"
mkdir -p "$OUT"

# Take the lock (see above). hold-lock exits 2 if another operation holds it.
if [ "${CODEDB_LOCK_TOKEN:-}" != "$$" ]; then
    exec python3 -B "$HERE/codedb.py" --root "$ROOT" hold-lock --label capture_compile_commands.sh -- \
        "$HERE/$(basename "$0")" "$@"
fi
unset CODEDB_LOCK_TOKEN

# The start time of a process as `ps -o lstart=` prints it in the C locale
# and UTC, whitespace collapsed (as codedb.py reads it, in the same
# environment, PS_ENV), or nothing if there is no such process.
start_time() {
    LC_ALL=C TZ=UTC0 ps -o lstart= -p "$1" 2>/dev/null | awk '{$1 = $1; print}'
}

MY_START="$(start_time $$)"
# Rewrites the lock file in place (the flock is on that file), with an
# optional child line.
write_lock() {
    printf '%s\ncapture_compile_commands.sh\n%s\n%s' "$$" "$MY_START" "${1:+$1
}" > "$LOCK"
}
# Removed while fd 9 still holds the lock; the kernel releases it at exit.
release_lock() {
    rm -f "$LOCK"
}
trap release_lock EXIT
BUILD_PID=""
on_signal() {
    trap '' INT TERM HUP
    if [ -n "$BUILD_PID" ]; then
        echo "capture_compile_commands.sh: signal received; killing the build (process group $BUILD_PID)" >&2
        kill -KILL -- "-$BUILD_PID" 2>/dev/null || true
    fi
    exit "$1"
}
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap 'on_signal 129' HUP

if [ "$MODE" = other ]; then
    OTHER_FRAG="$OUT/other-fragments"
    OTHER_BUILD="$OUT/other-build"
    mkdir -p "$OTHER_FRAG" "$OTHER_BUILD"
    SPEC="$(python3 -B "$HERE/codedb.py" --root "$ROOT" other-projects)"
    FAILED=0
    # One project: name, project, configuration, targets, extra settings.
    capture_other() {
        local name="$1" project="$2" configuration="$3" targets="$4" settings="$5"
        local partial="$OTHER_FRAG/$name.partial" frag="$OTHER_FRAG/$name" build="$OTHER_BUILD/$name"
        local log="$OUT/other-build-$name.log"
        # xcodebuild creates the empty directory
        # project.xcworkspace/xcshareddata/swiftpm/configuration in the project
        # when it is missing; nothing may be written inside submodules/.
        case "$project" in
            submodules/*)
                if [ ! -d "$project/project.xcworkspace/xcshareddata/swiftpm" ]; then
                    echo "$name: not captured: xcodebuild would create $project/project.xcworkspace/xcshareddata/swiftpm inside the submodule" >&2
                    return 0
                fi;;
        esac
        rm -rf "$partial" "$build" || return 1
        mkdir -p "$partial" || return 1
        local record
        record="$(python3 -B "$HERE/codedb.py" --root "$ROOT" capture-record --project "$name")" || return 1
        local extra=()
        local t
        for t in $settings; do
            extra+=("$t")
        done
        echo "Building $name (log: $log). Fragments go to $partial"
        : > "$log"
        local status=0
        # One build per kept target, through the scheme of the same name:
        # xcodebuild takes -derivedDataPath (which keeps its caches out of
        # ~/Library/Developer/Xcode/DerivedData) only with -scheme.
        for t in $targets; do
            local args=(-project "$project" -scheme "$t" -configuration "$configuration"
                        -derivedDataPath "$build/dd" build
                        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
                        ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES
                        SYMROOT="$build" OBJROOT="$build/obj" SHARED_PRECOMPS_DIR="$build/pch"
                        COMPILER_INDEX_STORE_ENABLE=NO)
            args+=(${extra[@]+"${extra[@]}"} ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"}
                   "OTHER_CFLAGS=\$(inherited) -gen-cdb-fragment-path $partial")
            set +e
            set -m
            xcodebuild "${args[@]}" 9>&- < /dev/null >> "$log" 2>&1 &
            BUILD_PID=$!
            set +m
            write_lock "child $BUILD_PID $(start_time "$BUILD_PID")"
            wait "$BUILD_PID"
            status=$?
            BUILD_PID=""
            write_lock ""
            set -e
            [ $status -eq 0 ] || break
        done
        local count
        count=$(find "$partial" -name '*.json' | wc -l | tr -d ' ')
        echo "$name: xcodebuild exit status $status; $count fragments written."
        if [ $status -ne 0 ]; then
            echo "The build of $name failed. See $log" >&2
            echo "The previous capture of $name in $frag is unchanged; the partial fragments are in $partial." >&2
            grep -E "error: " "$log" | head -20 >&2 || true
            return 1
        fi
        printf '%s\n' "$record" > "$partial/.capture-record" || return 1
        date -u +%Y-%m-%dT%H:%M:%SZ > "$partial/.captured" || return 1
        rm -rf "$frag" || return 1
        mv "$partial" "$frag" || return 1
        echo "Captured $count fragments of $name in $frag."
    }
    while IFS=$'\t' read -r name project configuration targets settings; do
        [ -n "$name" ] || continue
        capture_other "$name" "$project" "$configuration" "$targets" "$settings" || FAILED=1
    done <<< "$SPEC"
    exit $FAILED
fi

rm -rf "$PARTIAL"
mkdir -p "$PARTIAL"

# The build settings, SDK and date as of the start of the build. Written to
# the fragments only if the build succeeds.
RECORD="$(python3 -B "$HERE/codedb.py" --root "$ROOT" capture-record)"

# The same preparation `make Development` does.
cp -f xcstrings/Localizable.xcstrings sources/Localizable.xcstrings
cp plists/dev-iTerm2.plist plists/iTerm2.plist

echo "Building (log: $LOG). Fragments go to $PARTIAL"
set +e
# Job control puts the background build in its own process group, which the
# signal handler kills as a whole.
set -m
xcodebuild clean build-for-testing \
    -project iTerm2.xcodeproj \
    -scheme ModernTests \
    -configuration Development \
    -destination 'platform=macOS' \
    -skipPackagePluginValidation \
    -enableAddressSanitizer NO \
    -enableUndefinedBehaviorSanitizer NO \
    -enableThreadSanitizer NO \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES \
    SYMROOT="$ROOT/Build" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    ${JOBS_ARGS[@]+"${JOBS_ARGS[@]}"} \
    "OTHER_CFLAGS=\$(inherited) -gen-cdb-fragment-path $PARTIAL" \
    9>&- > "$LOG" 2>&1 &
BUILD_PID=$!
set +m
write_lock "child $BUILD_PID $(start_time "$BUILD_PID")"
# A trapped signal interrupts wait at once; a foreground command would delay
# the trap until the build ended.
wait "$BUILD_PID"
STATUS=$?
BUILD_PID=""
write_lock ""
set -e

COUNT=$(find "$PARTIAL" -name '*.json' | wc -l | tr -d ' ')
echo "xcodebuild exit status $STATUS; $COUNT fragments written."
if [ $STATUS -ne 0 ]; then
    echo "The build failed. See $LOG" >&2
    echo "The previous capture in $FRAG and the compile database are unchanged;" \
         "the partial fragments are in $PARTIAL." >&2
    grep -E "error: " "$LOG" | head -20 >&2 || true
    exit $STATUS
fi
# The Swift side's inputs: the build log's SwiftDriver commands for the
# Variant-NoSanitizers variant and a copy of each module's .SwiftFileList,
# which the next build overwrites (codedb.py swift-capture, a streaming
# filter over the log).
python3 -B "$HERE/codedb.py" --root "$ROOT" swift-capture --log "$LOG" --into "$PARTIAL/swift"
printf '%s\n' "$RECORD" > "$PARTIAL/.capture-record"
date -u +%Y-%m-%dT%H:%M:%SZ > "$PARTIAL/.captured"
rm -rf "$FRAG"
mv "$PARTIAL" "$FRAG"
echo "Captured $COUNT fragments in $FRAG."
