#!/bin/bash
# Make and refresh the separate clone that the unattended Swift migration
# session works in.
#
# Part of the Objective-C to Swift migration tooling. See
# docs/swift-migration/workflow.md sections 4 and 5, and the header of
# tools/swift_migration/nightly_start.sh, which uses this script.
#
# Why a clone. The nightly session never runs in the owner's working
# checkout, so that nothing it does touches his working tree, index or
# build products, and so that its repository has no remote it can write.
#
# Layout. Every path is derived from the two paths this script is given
# (--source, the owner's checkout, and --clone); none is read from inside
# the clone:
#   SOURCE                the owner's checkout (default $NIGHTLY_SOURCE,
#                         else the checkout this script is in). Only read.
#   CLONE                 a normal clone; the session works here. Its own
#                         Build/, tmp/ and tmp/codedb. Default $NIGHTLY_CLONE,
#                         else <parent of SOURCE>/iterm2-migration-nightly.
#   CLONE.origin.git      MIRROR: a bare repository holding the project's
#                         origin/master (its master), and nothing else. It
#                         is the clone's only remote (origin), by local
#                         path. Setup leaves the marker file nightly-mirror
#                         in it.
#   CLONE.runs/           made by nightly_start.sh, mode 0700: the lock, the
#                         run directories and logs, the tmux socket, the
#                         owner-refs records. Outside the clone.
#   CLONE.lanes/          made by nightly_start.sh, mode 0700: the nightly
#                         orchestrator's build lanes, made by lane_clone.py
#                         (its default lanes directory for the clone), each
#                         a detached `git worktree add` of the clone. The
#                         session may edit there (claude --add-dir).
#                         Outside the clone.
#   CLONE/.git/swift-migration-nightly.conf
#                         git-config format: nightly.source, nightly.mirror,
#                         nightly.branch (master), written by setup. It is
#                         NOT trusted: refresh, status, reset and check
#                         refuse (exit 10) when it disagrees with the
#                         derived paths.
#
# Nothing read from inside the clone is trusted. The session can write
# anything in the clone, including .git/config, .git/hooks and the
# .gitmodules of its commits, so before refresh, status, reset or check
# does anything in the clone, it refuses (exit 10, nothing changed) when:
#   the clone or its .git is a symbolic link, .git is not a directory, or
#   .git or any directory under .git/modules that could serve as a git
#   directory (it holds HEAD, commondir, gitdir or config) has a commondir,
#   config.worktree, info/grafts or info/attributes file, lacks its own
#   HEAD, objects/ or refs/, or holds any symbolic link (a commondir would
#   send ref updates into another repository, for example the owner's);
#   .git/worktrees/ holds anything but worktree registrations of the one
#   shape git worktree add makes for a lane or a Claude Code agent
#   worktree: a directory <name> whose commondir says exactly ../.. and
#   whose gitdir names exactly CLONE.lanes/<name>/.git or
#   CLONE/.claude/worktrees/<name>/.git, with no config.worktree,
#   info/attributes or info/grafts (the lanes themselves, and the
#   submodule repositories inside them, which borrow objects from
#   .git/modules through objects/info/alternates, are outside the clone
#   and not checked);
#   a gitlink's .git in the working tree is a directory (an embedded
#   repository) or a link, or a .git file that does not point exactly at
#   .git/modules/<name> for the name .gitmodules gives (git would use that
#   git directory's configuration and attributes inside the submodule);
#   the configuration file disagrees with the derived paths;
#   the mirror is a symbolic link, is missing its marker, is not laid out
#   as a bare repository, holds a symbolic link, a hard-linked file or a
#   file of another user (refresh runs chmod -R on it);
#   remote.origin.url is not exactly the mirror's path, or
#   remote.origin.pushurl is not a nightly-push-disabled: URL;
#   the owner's checkout is inside the clone or the mirror, or either is
#   inside the owner's checkout;
#   the clone's, the mirror's or a submodule's git configuration holds any
#   setting outside the short list that setup makes (the core settings git
#   init writes, remote.origin.url/fetch/pushurl, branch.*.remote/merge,
#   submodule.*.url/active, receive.denyNonFastForwards/denyDeletes in the
#   mirror, and a submodule's core.worktree, which must point inside the
#   clone). This refuses every setting that makes git run a program
#   (core.fsmonitor, core.sshCommand, core.pager, alias.*, filter.*,
#   diff.external, credential.helper, url.*.insteadOf, remote.*.uploadpack,
#   submodule.*.update, include.path, core.hooksPath, ...).
# The owner resolves it by hand (git config --unset, removing the file),
# after looking at what the session did.
#
# Every git command these scripts run, in the clone, the mirror, the
# submodules or the owner's checkout, goes through g() below: no global or
# system configuration, and on the command line (which wins over the
# repository's configuration and reaches the git processes it starts, such
# as the checkout in a submodule update) core.hooksPath=/dev/null (no
# hook runs: not post-checkout, post-merge, reference-transaction or any
# other), core.fsmonitor=false, core.pager=cat, protocol.allow=never with
# protocol.file.allow=always (nothing but local transports), no
# credential helper, no askpass, no ssh; GIT_NO_REPLACE_OBJECTS=1 and
# GIT_OPTIONAL_LOCKS=0. The clone and the mirror are named explicitly
# (--git-dir, --work-tree), never discovered. status runs with
# --ignore-submodules=all, and each submodule is checked separately
# through its validated git directory. These flags do not cover settings
# that have no command-line override (filter.<name>.*, merge drivers):
# those are kept out by the configuration list above. A .git file or
# directory elsewhere in the working tree (an untracked or ignored nested
# repository, such as a SwiftPM checkout) is not checked: none of these
# git commands reads its configuration (verified for status, including
# --untracked-files=all).
#
# What stops a push from the session. These are guards against accident
# and against a session that wanders, not against one that sets out to
# defeat them: it runs as the owner, with his files and his keychain.
#   0. The network: the session's network access is not restricted (the
#      owner's decision); only this script fetches the upstream, over https
#      with no credentials, and nothing here gives the session a way to
#      push.
#   1. The mirror is made read-only (chmod -R a-w) after every refresh, and
#      it is a bare repository, so a push to it fails on the file system.
#      The owner's checkout is never a remote of anything here.
#   2. remote.origin.pushurl, in the clone and in every submodule, is
#      nightly-push-disabled://..., a transport git does not have, so
#      `git push` and `git push origin` fail before opening anything.
#   3. nightly_start.sh sets, in the session's environment:
#      url.nightly-push-blocked://.pushInsteadOf for every URL form (stops a
#      push to a URL or a path given on the command line or as a remote's
#      url); protocol.file.allow=user with GIT_PROTOCOL_FROM_USER=0 (stops
#      every local-path and file:// transport, including a remote with an
#      explicit pushurl, which pushInsteadOf does not rewrite, and
#      `git send-pack`, which ignores pushInsteadOf; it also stops fetching
#      and cloning from local paths, see NIGHTLY_ALLOW_LOCAL_GIT there); an
#      empty credential helper, GIT_TERMINAL_PROMPT=0 and askpass
#      /usr/bin/false (no https credentials); an ssh wrapper that refuses
#      git-receive-pack, and no ssh agent socket.
#   4. The session's deny rules (nightly_start.sh): git push, git send-pack,
#      git remote, anything mentioning pushurl, send-pack, receive-pack or
#      protocol.file, gh, ssh, ...
#   5. Detection, not prevention: nightly_start.sh records the refs of the
#      owner's checkout and of each of his submodule repositories, with a
#      checksum of their config files and hooks, before the session and
#      compares after it; a difference is listed prominently in the
#      morning log. It is a report only: his other agents and worktrees
#      share the repository and change it overnight too.
#   Known ways around them, for a session that tries: undo the environment
#   guards (env -u, GIT_CONFIG_COUNT=0, GIT_PROTOCOL_FROM_USER=1, or
#   `git -c protocol.file.allow=always`, since -c wins over the
#   environment), then push into the owner's checkout (any branch but the
#   checked-out one) or his submodule repositories by local path; write
#   files in the owner's checkout or his .git directly, without git (refs,
#   objects, config, hooks: only the refs, config and hooks are compared
#   afterwards); use his keychain credential helper
#   (git -c credential.helper=osxkeychain) or his ssh keys
#   (GIT_SSH_COMMAND=ssh) to push to GitHub through a remote with an
#   explicit pushurl; run gh with its default configuration; chmod the
#   mirror writable and push into it (harmless: the next refresh resets its
#   master); run any of these through an interpreter or a script, which no
#   deny rule matches. Only Claude Code's auto mode classifier stands in
#   the way of those.
#
# The upstream. The clone follows the project's origin/master on GitHub,
# not the owner's local master: porting stale code is pointless (the
# owner, 2026-11-20). The URL is the owner's checkout's remote.origin.url,
# read from his checkout each time (never from the clone). It is fetched
# over https only: an https URL as it is, git@host:path and ssh:// URLs as
# their https equivalent, so that fetching needs no credentials and no ssh
# agent; any other URL is refused by setup and makes a refresh go on without
# fetching. The fetch, by this script only (gnet() below), allows exactly
# the https transport, with credentials, askpass and ssh still disabled,
# objects checked on the way in (fetch.fsckObjects, transfer.fsckObjects),
# and a stalled transfer abandoned after 60 seconds below 1 KB/s.
# NIGHTLY_TEST_ALLOW_FILE_UPSTREAM=1 also allows file://, for the tests.
#
# How work flows (nothing here ever writes to the owner's checkout; it is
# only read):
#   setup: the mirror's master is set to the owner's origin/master as his
#   checkout last fetched it (no network; from GitHub only when he has no
#   origin/master), and the clone's master to his local master, so that
#   commits of his that are not on GitHub start in the clone as its own.
#   setup prints how far his master is ahead of and behind his
#   origin/master (from his remote-tracking ref, without fetching), and
#   warns when it is ahead: he should rebase and push first, or the clone
#   rebases those commits onto origin/master every night until they are
#   upstream.
#   refresh, before each night (nightly_start.sh runs it, not the session):
#     1. the mirror is made writable and master is fetched from the
#        upstream into it. The fetched commit must be a fast-forward of the
#        mirror's master (the project's history is linear and never
#        rewritten): if it is not, someone force-pushed, and the refresh
#        refuses (exit 9) with the mirror and the clone unchanged. If the
#        fetch fails (offline, a timeout, GitHub down), the refresh goes on
#        with the mirror as it is and prints "nightly_clone: upstream: NOT
#        REFRESHED: ...": a stale upstream is better than a lost night. The
#        mirror is made read-only again either way;
#     2. the clone fetches origin (the mirror); then, with C the clone's
#        master and O origin/master:
#          C == O                  nothing to do;
#          C is an ancestor of O   fast-forward the clone to O;
#          O is an ancestor of C   keep C: the clone's commits are not
#                                  pushed yet; the session continues on top
#                                  of them;
#          otherwise, if C's tree is O's, or merging C into O leaves O's
#          tree as it is (`git merge-tree --write-tree O C`: everything the
#          clone's commits change is upstream, even if the owner squashed,
#          reworded or reordered them)
#                                  save C as refs/nightly-saved/<stamp>,
#                                  reset the clone's master to O, and print
#                                  "nightly_clone: already-upstream: reset
#                                  to <O>";
#          otherwise               save C as refs/nightly/pre-rebase/<stamp>
#                                  and rebase the clone's own commits onto O
#                                  (rebase_clone below): those already in O
#                                  as equivalent patches are dropped
#                                  (`git rev-list --cherry-pick`), each
#                                  other one is merged onto the new tip with
#                                  `git merge-tree --write-tree
#                                  --merge-base=<its parent>` and committed
#                                  with `git commit-tree`, keeping its
#                                  author, author date and message, and one
#                                  that becomes empty is dropped. Nothing
#                                  touches the clone's master, index or
#                                  working tree until every commit has been
#                                  made, and no hook, editor or merge driver
#                                  runs, so the rebase is all or nothing:
#                                  then the clone's master moves to the new
#                                  tip ("nightly_clone: rebased: <n> commits
#                                  onto <O>"). If nothing is left to apply,
#                                  it resets to O as above. A conflict, a
#                                  merge commit among the clone's commits or
#                                  a commit that moves a submodule pointer
#                                  refuses (exit 9: "nightly_clone:
#                                  rebase-failed: ..." with the commit and
#                                  the files), and the clone is exactly as
#                                  it was. The owner rebases by hand, or
#                                  runs `nightly_clone.sh reset`, which
#                                  saves C under refs/nightly-saved/ and
#                                  resets the clone's master to O.
#        A git command that fails while comparing or rebasing is an error
#        (exit 7), never taken as "already upstream". Nothing is ever
#        merged, so history stays linear and no night's work is lost.
#     3. submodules are brought to the commits the clone's master records
#        (below).
#   In the morning the owner takes the night's commits with one command,
#   run anywhere; it does nothing unless his checkout has master checked
#   out, so that it cannot fast-forward another branch:
#     [ "$(git -C <source> symbolic-ref -q --short HEAD)" = master ] &&
#       git -C <source> fetch <clone> master && git -C <source> merge --ff-only FETCH_HEAD
#   then reviews them and pushes. If merge --ff-only refuses because his
#   master has commits the clone does not (his own unpushed commits, or an
#   earlier night's commits he took and did not push), then, after the
#   same fetch:
#     [ "$(git -C <source> symbolic-ref -q --short HEAD)" = master ] &&
#       git -C <source> rebase FETCH_HEAD
#   which replays his own commits on top of the night's work and drops
#   those already in it as equivalent patches, an earlier night's commits
#   he took included. (A cherry-pick of master..FETCH_HEAD would be wrong:
#   that range also holds upstream commits his master lacks.) On a day he
#   does not push, the clone keeps its commits and the next refresh
#   rebases them onto the new origin/master.
#
# Recovery. A refresh starts by removing lock files a killed git left in
# the clone's git directory or the mirror (index.lock, other *.lock files
# at the top, ref locks under refs/), each only when no process names that
# repository on its command line (these scripts excepted), and says so;
# when one does, it refuses (exit 8) and leaves the lock. After a
# force-push upstream, `reset --accept-rewritten-upstream` takes the
# rewritten master, keeping the mirror's old one under
# refs/nightly/rewritten/ and the clone's under refs/nightly-saved/.
#
# Known limits, not handled:
#   an owner amend of a night commit's code before he pushes it makes the
#   next night's rebase conflict (the night is refused with a clear message);
#   a night commit that is empty on purpose is dropped by the rebase;
#   a file under an ignored path is overwritten if the upstream starts
#   tracking that path;
#   a hunk the owner deliberately dropped from a squash of night commits is
#   applied again by the next rebase.
#
# Submodules. Each submodule the source checkout has initialized is cloned
# from the source's own submodule repository (<source>/.git/modules/<name>,
# recursively for nested ones) by file:// URL, so nothing comes from the
# network and no file is hard-linked to the owner's repositories (a local
# path clone would hard-link objects). Submodules the source has not
# initialized are left uninitialized here too. Each submodule's remote is
# that file:// URL with the same disabled push URL. When the clone's master
# records a submodule commit that neither the owner's submodule repository
# nor the clone's has (the upstream moved the submodule further than his
# checkout), refresh fetches that commit from the submodule's URL in
# .gitmodules at origin/master (at HEAD for a nested submodule), over https
# as above, never from a URL in the clone's configuration; if that fails,
# the submodule stays at its old commit and "nightly_clone:
# submodule-stale: <path>: ..." says so (the build may fail). The names and paths
# come from the clone's .gitmodules, which the session can change, so a
# name or path with a .. component, a leading /, or a character outside
# [A-Za-z0-9._/-] is refused, and a submodule's .git file must point at
# its git directory inside the clone's .git/modules.
#
# Untracked files. setup copies, once, the two things under the source's
# tmp/ that the orchestrator needs and the tools cannot make again:
# tmp/parked/ (the saved patches that claims.md points to) and
# tmp/stored-state-corpus/ (the stored-state originals collected on vm1).
# Everything else under tmp/ (the code database tmp/codedb, sanitizer
# builds, coverage runs) is made again by the tools in the clone, and Build/
# is not copied: the first night spends time on a full build and a code
# database extraction. --no-copy-tmp skips the copy.
#
# Usage:
#   nightly_clone.sh setup   [--source DIR] [--clone DIR] [--no-copy-tmp] [--dry-run]
#   nightly_clone.sh refresh [--source DIR] [--clone DIR]
#   nightly_clone.sh status  [--source DIR] [--clone DIR]  read-only (git ls-remote of the
#                                                           upstream): what refresh would do
#   nightly_clone.sh reset   [--source DIR] [--clone DIR] [--accept-rewritten-upstream]
#                            fetch the upstream, save the clone's master, reset it to origin/master;
#                            with the option, also when the upstream was force-pushed
#   nightly_clone.sh check   [--source DIR] [--clone DIR]  read-only: the layout checks above
#   nightly_clone.sh clear-locks [--source DIR] [--clone DIR] [--dry-run]
#                            remove stale locks as a refresh does (exit 8 if one is in use)
#   nightly_clone.sh rule-pathspecs   print the pathspecs of the rule files (one definition,
#                            read by nightly_start.sh's preflight and by setup's warning)
#   nightly_clone.sh owner-refs [--source DIR]   print the refs, config and hook checksums of
#                                                the owner's checkout and submodule repositories
#   nightly_clone.sh selftest   check that the git wrapper refuses non-local transports
# refresh and reset print machine-readable lines (nightly_start.sh copies
# them into the run's refresh.status): "nightly_clone: upstream: refreshed:
# ..." or "... upstream: NOT REFRESHED: ..." (or "upstream: REWRITTEN" with
# exit 9); "nightly_clone: upstream-commits: none" or "... upstream-commits:
# taken <base>..<new> (<n> commits)"; "nightly_clone: rebased: <n> commits
# onto <sha> ...", "... already-upstream: reset to <sha> ..." or
# "... rebase-failed: ..."; and "nightly_clone: submodule-stale: <path>:
# ..." for each submodule left behind.
#
# Exit status: 0 done; 7 failed (nothing half-done is left writable);
# 8 the clone is missing or not in a state to refresh (dirty, not on
# master); 9 refused: the clone's commits could not be rebased onto
# origin/master, or the upstream was force-pushed; 10 refused: the clone's layout or
# configuration is not what setup made (see above); 64 bad usage.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TOOL_REPO=$(cd "$SCRIPT_DIR/../.." && pwd -P)
PUSH_DISABLED='nightly-push-disabled://the-nightly-clone-cannot-push'
CONF_NAME='swift-migration-nightly.conf'
MARKER_NAME='nightly-mirror'
COPIED_TMP_ITEMS='parked stored-state-corpus'
BRANCH=master

