#!/bin/bash
# Start the unattended Swift migration orchestrator for one night.
#
# Part of the Objective-C to Swift migration tooling. See
# docs/swift-migration/workflow.md section 4 ("Schedule and usage budget")
# and docs/swift-migration/orchestration.md.
#
# Where it runs. Never in the owner's working checkout: in a separate clone
# made once by hand with tools/swift_migration/nightly_clone.sh setup, whose
# only remote is a read-only bare mirror of the project's origin/master,
# fetched from GitHub each night by that script (layout,
# refresh rule, the checks on everything read from the clone, and the push
# layers are in that script's header). The clone is $NIGHTLY_CLONE, which
# the launchd agent sets; unset, it is <parent of this checkout>/
# iterm2-migration-nightly. The owner's checkout (the source) is
# $NIGHTLY_SOURCE, else the checkout this script is in; the mirror is always
# <clone>.origin.git. None of these is read from inside the clone, which the
# session can write. This script reads the owner's checkout (to refresh the
# mirror and to record its refs) and never writes to it.
#
# Outside the clone. The lock, the run directories with the logs, the
# status and root files, the tmux socket and the owner-refs records live
# in $NIGHTLY_ROOT, by default <clone>.runs/, which this script creates with
# mode 0700; a NIGHTLY_ROOT or socket inside the clone is refused. Inside
# the clone the session can change anything as a routine file edit in its
# working directory (auto mode does not send those to the classifier), and
# a `git clean -fdx` would remove them; outside it, a change takes a shell
# command, which the classifier reviews. It is still the same user, so this
# keeps the logs from accidents, not from intent.
#
# The build lanes. The orchestrator's agents build and test in lanes made by
# lane_clone.py (docs/swift-migration/orchestration.md section 3): detached
# `git worktree add` checkouts of the clone in <clone>.lanes/lane-N, the
# directory lane_clone.py uses by default for the clone. The path is always
# <clone>.lanes, derived from the clone path as <clone>.runs is, never read
# from inside the clone and not moved by NIGHTLY_ROOT. This script creates it
# with mode 0700 when absent (an existing one is never chmodded, and is
# refused when it is a symbolic link or group or others can write it) and
# starts the session with --add-dir <clone>.lanes, so that edits there run
# without a prompt as edits in the clone do; with nobody to answer a prompt,
# an edit outside the working directory would otherwise be denied. Each lane
# registers itself in the clone's .git/worktrees/<name>/ (commondir ../..,
# gitdir <clone>.lanes/<name>/.git), the one shape nightly_clone.sh check
# allows there; the clone's git status is unaffected. Lanes are detached, so
# the refresh's reset and fast-forward of the clone's master leave them be.
# Worktrees and the lanes' submodule repositories (objects borrowed through
# objects/info/alternates from the clone's .git/modules) use no git
# transport; lane_clone.py is tested in the session's environment. Not
# checked: the lanes' contents, including their submodule
# repositories' configuration, which the session can write and which
# lane_clone.py's git commands read when this script runs release --stale
# (hooks and fsmonitor are off there, filters are not); and what, if
# anything, Claude Code loads from an --add-dir directory besides access
# (a CLAUDE.md, settings or skills in a lane): not verified here, and the
# preflight's check of untracked files under .claude/ covers the clone
# only.
#
# How it runs. Not headless: an ordinary interactive Claude Code session in
# a tmux server on a private socket, so that the owner can attach, watch,
# type to it, and detach:
#   tmux -S <socket> attach -t swift-migration     (detach: C-b d)
# The socket is $NIGHTLY_ROOT/tmux.sock (tmux 3.8 makes the socket 0600); a
# path longer than 103 bytes (the macOS sun_path limit of 104 with its NUL)
# is refused. A socket directory that does not exist is created with mode
# 0700; an existing one is never chmodded, and is refused if group or
# others can write it. The server is started with -f /dev/null, so no tmux
# configuration file is read, and its update-environment is emptied, so
# that a window opened after the owner attaches does not take his
# SSH_AUTH_SOCK or SSH_ASKPASS.
#
# A launchd user agent runs this at local midnight. In order, it:
#   1. checks that the programs the run needs resolve on PATH (claude, tmux,
#      git, python3, xcodebuild, expect, ruby, make) and logs where;
#   2. refuses to start outside the start window (00:00 to 04:59:59 local
#      by default), because launchd runs a missed midnight job when the Mac
#      wakes, which may be when the owner sits down in the morning;
#   3. (no step: an owner-refs difference found by an earlier night is a
#      report in that night's log, never a reason not to start);
#   4. checks that the clone exists (else it says how to make it), runs
#      `nightly_clone.sh check` (the clone's layout and configuration must
#      be what setup made, exit 12 otherwise; see that script's header),
#      and preflights it: a .git/index.lock (or other stale lock) is
#      removed, and logged, when no process names the clone on its command
#      line (`nightly_clone.sh clear-locks`; a dry run only says so), and
#      refused when one does; it refuses when a rebase, merge, cherry-pick,
#      revert or bisect is in progress, HEAD is detached or not on master,
#      or `git status` cannot run. Nothing else is deleted or repaired;
#   5. takes a lock so that two orchestrators never run at once (an atomic
#      mkdir of $NIGHTLY_ROOT/lock holding this script's pid; a lock whose
#      pid is dead, or alive but not running nightly_start.sh, is stale, as
#      is a lock with no pid file older than 120 seconds; a stale lock is
#      renamed aside atomically, checked to be the one judged stale, and
#      replaced by a new mkdir; whoever loses either step exits 3);
#   6. refuses if a tmux server is already listening on the socket;
#      then, holding the lock so that two starts never race on it, makes
#      the lanes directory <clone>.lanes if absent (exit 7 if it is a
#      symbolic link or not private; see "The build lanes" above);
#   7. runs usage_check.py, which reads `claude /usage` and compares the
#      weekly figure with tonight's ceiling; anything but "may start" stops
#      here, and an unreadable reading is never taken as permission. The
#      one exception is an "at least one unit" night (NIGHTLY_ONE_UNIT_DATE
#      equal to tonight's local date, the date of NIGHTLY_NOW when that is
#      set; the owner, 2026-11-24: "Ensure the agent does at least one unit
#      tonight even if it goes over quota"). Under the ceiling (exit 0) it is
#      an ordinary night, except that the prompt says that if a usage check
#      reaches the ceiling before the night's first unit has landed, that
#      unit is still finished (committed or parked) and then the night
#      stops. At or over the ceiling (exit 1) is logged and the start goes
#      on, and the prompt tells the orchestrator to do exactly one unit and
#      that the ceiling does not apply tonight. Unknown usage (exit 2 or
#      anything else) still stops, and so does an exit 1 that does not come
#      with the line "verdict: at or over the ceiling (exit 1)"
#      (usage_check.py failing, which Python also reports as 1). A dry run
#      logs which case applies and that a real run would start anyway.
#      The option expires by itself: on any other date it does nothing but
#      log that it is set and does not apply. It is validated before step 1:
#      a value that is not a real date YYYY-MM-DD is a bad option (exit 64,
#      also under --dry-run); empty means unset. NIGHTLY_PROMPT, when set,
#      replaces the whole prompt, the at-least-one-unit instruction included;
#   8. refreshes the clone with `nightly_clone.sh refresh`, under a time
#      bound (NIGHTLY_REFRESH_SECONDS, default 20 minutes, through
#      deadline_run.py, which kills it and everything it started; exit 7
#      with a clear line), so that a hung network fetch cannot hold the
#      night: the mirror
#      fetches origin/master from GitHub over https (refused, exit 9, if it
#      is not a fast-forward: someone force-pushed; a failed fetch is
#      logged and the night goes on with the mirror as it was), then the
#      clone fast-forwards to it, keeps its own commits when it is strictly
#      ahead, resets to it when everything they change is already upstream,
#      or rebases them onto it; a rebase that fails (a conflict, a merge
#      commit, a submodule pointer change) resets the clone to it when the
#      owner's checkout holds the clone's commits (taken-by-owner), and
#      otherwise leaves the clone as it was and refuses the night (exit 9). The refresh's machine-readable lines go
#      to <run dir>/refresh.status, which the prompt names, so that the
#      orchestrator knows whether new code arrived (orchestration.md
#      section 1, step 4) and whether the upstream could be fetched. Then
#      it refuses (exit 8) if the clone's master changes CLAUDE.md, any
#      CLAUDE.local.md, anything under .claude/ (the agent definitions
#      among it) or .mcp.json relative to origin/master, or if the
#      working tree has any file under the top-level .claude/ (untracked
#      or ignored included; .claude/worktrees/, where Claude Code keeps
#      agent worktrees, is exempt) or a CLAUDE.local.md that origin/master
#      does not track: those carry rules, settings or hooks into the next
#      night and, through the morning fetch, into his checkout, so he takes
#      and pushes them, or drops them, first. "origin/master" is always
#      read from the mirror, which the trusted refresh just wrote, never
#      from a ref in the clone;
#      Then, when lanes exist ($LANES/lanes.json), it logs
#      `lane_clone.py status` and runs `lane_clone.py release --stale`,
#      which frees every lane whose holder (normally an earlier night's
#      Claude Code process) is dead, saving the lane's uncollected work as
#      patches under <clone>.lanes/saved/ and naming each in the log; a
#      failure is logged loudly and does not stop the night;
#   9. checks the agent definitions in the clone's .claude/agents/ (tracked
#      in git; an interactive session finds them there by itself, so no
#      --agents flag is passed): they must parse and pin Opus;
#  10. records the refs of the owner's checkout and of each of his
#      submodule repositories, with checksums of their config, attributes
#      and hooks (`nightly_clone.sh owner-refs`, reads only), writes the
#      session wrapper and starts the session under deadline_run.py in its
#      tmux mode, which ends it by a hard time limit and then kills every
#      process the run started; and keeps the Mac from idle sleep while it
#      runs (caffeinate -i -w);
#  11. afterwards: runs `nightly_clone.sh check` again and says loudly if
#      the session changed the clone's layout or configuration; records the
#      owner's refs again and, if anything differs, lists prominently in
#      the log which refs moved (old and new lines). That is a report, not
#      a stop: the owner's repository is shared with his other agents and
#      worktrees, so it changes overnight for ordinary reasons; the exit
#      status is the session's and nothing blocks the next night. It also
#      lists loudly any change to the rule files of step 8 that the night
#      made;
#  12. logs the state of the clone (HEAD, local branches, origin/master,
#      the number of `git status --porcelain` lines) before and after, and
#      a loud line if HEAD is no longer on the branch it started on. Every
#      git command it runs in the clone goes through nightly_clone.sh's
#      neutralizing flags (no hooks, no fsmonitor, no pager, no global
#      configuration), so a configuration the session wrote does not run.
# Everything is logged under $NIGHTLY_ROOT/<date>/run-<HHMMSS>-<pid>/. The
# run directory holds:
#   nightly_start.log   this script's log (also on stdout, which launchd
#                       sends to $NIGHTLY_LAUNCHD_LOG)
#   pane.log            the session's terminal output, raw, with escape
#                       sequences (tmux pipe-pane -o)
#   supervisor.log      deadline_run.py's log
#   session.sh, session-settings.json, prompt.txt, command.txt
#   session.status      claude's exit status, written by session.sh
#   session.done        written by nightly_done.sh, the session's last
#                       action when its work is done (see "The end")
#   session.root        claude's pid and start time (deadline_run.py --spawn-root)
# The conversation transcript is where Claude Code keeps it for the clone
# (code.claude.com/docs/en/claude-directory, "Application data"):
#   ~/.claude/projects/<clone path, every non-alphanumeric as ->/<session id>.jsonl
# The session id is chosen here (--session-id) and the path is logged. The
# night's report is written by the orchestrator, per orchestration.md
# section 8, to <clone>/tmp/swift-migration-night-<date>.md; its path is
# logged too. owner-refs-before.txt and owner-refs-after.txt hold the
# owner's refs (step 10 and 11).
#
# Permissions of the session. Each of these is applied by this script to
# its own session only; no settings file is changed.
#   --permission-mode auto: file reads and edits in the working directory
#     run without asking; other actions are reviewed by Claude Code's auto
#     mode classifier, which blocks by default force pushes,
#     `git reset --hard`, `git clean -fd`, deleting files that existed
#     before the session, downloading and running code, and sending data to
#     outside endpoints. Auto mode on its own allows pushing to the
#     repository's branches (code.claude.com/docs/en/permission-modes). In
#     an interactive session, after 3 blocks in a row or 20 in all, auto
#     mode pauses and Claude Code goes back to prompting (same page).
#   permissions.denyInsteadOfPrompting true (in --settings): a tool call
#     that would wait on a permission prompt is denied instead, so the
#     session keeps working with nobody there (docs/en/permissions; honored
#     from --settings since v2.1.319, docs/en/settings, "Exceptions to
#     managed settings precedence"). This replaces `--permission-prompts
#     none`, which works only with --print. So an owner who attaches sees no
#     prompts to approve; he can type to the session, press Esc to
#     interrupt it, approve a classifier block under /permissions, "Recently
#     blocked", so that Claude may retry it, run a command himself with
#     `!`, change mode with Shift+Tab, or end it with /exit.
#   Settings sources are not restricted. In the clone there is no
#     .claude/settings.local.json (git ignores it, so a clone never has one;
#     the preflight refuses if one appears) and no tracked
#     .claude/settings.json, so the project's CLAUDE.md, its tracked
#     .claude/agents/ and the owner's user settings load normally. The
#     owner's user-level hooks run in the session (the owner wants iTerm2's
#     status and to answer from his phone); a PermissionRequest hook could
#     approve what would otherwise be denied.
#   --settings <run dir>/session-settings.json, which sets:
#     autoMode.classifyAllShell true: every shell command goes to the
#       classifier even when an allow rule matches, so the user settings'
#       allow rules (`Bash(gh pr review:*)`, `Bash(~/bin/gitlab-issue-*:*)`,
#       `Bash(source ~/.zshrc)`) do not skip it (docs/en/settings-reference;
#       honored from --settings per docs/en/settings, "Exceptions");
#     permissions.denyInsteadOfPrompting true (above);
#     disableClaudeAiConnectors true (the Gmail, Docs, Drive and Calendar
#       connectors);
#     permissions.deny, the rules in DENY_RULES below. Deny rules win over
#       allow rules from every source (docs/en/permissions, "Settings
#       precedence"): pushes (`git push`, and `git <options> push` for
#       `git -C . push` and `git -c x=y push`), `git remote` (adding a
#       remote with an explicit pushurl), any command mentioning pushurl,
#       send-pack or receive-pack, `gh` entirely, osascript, launchctl, sudo, open, ssh, scp, it2 and
#       tmux (either can type into the owner's terminal sessions, outside
#       every guard here; `env -u TMUX tmux` reaches his default tmux
#       server), and the owner's GitLab issue scripts. Network commands are
#       not denied (the owner's choice).
#     Forms a pattern cannot catch (docs/en/permissions, "What a Bash rule
#     doesn't match"): an absolute path (/usr/bin/git push), a command run
#     by another interpreter or shell (sh -c '...', python3 -c with
#     subprocess, a script file), a git alias (git -c alias.p=push p), and
#     a command assembled from variables. The environment guards and the
#     clone's push layers do not depend on the pattern, except for the
#     local-path routes listed below, which no environment guard stops.
#   --add-dir <clone>.lanes: the build lanes (above) are a working
#     directory of the session as the clone is, so auto mode lets file
#     edits there run without asking (claude --help: "--add-dir
#     <directories...> More directories Claude can access").
#   --strict-mcp-config with no --mcp-config: no MCP server from
#     ~/.claude.json, .mcp.json or a plugin (docs/en/cli-reference).
#   --disallowedTools for tools that act outside the machine or schedule
#     work: every MCP tool (mcp__*), RemoteTrigger, CronCreate, CronDelete,
#     CronList, PushNotification, Workflow, DesignSync, ScheduleWakeup; and
#     AskUserQuestion, whose dialog nobody answers at night and which takes
#     a line typed into the session (the nudge) as its answer, losing it
#     (observed with Claude Code 2.1.331, 2026-11-24). The prompt never
#     asks for it. Any other dialog that is open at the clean stop would
#     take the nudge the same way; that exposure remains. The
#     Agent (Task) and SendMessage tools stay: the orchestrator needs them.
#   This is not --dangerously-skip-permissions / bypassPermissions.
#
# Guards in the session's environment. They are set on the tmux client
# that starts the server, so the server's global environment has them and
# every window and process in it inherits them unless it changes its
# environment on purpose:
#   GIT_CONFIG_COUNT/KEY/VALUE: credential.helper set to empty (no
#     keychain credentials), and url.nightly-push-blocked://.pushInsteadOf
#     for https://, http://, ssh://, git@, git://, file://, / and . so that
#     a push to any URL, any path starting with / or ., or a named remote
#     whose url is one of those is rewritten to a transport that does not
#     exist and fails before any network use. Fetch is not
#     affected. A remote with an explicit pushurl bypasses pushInsteadOf
#     (the clone's own pushurl is itself unusable), and `git send-pack`
#     ignores it; see below.
#   Local-path and file:// transports are not refused: git treats them as
#     it does in the owner's own shell (the owner, 2026-11-23: “I don't
#     understand why the nightly session can't clone. That is a senseless
#     rule.”; until then protocol.file.allow=user with
#     GIT_PROTOCOL_FROM_USER=0 refused them all). The session can clone
#     and fetch from a local path, origin (the mirror) included, and
#     resolve Swift packages: SwiftPM, inside xcodebuild, fills its
#     repository cache with `git clone --mirror`, updates it with
#     `git remote update -p`, and makes each working copy in
#     SourcePackages/checkouts with a local `git clone --shared
#     --no-checkout` from that cache (objects borrowed through alternates),
#     then checks it out and runs `git submodule update --init
#     --recursive`; those commands are tested in the session's
#     environment. git's own default still applies to submodules: a
#     submodule clone or update from a local path is refused unless the
#     command says -c protocol.file.allow=always, as in the owner's shell.
#     A clone of the mirror by plain path (origin is that path) links the
#     mirror's object files into the copy; nightly_clone.sh check accepts
#     such links and the refresh leaves them read-only (its header has the
#     rule).
#     What this makes possible that was refused before, all tested: writing
#     refs in the owner's checkout or his submodule repositories by local
#     path,
#       - by a push through a remote with an explicit pushurl, or through
#         `git send-pack`;
#       - by a plain `git push <path>` whose path's first character is
#         neither / nor . (pushInsteadOf rewrites only those). Such a path
#         may climb out with .. after an ordinary name, so it works from
#         any directory, the clone included, with no other option: from
#         the clone, `git push tmp/../../iterm2-alt HEAD:refs/heads/x`
#         reaches his checkout. Running from a directory above it with
#         --git-dir or GIT_DIR naming the clone is another form. A push to
#         an absolute path, a file:// URL or a path that begins with ../
#         still fails;
#       - by a fetch or pull run in his checkout from the clone or a lane,
#         `git -C <his checkout> fetch <clone> master:refs/heads/x`, which
#         creates the ref, or `git -C <his checkout> pull --ff-only <clone>
#         master`, which moves his checked-out branch and changes his
#         working tree and index (a push to a checked-out branch is refused;
#         this is not).
#     No environment guard stops any of these. The deny rules catch the
#     plain forms of the first two (`git push`, `git <options> push`,
#     `git remote`, pushurl, send-pack); nothing denies a fetch or pull, so
#     only the classifier reviews that one. Detection: the owner-refs
#     comparison (step 11) lists any ref, config or hook change in his
#     repositories in the morning log (a pull's ref move included, though
#     working tree and index changes are not compared), and a remote left
#     in the clone's configuration fails the check of step 11.
#   GIT_SSH_COMMAND: a wrapper that refuses git-receive-pack (push) and
#     runs /usr/bin/ssh otherwise. GIT_TERMINAL_PROMPT=0,
#     GIT_ASKPASS=/usr/bin/false, SSH_ASKPASS=/usr/bin/false, and no
#     SSH_AUTH_SOCK.
#   GH_CONFIG_DIR: an empty directory in the run directory, and GH_TOKEN,
#     GITHUB_TOKEN and GH_ENTERPRISE_TOKEN unset, so gh is not logged in.
#   SWIFT_MIGRATION_NIGHT_ID: unique to the run (added by deadline_run.py);
#     with macOS responsibility tracking it finds what is left to kill.
#   ANTHROPIC_API_KEY unset, as the owner's shell does, so the session uses
#     the subscription login (from the keychain, which a launchd agent in
#     the owner's GUI session can read). LANG defaults to en_US.UTF-8; tmux
#     sets TERM=tmux-256color in the pane.
#
# Stopping. Three times, all logged: the hard limit, the earlier of
# NIGHTLY_MAX_SECONDS from the start and the next NIGHTLY_STOP_AT, by
# which everything the run started is dead; the start of the stop
# sequence, as long before the hard limit as the sequence can take
# (NIGHTLY_INTERRUPT_WAIT + NIGHTLY_GRACE_SECONDS + 60 + 10 + 20 seconds of
# sweep and slack, 400 seconds with the defaults); and the clean stop, 45
# minutes before the hard limit. For the scheduled midnight start the six
# hour limit comes first: hard limit 06:00:00, stop sequence 05:53:20,
# clean stop 05:15:00; the 07:00 wall-clock limit applies only to a start
# after 01:00 (then 07:00:00, 06:53:20, 06:15:00). The prompt names the
# clean stop as
# the time by which the orchestrator must have stopped cleanly (workflow.md
# section 4, "Stopping cleanly"). At that time deadline_run.py types the
# fixed line NUDGE_TEXT into the session, once (--nudge-text; its header has
# the care taken), so that a session idle at its prompt waiting on
# background jobs gets a turn: on 2026-11-24 one got none, missed its
# clean stop and was killed at the hard limit with no report. The prompt
# also tells the session never to wait on a background job without a bound
# (suite_guard.py wait --pid PID --seconds N in the foreground). The stop
# sequence: deadline_run.py sends Escape (stops the turn in progress),
# after NIGHTLY_INTERRUPT_WAIT seconds clears the input line with Ctrl-C
# (leftover text would otherwise have /exit appended and go as a message)
# and a second later types /exit (ends the session, running its SessionEnd
# hooks), after NIGHTLY_GRACE_SECONDS sends SIGTERM
# to the pane's processes, after 60 more seconds kills the tmux server and
# SIGKILLs the pane, then sweeps every process the run started (builds and
# tests running in a lane are started by the session's tools like any other,
# so the sweep finds them by the same rules; where they run does not
# matter). The times
# are kept on the wall clock. The same sequence runs at once if the session
# is found waiting at the workspace trust dialog (exit 11), if neither its
# screen nor its transcript changes in its first NIGHTLY_STALL_SECONDS
# (a failed start, exit 14), and when this script gets SIGTERM (for example
# from launchctl kill).
# The end. An interactive session that has finished its work stays at its
# prompt (2026-11-25: done at 01:40, stopped at the time limit at 05:54),
# so the prompt tells the session to run tools/swift_migration/
# nightly_done.sh as its last action, once the night's report is written
# and the lanes are released. That writes session.done in the run
# directory (from SWIFT_MIGRATION_NIGHT_DIR), which deadline_run.py
# --done-file watches: the supervisor logs "session reported done", runs
# the stop sequence above at once and sweeps as at the deadline, and this
# script logs that and exits 0, not 5. A session.done from before the
# supervisor started is ignored.
# The session counts as ended when session.status appears, or when tmux
# itself answers repeatedly that the session or its server is gone: over a
# few seconds once the session's processes have died, over a minute while
# they still run (exit 4, "ended without an exit status", with what was
# observed in the supervisor's lines of the log; such an answer before the
# supervisor has learned the pane is exit 4, "could not be started"). A
# tmux call that fails (cannot be run, times out, any other error) is
# logged and is not such an answer; deadline_run.py's header has the rule.
# It also ends (exit 4, "ended without an exit status") when claude has
# exited without session.status appearing for a minute. On the first unattended night, 2026-11-23, a single tmux call
# that did not succeed under heavy load (most likely; nothing logged it
# then) ended a healthy session at 01:55 and its processes were killed.
# tmux calls in the stop sequence are short and bounded by the hard limit,
# so a hung tmux does not delay it.
#
# Usage:
#   tools/swift_migration/nightly_start.sh [--dry-run]
#   --dry-run  Run the checks and report them (programs, window, clone,
#              preflight, lock, socket, lanes directory and lane status,
#              usage, what the refresh would do),
#              write the session files, print the exact commands, and start
#              and change nothing. The lock is not taken. If the clone does
#              not exist, say so and print the command that makes it.
#
# Exit status:
#   0  the session ran and exited 0, or reported done with nightly_done.sh
#      and was stopped at once (logged "session reported done"), or
#      --dry-run finished
#   1  usage is at or over tonight's ceiling; nothing started (never on an
#      at-least-one-unit night, NIGHTLY_ONE_UNIT_DATE, which starts anyway)
#   2  usage could not be determined, or a signal arrived before the
#      session started; nothing started
#   3  another orchestrator holds the lock; nothing started
#   4  the session could not start, or exited with a failure status
#   5  the session was stopped at the time limit
#   6  outside the start window; nothing started
#   7  setup failed (a required program missing, agent definitions invalid,
#      socket path too long or its directory not private, the lanes
#      directory a symbolic link or not private, NIGHTLY_ROOT or the socket
#      inside the clone, the refresh failed or did not finish in time)
#   8  preflight failed: the clone is missing or not in a state to work in,
#      or carries rule changes that are not upstream yet
#   9  the clone's commits could not be rebased onto origin/master, or the
#      upstream was force-pushed; nothing started
#   10 a tmux server is already listening on the socket; nothing started
#   11 the session was waiting at the workspace trust dialog and was stopped
#   12 the clone's layout or configuration is not what setup made
#      (nightly_clone.sh check); nothing started
#   14 the session made no progress after starting (a dialog?) and was
#      stopped
#   64 bad option, or NIGHTLY_ONE_UNIT_DATE is not empty and not a date
#      YYYY-MM-DD; nothing started
#
# Environment (all optional):
#   NIGHTLY_CLONE               the clone (default <parent of this checkout>/iterm2-migration-nightly)
#   NIGHTLY_SOURCE              the owner's checkout (default: the checkout this script is in)
#   CLAUDE_BIN                  claude executable (default: claude on PATH)
#   NIGHTLY_TMUX                tmux executable (default: tmux on PATH)
#   PYTHON                      Python 3.9+ for these tools (default /usr/bin/python3)
#   NIGHTLY_ROOT                log and lock directory, outside the clone (default: <clone>.runs)
#   NIGHTLY_TMUX_SOCKET         default $NIGHTLY_ROOT/tmux.sock
#   NIGHTLY_TMUX_SESSION        default swift-migration
#   NIGHTLY_LATEST_START_HOUR   start only before this local hour (default 5)
#   NIGHTLY_MAX_SECONDS         hard limit on the session (default 21600, 6 hours)
#   NIGHTLY_STOP_AT             also stop at this local time, HH:MM (default 07:00)
#   NIGHTLY_INTERRUPT_WAIT      Escape to /exit at the limit (default 10)
#   NIGHTLY_GRACE_SECONDS       /exit to SIGTERM at the limit (default 300)
#   NIGHTLY_STALL_SECONDS       a failed start after this long with no change (default 300)
#   NIGHTLY_CLEAN_STOP_MARGIN   the clean stop, this many seconds before the hard limit (default
#                               2700); also when the nudge is typed (see "Stopping")
#   NIGHTLY_CLOSING_RESERVE     the closing checks start this many seconds before the clean
#                               stop (default 4500, 75 minutes; see CLOSING_RESERVE below)
#   NIGHTLY_REFRESH_SECONDS     time bound on the refresh, killed after it (default 1200)
#   NIGHTLY_CLONE_TOOL          replaces nightly_clone.sh, for tests only
#   NIGHTLY_MODEL               the session's model (default opus)
#   NIGHTLY_PROMPT              replaces the orchestrator prompt (for a test)
#   NIGHTLY_ONE_UNIT_DATE       YYYY-MM-DD: on that local date only, an "at least one unit" night
#                               (step 7); empty or unset: none; malformed: exit 64
#   NIGHTLY_REQUIRED_PROGRAMS   programs that must resolve, besides claude and tmux
#   NIGHTLY_CAFFEINATE          0 to skip caffeinate (default 1)
#   NIGHTLY_LAUNCHD_LOG         where launchd sends stdout, for the log only
#   NIGHTLY_NOW                 fixed local time YYYY-MM-DDTHH:MM[:SS], for tests
#   NIGHTLY_LOCK_TEST_BARRIER   a directory; for the stale-lock race test only
#
# Setting up (by hand, by the owner; nothing installs it). <clone> is the
# clone's path, quoted if it has spaces. First rebase your master onto
# origin/master and push, so that your unpushed commits do not start in the
# clone as its own (setup prints how far ahead and behind you are):
#   cd <repo>
#   tools/swift_migration/nightly_clone.sh setup [--clone <clone>]
#   cd <clone> && claude        # accept the trust dialog once, then /exit
#   cd <repo>
#   sed -e "s|__REPO__|$PWD|g" -e "s|__HOME__|$HOME|g" -e "s|__CLONE__|<clone>|g" \
#       -e "s|__ONE_UNIT_DATE__||g" \
#     tools/swift_migration/com.googlecode.iterm2.swift-migration-nightly.plist \
#     > ~/Library/LaunchAgents/com.googlecode.iterm2.swift-migration-nightly.plist
# (__ONE_UNIT_DATE__ empty: no at-least-one-unit night. To make one night an
# at-least-one-unit night (step 7), put its local date there instead,
# -e "s|__ONE_UNIT_DATE__|2026-11-23|g";
# it does nothing on other nights, so it need not be undone, though a later
# install replaces it. Every placeholder must be replaced: a literal
# __ONE_UNIT_DATE__ left in is malformed and refused, exit 64. Reinstalling
# an agent already loaded: launchctl bootout it first, then bootstrap.)
#   plutil -lint ~/Library/LaunchAgents/com.googlecode.iterm2.swift-migration-nightly.plist
#   tools/swift_migration/nightly_start.sh --dry-run    # with NIGHTLY_CLONE=<clone> if not the default
#   launchctl bootstrap gui/$(id -u) \
#     ~/Library/LaunchAgents/com.googlecode.iterm2.swift-migration-nightly.plist
#   launchctl print gui/$(id -u)/com.googlecode.iterm2.swift-migration-nightly
# Uninstalling:
#   launchctl bootout gui/$(id -u)/com.googlecode.iterm2.swift-migration-nightly
#   rm ~/Library/LaunchAgents/com.googlecode.iterm2.swift-migration-nightly.plist
# Stopping a night in progress: attach and type /exit, or
#   launchctl kill SIGTERM gui/$(id -u)/com.googlecode.iterm2.swift-migration-nightly
# Taking the night's work in the morning (does nothing unless the owner's
# checkout has master checked out, so another branch is never moved):
#   [ "$(git -C <repo> symbolic-ref -q --short HEAD)" = master ] &&
#     git -C <repo> fetch <clone> master && git -C <repo> merge --ff-only FETCH_HEAD
# then review and push. If that fast-forward refuses (his master has
# commits the clone does not), after the same fetch:
#   [ "$(git -C <repo> symbolic-ref -q --short HEAD)" = master ] && git -C <repo> rebase FETCH_HEAD
# which replays his own commits on top of the night's work and drops those
# already in it as equivalent patches, an earlier night's commits he took
# included.
# On a day he does not push, the clone keeps its commits and the next night
# rebases them onto origin/master; if that rebase fails, the night is
# skipped and the log says which commit and files and what to do.
# Two warnings for the owner: do not run `make install-hooks` in the
# clone (it sets core.hooksPath, which the configuration check refuses,
# so no night starts until it is removed); and do not build the
# third-party dependencies inside the clone's submodules (make
# paranoid-deps and the like): their untracked build directories make the
# next refresh refuse a dirty submodule.
#
# launchd (man launchd.plist, StartCalendarInterval): unlike cron, launchd
# runs a job whose time passed while the Mac was asleep when the Mac next
# wakes, and coalesces several missed times into one run; that late run is
# refused by the start window above. A launchd agent can start a tmux
# server: `new-session -d` needs no terminal.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TOOL_REPO=$(cd "$SCRIPT_DIR/../.." && pwd -P)
# launchd sets PATH (see the plist); these are only a fallback.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "nightly_start: unknown option: $arg" >&2; exit 64 ;;
  esac
