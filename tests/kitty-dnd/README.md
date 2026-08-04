# Kitty drag-and-drop (OSC 72) manual test harness

Client-side programs that speak the Kitty drag-and-drop protocol, for testing the
iTerm2 terminal-side implementation by hand. See `docs/kitty-dnd-design.md`.

Run each inside a debug-build iTerm2 session (`make run`).

## Programs

- `probe.py` — sends the query and accept sequences and prints the terminal's
  reply. Verifies the inbound handshake.
- `drop_target.py` — announces it accepts drops; logs hover/drop events and
  prints (or saves, with `--outdir`) the dropped data. Drag files/text onto the
  window.
- `drag_source.py` — offers text and a file to be dragged out; logs the drag
  lifecycle. Start a drag over the window and drop onto Finder/TextEdit.
- `kittydnd.py` — shared build/parse/reader helpers (also a spec reference).

## What works at each stage

- The **inbound handshake** (query, accept/offer registration, and reports back
  to the program) is wired now, so `probe.py` should report the query as
  recognized, and `drop_target.py` / `drag_source.py` will register without
  error.
- **Actual drops** onto the window are forwarded to the program only once the
  accept-drop AppKit adapter lands (then `drop_target.py` receives t=m/t=M/t=r).
- **Dragging out** works only once the offer AppKit adapter lands, and the
  drag-out gesture fires only when the app has mouse reporting enabled (the
  chosen way to avoid clobbering text selection).

## Notes

- Pass `--machine-id` to send the client's hashed machine id. Run locally it
  matches iTerm2's, so the drop is treated as local (Tier 1). To exercise the
  remote tiers, run the client over SSH.
- All programs put the tty in raw mode and restore it on exit; quit with Ctrl-C.
