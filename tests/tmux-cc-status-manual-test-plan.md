# Manual test plan: Session Status in tmux control-mode panes

Covers the addressing change that lets `cc-status` reach the session showing a tmux pane instead of
the control-mode gateway (issue 13049).

## Background

A process in a `tmux -CC` pane cannot learn its iTerm2 session ID: `TERM_SESSION_ID` is injected
only when iTerm2 forks the job, and the tmux server forks the pane. So `cc-status` now sends
`$TMUX` and `$TMUX_PANE` instead, and iTerm2 maps them to the pane's session. `$TMUX` carries
`<socket path>,<server pid>,<session id>`; the first two locate the server, and iTerm2 learns its
own copy from `display-message -p "#{socket_path},#{pid}"`. The session id is deliberately unused:
a pane id is unique across the whole server, so it adds nothing, and it is the one field that can
be stale -- `$TMUX` is baked into a pane's environment at creation, so `move-window` leaves the
pane naming a session it no longer lives in.

A socket path and pid only mean anything on the machine they were read on: `/private/tmp/tmux-501/default`
is byte-identical on any two Macs sharing a uid, and pids collide freely. So a lookup also carries
an **origin** naming the connection it arrived over: nothing for a local call, and the ssh
conductor's identifier for one that arrived over ssh integration. iTerm2 asks each tmux controller
for the same thing (the conductor of the session its gateway runs on) and only considers
controllers that agree. That is what makes Claude Code work in a `tmux -CC` pane on a remote host,
and what keeps a remote address from ever matching a local server by coincidence.

The origin names a connection, not a host, so a pane's `it2` has to call over the connection that
is driving the server. It cannot rely on its own environment for that: `IT2_SOCK`/`IT2_NONCE`
(remotely) and `IT2_SUITE` (locally) are frozen into the tmux server when it starts and name
whichever connection started it. So on attach each controller publishes its own record on the
server as a global user option, `@it2_client_<hex of its tmux client name>`, whose value is
`c_` plus the hex of a small JSON record (`{"sock":…,"nonce":…}` remotely, `{"suite":…}`
locally). `it2` lists the server's attached control-mode clients (`list-clients`), keeps only the
records whose client is still attached, and tries them newest attacher first before falling back
to its own environment. A controller removes its own record on a clean detach and removes any
other client's when tmux announces that client detached. Confirm with
`tmux show-options -g | grep @it2_client_` from a pane after attaching; decode a name with
`echo <hex> | xxd -r -p`.

Run the development build. Always pass `-suite claude-iterm2-alt7` if launching directly; `make
run` does this for you. Requires the Claude Code integration installed and the Python API enabled.

## Preconditions

Confirm the two environment variables really are what the code assumes, once per machine:

```
# In a tmux -CC pane:
echo "$TMUX"        # /private/tmp/tmux-501/default,52533,0
echo "$TMUX_PANE"   # %0

# From the same pane, ask the server for its own copy:
tmux display-message -p '#{socket_path},#{pid}'
```

The socket path and pid must match `$TMUX`'s first two fields **byte for byte**. tmux builds both
from one global, so they should; if they ever diverge, every lookup below fails and the matching
needs revisiting.

## Cases

Cases 11 through 11c need ssh integration specifically. Plain `ssh` gives no conductor, so a
remote `it2` cannot reach iTerm2 at all and there is nothing to test there.

### 1. Baseline, no tmux

Run `claude` in an ordinary tab. Session Status lists it and the state tracks working / waiting /
idle. This is the `TERM_SESSION_ID` path and must be unchanged.

### 2. Single tmux pane

1. `tmux -CC new -A -s main`
2. Run `claude` in the resulting tab.
3. Open the Session Status tool.

The session appears with live state. Before this change the tool stayed empty forever.

### 3. Two panes, two rows

Split the tmux window and run `claude` in both panes. Each gets its own row, and driving one does
not move the other's state. This is what pane-level addressing buys: previously both would have
addressed the same gateway.

### 4. Detach and reattach