done

# An absolute path without symlinks in its directories, for a path that may
# not exist yet.
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

PYTHON=${PYTHON:-/usr/bin/python3}
SOURCE=$(cd "${NIGHTLY_SOURCE:-$TOOL_REPO}" 2>/dev/null && pwd -P) || SOURCE=${NIGHTLY_SOURCE:-$TOOL_REPO}
CLONE=${NIGHTLY_CLONE:-$(dirname "$SOURCE")/iterm2-migration-nightly}
if RESOLVED=$(absolute "$CLONE"); then CLONE=$RESOLVED; fi
MIRROR="$CLONE.origin.git"
BRANCH=master
CONF="$CLONE/.git/swift-migration-nightly.conf"
NIGHTLY_ROOT=${NIGHTLY_ROOT:-$CLONE.runs}
if RESOLVED=$(absolute "$NIGHTLY_ROOT"); then NIGHTLY_ROOT=$RESOLVED; fi
# The build lanes: beside the clone, where lane_clone.py puts a repository's
# lanes by default; derived from the clone path only.
LANES="$CLONE.lanes"
SOCKET=${NIGHTLY_TMUX_SOCKET:-$NIGHTLY_ROOT/tmux.sock}
SESSION=${NIGHTLY_TMUX_SESSION:-swift-migration}
LATEST_START_HOUR=${NIGHTLY_LATEST_START_HOUR:-5}
MAX_SECONDS=${NIGHTLY_MAX_SECONDS:-21600}
STOP_AT=${NIGHTLY_STOP_AT:-07:00}
INTERRUPT_WAIT=${NIGHTLY_INTERRUPT_WAIT:-10}
GRACE_SECONDS=${NIGHTLY_GRACE_SECONDS:-300}
STALL_SECONDS=${NIGHTLY_STALL_SECONDS:-300}
CLEAN_STOP_MARGIN=${NIGHTLY_CLEAN_STOP_MARGIN:-2700}
# The closing checks (docs/swift-migration/lifecycle.md section 5) run once
# at the end of the night, one at a time. Measured on 2026-11-24 they were
# five runs (the plain whole suite about 9 minutes, nullability 7.5, integer
# 7, thread (serial) 17, the x86_64 build 1 to 8, the lints and the code
# database about 10: about an hour at worst). Since 2026-11-26 the plain,
# nullability and integer runs are one combined run (the owner: "Yes,
# please do"); the figures for it are in lifecycle.md section 5. The
# reserve was confirmed by the owner on 2026-11-24 ("keep them as is") and
# is not changed here. 75 minutes leaves a quarter of an hour to read the
# results and write the report. The prompt names the time they must start.
CLOSING_RESERVE=${NIGHTLY_CLOSING_RESERVE:-4500}
# Typed into the session once at the clean stop (deadline_run.py
# --nudge-text): an idle session waiting on background jobs gets no turn
# otherwise (2026-11-24). Fixed text, one line.
NUDGE_TEXT='It is the clean stop time. Stop now as docs/swift-migration/workflow.md section 4 says: start nothing new, stop or abandon background jobs that have not finished, commit what passed, write the night'"'"'s report, release lanes, then stop.'
MODEL=${NIGHTLY_MODEL:-opus}
REQUIRED_PROGRAMS=${NIGHTLY_REQUIRED_PROGRAMS:-git python3 xcodebuild expect ruby make}
LOCK_DIR="$NIGHTLY_ROOT/lock"
BLOCKED_PATTERN='Is this a project you created or one you trust|Yes, I trust this folder'
# NIGHTLY_CLONE_TOOL replaces nightly_clone.sh, for tests only.
CLONE_TOOL=(/bin/bash "${NIGHTLY_CLONE_TOOL:-$SCRIPT_DIR/nightly_clone.sh}")
REFRESH_SECONDS=${NIGHTLY_REFRESH_SECONDS:-1200}
CLONE_ARGS=(--source "$SOURCE" --clone "$CLONE")

