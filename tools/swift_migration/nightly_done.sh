#!/bin/bash
# Tell the nightly supervisor that the session's work is done, so that it
# ends the session now instead of at the time limit.
#
# Part of the Objective-C to Swift migration tooling. See
# docs/swift-migration/workflow.md section 4 and the headers of
# nightly_start.sh and deadline_run.py (--done-file).
#
# Why. An interactive Claude Code session that has finished its work stays
# at its prompt. On 2026-11-25 a night finished at 01:40 and then sat idle
# until the supervisor's time limit at 05:54.
#
# Who runs it. The nightly session, as its last action: after the night's
# report is written and the lanes are released. Nothing may follow it: the
# supervisor then runs its stop sequence at once (Escape, Ctrl-C, /exit,
# then signals), kills what the session left running, and logs "session
# reported done".
#
# What it does. It writes the done marker, session.done, in the run
# directory that nightly_start.sh names in the session's environment
# (SWIFT_MIGRATION_NIGHT_DIR), which deadline_run.py --done-file watches.
# Each run has its own directory, and the supervisor ignores a marker that
# was already there when it started, so a marker from an earlier run cannot
# end a new one. Outside a nightly session (SWIFT_MIGRATION_NIGHTLY is not 1
# or the run directory is not given) it refuses and changes nothing.
#
# Usage:
#   tools/swift_migration/nightly_done.sh
#
# Exit status: 0 the marker is written; 1 it could not be written; 2 not in
# a nightly session.

set -u

if [ "${SWIFT_MIGRATION_NIGHTLY:-}" != 1 ] || [ -z "${SWIFT_MIGRATION_NIGHT_DIR:-}" ]; then
  echo "nightly_done: not in a nightly session (SWIFT_MIGRATION_NIGHTLY=1 and SWIFT_MIGRATION_NIGHT_DIR are set by nightly_start.sh); nothing done" >&2
  exit 2
fi
DIR=$SWIFT_MIGRATION_NIGHT_DIR
if [ -L "$DIR" ] || [ ! -d "$DIR" ]; then
  echo "nightly_done: the run directory $DIR is missing or a symbolic link; nothing done" >&2
  exit 1
fi
TMP=$(mktemp "$DIR/.session.done.XXXXXX") || { echo "nightly_done: cannot write in $DIR" >&2; exit 1; }
date '+%Y-%m-%dT%H:%M:%S%z' > "$TMP" || { rm -f "$TMP"; echo "nightly_done: cannot write $TMP" >&2; exit 1; }
mv -f "$TMP" "$DIR/session.done" || { rm -f "$TMP"; echo "nightly_done: cannot write $DIR/session.done" >&2; exit 1; }
echo "nightly_done: wrote $DIR/session.done; the supervisor ends this session within seconds. Type nothing more."
exit 0