1. With `claude` running and idle in a tmux pane, detach (close the tmux window, or `tmux detach`).
2. Reattach from a **different** iTerm2 session: `tmux -CC attach -t main`.
3. Send `claude` a prompt.

The correct row updates. This is the case the old addressing could never survive: tmux does not
refresh `TERM_SESSION_ID` for panes that already exist, so a long-lived agent kept naming a gateway
that died with the first client. The server pid in `$TMUX` is unchanged by a reattach.

### 4a. Reattach after relaunching iTerm2

1. As in case 4, but between the detach and the reattach quit and relaunch iTerm2.
2. Reattach with `tmux -CC attach -t main` and send `claude` a prompt.

The row appears and updates. Locally this needs nothing special (the API socket path is stable
across launches); the interesting variant is the remote one in case 11d.

### 5. Two sessions, one server

1. `tmux -CC new -A -s alpha` in one iTerm2 session.
2. `tmux -CC new -A -s beta` in another. Same server, two gateways, two controllers.
3. Run `claude` in a pane of each.

Each updates only its own row. What separates them is the pane id, which is unique across the whole
server: the loop asks each controller for the server whether it holds that pane, and only one does.
Which tmux session either controller is showing never enters into it.

Worth also trying `move-window` to shift a pane's window from one of these sessions to the other
while `claude` runs in it. Status must keep working: the pane id does not change, and the now-stale
session id in that pane's `$TMUX` is not consulted.

### 6. Two servers, colliding pane ids

1. `tmux -L a -CC new -A -s one`
2. `tmux -L b -CC new -A -s two`

Both servers hand out `%0` and `$0`, so only the socket path and pid tell them apart. Run `claude`
in the first pane of each and confirm no cross-talk.

### 7. Plain tmux reports nothing, on purpose

Run plain `tmux` (no `-CC`) in a tab, then `claude` inside it. **No status should appear**, and
that is the intended outcome rather than a failure to file.

iTerm2 is not driving that server, so it cannot know which tmux window the session is rendering.
Attaching a status to the tab would be a claim about something it may not be showing at all.
Supporting non-control-mode tmux is a non-goal.

The boundary events do not pass `--quiet-if-unresolved`, so `cc-status` reports once at each end of
the session rather than leaving the user guessing:

```
No session is showing that tmux pane.
cc-status: it2 exited 3 for SessionStart
```

With debug logging on, `TmuxPaneLocator: no connected tmux server matches` appears once per
distinct address.

### 7c. An unresolvable pane reports failure

```
it2 session set-var --tmux "/tmp/nosuch,99999,0" --tmux-pane %0 -- user.x 1
echo $?
```

Must print an explanation on stderr and exit **nonzero**: nothing was set, and a calling script has
to be able to tell. Same for `get-var`, `get-status` and `set-status`.

Then the hook's own contract, which is the opposite and says so:

```
it2 session set-status --tmux "/tmp/nosuch,99999,0" --tmux-pane %0 --quiet-if-unresolved --status idle
echo $?
```

Silent, exit 0. `cc-status` passes that flag on per-tool-call events, because Claude Code in a tmux
session iTerm2 is not attached to would otherwise fail on every one.

### 7a. Malformed addressing fails loudly

```
it2 session set-status --tmux nonsense --tmux-pane %0 --status working
```

Must exit nonzero with a message about parsing, and must **not** touch the currently focused
session. The same for `--tmux` without `--tmux-pane`.

### 8. Background-task gating

The count is parked in the session's tab status (RAM only) by `set-status --background-tasks` and
read back by `get-background-tasks`, both of which now take a pane address.

1. In a tmux pane, ask `claude` to start a background task (`run_in_background`), then let the turn
   end.
2. The row must stay “working”, not flip to idle, including after the idle nudge about a minute
   later.
3. Check the stored value directly:
   `it2 session get-background-tasks --tmux "$TMUX" --tmux-pane "$TMUX_PANE"`
4. Repeat outside tmux with `-s "${TERM_SESSION_ID#*:}"` to confirm the non-tmux path.

### 9. Orchestration uses the exact path