say() { echo "nightly_clone: $*"; }
die() { local code=$1; shift; say "$*"; exit "$code"; }

COMMAND=${1:-}
[ -n "$COMMAND" ] && shift
SOURCE=
CLONE=
COPY_TMP=1
DRY_RUN=0
ACCEPT_REWRITTEN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --accept-rewritten-upstream) ACCEPT_REWRITTEN=1; shift ;;
    --source) SOURCE=${2:-}; shift 2 || die 64 "--source needs a value" ;;
    --clone) CLONE=${2:-}; shift 2 || die 64 "--clone needs a value" ;;
    --no-copy-tmp) COPY_TMP=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) die 64 "unknown option: $1" ;;
  esac
done
case "$COMMAND" in
  setup|refresh|status|reset|check|clear-locks|owner-refs|rule-pathspecs|selftest) ;;
  -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d'; exit 0 ;;
  *) die 64 "usage: nightly_clone.sh setup|refresh|status|reset|check|clear-locks|owner-refs|rule-pathspecs [options]" ;;
esac
if [ "$ACCEPT_REWRITTEN" = 1 ] && [ "$COMMAND" != reset ]; then
  die 64 "--accept-rewritten-upstream is for reset only"
fi

# The files that carry rules, settings or hooks into a session, as git
# pathspecs. nightly_start.sh's preflight reads this list
# (`nightly_clone.sh rule-pathspecs`), and setup warns about unpushed
# commits that touch it, so both use this one definition.
RULE_PATHSPECS=(':(glob)**/CLAUDE.md' ':(glob)**/CLAUDE.local.md' .claude .mcp.json)

