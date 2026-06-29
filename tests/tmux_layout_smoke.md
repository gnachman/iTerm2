# Tmux layout-update smoke test

Manual recipe for verifying that the tmux-driven tree-rebuild path in
`PTYTab` continues to behave correctly across the layout-application API
work (regression guard for Phases 2 and 3).

Run this on `master` first to capture the baseline, then re-run after
each phase that touches `_recursiveRestoreSplitters:` or
`replaceViewHierarchyWithParseTree:`. Behavior must be observably
identical.

## Setup

1. Build and launch iTerm2 from this branch: `make run`
2. In a terminal session, start a tmux server: `tmux new -s smoke`
3. Quit iTerm2, then re-launch and connect to the session in tmux
   integration mode: `tmux -CC attach -t smoke`
4. From a separate terminal (outside iTerm2), open a second tmux client:
   `tmux attach -t smoke` — this is the “other client” used to drive
   layout changes that iTerm2 has to react to.

## Scenarios

For each scenario, the “other client” drives the tmux layout change and
the iTerm2 window must reflect it correctly.

### A. Add a pane

Other client:
```
ctrl-b %    # split vertically
```

Verify in iTerm2:
- A new pane appears next to the existing one with no flicker.
- Both panes are interactive.
- Closing iTerm2 and re-attaching with `tmux -CC attach -t smoke`
  produces the same two-pane layout.

### B. Add a pane with mixed nesting

Other client (continuing from A):
```
ctrl-b "    # split horizontally inside the second pane
```

Verify in iTerm2:
- The second pane is now split horizontally; the first pane is
  unchanged.
- All three panes are interactive.

### C. Kill the middle pane

Other client (with the layout from B):
```
ctrl-b o    # cycle to the middle pane (top of the right split)
ctrl-b x    # kill it (confirm with y)
```

Verify in iTerm2:
- The killed pane is removed; the surviving panes resize to fill space.
- No orphaned views, no console errors, no flicker.

### D. Swap layouts

Other client (with two or more panes):
```
ctrl-b space    # rotate to next preset layout
```

Verify in iTerm2:
- iTerm2 redraws with the new layout (e.g. `even-horizontal` →
  `main-vertical`) without losing pane contents.
- Pane identities are preserved (the same shell/output stays in each
  pane; tmux pane numbering is unchanged).

### E. Maximize then layout change

In iTerm2 (with two or more panes):
1. Click into a pane and press `cmd-shift-enter` to maximize it.
2. From the other client, run `ctrl-b %` to add a new pane.

Verify in iTerm2:
- The maximized pane is automatically un-maximized when the new layout
  arrives.
- The new pane appears.
- The previously-maximized pane is still interactive.

### F. Variable window size

Other client:
```
tmux set-option -g window-size manual
tmux resize-window -y 40    # change height
```

Verify in iTerm2:
- The iTerm2 window resizes to match (no separate
  `beginTmuxOriginatedResize` / `endTmuxOriginatedResize` glitch).

## Expected console output

`PTYTab` emits debug logs via `DLog` for each layout swap. Watch
`tmp/iterm2.log` (or Console.app filtered by `iTerm2`) for:

- `Tweaked parse tree:` lines (variable-window-size branch).
- `Maximizing` / `Unmaximizing` lines as expected for scenario E.

There should be **no** asserts, exceptions, or `it_fatalError` lines.

## Baseline capture

When running on `master` for the first time, record:
- Console log lines for each scenario (especially A, C, E).
- Visual screenshots of iTerm2 after each step (optional, but helpful
  for regressions involving frame rounding or splitter sizing).

After each subsequent phase, diff the new console output against the
baseline. Any unexpected divergence is a regression.