# Git for this script, as in nightly_clone.sh (see its header): nothing
# from the environment that points git elsewhere, no global or system
# configuration, and the settings that make git run programs overridden on
# the command line, which wins over the repository's configuration. gc
# names the clone explicitly.
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
gc() { g --git-dir="$CLONE/.git" --work-tree="$CLONE" "$@"; }

if [ -n "${NIGHTLY_NOW:-}" ]; then
  NOW_DATE=${NIGHTLY_NOW:0:10}
  NOW_HOUR=${NIGHTLY_NOW:11:2}
  NOW_ISO=$NIGHTLY_NOW
else
  NOW_DATE=$(date +%Y-%m-%d)
  NOW_HOUR=$(date +%H)
  NOW_ISO=$(date +%Y-%m-%dT%H:%M:%S)
fi

# A private directory: made with mode 0700 when it does not exist; an
# existing one is never chmodded, and must be a real directory of this
# user that neither group nor others can write. Prints the problem.
private_dir_problem() {
  local dir=$1 mode
  if [ -L "$dir" ]; then echo "$dir is a symbolic link"; return; fi
  if [ ! -e "$dir" ]; then
    mkdir -p "$(dirname "$dir")" 2>/dev/null
    mkdir -m 700 "$dir" 2>/dev/null || { echo "cannot create $dir"; return; }
    return
  fi
  if [ ! -d "$dir" ] || [ ! -O "$dir" ]; then echo "$dir is not a directory of yours"; return; fi
  mode=$(stat -f %Lp "$dir")
  if [ $((8#$mode & 8#022)) != 0 ]; then
    echo "$dir is writable by group or others (mode $mode); make it private yourself (chmod 700)"
  fi
}

# The run directory lives in $NIGHTLY_ROOT, outside the clone; without a
# clone it is not made, and the log goes to stdout only.
RUN_DIR=
LOG=/dev/null
if [ -d "$CLONE" ]; then
  if inside "$NIGHTLY_ROOT" "$CLONE"; then
    echo "nightly_start: setup failed: NIGHTLY_ROOT $NIGHTLY_ROOT must be outside the clone $CLONE, which the session can write"
    exit 7
  fi
  PROBLEM=$(private_dir_problem "$NIGHTLY_ROOT")
  if [ -n "$PROBLEM" ]; then
    echo "nightly_start: setup failed: $PROBLEM"
    exit 7
  fi
  RUN_DIR="$NIGHTLY_ROOT/$NOW_DATE/run-$(date +%H%M%S)-$$"
  if ! mkdir -p "$RUN_DIR"; then
    echo "nightly_start: cannot create $RUN_DIR" >&2
    exit 7
  fi
  LOG="$RUN_DIR/nightly_start.log"
fi

log() {
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') nightly_start[$$]: $*"
  echo "$line"
  echo "$line" >> "$LOG"
}

# Quote one argument for display so that the printed command can be pasted
# into a shell.
shell_quote() {
  case "$1" in
    ''|*[!A-Za-z0-9_./:=@%+,-]*)
      printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
    *) printf '%s' "$1" ;;
  esac
}

LOCK_OWNED=0
CAFFEINATE_PID=
CHILD_PID=
cleanup() {
  if [ -n "$CAFFEINATE_PID" ]; then
    kill "$CAFFEINATE_PID" 2>/dev/null
    wait "$CAFFEINATE_PID" 2>/dev/null
  fi
  if [ "$LOCK_OWNED" = 1 ]; then
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null
  fi
}
trap cleanup EXIT

GOT_SIGNAL=0
on_signal() {
  GOT_SIGNAL=1
  log "received $1"
  if [ -n "$CHILD_PID" ]; then
    log "passing SIGTERM to pid $CHILD_PID"
    kill -TERM "$CHILD_PID" 2>/dev/null
  fi
}
trap 'on_signal SIGTERM' TERM
trap 'on_signal SIGINT' INT
trap 'on_signal SIGHUP' HUP

stop_if_signalled() {
  if [ "$GOT_SIGNAL" = 1 ]; then
    log "not starting: stopped by a signal ($1)"
    exit 2
  fi
}

log "started (dry run: $DRY_RUN), clone $CLONE, owner's checkout $SOURCE, logs in ${RUN_DIR:-(stdout only: no clone)}"
[ -z "${NIGHTLY_LAUNCHD_LOG:-}" ] || log "launchd log: $NIGHTLY_LAUNCHD_LOG"

# An "at least one unit" night (NIGHTLY_ONE_UNIT_DATE; see the header). Empty or unset
# means none. A value that is not a real date YYYY-MM-DD is a bad option
# (exit 64), checked before anything else so that a mistyped install never
# runs as an ordinary night; a dry run refuses it too.
ONE_UNIT=0
ONE_UNIT_DATE=${NIGHTLY_ONE_UNIT_DATE:-}
if [ -n "$ONE_UNIT_DATE" ]; then
  if ! [[ $ONE_UNIT_DATE =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
     [ "$(date -j -f %Y-%m-%d "$ONE_UNIT_DATE" +%Y-%m-%d 2>/dev/null)" != "$ONE_UNIT_DATE" ]; then
    log "bad option: NIGHTLY_ONE_UNIT_DATE=$(shell_quote "$ONE_UNIT_DATE") is not a date YYYY-MM-DD (empty means unset); nothing started"
    exit 64
  fi
  if [ "$ONE_UNIT_DATE" = "$NOW_DATE" ]; then
    ONE_UNIT=1
    log "at-least-one-unit night applies: NIGHTLY_ONE_UNIT_DATE=$ONE_UNIT_DATE is tonight's local date; the weekly ceiling (usage_check.py exit 1) does not stop the start, unknown usage still does; which case applies (under the ceiling, or at or over it) follows the usage check"
  else
    log "NIGHTLY_ONE_UNIT_DATE=$ONE_UNIT_DATE is set and does not apply tonight ($NOW_DATE): an ordinary night"
  fi
fi

# 1. Setup: the programs this run needs.
if ! CLAUDE=$(command -v "${CLAUDE_BIN:-claude}"); then
  log "setup failed: cannot find claude (${CLAUDE_BIN:-claude}) on PATH=$PATH"
  exit 7
fi
log "program claude: $CLAUDE"
if ! TMUX_BIN=$(command -v "${NIGHTLY_TMUX:-tmux}"); then
  log "setup failed: cannot find tmux (${NIGHTLY_TMUX:-tmux}) on PATH=$PATH"
  exit 7
fi
log "program tmux: $TMUX_BIN ($("$TMUX_BIN" -V 2>&1))"
MISSING=
for program in $REQUIRED_PROGRAMS; do
  if found=$(command -v "$program"); then
    log "program $program: $found"
  else
    MISSING="$MISSING $program"
  fi
done
if [ -n "$MISSING" ]; then
  log "setup failed: not found on PATH=$PATH:$MISSING"
  exit 7
fi
if ! "$PYTHON" -c 'import zoneinfo' 2>/dev/null; then
  log "setup failed: $PYTHON is not Python 3.9 or later"
  exit 7
fi
log "python for these tools: $PYTHON; PATH=$PATH"

# 2. The start window.
if [ $((10#$NOW_HOUR)) -ge $((10#$LATEST_START_HOUR)) ]; then
  if [ "$DRY_RUN" = 1 ]; then
    log "window: outside (local hour $NOW_HOUR, latest start hour $LATEST_START_HOUR); a real run would exit 6"
  else
    log "not starting: local hour $NOW_HOUR is outside the start window (before $LATEST_START_HOUR:00); probably a missed midnight run after wake"
    exit 6
  fi
else
  log "window: inside (local hour $NOW_HOUR)"
fi

# The owner's repositories are recorded before the session and compared
# after it (step 11); a difference is reported, nothing more.
owner_refs() {
  "${CLONE_TOOL[@]}" owner-refs --source "$SOURCE"
}

# Logs, prominently, how snapshot $1 differs from snapshot $2.
report_owner_change() {
  log "THE OWNER'S REPOSITORY CHANGED DURING THE NIGHT (his other agents or worktrees may have done it; look at these, - before the session, + after):"
  diff "$1" "$2" | grep '^[<>]' | sed -e 's/^</-/' -e 's/^>/+/' | while IFS= read -r line; do
    log "  $line"
  done
}

# 4. The clone, its layout, and the preflight.
SETUP_COMMAND="$(shell_quote "$SCRIPT_DIR/nightly_clone.sh") setup --clone $(shell_quote "$CLONE")"
if [ ! -f "$CONF" ]; then
  if [ ! -d "$CLONE" ]; then
    why="the nightly clone $CLONE does not exist"
  else
    why="$CLONE is not a nightly clone ($CONF is missing)"
  fi
  if [ "$DRY_RUN" = 1 ]; then
    log "clone: $why; a real run would exit 8"
    log "dry run: the owner must first make the clone, by hand, with:"
    log "  $SETUP_COMMAND"
    log "  then accept Claude Code's workspace trust dialog in it once: cd $(shell_quote "$CLONE") && claude (then /exit)"
    log "dry run: after that, each night would: take the lock in $NIGHTLY_ROOT; check that no tmux server listens on $SOCKET;"
    log "  read usage; refresh the clone from origin/master, fetched over https into the mirror ($(shell_quote "$SCRIPT_DIR/nightly_clone.sh") refresh --clone $(shell_quote "$CLONE"));"
    log "  create the lanes directory $LANES (mode 0700) and release lanes a dead session left held (lane_clone.py release --stale);"
    log "  check $CLONE/.claude/agents/; start claude --model $MODEL --permission-mode auto --add-dir $LANES in tmux session $SESSION on $SOCKET"
    log "  under deadline_run.py (hard limit the earlier of ${MAX_SECONDS}s and $STOP_AT); attach with: $(shell_quote "$TMUX_BIN") -S $(shell_quote "$SOCKET") attach -t $SESSION"
    exit 0
  fi
  log "not starting: preflight: $why; make it first, by hand, with: $SETUP_COMMAND"
  exit 8
fi
log "clone $CLONE: source (the owner's checkout, read only) $SOURCE; mirror $MIRROR; branch $BRANCH"

# The layout and configuration must be what setup made, before any git
# command runs in the clone (nightly_clone.sh check reads files only).
CHECK_OUT=$("${CLONE_TOOL[@]}" check "${CLONE_ARGS[@]}" 2>&1)
CHECK_RC=$?
while IFS= read -r line; do log "check: $line"; done <<< "$CHECK_OUT"
case "$CHECK_RC" in
  0) ;;
  10)
    if [ "$DRY_RUN" = 1 ]; then
      log "preflight: the clone's layout or configuration is not what setup made; a real run would exit 12"
    else
      log "not starting: preflight: the clone's layout or configuration is not what setup made (see above); look at what changed, then fix it by hand"
      exit 12
    fi ;;
  *)
    if [ "$DRY_RUN" = 1 ]; then
      log "preflight: nightly_clone.sh check exited $CHECK_RC; a real run would exit 8"
    else
      log "not starting: preflight: nightly_clone.sh check exited $CHECK_RC"
      exit 8
    fi ;;
esac

# Files in the clone's working tree that load into the session as rules,
# settings or hooks, and that origin/master does not track.
# What the owner has is read from his repository, never from a ref in the
# clone (the session can move refs/remotes/origin/master).
SOURCE_GITDIR=$(g -C "$SOURCE" rev-parse --absolute-git-dir 2>/dev/null)
# The rule files, as git pathspecs, from nightly_clone.sh's one definition.
RULE_PATHSPECS=()
while IFS= read -r line; do [ -z "$line" ] || RULE_PATHSPECS+=("$line"); done \
  < <("${CLONE_TOOL[@]}" rule-pathspecs 2>/dev/null)
if [ "${#RULE_PATHSPECS[@]}" = 0 ]; then
  log "setup failed: nightly_clone.sh rule-pathspecs printed nothing"
  exit 7
fi

# The upstream's master as the trusted refresh last fetched it into the
# mirror (outside the clone), never a ref in the clone.
upstream_master() { g --git-dir="$MIRROR" rev-parse -q --verify "refs/heads/$BRANCH"; }

# Every file under the clone's top-level .claude/ (untracked or ignored
# included), and a top-level CLAUDE.local.md, that origin/master $1
# does not track. .claude/worktrees/ is exempt: Claude Code keeps its own
# agent worktrees there.
untracked_rule_files() {
  local o=$1 f rel
  { [ -e "$CLONE/CLAUDE.local.md" ] && echo "$CLONE/CLAUDE.local.md"
    [ -d "$CLONE/.claude" ] && find "$CLONE/.claude" -path "$CLONE/.claude/worktrees" -prune -o ! -type d -print 2>/dev/null; } | sort |
  while IFS= read -r f; do
    rel=${f#"$CLONE"/}
    if [ -z "$o" ] || [ -z "$(g --git-dir="$MIRROR" ls-tree --name-only "$o" -- "$rel" 2>/dev/null)" ]; then
      echo "$rel"
    fi
  done
}

# Changes, in the clone's master relative to origin/master $1 (read from
# the mirror), to the files that carry rules into a session.
rule_changes() {
  local o=$1 c
  [ -n "$o" ] && c=$(gc rev-parse -q --verify "refs/heads/$BRANCH") ||
    { echo "(cannot read the owner's $BRANCH or the clone's)"; return; }
  gc diff --ignore-submodules=all --no-ext-diff --no-textconv --name-status "$o" "$c" -- \
    "${RULE_PATHSPECS[@]}" 2>&1 | tr '\t' ' '
}

preflight_problem() {
  local out gitdir="$CLONE/.git" branch
  if ! out=$(gc status --porcelain --ignore-submodules=all 2>&1 >/dev/null); then
    echo "git status cannot run in $CLONE: $out"; return
  fi
  # A lock left by a killed git is removed when no process names the
  # clone; nightly_clone.sh clear-locks says which, or refuses (exit 8).
  if [ -e "$gitdir/index.lock" ]; then
    local verb_args=()
    [ "$DRY_RUN" = 1 ] && verb_args=(--dry-run)
    if ! out=$("${CLONE_TOOL[@]}" clear-locks "${CLONE_ARGS[@]}" ${verb_args[@]+"${verb_args[@]}"} 2>&1); then
      echo "$gitdir/index.lock exists and is in use: $out"; return
    fi
    while IFS= read -r line; do [ -z "$line" ] || log "preflight: $line" >&2; done <<< "$out"
  fi
  if [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; then
    echo "a rebase is in progress"; return
  fi
  if [ -e "$gitdir/MERGE_HEAD" ]; then echo "a merge is in progress"; return; fi
  if [ -e "$gitdir/CHERRY_PICK_HEAD" ]; then echo "a cherry-pick is in progress"; return; fi
  if [ -e "$gitdir/REVERT_HEAD" ]; then echo "a revert is in progress"; return; fi
  if [ -e "$gitdir/BISECT_LOG" ]; then echo "a bisect is in progress"; return; fi
  if ! branch=$(gc symbolic-ref -q --short HEAD); then
    echo "HEAD is detached"; return
  fi
  if [ "$branch" != "$BRANCH" ]; then
    echo "HEAD is on branch $branch, not $BRANCH"; return
  fi
}
PROBLEM=
if [ "$CHECK_RC" = 0 ]; then
  PROBLEM=$(preflight_problem)
fi
if [ -n "$PROBLEM" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    log "preflight: $PROBLEM; a real run would exit 8"
  else
    log "not starting: preflight: $PROBLEM"
    exit 8
  fi
elif [ "$CHECK_RC" = 0 ]; then
  log "preflight: clean state, on $BRANCH, origin is the mirror and cannot be pushed to"
fi
stop_if_signalled preflight

# The tmux socket's path and directory.
SOCKET_BYTES=$(printf '%s' "$SOCKET" | wc -c | tr -d ' ')
if [ "$SOCKET_BYTES" -gt 103 ]; then
  log "setup failed: the tmux socket path $SOCKET is $SOCKET_BYTES bytes; a unix socket path on macOS must be at most 103; set NIGHTLY_TMUX_SOCKET"
  exit 7
fi
SOCKET_DIR=$(dirname "$SOCKET")
if [ -d "$CLONE" ] && inside "$(absolute "$SOCKET_DIR" || echo "$SOCKET_DIR")" "$CLONE"; then
  log "setup failed: the tmux socket $SOCKET must be outside the clone $CLONE, which the session can write"
  exit 7
fi
PROBLEM=$(private_dir_problem "$SOCKET_DIR")
if [ -n "$PROBLEM" ]; then
  log "setup failed: the tmux socket's directory: $PROBLEM"
  exit 7
fi
ATTACH="$(shell_quote "$TMUX_BIN") -S $(shell_quote "$SOCKET") attach -t $(shell_quote "$SESSION")"

# 5. The lock.
lock_holder_alive() {
  # Alive means the pid exists and is a nightly_start process, so that a
  # pid reused by an unrelated program after a crash does not hold the lock.
  local pid=$1
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  ps -p "$pid" -o command= 2>/dev/null | grep -q 'nightly_start\.sh'
}

lock_pid() {
  [ -f "$1/pid" ] && tr -cd '0-9' < "$1/pid"
}

lock_state() {
  # Prints "free", "held <pid>", "young" (no pid file yet) or "stale <why>".
  if [ ! -d "$LOCK_DIR" ]; then
    echo free; return
  fi
  local pid
  pid=$(lock_pid "$LOCK_DIR")
  if [ -z "$pid" ]; then
    local mtime age
    mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)
    age=$(( $(date +%s) - mtime ))
    if [ "$age" -lt 120 ]; then
      echo young
    else
      echo "stale no pid file, ${age}s old"
    fi
    return
  fi
  if lock_holder_alive "$pid"; then
    echo "held $pid"
  else
    echo "stale pid $pid is not a running nightly_start"
  fi
}

claim_lock() {
  # The directory is ours; record our pid and check that it is still ours.
  if ! echo "$$" > "$LOCK_DIR/pid" 2>/dev/null || [ "$(lock_pid "$LOCK_DIR")" != "$$" ]; then
    log "not starting: lost the lock $LOCK_DIR to another run while taking it"
    exit 3
  fi
  LOCK_OWNED=1
  log "lock taken: $LOCK_DIR"
}

take_lock() {
  mkdir -p "$NIGHTLY_ROOT"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    claim_lock; return
  fi
  local state stale_pid aside moved_pid
  state=$(lock_state)
  case "$state" in
    free)
      # Released between the mkdir and the look; try once more.
      if mkdir "$LOCK_DIR" 2>/dev/null; then claim_lock; return; fi
      log "not starting: another run took the lock $LOCK_DIR first"
      exit 3 ;;
    held*)
      log "not starting: another orchestrator holds the lock (pid ${state#held }, $LOCK_DIR)"
      exit 3 ;;
    young)
      log "not starting: the lock $LOCK_DIR is being created by another run"
      exit 3 ;;
  esac
  # For the race test only: the first run to get here waits until the
  # test creates $NIGHTLY_LOCK_TEST_BARRIER/go, which it does once the
  # other run has replaced the lock and started its session, so that this
  # run then acts on a judgment that is out of date. Bounded at 60 seconds.
  if [ -n "${NIGHTLY_LOCK_TEST_BARRIER:-}" ] &&
      mkdir "$NIGHTLY_LOCK_TEST_BARRIER/first" 2>/dev/null; then
    local waited=0
    while [ ! -e "$NIGHTLY_LOCK_TEST_BARRIER/go" ] && [ "$waited" -lt 1200 ]; do
      sleep 0.05; waited=$((waited + 1))
    done
  fi
  # Stale. Rename it aside (atomic: of two runs, only one can move it),
  # check that what was moved is the lock judged stale and not a fresh one
  # that another run made in the meantime, then mkdir a new one (atomic:
  # only one run can make it).
  # The pid that was judged stale, from the judgment itself: reading the
  # pid file again here could read a fresh lock's pid.
  case "$state" in
    "stale pid "*) stale_pid=${state#stale pid }; stale_pid=${stale_pid%% *} ;;
    *) stale_pid= ;;
  esac
  aside="$LOCK_DIR.stale.$$"
  if ! mv "$LOCK_DIR" "$aside" 2>/dev/null; then
    log "not starting: another run is replacing the stale lock $LOCK_DIR"
    exit 3
  fi
  moved_pid=$(lock_pid "$aside")
  if [ "$moved_pid" != "$stale_pid" ]; then
    # It was another run's fresh lock: put it back and give way.
    mv "$aside" "$LOCK_DIR" 2>/dev/null ||
      log "could not put back $aside as $LOCK_DIR"
    log "not starting: another run replaced the stale lock first"
    exit 3
  fi
  rm -f "$aside/pid"
  rmdir "$aside" 2>/dev/null
  log "replaced stale lock: ${state#stale }"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log "not starting: another run took the lock $LOCK_DIR first"
    exit 3
  fi
  claim_lock
}

if [ "$DRY_RUN" = 1 ]; then
  STATE=$(lock_state)
  case "$STATE" in
    held*) log "lock: held by pid ${STATE#held }; a real run would exit 3" ;;
    young) log "lock: being created by another run; a real run would exit 3" ;;
    *) log "lock: $STATE" ;;
  esac