# Quote one argument so that a printed command can be pasted into a shell.
q() {
  case "$1" in
    ''|*[!A-Za-z0-9_./:=@%+,-]*)
      printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
    *) printf '%s' "$1" ;;
  esac
}

# An absolute path without symlinks in its directories, for a path that may
# not exist yet. The last component is not resolved (see is_link checks).
absolute() {
  local dir base
  dir=$(dirname "$1"); base=$(basename "$1")
  dir=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
  echo "$dir/$base"
}

# True when $1 is $2 or inside it.
inside() {
  case "$1/" in "$2/"*) return 0 ;; esac
  return 1
}

# Git for these tools; see the header. Nothing from the environment that
# could point git elsewhere, no global or system configuration, and the
# settings that make git run programs overridden on the command line.
g() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
      -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
      -u GIT_CONFIG -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
      -u GIT_PROTOCOL_FROM_USER -u GIT_EXTERNAL_DIFF \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
      GIT_ASKPASS=/usr/bin/false SSH_ASKPASS=/usr/bin/false \
      GIT_SSH_COMMAND=/usr/bin/false GIT_PAGER=cat PAGER=cat \
      GIT_NO_REPLACE_OBJECTS=1 GIT_OPTIONAL_LOCKS=0 \
    git -c core.hooksPath=/dev/null -c core.fsmonitor=false \
        -c core.pager=cat -c core.sshCommand=/usr/bin/false \
        -c core.askPass=/usr/bin/false -c credential.helper= \
        -c protocol.allow=never -c protocol.file.allow=always \
        "$@"
}
# Git in the clone and in the mirror, named explicitly.
gc() { g --git-dir="$CLONE/.git" --work-tree="$CLONE" "$@"; }
gm() { g --git-dir="$MIRROR" "$@"; }

# Git for the one network operation these scripts make: fetching the
# upstream (and a submodule commit the clone lacks) over https. Everything
# g() disables stays disabled (credentials, askpass, ssh, hooks); the
# transports are https only; objects are checked on the way in; a transfer
# that stalls below 1 KB/s for 60 seconds is abandoned. The test hook
# NIGHTLY_TEST_ALLOW_FILE_UPSTREAM=1 also allows file:// (and only that),
# so that tests need no network.
gnet() {
  local file=never
  [ "${NIGHTLY_TEST_ALLOW_FILE_UPSTREAM:-}" = 1 ] && file=always
  g -c protocol.allow=never -c protocol.https.allow=always -c protocol.file.allow=$file \
    -c fetch.fsckObjects=true -c transfer.fsckObjects=true \
    -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 "$@"
}

# The https URL to fetch for git URL $1: https as it is; git@host:path and
# ssh://[user@]host[:port]/path as https://host/path, so that fetching
# needs no credentials and no ssh agent. Anything else fails (file:// only
# under the test hook).
https_url() {
  local u=$1 rest host
  case "$u" in
    https://?*) echo "$u" ;;
    git@?*:?*) rest=${u#git@}; echo "https://${rest%%:*}/${rest#*:}" ;;
    ssh://?*/?*)
      rest=${u#ssh://}; host=${rest%%/*}; host=${host#*@}; host=${host%%:*}
      echo "https://$host/${rest#*/}" ;;
    file://?*) [ "${NIGHTLY_TEST_ALLOW_FILE_UPSTREAM:-}" = 1 ] && echo "$u" || return 1 ;;
    *) return 1 ;;
  esac
}

# The upstream: the project's origin, as the owner's checkout names it
# (remote.origin.url, read from his checkout each time, never from the
# clone), fetched over https.
resolve_upstream() {
  UPSTREAM_RAW=$(g -C "$SOURCE" config --get remote.origin.url 2>/dev/null)
  UPSTREAM=$(https_url "$UPSTREAM_RAW") || UPSTREAM=
}

# The owner's morning commands: the fetch and fast-forward, and, when the
# fast-forward refuses, a rebase of his master onto the fetched commit. Both
# do nothing unless his checkout has master checked out.
morning_command() {
  local s c guard
  s=$(q "$SOURCE"); c=$(q "$CLONE")
  guard="[ \"\$(git -C $s symbolic-ref -q --short HEAD)\" = $BRANCH ]"
  echo "  $guard && git -C $s fetch $c $BRANCH && git -C $s merge --ff-only FETCH_HEAD"
  echo "  if that fast-forward refuses (your $BRANCH has commits the clone does not), run this after the fetch; it replays your own commits on top of the night's work and drops those already in it as equivalent patches, an earlier night's commits you took included:"
  echo "  $guard && git -C $s rebase FETCH_HEAD"
}

# Pids of processes whose command line names path $1 (followed by a space,
# a slash or the end), other than these scripts themselves.
processes_naming() {
  local path=$1 snapshot line rest found=
  snapshot=$(ps -axo pid=,command= 2>/dev/null)
  while IFS= read -r line; do
    case "$line " in
      *nightly_clone.sh*|*nightly_start.sh*) continue ;;
      *"$path "*|*"$path/"*) ;;
      *) continue ;;
    esac
    rest=${line#"${line%%[![:space:]]*}"}
    found="$found${rest%%[[:space:]]*} "
  done <<< "$snapshot"
  printf '%s' "${found% }"
}

# Lock files that a killed git leaves behind, in the clone's git directory
# and in the mirror: index.lock and the other *.lock files at the top, and
# ref locks under refs/. Each is removed, and said so, when no process names
# its repository on its command line; otherwise refuse (exit 8) and leave
# it. With $1 = dry, only say what would happen.
clear_stale_locks() {
  local mode=${1:-} repo top lock pids mirror_touched=0
  for top in "$CLONE" "$MIRROR"; do
    repo=$top; [ "$top" = "$CLONE" ] && repo="$CLONE/.git"
    while IFS= read -r lock; do
      [ -n "$lock" ] || continue
      pids=$(processes_naming "$top")
      if [ -n "$pids" ]; then
        die 8 "not refreshing: $lock exists, and process $pids names $top on its command line, so a git command may still be using it; look, then remove the lock by hand"
      fi
      if [ "$mode" = dry ]; then
        say "stale lock $lock (no process names $top); a real run would remove it"
        continue
      fi
      if [ "$top" = "$MIRROR" ]; then chmod u+w "$(dirname "$lock")" 2>/dev/null; mirror_touched=1; fi
      rm -f "$lock" || die 7 "cannot remove $lock"
      say "removed a stale lock $lock (no process names $top on its command line)"
    done < <({ find "$repo" -maxdepth 1 -type f -name '*.lock'; find "$repo/refs" -type f -name '*.lock'; } 2>/dev/null)
  done
  [ "$mirror_touched" = 0 ] || make_mirror_read_only
}

mirror_writable_entry() {
  find "$MIRROR" \( -perm -u+w -o -perm -g+w -o -perm -o+w \) -print 2>/dev/null | head -1
}

make_mirror_read_only() {
  chmod -R -P a-w "$MIRROR" 2>/dev/null
  local left
  left=$(mirror_writable_entry)
  if [ -n "$left" ]; then
    say "COULD NOT MAKE THE MIRROR READ-ONLY: $left is writable"
    return 1
  fi
  return 0
}

MIRROR_OPEN=0
on_exit() {
  if [ "$MIRROR_OPEN" = 1 ]; then
    make_mirror_read_only
  fi
}
trap on_exit EXIT

# At setup: the mirror's master is the owner's origin/master as his
# checkout last fetched it (a local fetch; nothing from the network), so
# that the first night's upstream fetch is a fast-forward of it. Falls back
# to the upstream when his checkout has no origin/master.
fill_mirror() {
  MIRROR_OPEN=1
  local rc=0
  if g -C "$SOURCE" rev-parse -q --verify "refs/remotes/origin/$BRANCH" >/dev/null; then
    gm fetch -q --no-tags --no-recurse-submodules "$SOURCE" \
      "+refs/remotes/origin/$BRANCH:refs/heads/$BRANCH" || rc=1
  else
    gnet --git-dir="$MIRROR" fetch -q --no-tags --no-recurse-submodules "$UPSTREAM" \
      "+refs/heads/$BRANCH:refs/heads/$BRANCH" || rc=1
  fi
  make_mirror_read_only || rc=1
  MIRROR_OPEN=0
  return $rc
}