With `claude` running in a tmux pane and a workgroup active, confirm the orchestrator treats the
session as status-reporting rather than falling back to screen polling. In a debug log,
`WorkgroupIntrospection.reportsSessionStatus` should be true for that session, and watchers should
fire on tab-status transitions.

### 10. Connect-time race

Start `claude` in a pane immediately after attaching, before the server-identity response lands. The
first event or two may be dropped and logged; the next event resolves normally. Nothing should be
misdelivered, and nothing should be permanently stuck.

### 10a. Status reads back the way it was written

```
it2 session set-status -s "${TERM_SESSION_ID#*:}" --status working --dot-color '#ff9500' --detail '- a bulleted note'
it2 session get-status -s "${TERM_SESSION_ID#*:}"
```

The JSON must echo the same status, the same `#ff9500` (not `#ff9400` -- the formatter rounds
rather than truncates), and the detail intact including its leading dash. Unset fields read as
`null` rather than being absent. Clear one and confirm it flips to null:

```
# Two elements, not --detail= : ArgumentParser reads a bare "--name=" as a missing value, which
# is why the producers special-case an empty value.
it2 session set-status -s "${TERM_SESSION_ID#*:}" --detail ""
it2 session get-status -s "${TERM_SESSION_ID#*:}"
```

### 11. A remote tmux must not capture a local pane

Needs two machines, or one plus an ssh loopback. Use iTerm2's **ssh integration** (`it2ssh` or a
profile configured for it), not plain `ssh`, for every remote case from here down; the difference
is what the whole machine question turns on.

1. `ssh host`, then `tmux -CC` there. iTerm2 now has a controller whose pid and socket path were
   read on the remote host.
2. Locally, run `tmux -CC` and start `claude` in a pane.

The local pane must resolve to its own session. The remote controller is skipped because its
origin names an ssh conductor while the local request has none; matching on it would compare a
local `$TMUX` against a remote machine's pid, and `/private/tmp/tmux-501/default` is the same
string on any two Macs with the same uid. Debug logging prints `origin=` and `local=` for each
candidate.

### 11b. Claude Code in a remote `tmux -CC` pane

The case §11 used to make impossible. On the remote host, inside a `tmux -CC` started over ssh
integration:

1. Run `claude` in a pane.
2. Open the Session Status tool locally.

The session must appear and track state, exactly as a local pane does. Nothing about the address
is comparable across machines; what makes it work is that the `it2` call tunnels back over the
conductor, so iTerm2 knows which ssh connection it arrived on and searches only tmux servers whose
gateway is on that same connection.

By hand, from the same pane:

```
it2 session set-status --tmux "$TMUX" --tmux-pane "$TMUX_PANE" --status working; echo $?
```

Exit 0, and the status lands on the remote pane's own tab.

### 11c. Two ssh connections, one host

1. ssh to a host (connection A) and start `tmux -CC`. Run `claude` in a pane.
2. Leave connection A open. From a second iTerm2 tab, ssh to the same host (connection B) and
   `tmux -CC attach` to the same session.
3. Detach the controller on A, so only B's controller remains.
4. Send `claude` a prompt.

The row updates. The pane's own `IT2_SOCK` still names A's framer socket, but B's controller
published its own socket and nonce on the server on attach, and `it2` prefers a record whose
client is attached, so the call arrives over B and B's controller places the pane. Check from the
pane:

```
tmux show-options -g | grep @it2_client_   # exactly one record, B's; A's was removed on detach
tmux list-clients -F '#{client_name} #{client_control_mode}'
```

Then reattach from A. The row keeps updating: A published a fresh record, and it is now the
newest attached client.

With BOTH controllers attached at once, the one that attached last owns the pane's updates; the
other shows nothing for it. That is the intended rule, not a misdelivery: nothing must ever be
written to a session on the other connection.

### 11c-2. The later attacher leaves, the earlier one stays

1. As in 11c: A attaches `tmux -CC`, then B attaches to the same session. Leave A attached.
2. Detach B (or kill B's ssh connection, or quit B's iTerm2 outright).
3. Send `claude` a prompt in the pane.