else
  take_lock
fi
stop_if_signalled lock

# 6. One session at a time on the socket.
if "$TMUX_BIN" -S "$SOCKET" list-sessions >/dev/null 2>&1; then
  if [ "$DRY_RUN" = 1 ]; then
    log "socket: a tmux server is listening on $SOCKET; a real run would exit 10"
  else
    log "not starting: a tmux server is already listening on $SOCKET (look with: $ATTACH)"
    exit 10
  fi
else
  log "socket: no tmux server on $SOCKET"
fi

# The lanes directory, which the session may edit (--add-dir). Like the run
# directory: made with mode 0700 when absent, never chmodded, refused when
# it is a symbolic link or others can write it. A dry run makes nothing.
# After the lock, so that two starts never race to create it.
if [ "$DRY_RUN" = 1 ] && [ ! -e "$LANES" ] && [ ! -L "$LANES" ]; then
  log "lanes: $LANES does not exist; a real run would create $LANES with mode 0700; the session may edit there (--add-dir)"
else
  PROBLEM=$(private_dir_problem "$LANES")
  if [ -z "$PROBLEM" ]; then
    log "lanes: $LANES (the session may edit there: --add-dir)"
  elif [ "$DRY_RUN" = 1 ]; then
    log "lanes: the lanes directory: $PROBLEM; a real run would exit 7"
  else
    log "setup failed: the lanes directory: $PROBLEM"
    exit 7
  fi