# Each night: fetch the upstream's master into the mirror. The fetched
# commit must be a fast-forward of the mirror's master: the project's
# history is linear and never rewritten, so anything else means someone
# force-pushed, and the night is refused (return 9, the mirror unchanged).
# When the fetch itself fails (offline, timeout, the upstream down, an
# upstream that is not https) the night goes on with the mirror as it is,
# and the line "nightly_clone: upstream: NOT REFRESHED ..." says so.
# Returns 7 when the mirror cannot be made writable.
fetch_upstream() {
  local old new out
  old=$(gm rev-parse -q --verify "refs/heads/$BRANCH")
  if [ -z "$UPSTREAM" ]; then
    say "upstream: NOT REFRESHED: the owner's origin URL '$UPSTREAM_RAW' cannot be fetched over https; going on with the mirror's master ${old:-(none)}"
    return 0
  fi
  MIRROR_OPEN=1
  chmod -R -P u+w "$MIRROR" || { make_mirror_read_only; MIRROR_OPEN=0; return 7; }
  if ! out=$(gnet --git-dir="$MIRROR" fetch -q --no-tags --no-recurse-submodules "$UPSTREAM" \
               "+refs/heads/$BRANCH:refs/nightly-incoming" 2>&1); then
    gm update-ref -d refs/nightly-incoming 2>/dev/null
    make_mirror_read_only; MIRROR_OPEN=0
    say "upstream: NOT REFRESHED: fetching $BRANCH from $UPSTREAM failed: $(printf '%s' "$out" | tr '\n' ' '); going on with the mirror's master ${old:-(none)}"
    return 0
  fi
  new=$(gm rev-parse refs/nightly-incoming)
  if [ -n "$old" ] && ! gm merge-base --is-ancestor "$old" "$new"; then
    if [ "$ACCEPT_REWRITTEN" = 1 ]; then
      local kept="refs/nightly/rewritten/$(date +%Y%m%d-%H%M%S)-${old:0:12}"
      gm update-ref "$kept" "$old" || { gm update-ref -d refs/nightly-incoming; make_mirror_read_only; MIRROR_OPEN=0; return 7; }
      say "upstream: REWRITTEN and accepted (--accept-rewritten-upstream): kept the mirror's old $BRANCH $old as $kept in the mirror"
    else
      gm update-ref -d refs/nightly-incoming
      make_mirror_read_only; MIRROR_OPEN=0
      say "upstream: REWRITTEN: $UPSTREAM's $BRANCH ($new) does not contain the mirror's $old: someone force-pushed; the mirror and the clone are unchanged; look at what happened upstream, then accept it with: $(q "$SCRIPT_DIR/nightly_clone.sh") reset --accept-rewritten-upstream --clone $(q "$CLONE") (which keeps the old $BRANCH under refs/nightly/rewritten/ in the mirror and the clone's under refs/nightly-saved/)"
      return 9
    fi
  fi
  gm update-ref "refs/heads/$BRANCH" "$new" && gm update-ref -d refs/nightly-incoming
  make_mirror_read_only || { MIRROR_OPEN=0; return 7; }
  MIRROR_OPEN=0
  say "upstream: refreshed: $BRANCH is $new (from $UPSTREAM)"
  return 0
}

# The settings setup makes; anything else in these files is refused.
CLONE_KEYS='^(core\.(repositoryformatversion|filemode|bare|logallrefupdates|ignorecase|precomposeunicode)|remote\.origin\.(url|fetch|pushurl)|branch\..+\.(remote|merge)|submodule\..+\.(url|active))$'
MODULE_KEYS='^(core\.(repositoryformatversion|filemode|bare|logallrefupdates|ignorecase|precomposeunicode|worktree)|remote\.origin\.(url|fetch|pushurl)|branch\..+\.(remote|merge)|submodule\..+\.(url|active))$'
MIRROR_KEYS='^(core\.(repositoryformatversion|filemode|bare|logallrefupdates|ignorecase|precomposeunicode)|receive\.(denynonfastforwards|denydeletes))$'

# Prints a problem if config file $1 ($2 names it) has a setting outside
# the regular expression $3. Reading a file with git config -f runs nothing
# and follows no include.
config_problem() {
  local file=$1 label=$2 allowed=$3 names bad
  if [ -L "$file" ] || [ ! -f "$file" ]; then
    echo "$label: $file is missing or not a regular file"; return
  fi
  if ! names=$(g config -f "$file" --list --name-only 2>&1); then
    echo "$label: cannot read $file: $names"; return
  fi
  bad=$(printf '%s\n' "$names" | grep -v '^$' | grep -Ev "$allowed" | sort -u | tr '\n' ' ')
  if [ -n "$bad" ]; then
    echo "$label has settings that setup did not make (they could make git run a program or write elsewhere): ${bad% }; look, then remove them with git config -f $(q "$file") --unset-all NAME"
  fi
}

# Prints a problem about git directory $1 ($2 names it) holding anything
# that redirects git to another repository.
gitdir_problem() {
  local dir=$1 label=$2 name link
  if [ -L "$dir" ] || [ ! -d "$dir" ]; then
    echo "$label: $dir is a symbolic link or not a directory"; return
  fi
  for name in commondir config.worktree info/grafts gitdir; do
    if [ -e "$dir/$name" ] || [ -L "$dir/$name" ]; then
      echo "$label: $dir/$name exists (it would make git read or write another repository)"; return
    fi
  done
  # Setup never writes info/attributes, which could name a filter.
  if [ -e "$dir/info/attributes" ] || [ -L "$dir/info/attributes" ]; then
    echo "$label: $dir/info/attributes exists (setup does not write one)"; return
  fi
  if [ ! -f "$dir/HEAD" ] || [ ! -d "$dir/objects" ] || [ ! -d "$dir/refs" ]; then
    echo "$label: $dir lacks its own HEAD, objects/ or refs/"; return
  fi
  link=$(find "$dir" -type l -print 2>/dev/null | head -1)
  if [ -n "$link" ]; then
    echo "$label: $link is a symbolic link"; return
  fi
}

# Prints a problem about the worktree registrations in the clone's
# .git/worktrees/. git worktree add (lane_clone.py's lanes, and Claude
# Code's agent worktrees) registers worktree <name> there with a commondir
# file, which must say exactly ../.. (this repository), and a gitdir file,
# which must name exactly <clone>.lanes/<name>/.git or
# <clone>/.claude/worktrees/<name>/.git. A config.worktree, info/attributes
# or info/grafts in a registration, an entry that is not a directory, and
# any other commondir or gitdir are refused. Nothing in a lane itself is
# looked at: the lanes are outside the clone, and their submodule
# repositories borrow objects from .git/modules through alternates.
worktrees_problem() {
  local reg="$CLONE/.git/worktrees" dir name f v
  [ -e "$reg" ] || [ -L "$reg" ] || return 0
  if [ -L "$reg" ] || [ ! -d "$reg" ]; then
    echo "$reg is a symbolic link or not a directory"; return
  fi
  for dir in "$reg"/* "$reg"/.[!.]* "$reg"/..?*; do
    [ -e "$dir" ] || [ -L "$dir" ] || continue
    name=${dir##*/}
    if [ -L "$dir" ] || [ ! -d "$dir" ]; then
      echo "$dir is not a worktree registration (not a directory)"; return
    fi
    case "$name" in
      .*|*[!A-Za-z0-9._-]*) echo "$dir is not a worktree registration git makes (its name)"; return ;;
    esac
    for f in config.worktree info/attributes info/grafts; do
      if [ -e "$dir/$f" ] || [ -L "$dir/$f" ]; then
        echo "$dir/$f exists (git worktree add does not write one)"; return
      fi
    done
    f="$dir/commondir"
    if [ ! -f "$f" ] || [ "$(cat "$f")" != '../..' ]; then
      echo "$f is missing or does not say ../.. (it would make git read or write another repository)"; return
    fi
    f="$dir/gitdir"
    v=$( [ -f "$f" ] && cat "$f")
    if [ "$v" != "$CLONE.lanes/$name/.git" ] && [ "$v" != "$CLONE/.claude/worktrees/$name/.git" ]; then
      echo "$f names '$v', not the lane $CLONE.lanes/$name/.git or the agent worktree $CLONE/.claude/worktrees/$name/.git"; return
    fi
  done
}

# Checks submodule git directory $1 (under the clone's .git/modules): the
# git directory checks, the configuration list, and a core.worktree inside
# the clone's working tree (equal to $2 when given).
module_problem() {
  local dir=$1 want=${2:-} p wt resolved
  p=$(gitdir_problem "$dir" "a submodule's git directory"); [ -z "$p" ] || { echo "$p"; return; }
  p=$(config_problem "$dir/config" "$dir/config" "$MODULE_KEYS"); [ -z "$p" ] || { echo "$p"; return; }
  wt=$(g config -f "$dir/config" --get-all core.worktree)
  if [ -n "$wt" ]; then
    if ! resolved=$(cd "$dir" 2>/dev/null && cd "$wt" 2>/dev/null && pwd -P); then
      echo "$dir/config: core.worktree $wt does not exist"; return
    fi
    if ! inside "$resolved" "$CLONE" || inside "$resolved" "$CLONE/.git"; then
      echo "$dir/config: core.worktree $wt points outside the clone's working tree ($resolved)"; return
    fi
    if [ -n "$want" ] && [ "$resolved" != "$(cd "$want" 2>/dev/null && pwd -P)" ]; then
      echo "$dir/config: core.worktree $wt is not the submodule's path $want"; return
    fi
  fi
}

