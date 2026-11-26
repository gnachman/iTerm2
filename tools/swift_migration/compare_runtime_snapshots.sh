#!/bin/bash
# Compares two Objective-C runtime snapshots made by runtime_snapshot.sh and
# reports every difference. See docs/swift-migration/phase0.md section 9.
#
# Usage:
#   tools/swift_migration/compare_runtime_snapshots.sh <before-file> <after-file>
#
# A class whose language is objc before and swift after (a class ported to
# Swift) is compared by the rule "identical in meaning": the systematic
# differences a move to Swift brings are listed as expected, each with its
# reason; what the runtime cannot judge (a vanished ivar that code may reach
# by name, weak versus unowned, an added -init, an atomic property that Swift
# makes nonatomic) is listed under CHECK AGAINST THE SOURCE for the reviewer;
# everything else fails. A property listed only after on a class that is
# Swift after (ported or already Swift) is expected when it is readonly with
# no custom setter and its getter is a method of the class with the same
# encoding before and after, returning the property's type: Swift overrides
# an inherited getter the SDK imports as a property only with `override
# var` (the orchestrator's decision of 2026-11-26, open to the owner).
# The rules, and the
# experiment they come from, are described in
# ModernTests/RuntimeSnapshotComparison.swift.
#
# Exit status:
#   0  The snapshots match, apart from the expected differences allow-listed in
#      ModernTests/RuntimeSnapshotComparison.swift and, for a class ported to
#      Swift, the expected differences of that move. Items to check against
#      the source do not change the status; read them.
#   1  They differ, or some class gets no verdict: one that changed language
#      from Swift to Objective-C, or whose language is unknown in either
#      snapshot. A duplicate selector or an ivar ownership conflict in either
#      snapshot is a difference, except a duplicate that is identical in
#      both snapshots with every entry in a system image (not the app's,
#      the test bundle's or an embedded framework's), which is listed under
#      "Duplicates present in both snapshots, not from this app: ignored"
#      (the owner, 2026-11-25).
#   2  They cannot be compared: bad arguments, an unreadable file, input that is
#      not a well-formed snapshot, snapshots from different architectures,
#      build configurations, or variants, a failure to build this tool, or
#      any other failure of this script itself.
#   130  Interrupted.
#
# A pass means only that the recorded lines match. Known gaps, which this
# tool does not compare:
# - what methods do, including methods that decide at run time which selectors
#   or keys an object answers (respondsToSelector:, forwarding, method
#   resolution, valueForUndefinedKey:), so selectors a class forwards or
#   resolves dynamically are not covered
# - the contents of adopted protocols; only their names are recorded
# - classes not named in the snapshot, including the members of superclasses
#   and subclasses
# - the ownership of an ivar whose label says the runtime cannot tell it
#   (unretained-or-manual, manual, struct-or-cxx-object and the like; see
#   ivar_ownership_check.py for the compiler's answer), and of a Swift
#   class's stored properties
# - the type of an ivar whose encoding the runtime leaves unknown or empty
# - the class of an object parameter or return value, which every method
#   encoding writes as plain @ (NSString * becoming NSArray * is not seen);
#   the reviewer compares the Swift signatures with the Objective-C
#   declarations, and for an Objective-C header swift_interface.py shows the
#   types Swift sees
# - nullability: a Swift parameter that is not optional where the
#   Objective-C method accepted nil is not seen; nullability claims are
#   proven by the annotate process (docs/swift-migration/nullability.md) and
#   checked at run time by the nullability sanitizer configuration
# - ivar declaration order, which decides teardown order under ARC
# - the ownership of a property printed as unrecorded
# - weak versus unowned in Swift, including a property that a Swift extension
#   declares on an Objective-C class, which is printed as weak even when Swift
#   declared it unowned
# - for a Swift class, whether a member is dynamic
# - build configurations other than the one snapshotted
#
# The comparison is the same Swift code the ModernTests tests exercise. It is
# compiled into tmp/ on first use, and again whenever a SHA-256 digest of its
# source files, the compiler version and the compiler flags differs from the
# one recorded beside the binary at its last build. File times are not used,
# because they miss an edit made within the same second as the build and a
# file restored with an older time.
set -euo pipefail
# A failure of this script itself (a directory that cannot be written, a full
# disk) must exit 2, not 1, which would mean that the snapshots differ.
trap 'exit 2' ERR

if [[ $# -ne 2 ]]; then
    # Print the comment block above, without its leading "# ".
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
    exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCES=("$ROOT/ModernTests/RuntimeSnapshotComparison.swift"
         "$ROOT/tools/swift_migration/compare_runtime_snapshots_main.swift")
BINARY="$ROOT/tmp/runtime-snapshot-compare/compare_runtime_snapshots"

STAMP="$BINARY.sources-sha256"

# The digest of the sources as they are now (each file's own digest and path),
# with the compiler version and flags. A source that cannot be read is an
# error, not a reason to run an old binary. A source edited while the build is
# running is not detected; do not edit the sources during a comparison.
SWIFTC_FLAGS=(-parse-as-library -warnings-as-errors)
if ! digest="$( { shasum -a 256 "${SOURCES[@]}" && xcrun swiftc --version 2>&1 && echo "${SWIFTC_FLAGS[*]}"; } | shasum -a 256)"; then
    echo "Could not read the snapshot comparison tool's sources." >&2
    exit 2
fi

needs_build=1
if [[ -x "$BINARY" && -f "$STAMP" && "$(cat "$STAMP")" == "$digest" ]]; then
    needs_build=0
fi
if [[ $needs_build -eq 1 ]]; then
    mkdir -p "$(dirname "$BINARY")"
    # Build under a temporary name and move it into place, so two first runs
    # at once do not write the same file. A build failure exits 2, the code
    # for an error, not 1, which means the snapshots differ.
    TEMPORARY="$(mktemp "$BINARY.XXXXXX")"
    # Remove the partial binary if the build fails or is interrupted.
    trap 'rm -f "$TEMPORARY"' EXIT
    trap 'exit 130' INT TERM
    # Remove the old record first: if this run is interrupted between the two
    # moves below, the next run finds no record and builds again.
    rm -f "$STAMP"
    if ! xcrun swiftc "${SWIFTC_FLAGS[@]}" -o "$TEMPORARY" "${SOURCES[@]}"; then
        rm -f "$TEMPORARY"
        echo "Could not build the snapshot comparison tool; see the compiler errors above." >&2
        exit 2
    fi
    mv -f "$TEMPORARY" "$BINARY"
    printf '%s\n' "$digest" > "$TEMPORARY"
    mv -f "$TEMPORARY" "$STAMP"
    trap - EXIT INT TERM
fi

# If the binary cannot be run, exit 2. Without execfail, bash exits 1 on a
# failed exec, which would mean that the snapshots differ.
set +e
shopt -s execfail
exec "$BINARY" "$1" "$2"
exit 2