fi

# 7. Usage. In the background, so that a signal stops it at once.
USAGE_OUT=${RUN_DIR:-/dev/null}/usage.txt
USAGE_ARGS=(--run --claude "$CLAUDE" --timeout 120)
if [ -n "${NIGHTLY_NOW:-}" ]; then
  USAGE_ARGS+=(--now "$NIGHTLY_NOW")
fi
"$PYTHON" -B "$SCRIPT_DIR/usage_check.py" "${USAGE_ARGS[@]}" > "$USAGE_OUT" 2>&1 &
CHILD_PID=$!
wait "$CHILD_PID"
USAGE_RC=$?
if [ "$GOT_SIGNAL" = 1 ]; then
  wait "$CHILD_PID" 2>/dev/null
  USAGE_RC=$?
fi
CHILD_PID=
while IFS= read -r line; do log "usage: $line"; done < "$USAGE_OUT"
stop_if_signalled "during the usage check, which exited $USAGE_RC"
# On an at-least-one-unit night exit 1 lets the night start, so it must be the
# ceiling verdict itself: Python also exits 1 when usage_check.py dies of an
# uncaught exception, and that is usage unknown.
if [ "$ONE_UNIT" = 1 ] && [ "$USAGE_RC" = 1 ] &&
   ! grep -q '^verdict: at or over the ceiling (exit 1)$' "$USAGE_OUT" 2>/dev/null; then
  log "usage: usage_check exited 1 without its ceiling verdict (it failed); taken as unknown"
  USAGE_RC=2