# The name .gitmodules (in working tree $1) gives the submodule at path $2.
module_name() {
  g config -f "$1/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null |
    while IFS= read -r line; do
      if [ "${line#* }" = "$2" ]; then
        line=${line%% *}; line=${line#submodule.}; echo "${line%.path}"; break
      fi
    done
}

# Every gitlink in the index of repository $1 (git directory $2): its .git
# must be absent (not initialized) or a regular file pointing exactly at
# $2/modules/<name> for the name .gitmodules gives, a validated submodule
# git directory whose core.worktree is that path. An embedded repository
# (a .git directory) or a symbolic link is refused. Recursive. Runs only
# ls-files in repositories already checked, which runs no filter.
gitlinks_problem() {
  local dir=$1 gitdir=$2 mode sha stage path name gitfile target want p
  while IFS=$' \t' read -r mode sha stage path; do
    [ "$mode" = 160000 ] || continue
    gitfile="$dir/$path/.git"
    if [ ! -e "$gitfile" ] && [ ! -L "$gitfile" ]; then continue; fi
    if [ -L "$gitfile" ] || [ ! -f "$gitfile" ]; then
      echo "the submodule $dir/$path has a .git that is not a regular .git file (an embedded repository or a link)"; return
    fi
    name=$(module_name "$dir" "$path")
    if [ -z "$name" ] || ! plain_relative_path "$name"; then
      echo "the submodule $dir/$path has a .git file but no plain name in $dir/.gitmodules"; return
    fi
    want="$gitdir/modules/$name"
    target=$(sed -n 's/^gitdir: //p' "$gitfile" | head -1)
    case "$target" in /*) ;; *) target="$dir/$path/$target" ;; esac
    target=$(cd "$target" 2>/dev/null && pwd -P)
    if [ -z "$target" ] || [ "$target" != "$(cd "$want" 2>/dev/null && pwd -P)" ]; then
      echo "$gitfile points at '$target', not the submodule's git directory $want"; return
    fi
    p=$(module_problem "$want" "$dir/$path"); [ -z "$p" ] || { echo "$p"; return; }
    p=$(gitlinks_problem "$dir/$path" "$want"); [ -z "$p" ] || { echo "$p"; return; }
  done < <(g --git-dir="$gitdir" --work-tree="$dir" ls-files -s 2>/dev/null)
}

check_mirror() {
  local bad
  if [ -L "$MIRROR" ]; then echo "the mirror $MIRROR is a symbolic link"; return; fi
  if [ ! -d "$MIRROR" ]; then echo "the mirror $MIRROR is missing"; return; fi
  if [ ! -O "$MIRROR" ]; then echo "the mirror $MIRROR is not yours"; return; fi
  if [ -L "$MIRROR/$MARKER_NAME" ] || [ ! -f "$MIRROR/$MARKER_NAME" ]; then
    echo "the mirror $MIRROR has no $MARKER_NAME marker (setup leaves one): not a mirror made by setup"; return
  fi
  if [ ! -f "$MIRROR/HEAD" ] || [ ! -d "$MIRROR/objects" ] || [ ! -d "$MIRROR/refs" ] ||
     [ -e "$MIRROR/.git" ]; then
    echo "the mirror $MIRROR is not laid out as a bare repository"; return
  fi
  for name in commondir config.worktree info/grafts; do
    if [ -e "$MIRROR/$name" ]; then echo "the mirror has $MIRROR/$name"; return; fi
  done
  bad=$(find "$MIRROR" \( -type l -o \( -type f -links +1 \) -o ! -user "$(id -u)" \) -print 2>/dev/null | head -1)
  if [ -n "$bad" ]; then
    echo "the mirror holds $bad, a symbolic link, a hard-linked file or another user's file (refresh would chmod it)"; return
  fi
  config_problem "$MIRROR/config" "the mirror's configuration" "$MIRROR_KEYS"
  [ "$(g config -f "$MIRROR/config" --get-all core.bare 2>/dev/null)" = true ] ||
    echo "the mirror's core.bare is not true"
}

# The checks in the header, before anything is done in the clone. Prints
# the first problem found; nothing when the layout is as setup made it.
layout_problem() {
  local conf="$CLONE/.git/$CONF_NAME" p v names
  if [ -L "$CLONE" ]; then echo "the clone $CLONE is a symbolic link"; return; fi
  if inside "$SOURCE" "$CLONE" || inside "$SOURCE" "$MIRROR" ||
     inside "$CLONE" "$SOURCE" || inside "$MIRROR" "$SOURCE"; then
    echo "the owner's checkout $SOURCE and the clone $CLONE or its mirror are inside one another"; return
  fi
  p=$(gitdir_problem "$CLONE/.git" "the clone's git directory"); [ -z "$p" ] || { echo "$p"; return; }
  p=$(worktrees_problem); [ -z "$p" ] || { echo "$p"; return; }
  # The configuration file: only the three settings setup writes, and
  # they must agree with the derived paths.
  if ! names=$(g config -f "$conf" --list --name-only 2>&1); then
    echo "cannot read $conf: $names"; return
  fi
  if [ "$(printf '%s\n' "$names" | sort | tr '\n' ' ')" != "nightly.branch nightly.mirror nightly.source " ]; then
    echo "$conf holds settings other than nightly.source, nightly.mirror and nightly.branch: $(printf '%s' "$names" | tr '\n' ' ')"; return
  fi
  v=$(g config -f "$conf" --get-all nightly.source)
  [ "$v" = "$SOURCE" ] || { echo "$conf disagrees: nightly.source is '$v', but the owner's checkout is $SOURCE"; return; }
  v=$(g config -f "$conf" --get-all nightly.mirror)
  [ "$v" = "$MIRROR" ] || { echo "$conf disagrees: nightly.mirror is '$v', but the mirror is $MIRROR (always <clone>.origin.git)"; return; }
  v=$(g config -f "$conf" --get-all nightly.branch)
  [ "$v" = "$BRANCH" ] || { echo "$conf disagrees: nightly.branch is '$v', not $BRANCH"; return; }
  p=$(check_mirror); [ -z "$p" ] || { echo "$p"; return; }
  # The clone's own configuration.
  p=$(config_problem "$CLONE/.git/config" "the clone's .git/config" "$CLONE_KEYS"); [ -z "$p" ] || { echo "$p"; return; }
  v=$(g config -f "$CLONE/.git/config" --get-all remote.origin.url)
  [ "$v" = "$MIRROR" ] || { echo "origin is '$v', not the mirror $MIRROR"; return; }
  v=$(g config -f "$CLONE/.git/config" --get-all remote.origin.pushurl)
  case "$v" in
    nightly-push-disabled:*) [ "$(printf '%s\n' "$v" | grep -cv '^nightly-push-disabled:')" = 0 ] ||
                               { echo "origin has more than one push URL: $(printf '%s' "$v" | tr '\n' ' ')"; return; } ;;
    *) echo "origin's push URL is '$v', not a nightly-push-disabled: URL"; return ;;
  esac
  v=$(g config -f "$CLONE/.git/config" --get-all remote.origin.fetch)
  [ "$v" = '+refs/heads/*:refs/remotes/origin/*' ] ||
    { echo "origin's fetch refspec is '$v', not the one clone makes"; return; }
  [ "$(g config -f "$CLONE/.git/config" --get-all core.bare)" = false ] ||
    { echo "the clone's core.bare is not false"; return; }
  # Every directory under .git/modules that could serve as a git
  # directory (it holds HEAD, commondir, gitdir or config), whether or not
  # it has objects/: each must be a complete submodule git directory with
  # no redirect.
  if [ -d "$CLONE/.git/modules" ]; then
    local dir
    while IFS= read -r dir; do
      p=$(module_problem "$dir"); [ -z "$p" ] || { echo "$p"; return; }
    done < <(find "$CLONE/.git/modules" \( -name HEAD -o -name commondir -o -name gitdir -o -name config \) \
               ! -path '*/logs/*' ! -path '*/refs/*' ! -path '*/objects/*' ! -path '*/hooks/*' \
               -exec dirname {} \; 2>/dev/null | sort -u)
  fi
  # Every gitlink's .git, before any git command looks inside a submodule.
  p=$(gitlinks_problem "$CLONE" "$CLONE/.git"); [ -z "$p" ] || { echo "$p"; return; }
}

# Validates a submodule name or path from .gitmodules.
plain_relative_path() {
  case "$1" in
    ''|/*|*[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  case "/$1/" in
    */../*|*/./*|*//*) return 1 ;;
  esac
  return 0
}

# Checks that submodule working tree $1 has a .git file pointing at git
# directory $2 (inside the clone's .git); says why not and returns 1.
gitfile_problem() {
  local gitfile="$1/.git" want=$2 target
  if [ -L "$gitfile" ] || [ ! -f "$gitfile" ]; then
    say "submodule $1: $gitfile is not a .git file"; return 1
  fi
  target=$(sed -n 's/^gitdir: //p' "$gitfile" | head -1)
  case "$target" in /*) ;; *) target="$1/$target" ;; esac
  target=$(cd "$target" 2>/dev/null && pwd -P) || { say "submodule $1: $gitfile points nowhere"; return 1; }
  want=$(cd "$want" 2>/dev/null && pwd -P) || { say "submodule $1: no git directory at $2"; return 1; }
  if [ "$target" != "$want" ]; then
    say "submodule $1: $gitfile points at $target, not $want"; return 1
  fi
  return 0
}

# Initialize and update the submodules of repository $1 (its git directory
# is $2) that the source has initialized, from the source's own module
# repositories under $3 (a git directory), recursively.
# Fetches commit $4 of submodule $2 (git directory $3, path $5) from the
# URL that .gitmodules gives at the upstream commit (for the clone itself;
# at HEAD for a nested submodule), over https only. Says why not and
# returns 1 when it cannot.
fetch_submodule_commit() {
  local gitdir=$1 name=$2 subgit=$3 sha=$4 path=$5 dir=$6 rev=HEAD raw url out
  if [ "$dir" = "$CLONE" ] && [ -n "${UPSTREAM_REV:-}" ]; then rev=$UPSTREAM_REV; fi
  raw=$(g --git-dir="$gitdir" config --blob "$rev:.gitmodules" --get "submodule.$name.url" 2>/dev/null)
  if [ ! -d "$subgit" ]; then
    say "submodule-stale: $path: needs $sha, and it has no repository in the clone yet; left as it is (the build may fail)"
    return 1
  fi
  if ! url=$(https_url "$raw"); then
    say "submodule-stale: $path: needs $sha, which no local repository has, and its URL '$raw' cannot be fetched over https; left at its old commit (the build may fail)"
    return 1
  fi
  if ! out=$(gnet --git-dir="$subgit" fetch -q --no-tags --no-recurse-submodules "$url" "$sha" 2>&1) ||
     ! g --git-dir="$subgit" cat-file -e "$sha^{commit}" 2>/dev/null; then
    say "submodule-stale: $path: fetching $sha from $url failed: $(printf '%s' "$out" | tr '\n' ' '); left at its old commit (the build may fail)"
    return 1
  fi
  say "submodule $path: fetched $sha from $url"
}

init_submodules() {
  local dir=$1 gitdir=$2 owner_gitdir=$3 line key path name moddir subgit sha
  [ -f "$dir/.gitmodules" ] || return 0
  [ ! -L "$dir/.gitmodules" ] || { say "$dir/.gitmodules is a symbolic link"; return 1; }
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key=${line%% *}; path=${line#* }
    name=${key#submodule.}; name=${name%.path}
    if ! plain_relative_path "$name" || ! plain_relative_path "$path"; then
      say "submodule name '$name' or path '$path' in $dir/.gitmodules is not a plain relative path; refusing it"
      return 1
    fi
    moddir="$owner_gitdir/modules/$name"
    if [ ! -d "$moddir" ]; then
      say "submodule $path: not initialized in the source checkout; left uninitialized"
      continue
    fi
    subgit="$gitdir/modules/$name"
    if [ -e "$dir/$path/.git" ] || [ -L "$dir/$path/.git" ]; then
      gitfile_problem "$dir/$path" "$subgit" || return 1
    fi
    g config -f "$gitdir/config" "submodule.$name.url" "file://$moddir" || return 1
    g config -f "$gitdir/config" "submodule.$name.active" true || return 1
    # A recorded commit that neither the owner's submodule repository nor
    # the clone's has (the upstream moved the submodule further than the
    # owner's checkout): fetched from the URL in .gitmodules at the upstream
    # commit, over https. If that fails the submodule stays where it was.
    sha=$(g --git-dir="$gitdir" --work-tree="$dir" ls-files -s -- "$path" | awk '$1 == 160000 { print $2; exit }')
    if [ -n "$sha" ] && ! g --git-dir="$moddir" cat-file -e "$sha^{commit}" 2>/dev/null &&
       ! { [ -d "$subgit" ] && g --git-dir="$subgit" cat-file -e "$sha^{commit}" 2>/dev/null; }; then
      if ! fetch_submodule_commit "$gitdir" "$name" "$subgit" "$sha" "$path" "$dir"; then
        continue
      fi
    fi
    # git submodule needs a working tree found from the directory: $dir/.git
    # is the clone's checked .git directory, or a .git file checked below.
    if ! g -C "$dir" submodule update -q --init -- "$path"; then
      say "submodule $path: update from file://$moddir failed"
      return 1
    fi
    { [ -d "$subgit" ] && [ ! -L "$subgit" ]; } || { say "submodule $path: no git directory at $subgit"; return 1; }
    gitfile_problem "$dir/$path" "$subgit" || return 1
    g config -f "$subgit/config" remote.origin.url "file://$moddir" || return 1
    g config -f "$subgit/config" remote.origin.pushurl "$PUSH_DISABLED" || return 1
    init_submodules "$dir/$path" "$subgit" "$moddir" || return 1
  done < <(g config -f "$dir/.gitmodules" --get-regexp '^submodule\..*\.path$')
  return 0
}

copy_tmp_items() {
  local item
  for item in $COPIED_TMP_ITEMS; do
    if [ -e "$SOURCE/tmp/$item" ]; then
      mkdir -p "$CLONE/tmp" && cp -Rp "$SOURCE/tmp/$item" "$CLONE/tmp/" || return 1
      say "copied tmp/$item ($(du -sh "$CLONE/tmp/$item" | cut -f1))"
    else
      say "tmp/$item: not in the source checkout; nothing copied"
    fi
  done
}

resolve_source() {
  [ -n "$SOURCE" ] || SOURCE=${NIGHTLY_SOURCE:-$TOOL_REPO}
  SOURCE=$(cd "$SOURCE" 2>/dev/null && pwd -P) || die 64 "no such source directory: $SOURCE"
  SOURCE_GITDIR=$(g -C "$SOURCE" rev-parse --absolute-git-dir 2>/dev/null) ||
    die 64 "$SOURCE is not a git checkout"
  SOURCE_GITDIR=$(cd "$SOURCE_GITDIR" && pwd -P)
}

resolve_clone() {
  [ -n "$CLONE" ] || CLONE=${NIGHTLY_CLONE:-$(dirname "$SOURCE")/iterm2-migration-nightly}
  CLONE=$(absolute "$CLONE") || die 64 "the parent directory of the clone $CLONE does not exist"
  MIRROR="$CLONE.origin.git"
}

# For refresh, status, reset and check: the clone must exist and pass the
# layout checks before anything is done in it.
load_clone() {
  resolve_source
  resolve_clone
  if [ ! -f "$CLONE/.git/$CONF_NAME" ]; then
    die 8 "no nightly clone at $CLONE ($CLONE/.git/$CONF_NAME is missing); make it first with: $(q "$SCRIPT_DIR/nightly_clone.sh") setup --clone $(q "$CLONE")"
  fi
  local problem
  problem=$(layout_problem)
  if [ -n "$problem" ]; then
    die 10 "refused, nothing changed: $problem"
  fi
}

# Submodules of repository $1 (git directory $2), through their validated
# git directories: each initialized one must be clean and at the commit the
# superproject's index records. Recursive.
submodule_state_problem() {
  local dir=$1 gitdir=$2 mode sha stage path name sub head out
  while IFS=$' \t' read -r mode sha stage path; do
    [ "$mode" = 160000 ] || continue
    [ -f "$dir/$path/.git" ] || continue
    name=$(module_name "$dir" "$path")
    sub="$gitdir/modules/$name"
    # A submodule at another commit than the recorded one is allowed: the
    # refresh checks out the recorded one, or says loudly that it could not.
    if ! out=$(g --git-dir="$sub" --work-tree="$dir/$path" status --porcelain --ignore-submodules=all 2>&1) || [ -n "$out" ]; then
      echo "the submodule $path has uncommitted changes or untracked files: $(echo "$out" | head -3 | tr '\n' ';')"; return
    fi
    out=$(submodule_state_problem "$dir/$path" "$sub"); [ -z "$out" ] || { echo "$out"; return; }
  done < <(g --git-dir="$gitdir" --work-tree="$dir" ls-files -s 2>/dev/null)
}

clone_state_problem() {
  local branch out
  if ! out=$(gc status --porcelain --ignore-submodules=all 2>&1); then
    echo "git status failed in $CLONE: $out"; return
  fi
  if [ -n "$out" ]; then
    echo "the clone has uncommitted changes or untracked files: $(echo "$out" | head -3 | tr '\n' ';')"; return
  fi
  out=$(submodule_state_problem "$CLONE" "$CLONE/.git"); [ -z "$out" ] || { echo "$out"; return; }
  branch=$(gc symbolic-ref -q --short HEAD) || { echo "HEAD is detached"; return; }
  [ "$branch" = "$BRANCH" ] || echo "HEAD is on $branch, not $BRANCH"
}

short() { gc rev-parse --short=12 "$1" 2>/dev/null || echo "$1"; }

save_clone_head() {
  local head=$1 ref
  ref="refs/nightly-saved/$(date +%Y%m%d-%H%M%S)-$(short "$head")"
  gc update-ref "$ref" "$head" || return 1
  say "saved the clone's previous master $(short "$head") as $ref"
}

do_setup() {
  resolve_source
  g -C "$SOURCE" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null ||
    die 64 "$SOURCE has no $BRANCH branch"
  resolve_clone
  if inside "$CLONE" "$SOURCE" || inside "$MIRROR" "$SOURCE" ||
     inside "$CLONE" "$SOURCE_GITDIR" || inside "$SOURCE" "$CLONE" ||
     inside "$SOURCE" "$MIRROR"; then
    die 64 "the clone and its mirror must be outside the owner's checkout $SOURCE (and not contain it)"
  fi
  resolve_upstream
  if [ -z "$UPSTREAM" ]; then
    die 64 "the owner's checkout's origin URL '$UPSTREAM_RAW' cannot be fetched over https (an https URL, or a git@host:path or ssh:// URL, which is fetched as https); nothing made"
  fi
  say "source checkout: $SOURCE (branch $BRANCH, read only)"
  say "upstream: $UPSTREAM (the owner's origin${UPSTREAM_RAW:+ $UPSTREAM_RAW}; fetched each night over https)"
  say "clone: $CLONE"
  say "mirror (its only remote, read-only): $MIRROR"
  local counts behind ahead
  if counts=$(g -C "$SOURCE" rev-list --left-right --count "refs/remotes/origin/$BRANCH...refs/heads/$BRANCH" 2>/dev/null); then
    behind=${counts%%[[:space:]]*}; ahead=${counts##*[[:space:]]}
    say "your $BRANCH is $ahead commits ahead of and $behind behind your origin/$BRANCH (as your checkout last fetched it; nothing was fetched now)"
    if [ "$ahead" != 0 ]; then
      say "WARNING: the clone starts from your $BRANCH, so it carries those $ahead unpushed commits as its own and rebases them onto origin/$BRANCH every night until they are upstream; rebase your $BRANCH onto origin/$BRANCH and push first"
      local rules
      rules=$(g -C "$SOURCE" log --format='%H %s' "refs/remotes/origin/$BRANCH..refs/heads/$BRANCH" -- "${RULE_PATHSPECS[@]}" 2>/dev/null)
      if [ -n "$rules" ]; then
        say "WARNING: EVERY NIGHT WILL BE REFUSED (nightly_start.sh exit 8) until these unpushed commits are on GitHub, because they change files that carry rules into a session (CLAUDE.md, CLAUDE.local.md, .claude/, .mcp.json):"
        printf '%s\n' "$rules" | while IFS= read -r line; do say "  $line"; done
      fi
    fi
  fi
  if [ "$DRY_RUN" = 1 ]; then
    say "dry run: nothing made"
    exit 0
  fi
  { [ ! -e "$CLONE" ] && [ ! -L "$CLONE" ]; } || die 7 "$CLONE exists; not touching it"
  { [ ! -e "$MIRROR" ] && [ ! -L "$MIRROR" ]; } || die 7 "$MIRROR exists; not touching it"
  local started=$SECONDS
  umask 022
  g init -q --bare "$MIRROR" || die 7 "cannot create $MIRROR"
  gm symbolic-ref HEAD "refs/heads/$BRANCH"
  gm config receive.denyNonFastForwards true
  gm config receive.denyDeletes true
  echo "made by nightly_clone.sh setup for the clone $CLONE; refresh requires this file" > "$MIRROR/$MARKER_NAME"
  if ! fill_mirror; then
    die 7 "could not fill $MIRROR with origin/$BRANCH (left in place, read-only; remove it with chmod -R u+w and rm -rf before trying again)"
  fi
  say "mirror filled in $((SECONDS - started))s"
  if ! g clone -q --no-hardlinks "$MIRROR" "$CLONE"; then
    die 7 "git clone of $MIRROR into $CLONE failed"
  fi
  # The clone's master starts as the owner's master (a local fetch).
  if ! g --git-dir="$CLONE/.git" fetch -q --no-tags --no-recurse-submodules "$SOURCE" "refs/heads/$BRANCH" ||
     ! g --git-dir="$CLONE/.git" --work-tree="$CLONE" reset -q --hard FETCH_HEAD; then
    die 7 "could not set the clone's $BRANCH to the owner's"
  fi
  rm -f "$CLONE/.git/FETCH_HEAD"
  g config -f "$CLONE/.git/config" remote.origin.pushurl "$PUSH_DISABLED"
  local conf="$CLONE/.git/$CONF_NAME"
  g config -f "$conf" nightly.source "$SOURCE"
  g config -f "$conf" nightly.mirror "$MIRROR"
  g config -f "$conf" nightly.branch "$BRANCH"
  say "clone made at $((SECONDS - started))s"
  if ! init_submodules "$CLONE" "$CLONE/.git" "$SOURCE_GITDIR"; then
    die 7 "submodules failed; the clone is at $CLONE"
  fi
  say "submodules done at $((SECONDS - started))s"
  if [ "$COPY_TMP" = 1 ]; then
    copy_tmp_items || die 7 "copying tmp items failed"
  fi
  say "done in $((SECONDS - started))s; disk: clone $(du -sh "$CLONE" | cut -f1), mirror $(du -sh "$MIRROR" | cut -f1)"
  cat <<EOF
nightly_clone: next steps for the owner:
  1. Accept Claude Code's workspace trust dialog for the clone once (an
     interactive session shows it in every folder not yet trusted, and
     nobody is there at night to answer it):
       cd $(q "$CLONE") && claude
     choose "Yes, I trust this folder", then type /exit.
  2. Install the launchd agent with NIGHTLY_CLONE=$(q "$CLONE") (see the header of
     tools/swift_migration/nightly_start.sh).
  Each morning, take the night's commits into your checkout with (it does
  nothing unless your checkout has $BRANCH checked out):
$(morning_command)
EOF
}

# Prints one of: same, behind, ahead, diverged. Returns 2 (and prints
# why) when a git command fails.
relation() {
  local c=$1 o=$2 rc
  if [ "$c" = "$o" ]; then echo same; return 0; fi
  gc merge-base --is-ancestor "$c" "$o"; rc=$?
  case "$rc" in 0) echo behind; return 0 ;; 1) ;; *) echo "git merge-base failed ($rc)"; return 2 ;; esac
  gc merge-base --is-ancestor "$o" "$c"; rc=$?
  case "$rc" in 0) echo ahead; return 0 ;; 1) ;; *) echo "git merge-base failed ($rc)"; return 2 ;; esac
  echo diverged
}

# Whether everything the clone's master $1 changes is already in the
# upstream's $2: their trees are equal, or merging $1 into $2 leaves $2's
# tree as it is (the owner squashed, reworded or reordered the night's
# commits before pushing them, which patch equivalence cannot see).
# Prints yes or no; returns 2 (and prints why) when a git command fails.
already_upstream() {
  local c=$1 o=$2 rc tree otree
  otree=$(gc rev-parse "$o^{tree}") || { echo "git rev-parse failed"; return 2; }
  if [ "$(gc rev-parse "$c^{tree}")" = "$otree" ]; then echo yes; return 0; fi
  tree=$(gc merge-tree --write-tree --no-messages "$o" "$c" 2>/dev/null); rc=$?
  case "$rc" in
    0) [ "${tree%%$'\n'*}" = "$otree" ] && echo yes || echo no ;;
    1) echo no ;;
    *) echo "git merge-tree failed ($rc)"; return 2 ;;
  esac
}

# Rebases the clone's own commits (those of $2..$1 not in the upstream as
# equivalent patches, oldest first) onto the upstream's $2, without
# touching the clone's master, index or working tree: each commit's change
# is merged onto the new tip with `git merge-tree --write-tree
# --merge-base=<its parent>` and committed with `git commit-tree`, keeping
# its author, author date, committer name and message. No hook, editor or
# merge driver runs, and nothing is left half-done to abort. A commit whose
# change is already in the new tip (it became empty) is dropped. Refused:
# a merge commit, a commit that changes a submodule pointer, a conflict.
# Sets REBASE_TIP, REBASE_COUNT and REBASE_DROPPED; on failure sets
# REBASE_WHY and returns 1 (refused) or 2 (a git command failed).
rebase_clone() {
  local c=$1 o=$2 list x tip out rc tree msg info an ae ad cn ce
  REBASE_COUNT=0; REBASE_DROPPED=0; REBASE_WHY=; REBASE_TIP=$o
  if ! out=$(gc rev-list --merges "$o..$c"); then REBASE_WHY="git rev-list failed"; return 2; fi
  if [ -n "$out" ]; then
    REBASE_WHY="the clone's commits include a merge commit ($(short "${out%%$'\n'*}")); history must stay linear"; return 1
  fi
  if ! list=$(gc rev-list --reverse --no-merges --right-only --cherry-pick "$o...$c"); then
    REBASE_WHY="git rev-list --cherry-pick failed"; return 2
  fi
  REBASE_DROPPED=$(( $(gc rev-list --count "$o..$c") - $(printf '%s' "$list" | grep -c .) ))
  msg=$(mktemp "${TMPDIR:-/tmp}/nightly-rebase-msg.XXXXXX") || { REBASE_WHY="mktemp failed"; return 2; }
  tip=$o
  for x in $list; do
    if gc diff-tree -r --raw --no-commit-id "$x^" "$x" | awk '$1 == ":160000" || $2 == "160000" { f = 1 } END { exit !f }'; then
      REBASE_WHY="commit $(short "$x") \"$(gc log -1 --format=%s "$x")\" changes a submodule pointer; the night must not commit submodule changes"
      rm -f "$msg"; return 1
    fi
    out=$(gc merge-tree --write-tree --name-only --no-messages --merge-base="$x^" "$tip" "$x" 2>&1); rc=$?
    case "$rc" in
      0) ;;
      1) REBASE_WHY="conflict applying $(short "$x") \"$(gc log -1 --format=%s "$x")\" onto $(short "$tip"), in: $(printf '%s\n' "$out" | sed 1d | sort -u | tr '\n' ' ')"
         rm -f "$msg"; return 1 ;;
      *) REBASE_WHY="git merge-tree failed ($rc) on $(short "$x"): $out"; rm -f "$msg"; return 2 ;;
    esac
    tree=${out%%$'\n'*}
    if [ "$tree" = "$(gc rev-parse "$tip^{tree}")" ]; then
      REBASE_DROPPED=$((REBASE_DROPPED + 1)); continue
    fi
    gc cat-file commit "$x" | sed '1,/^$/d' > "$msg"
    info=$(gc log -1 --date=raw --format='%an%x1f%ae%x1f%ad%x1f%cn%x1f%ce' "$x") ||
      { REBASE_WHY="git log failed"; rm -f "$msg"; return 2; }
    IFS=$'\037' read -r an ae ad cn ce <<< "$info"
    if ! tip=$(GIT_AUTHOR_NAME=$an GIT_AUTHOR_EMAIL=$ae GIT_AUTHOR_DATE=$ad \
               GIT_COMMITTER_NAME=$cn GIT_COMMITTER_EMAIL=$ce \
               gc commit-tree "$tree" -p "$tip" -F "$msg"); then
      REBASE_WHY="git commit-tree failed on $(short "$x")"; rm -f "$msg"; return 2
    fi
    REBASE_COUNT=$((REBASE_COUNT + 1))
  done
  rm -f "$msg"
  REBASE_TIP=$tip
  return 0
}

report_rebase_failed() {
  local c=$1 o=$2 why=$3
  say "rebase-failed: $why"
  say "the clone is as it was: $BRANCH at $(short "$c"); origin/$BRANCH is $(short "$o")"
  say "commits in the clone that origin/$BRANCH does not have (+ means no equivalent patch upstream):"
  gc cherry -v "$o" "$c" | while IFS= read -r line; do say "  $line"; done
  say "to resolve, rebase the clone's $BRANCH onto origin/$BRANCH by hand (cd $(q "$CLONE") && git rebase origin/$BRANCH), or take its commits into your checkout first:"
  morning_command
  say "  or set them aside (saved under refs/nightly-saved/) with: $(q "$SCRIPT_DIR/nightly_clone.sh") reset --clone $(q "$CLONE")"
}

# One machine-readable line: whether the refresh brought upstream commits
# into the clone, and which range (base..new).
upstream_commits_line() {
  local base=$1 new=$2 n
  if [ "$base" = "$new" ]; then
    echo "nightly_clone: upstream-commits: none"
  else
    n=$(gc rev-list --count "$base..$new")
    echo "nightly_clone: upstream-commits: taken $base..$new ($n commits)"
  fi
}

save_pre_rebase() {
  local head=$1 ref
  ref="refs/nightly/pre-rebase/$(date +%Y%m%d-%H%M%S)-$(short "$head")"
  gc update-ref "$ref" "$head" || return 1
  say "saved the clone's $BRANCH $(short "$head") as $ref before rebasing"
}

do_refresh() {
  load_clone
  resolve_upstream
  clear_stale_locks
  local problem
  problem=$(clone_state_problem)
  if [ -n "$problem" ]; then
    die 8 "not refreshing: $problem"
  fi
  local c o rel base rc fetched up
  fetch_upstream; rc=$?
  case "$rc" in
    0) ;;
    9) exit 9 ;;
    *) die 7 "could not make the mirror writable to fetch the upstream (it is read-only again)" ;;
  esac
  gc fetch -q --no-recurse-submodules origin || die 7 "the clone could not fetch from the mirror"
  o=$(gm rev-parse "refs/heads/$BRANCH") || die 7 "cannot read the mirror's $BRANCH"
  fetched=$(gc rev-parse "refs/remotes/origin/$BRANCH") || die 7 "cannot read origin/$BRANCH"
  [ "$fetched" = "$o" ] || die 7 "the clone's origin/$BRANCH ($fetched) is not the mirror's $BRANCH ($o)"
  UPSTREAM_REV=$o
  c=$(gc rev-parse "refs/heads/$BRANCH") || die 7 "cannot read the clone's $BRANCH"
  if [ "$COMMAND" = reset ]; then
    save_clone_head "$c" || die 7 "could not save the clone's master"
    base=$(gc merge-base "$c" "$o")
    gc reset -q --hard "$o" || die 7 "reset failed"
    say "reset the clone's $BRANCH to origin/$BRANCH $(short "$o")"
    upstream_commits_line "$base" "$o"
  else
    rel=$(relation "$c" "$o") || die 7 "could not compare the clone's $BRANCH with origin/$BRANCH, nothing changed: $rel"
    case "$rel" in
      same) say "up to date: the clone's $BRANCH is origin/$BRANCH $(short "$o")"
        upstream_commits_line "$o" "$o" ;;
      behind)
        gc merge -q --ff-only "$o" || die 7 "fast-forward failed"
        say "fast-forward: the clone's $BRANCH moved from $(short "$c") to $(short "$o") ($(gc rev-list --count "$c..$o") commits)"
        upstream_commits_line "$c" "$o" ;;
      ahead)
        say "the clone's $BRANCH is $(gc rev-list --count "$o..$c") commits ahead of origin/$BRANCH (not pushed yet); continuing from $(short "$c")"
        upstream_commits_line "$o" "$o" ;;
      diverged)
        base=$(gc merge-base "$c" "$o") || die 7 "git merge-base failed"
        up=$(already_upstream "$c" "$o") || die 7 "could not compare the clone's $BRANCH with origin/$BRANCH, nothing changed: $up"
        if [ "$up" = no ]; then
          save_pre_rebase "$c" || die 7 "could not save the clone's $BRANCH"
          rebase_clone "$c" "$o"; rc=$?
          case "$rc" in
            0) ;;
            1) report_rebase_failed "$c" "$o" "$REBASE_WHY"; exit 9 ;;
            *) die 7 "rebase-failed: $REBASE_WHY; nothing changed" ;;
          esac
          [ "$REBASE_COUNT" = 0 ] && up=yes
        fi
        if [ "$up" = yes ]; then
          save_clone_head "$c" || die 7 "could not save the clone's master"
          gc reset -q --hard "$o" || { gc reset -q --hard "$c"; die 7 "reset failed; the clone is back at $(short "$c")"; }
          say "already-upstream: reset to $o (everything the clone's commits change is in origin/$BRANCH)"
        else
          if ! gc reset -q --hard "$REBASE_TIP"; then
            gc reset -q --hard "$c"
            die 7 "moving the clone's $BRANCH to the rebased commits failed; the clone is back at $(short "$c")"
          fi
          say "rebased: $REBASE_COUNT commits onto $o ($REBASE_DROPPED dropped as already upstream); the clone's $BRANCH is now $(short "$REBASE_TIP")"
        fi
        upstream_commits_line "$base" "$o" ;;
      *) die 7 "unexpected comparison result: $rel" ;;
    esac
  fi
  init_submodules "$CLONE" "$CLONE/.git" "$SOURCE_GITDIR" || die 7 "submodule update failed"
  say "clone $CLONE at $(short "$(gc rev-parse HEAD)"); in the morning take its commits with:"
  morning_command
}

do_status() {
  load_clone
  resolve_upstream
  local c o u rel=unknown out
  c=$(gc rev-parse "refs/heads/$BRANCH")
  o=$(gm rev-parse -q --verify "refs/heads/$BRANCH")
  say "clone $CLONE: $BRANCH at $(short "$c")"
  say "mirror $MIRROR: $BRANCH at ${o:-none}, $( [ -z "$(mirror_writable_entry)" ] && echo read-only || echo 'WRITABLE (refresh makes it read-only)')"
  u=
  if [ -z "$UPSTREAM" ]; then
    say "upstream: the owner's origin URL '$UPSTREAM_RAW' cannot be fetched over https; refresh would go on with the mirror as it is"
  elif ! out=$(gnet ls-remote "$UPSTREAM" "refs/heads/$BRANCH" 2>&1); then
    say "upstream: cannot read $UPSTREAM now ($(printf '%s' "$out" | tr '\n' ' ')); comparing with the mirror"
  else
    u=${out%%[[:space:]]*}
    say "upstream $UPSTREAM: $BRANCH at ${u:-none}"
  fi
  if [ -n "$u" ] && ! gc cat-file -e "$u^{commit}" 2>/dev/null; then
    say "refresh would fetch origin/$BRANCH $u, which the mirror does not have yet, then fast-forward the clone or rebase its commits onto it"
  else
    [ -n "$u" ] || u=$o
    rel=$(relation "$c" "$u") || rel="error: $rel"
    case "$rel" in
      same) say "refresh would find it up to date" ;;
      behind) say "refresh would fast-forward the clone to origin/$BRANCH" ;;
      ahead) say "refresh would continue from the clone, which is ahead (commits not pushed yet)" ;;
      diverged) say "refresh would rebase the clone's commits onto origin/$BRANCH (or reset to it if they are already upstream; on a conflict it refuses and changes nothing)" ;;
      *) say "refresh would fail: $rel" ;;
    esac
  fi
  local problem
  problem=$(clone_state_problem)
  [ -z "$problem" ] || say "refresh would refuse: $problem"
}

do_check() {
  load_clone
  say "layout: as setup made it (clone $CLONE, mirror $MIRROR, source $SOURCE)"
}

# One line per ref, then the checksums of the config file, info/attributes
# and every hook, for git directory $1 labelled $2.
repo_fingerprint() {
  local dir=$1 label=$2 head f
  # A work tree that always exists: a module directory left by a removed
  # submodule records a core.worktree that is gone, and git would refuse.
  local rg=(g --git-dir="$dir" --work-tree=/var/empty)
  head=$("${rg[@]}" symbolic-ref -q HEAD || "${rg[@]}" rev-parse -q --verify HEAD || echo none)
  echo "$label HEAD $head"
  "${rg[@]}" for-each-ref --format="$label %(objectname) %(refname)" || return 1
  for f in config info/attributes; do
    if [ -f "$dir/$f" ]; then
      echo "$label file $f $(shasum -a 256 < "$dir/$f" | cut -d' ' -f1)"
    fi
  done
  if [ -d "$dir/hooks" ]; then
    find "$dir/hooks" -type f -o -type l | sort | while IFS= read -r f; do
      echo "$label hook ${f#"$dir"/} $(shasum -a 256 < "$f" 2>/dev/null | cut -d' ' -f1)"
    done
  fi
}

do_owner_refs() {
  resolve_source
  repo_fingerprint "$SOURCE_GITDIR" . || die 7 "cannot list the refs of $SOURCE"
  if [ -d "$SOURCE_GITDIR/modules" ]; then
    local head dir
    while IFS= read -r head; do
      dir=$(dirname "$head")
      [ -d "$dir/objects" ] || continue
      repo_fingerprint "$dir" "${dir#"$SOURCE_GITDIR"/}" || die 7 "cannot list the refs of $dir"
    done < <(find "$SOURCE_GITDIR/modules" -name HEAD -type f ! -path '*/logs/*' ! -path '*/refs/*' 2>/dev/null | sort)
  fi
}

# The git wrapper's own guard, checked on a URL that never leaves the
# machine when the guard works: git must refuse the transport.
do_selftest() {
  local out
  out=$(g ls-remote https://nightly-selftest.invalid/x 2>&1)
  case "$out" in
    *"not allowed"*) say "git wrapper: non-local transports are refused" ;;
    *) die 7 "git wrapper: a non-local transport was not refused: $out" ;;
  esac
}

case "$COMMAND" in
  rule-pathspecs) printf '%s\n' "${RULE_PATHSPECS[@]}" ;;
  clear-locks) load_clone; clear_stale_locks $([ "$DRY_RUN" = 1 ] && echo dry) ;;
  selftest) do_selftest ;;
  setup) do_setup ;;
  refresh|reset) do_refresh ;;
  status) do_status ;;
  check) do_check ;;
  owner-refs) do_owner_refs ;;
esac
exit 0
