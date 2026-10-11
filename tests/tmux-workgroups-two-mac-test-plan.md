# Manual test plan: workgroups in tmux Integration, two Macs on one server

The end-to-end harness (`ITERM2_ONSCREEN_TESTS=1 tools/run_tmux_workgroup_live.sh --e2e`) drives one
iTerm2 against a private tmux server, with the other client played by a plain `tmux -C` connection
(`TmuxTestClient`). One iTerm2 cannot attach to the same tmux session twice, so what only shows up
with two real iTerm2s, each with its own workgroup definitions, window sizes and timing, is checked
here by hand.

## Background

A workgroup entered in a `tmux -CC` tab lives on the server, not in either Mac:

- Each member pane is tagged `@iterm2_wg` = `m_<hex>` (instance, position, and `w` while a code
  review or diff member is waiting to start).
- Each peer that is not in view is parked in a hidden window of its own, tagged
  `@iterm2_wg_parked` = `p_<hex>`, pinned to the size of the slot it fills when shown. iTerm2
  never opens a parked window as a tab; its pane has a buried session so output keeps arriving.
- The session option `@iterm2_wg_<instance>` = `g_<hex>` records the workgroup's ID, git base and
  shape (its skeleton).
- `@iterm2_wg_lock` = `l_<hex>` serializes changes (entry, peer creation, repairs) between clients.

A client that attaches adopts an instance when exactly one of its own workgroups has the stored
shape, preferring the one with the stored ID if several do. With several and none with that ID it
asks. With none, the panes stay ordinary and nothing on the server changes, so a Mac that does have
a matching workgroup can still adopt it.

Inspect the server from any shell on the host:

```
tmux list-panes -a -F '#{pane_id} #{window_id} #{pane_width}x#{pane_height} #{@iterm2_wg}'
tmux list-windows -a -F '#{window_id} #{window_name} #{@iterm2_wg_parked}'
tmux show-options | grep iterm2_wg
```

Decode a tag's hex with `echo <hex> | xxd -r -p`. After every case below that ends a workgroup,
all three commands should show nothing of it: no tagged panes, no parked windows, no record, no
lock.

## Setup

- A host with tmux 3.2 or later that both Macs can reach (ssh), or one Mac's own tmux for the
  cases that don't need two physical machines (run two dev builds with different `-suite`
  values instead). Repeat the core cases (1 to 5) on tmux 3.2a, 3.7 and 3.8 or later: before
  3.8 relaunching a member replaces its pane instead of respawning it.
- On Mac A and Mac B, the same workgroup, e.g. a root with two peers, a split and a tab. Export
  it from A and import it on B so the IDs match. For case 2, also make a copy with a new ID.
- Attach both with `tmux -CC attach -t <session>`. Make B's window a different size from A's.

## Cases

### 1. Enter on one, the other adopts

1. On A, enter the workgroup in the tmux tab.
2. B, already attached, adopts it: the toolbar and peer switcher appear, the split and tab open,
   and the peers are listed. A peer's output written before B attached is in its scrollback.
3. Detach B and reattach it. It adopts again, without asking.
4. Expected on the server: one record, one tagged pane per member, one parked window per hidden
   peer. Nothing was created twice.

### 2. Matching on attach

1. On B, delete the workgroup (keep a backup), then attach. A notification “Workgroup Not
   Recognized” appears once; the panes are ordinary tabs and splits; A keeps working; the server is
   unchanged.
2. Restore the workgroup on B under a different ID, plus a second copy with the same shape. Attach:
   “Choose a Workgroup” lists only those two. Pick one: B adopts with it. Detach and reattach: it
   asks again (the pick lasts for the connection only).
3. “Leave as Ordinary Panes” leaves the server unchanged.

### 3. Switching peers

1. Switch peers on A. B follows within a moment, with the same peer in view and the same pane
   size it had before (no reflow). The peer's hidden output is intact.
2. Switch on B. A follows.
3. Switch on both at nearly the same time, several times. Both end up showing the same peer; no
   pane is lost, duplicated, or left visible beside another peer.
4. Resize B's window, then switch on A. The peer comes in at the slot's size on each Mac.

### 4. Waiting for the other client

1. On A, enter a workgroup whose peers take a while to start (e.g. a command that sleeps first).
   While A is setting up, enter it on B, or reattach B.
2. After about three seconds B announces “Another iTerm2 attached to this tmux session is setting
   up a workgroup. This one is waiting for it to finish.” with Take Over and Stop Waiting.
3. When A finishes, the announcement goes away and B carries on.
4. Repeat, and detach A while B waits: B stops waiting promptly, without a timeout.
5. Repeat, and Take Over on B: B proceeds; A's later steps don't duplicate anything.
6. Repeat, and Stop Waiting on B: B gives up; the server is left as A makes it.

### 5. The leader exits

1. With both attached, exit the leader's shell on A (or on B).
2. Both Macs end the workgroup: the split, tab and peers close on both. The members are killed
   once (no errors in either Mac's debug log about missing panes).
3. Expected on the server: nothing of the workgroup is left.
4. Repeat with a peer in view instead of the leader when it exits.
5. Repeat with Exit Workgroup from the menu on B: A ends it too; the leader stays.

### 6. Code review and diff members

1. Enter a workgroup with a code review peer and a diff peer. Both wait on both Macs.
2. Start the code review on A. B stops showing the waiting state and shows the review running.
3. Fire the diff peer's launch on B. A follows.
4. Detach A, start a member on B, reattach A: A shows it running, not waiting.

### 7. Reload

1. On A, Reload a split. B follows the new pane in the same place.
2. On B, Reload the peer in view. A follows; the peer is still in view on both.
3. On tmux before 3.8, confirm the server did not crash (`tmux ls` still lists the session).

### 8. Detach and reattach with a peer in view

1. Switch to a peer on A, then detach A.
2. Reattach A. The peer is in view and active in the switcher; the leader is parked.
3. Switch back to the leader. B follows.

### 9. Crashes and dropped connections

1. Start a peer switch on A and kill A (`kill -9`) right away. B shows a consistent state; if
   a peer was left beside the leader, or none is in view, B repairs it within a moment.
2. While A holds the lock (case 4's slow entry), kill A. B takes the lock over without waiting
   for a timeout once tmux reports A's client gone.
3. Drop A's network (e.g. turn off Wi-Fi) mid-session, then restore it and reattach. A adopts
   the instance as B left it.

### 10. Edits made in tmux directly

1. From a plain shell, `join-pane -d -s <parked peer pane> -t <leader pane>`. The attached clients
   park the peer again; the leader stays in view.
2. `kill-pane` the peer in view. The leader comes back in a tab of its own.
3. `set -p -t <a plain pane> @iterm2_wg m_00` (garbage). Nothing crashes; the tag is removed or
   ignored; the workgroup keeps working.
4. `set @iterm2_wg_<instance> g_zz` (undecodable record). Neither Mac adopts or crashes; nothing
   is removed.