fi
# ONE_UNIT_OVER: on an at-least-one-unit night, usage was at or over the
# ceiling at the start, so the night does exactly one unit.
ONE_UNIT_OVER=0
case "$USAGE_RC" in
  0)
    [ "$ONE_UNIT" = 0 ] ||
      log "usage: under tonight's ceiling on the at-least-one-unit night (NIGHTLY_ONE_UNIT_DATE): an ordinary night, except that until one unit has landed the ceiling does not stop it: it takes or finishes one unit, then stops" ;;
  1)
    if [ "$ONE_UNIT" = 1 ]; then
      ONE_UNIT_OVER=1
      if [ "$DRY_RUN" = 1 ]; then
        log "usage: at or over tonight's ceiling, but this is an at-least-one-unit night (NIGHTLY_ONE_UNIT_DATE): a real run would start anyway and do exactly one unit"
      else
        log "usage: at or over tonight's ceiling; starting anyway: this is an at-least-one-unit night (NIGHTLY_ONE_UNIT_DATE), and it does exactly one unit"
      fi
    elif [ "$DRY_RUN" = 1 ]; then
      log "would not start: at or over the ceiling (a real run would exit 1)"
    else
      log "not starting: weekly usage is at or over tonight's ceiling"
      exit 1
    fi ;;
  *)
    if [ "$DRY_RUN" = 1 ]; then
      log "would not start: usage could not be determined (a real run would exit 2)"
    else
      log "not starting: usage could not be determined (usage_check exit $USAGE_RC)"
      exit 2
    fi ;;
esac

# 8. Refresh the clone from origin/master (fetched into the mirror over https).
if [ "$DRY_RUN" = 1 ]; then
  REFRESH_VERB=status
else
  REFRESH_VERB=refresh
fi
# Under a time bound (NIGHTLY_REFRESH_SECONDS, default 20 minutes): a
# network fetch that hangs must not hold the night. deadline_run.py runs it
# in its own session and, at the bound, kills it and everything it started
# (exit 124).
REFRESH_OUT=$("$PYTHON" -B "$SCRIPT_DIR/deadline_run.py" --seconds "$REFRESH_SECONDS" \
                --grace 5 --term-grace 5 --sweep-grace 5 -- \
                "${CLONE_TOOL[@]}" "$REFRESH_VERB" "${CLONE_ARGS[@]}" 2>&1)
REFRESH_RC=$?
if [ "$REFRESH_RC" = 124 ]; then
  log "setup failed: the refresh did not finish within $REFRESH_SECONDS seconds (NIGHTLY_REFRESH_SECONDS); it and everything it started were killed; nothing starts tonight"
  while IFS= read -r line; do log "refresh: $line"; done <<< "$REFRESH_OUT"
  exit 7
fi
# What the refresh did, for the orchestrator: one line each for whether
# origin/master could be fetched tonight, whether upstream commits came in,
# and whether the clone's commits were rebased or reset (the prompt names
# this file).
REFRESH_STATUS="${RUN_DIR:-/dev/null}/refresh.status"
[ -z "$RUN_DIR" ] || printf '%s\n' "$REFRESH_OUT" |
  grep -E '^nightly_clone: (upstream|upstream-commits|rebased|rebase-failed|already-upstream|taken-by-owner|submodule-stale):' > "$REFRESH_STATUS"
while IFS= read -r line; do log "refresh: $line"; done <<< "$REFRESH_OUT"
stop_if_signalled "during the refresh"
if [ "$DRY_RUN" != 1 ]; then
  case "$REFRESH_RC" in
    0) ;;
    9) log "not starting: the clone's commits could not be rebased onto origin/$BRANCH, or the upstream was force-pushed (see above); nothing changed in the clone"; exit 9 ;;
    8) log "not starting: the clone is not in a state to refresh"; exit 8 ;;
    10) log "not starting: the clone's layout or configuration is not what setup made"; exit 12 ;;
    *) log "setup failed: the refresh failed (nightly_clone.sh exit $REFRESH_RC)"; exit 7 ;;
  esac
fi

# Rule files the clone would carry into the session that are not upstream
# (origin/master, as the refresh just fetched it into the mirror).
OWNER_MASTER=$(upstream_master)
if [ "$CHECK_RC" = 0 ]; then
  RULES=$(rule_changes "$OWNER_MASTER"; untracked_rule_files "$OWNER_MASTER" | sed 's/^/not tracked upstream: /')
  if [ -n "$RULES" ]; then
    log "preflight: the clone's $BRANCH changes files that carry rules into a session, which are not upstream (origin/$BRANCH) yet:"
    while IFS= read -r line; do log "  $line"; done <<< "$RULES"
    if [ "$DRY_RUN" = 1 ]; then
      log "preflight: a real run would exit 8"
    else
      log "not starting: preflight: remove the files listed as not tracked upstream (rm them in $CLONE), and take and push the commits that change rule files (or drop them with nightly_clone.sh reset)"
      exit 8
    fi
  fi
fi

# Build lanes that an earlier session left held: its Claude Code process,
# the holder lane_clone.py recorded, is dead, so the lock is stale and the
# lane would never be handed out again. release --stale saves the lane's
# uncollected work under $LANES/saved/ and frees it. Only after the layout
# check passed (lane_clone.py runs git in the clone and its lanes, with
# hooks and fsmonitor off), with no global or system git configuration and
# none of the variables that point git elsewhere.
lane_tool() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
      -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
      -u GIT_CONFIG -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
      -u GIT_PROTOCOL_FROM_USER -u GIT_EXTERNAL_DIFF \
      GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
    "$PYTHON" -B "$SCRIPT_DIR/lane_clone.py" --repo "$CLONE" --lanes-dir "$LANES" "$@"
}
if [ "$CHECK_RC" = 0 ]; then
  if [ ! -f "$LANES/lanes.json" ]; then
    log "lanes: no lanes made yet in $LANES"
  else
    LANES_OUT=$(lane_tool status 2>&1)
    LANES_RC=$?
    while IFS= read -r line; do log "lanes: $line"; done <<< "$LANES_OUT"
    [ "$LANES_RC" = 0 ] || log "LANES: lane_clone.py status exited $LANES_RC"
    if [ "$DRY_RUN" = 1 ]; then
      log "lanes: a real run would run release --stale here, saving the uncollected work of each lane whose holder is dead under $LANES/saved/"
    else
      LANES_OUT=$(lane_tool release --stale 2>&1)
      LANES_RC=$?
      while IFS= read -r line; do [ -z "$line" ] || log "lanes: release --stale: $line"; done <<< "$LANES_OUT"
      if [ "$LANES_RC" = 0 ]; then
        log "lanes: release --stale done (work saved, if any, is named above and is under $LANES/saved/)"
      else
        log "LANES: lane_clone.py release --stale exited $LANES_RC; a lane it could not release stays held, and the orchestrator sees it with status"
      fi
    fi
  fi
fi
stop_if_signalled "while releasing stale lanes"

# 9. The agent definitions, tracked in the clone's .claude/agents/.
AGENTS_DIR="$CLONE/.claude/agents"
if ! "$PYTHON" -B "$SCRIPT_DIR/agents_json.py" --require-model opus \
    --output "$RUN_DIR/agents-check.json" \
    "$AGENTS_DIR/migration-author.md" "$AGENTS_DIR/migration-reviewer.md" >> "$LOG" 2>&1; then
  log "setup failed: the agent definitions in $AGENTS_DIR are missing, do not parse, or do not pin opus"
  exit 7
fi
log "agents: $AGENTS_DIR/migration-author.md and migration-reviewer.md parse and pin opus; the session finds them there"

# 10. The session.
DEADLINE_ARGS=(--seconds "$MAX_SECONDS" --until "$STOP_AT")
SHOW_ARGS=("${DEADLINE_ARGS[@]}" --interrupt-wait "$INTERRUPT_WAIT" --grace "$GRACE_SECONDS"
           --clean-stop-margin "$CLEAN_STOP_MARGIN")
if [ -n "${NIGHTLY_NOW:-}" ]; then
  SHOW_ARGS+=(--now "$NIGHTLY_NOW")
fi
if ! TIMES=$("$PYTHON" -B "$SCRIPT_DIR/deadline_run.py" --show-deadline "${SHOW_ARGS[@]}" 2>&1); then
  log "setup failed: cannot compute the deadline: $TIMES"
  exit 7
fi
HARD=$(printf '%s\n' "$TIMES" | sed -n 's/^hard=//p')
STOP_START=$(printf '%s\n' "$TIMES" | sed -n 's/^stop_start=//p')
CLEAN_STOP=$(printf '%s\n' "$TIMES" | sed -n 's/^clean_stop=//p')
log "clean stop by $CLEAN_STOP; the stop sequence starts at $STOP_START; hard limit $HARD"
if ! CLOSING_TIMES=$("$PYTHON" -B "$SCRIPT_DIR/deadline_run.py" --show-deadline "${SHOW_ARGS[@]}" \
    --clean-stop-margin "$((CLEAN_STOP_MARGIN + CLOSING_RESERVE))" 2>&1); then
  log "setup failed: cannot compute the closing checks' start: $CLOSING_TIMES"
  exit 7
fi
CLOSING_BY=$(printf '%s\n' "$CLOSING_TIMES" | sed -n 's/^clean_stop=//p')
log "closing checks by $CLOSING_BY ($CLOSING_RESERVE seconds before the clean stop)"

NIGHT_ID="night-$NOW_DATE-$(date +%H%M%S)-$$-$(uuidgen 2>/dev/null || echo $RANDOM$RANDOM)"
SESSION_ID=$(uuidgen | tr 'A-F' 'a-f')
CLONE_PHYSICAL=$(cd "$CLONE" && pwd -P)
TRANSCRIPT="$HOME/.claude/projects/$(printf '%s' "$CLONE_PHYSICAL" | sed 's/[^A-Za-z0-9]/-/g')/$SESSION_ID.jsonl"
REPORT="$CLONE/tmp/swift-migration-night-$NOW_DATE.md"

