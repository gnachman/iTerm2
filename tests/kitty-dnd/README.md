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
- `drag_source.py` — offers text, a file, and a directory tree to be dragged
  out; logs the drag lifecycle. Start a drag over the window and drop onto
  Finder/TextEdit.
- `kittydnd.py` — shared build/parse/reader helpers (also a spec reference).

## What works

Both directions are implemented on this branch:

- **Inbound handshake** — `probe.py` reports the query as recognized; the
  clients register without error.
- **Drops onto the window** are forwarded to the program, so `drop_target.py`
  receives t=m/t=M/t=r (hold Option while dropping to force the old
  paste/upload behavior).
- **Dragging out** works, but the drag-out gesture fires only while the app has
  mouse reporting enabled (`drag_source.py` turns it on for you). This is the
  chosen way to avoid clobbering text selection, so drag-out works from a
  full-screen / mouse-reporting program, not a plain shell prompt.

## Notes

- The clients send their hashed machine id by default (derived from the
  platform: `IOPlatformUUID` on macOS, `/etc/machine-id` on Linux). Run on the
  same host as iTerm2 it matches, so the drop is treated as local; run over
  plain `ssh` it differs, so the drop is cross-machine (`X=1`) and files are
  transferred in-band into `--outdir`. Pass `--no-machine-id` to suppress it.
  Over an it2ssh (SSH-integration) session the conductor makes the drop remote
  automatically, no machine id needed.
- All programs put the tty in raw mode and restore it on exit; quit with Ctrl-C.
