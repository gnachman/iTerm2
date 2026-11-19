#!/bin/bash
# Regenerates the snapshot pairs in
# tools/swift_migration/tests/fixtures/runtime_snapshot_compare/ from the
# fixture classes in ModernTests/RuntimeSnapshotFixtures/RuntimeSnapshotPortFixtures.*,
# with tools/swift_migration/runtime_snapshot.sh (which builds and runs the
# test host, so it needs the build lane). test_compare_runtime_snapshots.py
# compares each pair.
#
# Each pair is a before.txt holding an Objective-C class and an after.txt
# holding a Swift class, both exactly as the snapshot tool wrote them, except
# that the Swift class's section is renamed to the Objective-C class's name,
# as a real port keeps it with @objc(Name): the two cannot have one name in
# one process. Only the "class" and "end class" lines are renamed. The
# renamed pair is the exception: its Swift class keeps its own name; and the
# renamed-module pair gives it ModernTests.<Objective-C name>, the runtime
# name of a port that forgot @objc(Name).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
OUT="$ROOT/tools/swift_migration/tests/fixtures/runtime_snapshot_compare"
TMP="$(mktemp -d "$ROOT/tmp/runtime-snapshot-compare-fixtures.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

"$ROOT/tools/swift_migration/runtime_snapshot.sh" "$TMP/all.txt" \
    RuntimeSnapshotPortObjCFixture RuntimeSnapshotPortSwiftFixture \
    RuntimeSnapshotPortSwiftDroppedMethodFixture RuntimeSnapshotPortSwiftChangedFixture \
    RuntimeSnapshotPortSwiftReadonlyFixture \
    RuntimeSnapshotPortLoadObjCFixture RuntimeSnapshotPortLoadSwiftFixture \
    RuntimeSnapshotPortAtomicObjCFixture RuntimeSnapshotPortAtomicSwiftFixture \
    RuntimeSnapshotPortAtomicSwiftReadonlyFixture \
    RuntimeSnapshotPortInitObjCFixture RuntimeSnapshotPortInitSwiftFixture

# The header: the lines before the first class section.
header() {
    awk '/^class /{exit} {print}' "$TMP/all.txt"
}

# The section of class $1, renamed to $2.
section() {
    awk -v name="$1" -v to="$2" '
        $0 == "class " name { inside = 1; print "class " to; next }
        inside && $0 == "end class " name { print "end class " to; inside = 0; next }
        inside { print }' "$TMP/all.txt"
}

pair() {
    local dir="$OUT/$1" before="$2" after="$3" name="$4"
    mkdir -p "$dir"
    { header; section "$before" "$before"; } > "$dir/before.txt"
    { header; section "$after" "$name"; } > "$dir/after.txt"
}

pair faithful RuntimeSnapshotPortObjCFixture RuntimeSnapshotPortSwiftFixture RuntimeSnapshotPortObjCFixture
pair dropped-method RuntimeSnapshotPortObjCFixture RuntimeSnapshotPortSwiftDroppedMethodFixture RuntimeSnapshotPortObjCFixture
pair changed-selector-encoding-protocol RuntimeSnapshotPortObjCFixture RuntimeSnapshotPortSwiftChangedFixture RuntimeSnapshotPortObjCFixture
pair readonly RuntimeSnapshotPortObjCFixture RuntimeSnapshotPortSwiftReadonlyFixture RuntimeSnapshotPortObjCFixture
pair renamed RuntimeSnapshotPortObjCFixture RuntimeSnapshotPortSwiftFixture RuntimeSnapshotPortSwiftFixture
pair load-initialize RuntimeSnapshotPortLoadObjCFixture RuntimeSnapshotPortLoadSwiftFixture RuntimeSnapshotPortLoadObjCFixture
pair atomic RuntimeSnapshotPortAtomicObjCFixture RuntimeSnapshotPortAtomicSwiftFixture RuntimeSnapshotPortAtomicObjCFixture
pair atomic-readonly RuntimeSnapshotPortAtomicObjCFixture RuntimeSnapshotPortAtomicSwiftReadonlyFixture RuntimeSnapshotPortAtomicObjCFixture
pair init-stub RuntimeSnapshotPortInitObjCFixture RuntimeSnapshotPortInitSwiftFixture RuntimeSnapshotPortInitObjCFixture
# The realistic renaming mistake: a port without @objc(Name), whose runtime
# name is Module.Name. The section is renamed to that name.
pair renamed-module RuntimeSnapshotPortObjCFixture RuntimeSnapshotPortSwiftFixture ModernTests.RuntimeSnapshotPortObjCFixture

for dir in "$OUT"/*/; do
    for file in "$dir"before.txt "$dir"after.txt; do
        if ! grep -q "^end class " "$file"; then
            echo "No class section in $file" >&2
            exit 1
        fi
    done
done
echo "Wrote the pairs in $OUT"