# Deny rules; see the header for what they cover and what they cannot.
DENY_RULES=(
  'Bash(git push *)' 'Bash(git * push *)' 'Bash(git * push)'
  'Bash(git send-pack *)' 'Bash(git * send-pack *)'
  'Bash(git remote *)' 'Bash(git * remote *)'
  'Bash(*pushurl*)' 'Bash(*send-pack*)' 'Bash(*receive-pack*)'
  'Bash(gh *)'
  'Bash(osascript *)' 'Bash(launchctl *)' 'Bash(sudo *)' 'Bash(open *)'
  'Bash(ssh *)' 'Bash(scp *)'
  'Bash(it2 *)' 'Bash(*/it2 *)'
  'Bash(tmux *)' 'Bash(*/tmux *)'
  'Bash(*gitlab-issue-*)'
)
DISALLOWED_TOOLS=(
  'mcp__*' RemoteTrigger CronCreate CronDelete CronList PushNotification
  Workflow DesignSync ScheduleWakeup AskUserQuestion
)
if ! "$PYTHON" -c '
import json, sys
json.dump({
    "permissions": {"deny": sys.argv[1:], "denyInsteadOfPrompting": True},
    "autoMode": {"classifyAllShell": True},
    "disableClaudeAiConnectors": True,
}, sys.stdout, indent=2)
print()' "${DENY_RULES[@]}" > "$RUN_DIR/session-settings.json"; then
  log "setup failed: cannot write the session settings"
  exit 7
fi

# Git and gh guards.
GH_EMPTY="$RUN_DIR/gh-config-empty"
SSH_WRAPPER="$RUN_DIR/ssh-no-push"
mkdir -p "$GH_EMPTY"
cat > "$SSH_WRAPPER" <<'EOF'
#!/bin/sh
# GIT_SSH_COMMAND for the nightly session: refuse a push, allow the rest.
for a in "$@"; do
  case "$a" in
    *git-receive-pack*)
      echo "nightly_start guard: a push over ssh was refused" >&2
      exit 1 ;;
  esac
done
exec /usr/bin/ssh "$@"
EOF
chmod +x "$SSH_WRAPPER"
GIT_GUARDS=("GIT_CONFIG_KEY_0=credential.helper" "GIT_CONFIG_VALUE_0=")
n=1
for prefix in https:// http:// ssh:// git@ git:// file:// / .; do
  GIT_GUARDS+=("GIT_CONFIG_KEY_$n=url.nightly-push-blocked://.pushInsteadOf"
               "GIT_CONFIG_VALUE_$n=$prefix")
  n=$((n + 1))
done
GIT_GUARDS+=("GIT_CONFIG_COUNT=$n")

UPSTREAM_NOTE=
if grep -q '^nightly_clone: upstream: NOT REFRESHED' "$REFRESH_STATUS" 2>/dev/null; then
  UPSTREAM_NOTE=" origin/master could not be fetched tonight (see $REFRESH_STATUS), so it is as old as the last fetch that worked: say so in the night's report."
fi
ONE_UNIT_NOTE=
if [ "$ONE_UNIT" = 1 ] && [ "$ONE_UNIT_OVER" = 0 ]; then
  ONE_UNIT_NOTE=" By the owner's order, set for tonight ($NOW_DATE) through NIGHTLY_ONE_UNIT_DATE, this night does at least one unit. Until one unit has landed (committed), an exit status 1 from usage_check.py --run whose output has the line 'verdict: at or over the ceiling (exit 1)' is not a reason to stop: if no unit is in progress yet, take one (the unparked claimed unit in claims.md if there is one, else the next eligible unit); if units are in progress, start no new unit, carry the one nearest to landing through to its commits, and save the others as \"Stopping cleanly\" in docs/swift-migration/workflow.md section 4 says. Do not park that unit because of the ceiling; if it must be parked for a reason the documents give, take the next eligible unit the same way, unless that is past the closing-checks start time. Once a unit has landed, exit status 1 stops the night as on any other night: do the end-of-session steps, write the night's report and stop. An exit status 1 without that verdict line, or exit status 2, means usage is unknown: stop at any time."
elif [ "$ONE_UNIT" = 1 ]; then
  ONE_UNIT_NOTE=" By the owner's order, set for tonight ($NOW_DATE) through NIGHTLY_ONE_UNIT_DATE, this night does exactly one unit: resume the unparked claimed unit in claims.md if there is one, else take the next eligible unit; carry it through to its commits, or park it as the documents say; start no second unit; then do the end-of-session steps (\"Stopping cleanly\" in docs/swift-migration/workflow.md section 4), write the night's report and stop. Tonight the weekly usage ceiling does not apply: an exit status 1 from usage_check.py --run is not a reason to stop tonight, but exit status 2 (usage unknown) still is. An exit status 1 whose output lacks the line 'verdict: at or over the ceiling (exit 1)' means the check itself failed, which is unknown: stop. This order is also the owner's word that units may start (docs/swift-migration/lifecycle.md section 3)."
fi
if [ -n "${NIGHTLY_PROMPT:-}" ]; then
  PROMPT=$NIGHTLY_PROMPT
  log "prompt replaced by NIGHTLY_PROMPT"
  [ "$ONE_UNIT" = 0 ] || log "NIGHTLY_PROMPT replaces the prompt, so it does not carry the at-least-one-unit instruction"
else
  PROMPT="You are the Swift migration orchestrator, started unattended at $NOW_ISO by tools/swift_migration/nightly_start.sh (SWIFT_MIGRATION_NIGHTLY=1) in an interactive session inside tmux; nobody is watching, though the owner may attach. Follow docs/swift-migration/orchestration.md from the top. Never wait for the owner: permission prompts are denied automatically, so if something is denied, find another way or record it for the owner. This is the separate nightly clone, not the owner's checkout: its origin is a read-only mirror of the project's origin/master, which was fetched from GitHub and onto which the clone's commits were rebased before you started, so there is nothing to fetch or rebase; master may hold earlier nights' commits that are not upstream yet, which is normal. What the refresh did is in $REFRESH_STATUS: if it shows upstream-commits: taken, rebased:, already-upstream: or taken-by-owner: (replaying the clone's earlier commits conflicted, the owner's checkout holds them, and master was reset to origin/master), new code arrived. Whether or not it did, follow orchestration.md section 1, step 4, whose three rules are: Rule 1. Run tools/swift_migration/codedb/refresh.sh --status in the checkout that holds the database before briefing any unit. Rule 2. Current (exit 0): qualify and brief. Behind (exit 4): run qualify_unit.py UNIT for the candidate trivial units first, brief those that print trivial, then start the database refresh, and qualify each of them again after it exits 0 and before collecting it; light and full units wait for it. Running (exit 75): wait, and act on no answer from the database. Rule 3. Read the database refresh's exit status before anything depends on it, and change no file the build or the classification reads in that checkout while it runs. Its exit statuses: 0 success; 3 a file the build or the classification reads changed during it, so run it again; 5 a rebase, merge or similar git operation is in progress, so it did not start; 11, 12 or 13 the step its verdict names failed; 75 another database refresh is running. When behind, start the database refresh (tools/swift_migration/codedb/refresh.sh) and, if orchestration.md section 1 step 4.5 calls for it, the baseline in the background and start the first trivial unit at once (unless units are landed, closing checks pending: their closing checks come first), telling its author not to run qualify_unit.py or a database query until the database refresh has ended; the candidates come from tmp/classify.txt, and if tmp/classify.txt is missing, wait for the database refresh; light and full units start only after the refresh has exited 0; while the capture and the baseline run, at most one author builds (orchestration.md section 1, step 4); a submodule-stale: line names a submodule left behind, so the build may fail.$UPSTREAM_NOTE Never push and never add or change remotes: pushing, gh, osascript, launchctl, sudo, open, ssh, it2 and tmux are denied, and git is set up so that a push fails. Write each commit message to a file and commit with git commit -F, so that a message that mentions pushing is not taken for a push. Check usage with \`python3 tools/swift_migration/usage_check.py --run\` (exit 0 may start another agent, 1 at or over the ceiling, 2 unknown, which means stop) before each subagent and each gate run.$ONE_UNIT_NOTE Use the migration-author agent for authors and a new migration-reviewer agent for every review. Bugs come first, then ports (the owner, 2026-11-27): before any unit, fix the bugs in docs/swift-migration/bugs/ one at a time in file-name order, each as one fix commit by docs/swift-migration/README.md section 5, \"Fixing a bug in the app\" (a test seen failing, the fix, the test seen passing, a new migration-reviewer, back to the test on a nontrivial finding), and take units only when the folder is empty or every remaining bug is waiting on the owner; a bug whose fix would change a file under a reserved prefix (docs/swift-migration/reserved.md), or that was parked, waits on the owner and the next one is taken. A real bug in the app found tonight that still exists gets its own file in docs/swift-migration/bugs/ (README.md section 7, \"Bugs in the app\"), and after the closing checks the bug files whose source changed are checked again. Each unit takes the trivial, light or full path that tools/swift_migration/qualify_unit.py prints (docs/swift-migration/lifecycle.md section 3), and a unit for which it prints reserved (docs/swift-migration/reserved.md) is not ported at all; when eligible trivial units exist, prefer a batch of them, each its own commit with its own review (orchestration.md section 2). Trivial or light units with no dependency on each other may be authored in parallel, at most three at once (the owner allowed it for trivial units on 2026-11-24, light units were already allowed; three is the migration's number), each in its own lane, their commits landing one at a time; if a later unit's project-file change no longer applies, run pbxproj_swap.py again in this clone (lifecycle.md section 3, \"The project file\"). Do not wait idle on one author: launch authors up to that limit, gate and commit each unit as it comes back, and launch the next. Never park a unit on a tool defect: when a lint, comparison or other gate tool fails for a reason shown not to be the unit's (the same failure on the unmodified tree or on the before state compared with itself; never a build failure or a failing test), record it in bugs.md with the evidence first, say so in the commit message and the night's report, and commit the unit; park only when the failure may be the unit's, the evidence is missing, or the question is a behavior change for users (docs/swift-migration/workflow.md section 2). Light and full code commits pass the plain whole suite through tools/swift_migration/whole_suite.sh before they are committed (docs/swift-migration/README.md section 5, step 3); the trivial path runs none, and whole suites serialize through the whole-suite lock. No unit runs a sanitizer suite, the x86_64 build or the lints: those are the closing checks, run once over everything that landed, one at a time in this order: the combined run (tools/swift_migration/sanitizer_tests.sh combined --parallel: the test plan's address sanitizer plus the nullability and integer checks in one build and one run, with three verdicts; it is also the plain whole suite once more), the thread run (sanitizer_tests.sh thread, serial), the x86_64 build, then tools/swift_migration/codedb/refresh.sh (read its exit status first: nonzero is a failed check) and, when it succeeded, the lints. Start the closing checks (docs/swift-migration/lifecycle.md section 5) by $CLOSING_BY: start no new unit after that, or earlier if a unit cannot be committed by then, and if they cannot all finish by the clean stop, say in the night's report which did not run and that the units they cover are landed, closing checks pending. osascript stays denied tonight, so a unit named in iTerm2.sdef stays landed, closing checks pending with the note \"AppleScript comparison owed\" (docs/swift-migration/lifecycle.md section 3) for a day session. Agents that build or test work in build lanes from tools/swift_migration/lane_clone.py (orchestration.md section 3); this clone's lanes are in $LANES, outside the clone, where this session may edit. Never wait on a background job without a bound. Run whole suites one at a time and only through the migration's scripts (tools/swift_migration/whole_suite.sh for the plain whole suite, fast_tests.sh, sanitizer_tests.sh, coverage_tests.sh). All of them take the machine-wide whole-suite lock and exit 124 when their stall watchdog stops a run; fast_tests.sh, sanitizer_tests.sh and coverage_tests.sh also give every test XCTest's time allowance, and a test over it fails the run (exit 65); whole_suite.sh cannot pass the allowance, and its watchdog is run_tests.expect's own (300 seconds with no output; it writes tmp/test-stall-<time>.txt). Never run sanitizer_tests.sh thread with --parallel. Such a script prints its pid first; when you run it in the background, wait for it only with a foreground command that returns when it ends or a bound passes, \`python3 tools/swift_migration/suite_guard.py wait --pid PID --seconds 540\` (exit 0: it ended; 3: still running) with a Bash timeout of 600000 ms, and after each return compare the time with the clean stop below before waiting again; do not end your turn to wait for a background job's notification, since an idle session gets no turn until something arrives. At $CLEAN_STOP the line \"$NUDGE_TEXT\" is typed into this session; when you see it, do what it says. You must have stopped cleanly, following \"Stopping cleanly\" in docs/swift-migration/workflow.md section 4, by $CLEAN_STOP local time: start nothing new after that, let running subagents finish, commit what passed the loop and the gate, save other work as a patch recorded in claims.md, restore the tree, and write the night's report to $REPORT. When the night's work is done, at the clean stop or earlier (the night's report written, the lanes released), your last action is to run $SCRIPT_DIR/nightly_done.sh: it tells the supervisor that the work is done, and the supervisor then ends this session at once (an idle session otherwise sits at its prompt until the hard limit). Type nothing after it. At $HARD the hard limit kills the session and everything it started, finished or not. This run's logs are in $RUN_DIR."
