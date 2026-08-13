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
- [ ] Split panes in tab 2: only the active pane
      receives the command.
- [ ] Target tab enrolled in Broadcast Input:
      command must NOT fan out to other sessions.
- [ ] tmux integration window as target: works.
- [ ] Advanced setting composerTabRouting = No:
      `@2 x` is sent locally like any text.
- [ ] Auto composer (if profile uses it): `@2 x`
      routes; composer clears, stays usable.
