# Composer @-routing manual test

Setup: `make run`, open a window with 3 tabs; run
`claude` (or any TUI) in tab 3. Open the composer
(Cmd-Shift-.) in tab 1.

- [ ] `@2 echo hi` → “hi” runs in tab 2; toast
      “Sent to tab 2 — ⟨name⟩”; composer stays
      open and is empty; focus stays on tab 1.
- [ ] `@3 hello` → text lands in the TUI’s input
      and is submitted (CR terminator).
- [ ] `@7 x` → toast “No tab 7 in this window”;
      composer keeps “@7 x”.
- [ ] `@0 x` → same out-of-range toast.
- [ ] Exit the shell in tab 2 (leave tab open),
      `@2 x` → toast “Session in tab 2 has ended”.
- [ ] `@all echo hi` → runs in tabs 2+3 only;
      toast “Sent to 2 tabs”. Controller skipped.
- [ ] One-tab window: `@all x` → “No other tabs”.
- [ ] `\@2 x` → “@2 x” typed into OWN session.
- [ ] `@2fa/cli --help` → sent locally unchanged.
- [ ] Split panes in tab 2: `@2 x` goes to the
      active pane only.
- [ ] `@2.1` / `@2.2` hit panes of tab 2 in
      reading order (top-left is 1). `@2.9` →
      toast “No pane 9 in tab 2”.
- [ ] Second window open: `@w2 x` lands in
      window 2’s active tab (window numbers as
      in ⌘⌥N). `@w2.1.2` reaches a pane there.
      `@w9 x` → “No window 9”. Focus stays put.
- [ ] `@all x` now hits every other pane in the
      window, including siblings of the
      controller’s own tab.
- [ ] `@wall x` hits every session in all
      windows except the controller.
- [ ] Target tab enrolled in Broadcast Input:
      command must NOT fan out to other sessions.
- [ ] tmux integration window as target: works.
- [ ] Advanced setting composerTabRouting = No:
      `@2 x` is sent locally like any text.
- [ ] Auto composer (if profile uses it): `@2 x`
      routes; composer clears, stays usable.