fi
printf '%s' "$PROMPT" > "$RUN_DIR/prompt.txt"

STATUS_FILE="$RUN_DIR/session.status"
DONE_FILE="$RUN_DIR/session.done"
ROOT_FILE="$RUN_DIR/session.root"
CLAUDE_ARGS=(--model "$MODEL"
             --permission-mode auto
             --settings "$RUN_DIR/session-settings.json"
             --strict-mcp-config
             --disallowedTools "${DISALLOWED_TOOLS[@]}"
             --add-dir "$LANES"
             --name "swift-migration-$NOW_DATE"
             --session-id "$SESSION_ID")
# The pane runs this wrapper: claude, then its exit status into the status
# file, which deadline_run.py reads, then it waits to be closed. claude runs
# under `deadline_run.py --spawn-root`, which disclaims responsibility so
# that macOS links what claude starts to it (tmux 3.8 makes every pane
# process its own responsible process) and records its pid for the
# supervisor's sweep. The prompt is the last argument, after
# an option that takes one value, so --disallowedTools (which takes many)
# cannot swallow it.
{
  echo '#!/bin/bash'
  echo "# Written by nightly_start.sh for $RUN_DIR; runs in tmux session $SESSION."
  printf 'cd %q || { echo 70 > %q; exit 70; }\n' "$CLONE" "$STATUS_FILE"
  echo "trap 'echo \"session.sh: SIGTERM; waiting for claude to exit\"' TERM"
  printf '%q -B %q --spawn-root %q -- %q' "$PYTHON" "$SCRIPT_DIR/deadline_run.py" "$ROOT_FILE" "$CLAUDE"
  printf ' %q' "${CLAUDE_ARGS[@]}"
  printf ' "$(cat %q)"\n' "$RUN_DIR/prompt.txt"
  echo 'rc=$?'
  printf 'echo "$rc" > %q\n' "$STATUS_FILE"
  echo 'echo "session.sh: claude exited with status $rc; the supervisor closes this pane"'
  echo '# Stay open until the supervisor has looked at what is left and closed'
  echo '# the pane: closing it here would hang up processes before they are seen.'
  echo 'exec sleep 86400'
} > "$RUN_DIR/session.sh"
chmod +x "$RUN_DIR/session.sh"

PIPE_COMMAND="cat >> $(printf '%q' "$RUN_DIR/pane.log")"
TMUX_COMMAND=(env -u ANTHROPIC_API_KEY -u SSH_AUTH_SOCK
              -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN
              -u TMUX -u TMUX_PANE
              "LANG=${LANG:-en_US.UTF-8}"
              SWIFT_MIGRATION_NIGHTLY=1
              "SWIFT_MIGRATION_NIGHT_DIR=$RUN_DIR"
              "${GIT_GUARDS[@]}"
              GIT_TERMINAL_PROMPT=0
              GIT_ASKPASS=/usr/bin/false
              SSH_ASKPASS=/usr/bin/false
              "GIT_SSH_COMMAND=$SSH_WRAPPER"
              "GH_CONFIG_DIR=$GH_EMPTY"
              "$TMUX_BIN" -S "$SOCKET" -f /dev/null
              new-session -d -s "$SESSION" -x 220 -y 50 -c "$CLONE"
              /bin/bash "$RUN_DIR/session.sh"
              ';' set-option -g update-environment ''
              ';' pipe-pane -o -t "$SESSION" "$PIPE_COMMAND")
CMD=("$PYTHON" -B "$SCRIPT_DIR/deadline_run.py"
     "${DEADLINE_ARGS[@]}" --grace "$GRACE_SECONDS" --night-id "$NIGHT_ID"
     --tmux-socket "$SOCKET" --tmux-session "$SESSION" --tmux "$TMUX_BIN"
     --status-file "$STATUS_FILE" --root-file "$ROOT_FILE"
     --interrupt-wait "$INTERRUPT_WAIT"
     --blocked-pattern "$BLOCKED_PATTERN" --blocked-seconds 120
     --stall-seconds "$STALL_SECONDS" --transcript "$TRANSCRIPT"
     --clean-stop-margin "$CLEAN_STOP_MARGIN" --nudge-text "$NUDGE_TEXT"
     --done-file "$DONE_FILE"
     --
     "${TMUX_COMMAND[@]}")

PRINTED="cd $(shell_quote "$CLONE") &&"
for a in "${CMD[@]}"; do PRINTED="$PRINTED $(shell_quote "$a")"; done
PRINTED="$PRINTED < /dev/null 2> $(shell_quote "$RUN_DIR/supervisor.log")"
{ echo "$PRINTED"; echo; echo "# $RUN_DIR/session.sh:"; cat "$RUN_DIR/session.sh"; } > "$RUN_DIR/command.txt"

git_state() {
  local when=$1
  log "git $when: HEAD $(gc rev-parse HEAD 2>&1)"
  log "git $when: on $(gc symbolic-ref -q --short HEAD || echo 'DETACHED HEAD')"
  log "git $when: branches $(gc for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ')"
  log "git $when: origin/master $(gc rev-parse -q --verify refs/remotes/origin/master || echo none)"
  log "git $when: status lines $(gc status --porcelain --ignore-submodules=all 2>/dev/null | wc -l | tr -d ' ')"
}

where_things_are() {
  log "attach to watch or intervene (detach with C-b d): $ATTACH"
  log "terminal output (raw): $RUN_DIR/pane.log"
  log "transcript: $TRANSCRIPT"
  log "the night's report, when written: $REPORT"
  [ -z "${NIGHTLY_LAUNCHD_LOG:-}" ] || log "launchd log: $NIGHTLY_LAUNCHD_LOG"
  local s c
  s=$(shell_quote "$SOURCE"); c=$(shell_quote "$CLONE")
  log "in the morning (does nothing unless your checkout has $BRANCH checked out): [ \"\$(git -C $s symbolic-ref -q --short HEAD)\" = $BRANCH ] && git -C $s fetch $c $BRANCH && git -C $s merge --ff-only FETCH_HEAD"
  log "  if that fast-forward refuses (your $BRANCH has commits the clone does not), run this after the fetch; it replays your own commits on top of the night's work and drops those already in it as equivalent patches, an earlier night's commits you took included:"
  log "  [ \"\$(git -C $s symbolic-ref -q --short HEAD)\" = $BRANCH ] && git -C $s rebase FETCH_HEAD"
}

if [ "$DRY_RUN" = 1 ]; then
  git_state before
  if OWNER_TEXT=$(owner_refs 2>&1); then
    log "owner check: $(printf '%s\n' "$OWNER_TEXT" | wc -l | tr -d ' ') lines of refs, config and hook checksums read from the owner's repositories (a real run compares them after the session)"
  else
    log "owner check: cannot read the owner's refs (a real run would exit 7): $OWNER_TEXT"
  fi
  log "dry run: the session settings would be:"
  cat "$RUN_DIR/session-settings.json"
  log "dry run: the session wrapper $RUN_DIR/session.sh would be:"
  cat "$RUN_DIR/session.sh"
  log "dry run: the command would be (the environment is in the env arguments; the rest is inherited, PATH=$PATH):"
  echo "$PRINTED"
  where_things_are
  exit 0
fi

if [ "${NIGHTLY_CAFFEINATE:-1}" != 0 ] && [ -x /usr/bin/caffeinate ]; then
  /usr/bin/caffeinate -i -w $$ &
  CAFFEINATE_PID=$!
fi

stop_if_signalled "before the session"
OWNER_BEFORE="$RUN_DIR/owner-refs-before.txt"
OWNER_AFTER="$RUN_DIR/owner-refs-after.txt"
if ! owner_refs > "$OWNER_BEFORE"; then
  log "setup failed: cannot record the owner's refs"
  exit 7
fi
log "owner check: recorded $(wc -l < "$OWNER_BEFORE" | tr -d ' ') lines from the owner's repositories in $OWNER_BEFORE"
START_BRANCH=$(gc symbolic-ref -q --short HEAD || echo 'DETACHED HEAD')
git_state before
log "starting the session in tmux (hard limit $HARD, clean stop by $CLEAN_STOP, night id $NIGHT_ID, session id $SESSION_ID)"
where_things_are
cd "$CLONE" || { log "setup failed: cannot cd to $CLONE"; exit 7; }
"${CMD[@]}" < /dev/null > /dev/null 2> "$RUN_DIR/supervisor.log" &
CHILD_PID=$!
wait "$CHILD_PID"
RC=$?
if [ "$GOT_SIGNAL" = 1 ]; then
  wait "$CHILD_PID" 2>/dev/null
  RC=$?
fi
CHILD_PID=
while IFS= read -r line; do log "supervisor: $line"; done < "$RUN_DIR/supervisor.log"

# 11. What the night changed outside its work.
if ! owner_refs > "$OWNER_AFTER"; then
  log "owner check: COULD NOT READ THE OWNER'S REFS AFTER THE SESSION; nothing compared"
elif cmp -s "$OWNER_BEFORE" "$OWNER_AFTER"; then
  log "owner check: the owner's repositories are as they were before the session"
else
  report_owner_change "$OWNER_BEFORE" "$OWNER_AFTER"
fi
CHECK_OUT=$("${CLONE_TOOL[@]}" check "${CLONE_ARGS[@]}" 2>&1)
if [ $? != 0 ]; then
  log "THE CLONE'S LAYOUT OR CONFIGURATION WAS CHANGED DURING THE NIGHT; the next night refuses until it is fixed by hand:"
  while IFS= read -r line; do log "  $line"; done <<< "$CHECK_OUT"
fi
RULES=$(rule_changes "$OWNER_MASTER"; untracked_rule_files "$OWNER_MASTER" | sed 's/^/not tracked upstream: /')
if [ -n "$RULES" ]; then
  log "THE NIGHT CHANGED RULE FILES (look before taking the commits; the next night refuses until you take or drop them):"
  while IFS= read -r line; do log "  $line"; done <<< "$RULES"
fi
git_state after
END_BRANCH=$(gc symbolic-ref -q --short HEAD || echo 'DETACHED HEAD')
if [ "$END_BRANCH" != "$START_BRANCH" ]; then
  log "WARNING: HEAD IS NO LONGER ON $START_BRANCH (now: $END_BRANCH); look before doing anything else"
fi
where_things_are
case "$RC" in
  0) log "session finished"; exit 0 ;;
  120) log "session reported done (nightly_done.sh) and was stopped at once, not at the time limit"; exit 0 ;;
  124) log "session stopped at the time limit"; exit 5 ;;
  122) log "session stopped: it was waiting at Claude Code's workspace trust dialog; accept it once by hand: cd $(shell_quote "$CLONE") && claude (then /exit)"; exit 11 ;;
  121) log "session stopped: no progress in its first ${STALL_SECONDS}s (a startup dialog other than the trust dialog?); see the screen above and $RUN_DIR/pane.log"; exit 14 ;;
  127) log "the session could not be started"; exit 4 ;;
  125) log "the session ended without an exit status (ended from outside?)"; exit 4 ;;
  *) log "session exited with status $RC"; exit 4 ;;
esac