The row on A updates. B's record is gone (removed by B on a clean detach, or by A when tmux
announced B's detach), and even if it were still there `it2` would skip it because B's client is
no longer in `list-clients`. A's record is present because A never left. With the old single-value
scheme this case failed permanently: the server still named B's dead socket and `it2` had no
fallback.

```
tmux show-options -g | grep @it2_client_   # only A's record remains
```

### 11d. Reattach after relaunching iTerm2, remote

1. As in 11b: ssh integration to a host, `tmux -CC`, `claude` in a pane. Detach.
2. Quit and relaunch iTerm2. ssh to the host again with integration and `tmux -CC attach`.
3. Send `claude` a prompt.

The row updates. The socket path and nonce the pane inherited belong to a dead framer (the new
one swept its socket on connect), so without the published record the call could not reach
iTerm2 at all. With an `it2.py` predating the records (an old shell integration on the host),
this case fails closed instead: `it2: cannot reach iTerm2`.

### 11a. A pane with no TERM_SESSION_ID at all

The common shape when the tmux server was not started from an iTerm2 shell, which is any time you
attach to a pre-existing one:

1. From Terminal.app, or a login item: `tmux new -s work -d`
2. From iTerm2: `tmux -CC attach -t work`
3. Run `claude` in a pane. `$TMUX` and `$TMUX_PANE` are set; `TERM_SESSION_ID` is not.

Status must resolve. The pane address is self-sufficient: `it2` reaches iTerm2 over its local
socket with cookie auth and never consults `TERM_SESSION_ID`.
Attaching to a pre-existing server is an ordinary way to use tmux Integration, so this is the case
to check if pane addressing ever looks like it silently does nothing.

### 12. A slow connection just takes a moment

`tmux -CC` over a high-latency ssh link, ideally one with ~1s RTT (Network Link Conditioner, or a
distant host).

Start `claude` in a pane. Status may be missing for the first event or two while the controller
finishes identifying itself, then resolves normally. There is nothing to recover from and no
deadline to tune: a controller that has not yet learned its server's pid simply does not match, the
event is dropped, and the next one finds it ready.

In a debug log, `Tmux server identity: pid=...` should appear once the handshake completes.

### 13. A tmux binary not named exactly "tmux"

Install or symlink a tmux as `tmux-3.5a` (or run one through a wrapper) and start `tmux -CC` with
it. Pane addressing must still work.

iTerm2 decides whether a tmux server is local by asking the kernel for the name of the process with
the server's pid, and `p_comm` is the executable basename, so an exact-match test would read a
renamed local server as remote and silently drop every status update. The test matches a `tmux`
prefix. In a debug log, `matches the requested server but reports a non-local tmux server` must not
appear.

### 14. Version skew during an in-place update

The case that makes a per-event failure real rather than theoretical.

1. With `claude` running in a tmux pane, replace the iTerm2 bundle in place (an update) without
   relaunching. The old process keeps running; `cc-status` and `it2` are resolved from
   `Contents/Resources/utilities` on every hook event, so a new CLI is now talking to an app that
   has neither `session_id_for_tmux_pane` nor `set_session_status`.
2. Drive a few tool calls.

The transcript must stay clean between boundaries: no error on any tool call. `cc-status` asks
it2 for silence on the per-tool-call events and does not on the two session boundaries, so the
problem is reported once at each end of the session and nowhere in between. Relaunching iTerm2
restores status.

By hand, without the flag, the same command must still explain itself and exit nonzero:

```
it2 set-status --tmux "$TMUX" --tmux-pane "$TMUX_PANE" --status working; echo $?
```

## Older tmux

Two different thresholds, easy to conflate:

* **tmux 2.1** has `#{pid}` but not `#{socket_path}`. iTerm2 learns the server pid, the socket path
  stays nil, and the match tolerates that (a pid identifies a running server uniquely). Pane
  lookups resolve normally; you lose only the socket-path cross-check against a recycled pid.
* **tmux older than 2.1** has neither, so `serverPid` stays 0 for the life of the connection.
  Pane lookups against that server never match and its panes get no status, the same as any other
  server iTerm2 cannot identify. Nothing else is affected: other servers resolve normally.

Status outside tmux is unaffected by either.
