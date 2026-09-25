# Lock Location: manual test plan

Covers Window > Lock Location. The feature exists to survive display
disconnect and reconnect, which is the one thing that cannot be tested without
real hardware, so the whole of section 2 is the part that matters most.

Implementation: `sources/TerminalView/WindowLocationLock.swift` (the anchor and
its dormancy), `sources/TerminalView/WindowLocationLockController.swift` (policy
and enforcement), plus thin forwarding in `PseudoTerminal.m`.

---

## 0. Environment and conventions

- **Build & run:** `make run` launches `Build/Development/iTerm2.app` with
  `-suite <working-directory-basename>`. Never run without `-suite`.
- **Target this instance from AppleScript by pid**, not by name, since several
  iTerm2 instances are usually running. From the working directory:

  ```bash
  DEVPID=$(pgrep -f "^$PWD/Build/Development/iTerm2.app/Contents/MacOS/iTerm2 -suite ${PWD##*/}$")
  ```

  The anchoring matters: a sibling worktree launched with a relative path and
  `make`'s own `/bin/sh` wrapper both match looser patterns.

- **Move a window programmatically** (this is the accessibility path, which is
  what the lock is built to fight):

  ```bash
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $DEVPID) to set position of window 1 to {600, 400}"
  ```

- **Read geometry back:**

  ```bash
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $DEVPID) to get {position, size} of window 1"
  ```

- **Log lines to watch for** (turn on debug logging). The useful ones:
  - `Locked <window> to <lock>` when a lock is taken
  - `Going dormant: the displays changed`
  - `Waking: the window is home`
  - `Location lock is lying in wait`
  - `Location lock moving window from X to Y (restoreSize=… dormant=…)`
  - `Location lock moving window to display …`
  - `Not absorbing a resize while dormant`
  - `Absorb resize to … into …`
  - `User dragged a location-locked window. Unlocking it.`
  - `Location lock deferring: the window is on no screen`
  - `Display … is W×H but was W'×H' when locked`
  - `Display … had N matching display(s) but M are attached`

- **Ambient noise:** idle 1-pixel `windowDidMove:` events occur on their own. A
  one-pixel discrepancy is noise, not a failure. Snapping back to a clearly
  different origin is the signal.

---

## 1. Base behavior, single display

Quick smoke tests. These were confirmed working during development.

1. **Fights a programmatic move.** Lock a normal window, run the `set position`
   command. Position reads back unchanged.
2. **Unlocks on drag.** With the window still locked, drag it by the title bar.
   It follows the cursor, the menu item unchecks, and a subsequent
   `set position` sticks. Repeat by dragging a Compact window by its tab bar,
   and again with Three Finger Drag enabled in System Settings (confirmed
   working; `pressedMouseButtons` reports the button down for that input mode).
3. **Menu item off by default,** and toggling it twice leaves the window free.

---

## 2. Display disconnect and reconnect (the point of the feature)

Requires a real external display. Sleep or lid-close is the scenario users hit;
unplugging is the faster way to iterate and exercises the same code path.

4. **Frame mode returns to the exact frame.** Put a normal window on the
   external display, sized noticeably smaller than that display. Lock it. Note
   the frame. Disconnect the display (or sleep the machine). macOS relocates the
   window to the built-in display, probably shrinking it. Reconnect.

   **Expect:** the window returns to the external display at the *exact* locked
   frame, size included. Log shows `Going dormant` at disconnect, then
   `Location lock moving window … (restoreSize=1 dormant=1)` and `Waking: the
   window is home`.

   **This is the test that matters.** Size being wrong on return is the specific
   bug the dormancy latch exists to prevent, so check the size, not just the
   position.

5. **Lying in wait while the display is gone.** Same setup, but while the
   display is disconnected, drag the displaced window somewhere on the built-in
   display and resize it.

   **Expect:** the lock does not fight either (it is lying in wait, and dragging
   unlocks it anyway, so confirm the menu item unchecks). If instead you *move
   it programmatically* while disconnected, the lock must not interfere; log
   shows `Location lock is lying in wait`.

6. **Screen mode.** Set a window to Maximized (Window > Window Style), put it on
   the external display, lock it. Disconnect, reconnect.

   **Expect:** it returns to the external display and fills it correctly. Log
   shows `Location lock moving window to display …`. Repeat for one
   edge-attached style (Top of Screen) and one Centered style.

7. **Returning at a different resolution.** Lock a normal window on the external
   display. Disconnect, change that display's resolution, reconnect.

   **Expect:** frame mode stays dormant and leaves the window alone; log shows
   `Display … is W×H but was W'×H' when locked`. Screen mode (test 6) *should*
   still bring the window back, because it only pins the display and lets the
   canonicalizer reshape it. This asymmetry is deliberate.

8. **Sleep rather than unplug.** Repeat test 4 by closing the lid or letting the
   machine sleep with the external attached. This is the reported scenario and
   may differ from unplugging in timing.

9. **Spaces.** With "Displays have separate Spaces" on, put locked windows on
   two different Spaces of the external display, then disconnect and reconnect.
   **Known limitation:** they come back to the right display but land on
   whichever Space that display is showing. Confirm it is no worse than that,
   and that the release note's wording matches what you see.

---

## 3. State corruption paths

These are the ways the remembered frame gets quietly replaced with something the
user never chose. Each was a real bug found in review.

10. **Full screen does not poison the anchor.** Lock a normal window on the
    external display. Enter full screen (Cmd+Enter, and separately test Lion
    full screen). While in full screen, disconnect and reconnect the display.
    Exit full screen.

    **Expect:** the window returns to its original locked frame, *not* the size
    of the display. Log must not show `Absorb resize` while full screen.

11. **Resize is absorbed, not fought.** With a locked window on a settled
    single-display setup, drag its right edge to resize it. Then run a
    `set position` command.

    **Expect:** the resize sticks (Lock Location is not Lock Size), and the
    subsequent programmatic move snaps back to the *new* size, not the original.
    Log shows `Absorb resize to …`.

12. **Resize is not absorbed while dormant.** Disconnect a second display (any
    display) to force dormancy, then immediately resize the locked window with a
    non-drag method (change font size with Cmd+Plus).

    **Expect:** log shows `Not absorbing a resize while dormant`. Note that a
    *live* drag resize is deliberately still absorbed even while dormant.

13. **Miniaturized across a display change.** Lock a window, miniaturize it,
    disconnect and reconnect the display, then deminiaturize.

    **Expect:** log shows `Location lock deferring: the window is on no screen`
    during the display change, and the window is restored to its locked frame
    when it comes out of the dock. No crash and no absurd frame, which is what a
    NaN rect would produce.

---

## 4. Persistence

14. **Saved window arrangement.** Lock a window, Window > Save Window
    Arrangement, quit, relaunch, restore the arrangement.

    **Expect:** the window is locked (menu item checked) and at the right place.
    Log shows `Restored <lock> from arrangement`. A restored lock starts dormant,
    so the first enforcement is a full-frame restore.

15. **System restoration.** Lock a window, quit with window restoration enabled,
    relaunch.

    **Expect:** same as above, via `didFinishRestoringWindow` rather than
    `loadArrangement:`.

16. **Tab arrangements must NOT carry the lock.** Lock a window. Use Window >
    Save Tab as Window Arrangement (and separately Save Tab Group as Window
    Arrangement). Restore that arrangement twice.

    **Expect:** both new windows are *unlocked* and independently draggable. A
    failure here produces two windows pinned to the identical frame, stacked and
    refusing to be dragged apart.

17. **Arrangement saved while displaced.** Lock a window on the external
    display, disconnect (window moves to built-in), quit, reconnect the display,
    relaunch.

    **Expect:** the window ends up at its locked frame on the external display,
    not where macOS left it. This is what the deferred first enforcement is for.

---

## 5. Availability and interaction with other features

18. **Follow-cursor profiles.** Set a profile's Screen to "Screen with Cursor".
    Its windows must have Lock Location greyed out.

19. **Follow-cursor applied after locking.** Lock a hotkey window whose profile
    names a concrete screen, then edit that profile's Screen to "Screen with
    Cursor".

    **Expect:** the lock is dropped, log shows `Profile screen preference became
    follow-cursor`, and the window is not fought when it moves to the cursor's
    screen.

20. **Full screen menu state.** Lock a window, enter full screen, open the
    Window menu.

    **Expect:** Lock Location still reads checked and is still selectable, so it
    can be turned off. Enforcement is dormant meanwhile; on exiting full screen
    the window returns to its locked frame.

21. **Hotkey windows.** Lock a revealed hotkey window, then hide and show it
    repeatedly.

    **Expect:** roll-in and roll-out animate normally and are never fought. The
    window still lands where the hotkey machinery puts it.

22. **Lock Size and Lock Layout are independent.** All three can be on at once;
    turning one on must not turn Lock Location off, and vice versa. (Lock Size
    and Lock Layout remain mutually exclusive with each other.)

---

## 6. Identical displays (only if you have two of the same model)

Displays are identified by model, vendor, and serial, and many report serial 0,
so two identical monitors share a key. The lock records which one it was by
position and how many there were.

23. **Attaching a twin.** Lock a window on a single external monitor. Attach a
    second monitor of the same model.

    **Expect:** the lock lies in wait and does *not* move the window to the new
    monitor. Log shows `Display … had 1 matching display(s) but 2 are attached`.

24. **Detaching one of two twins.** With two identical monitors, lock a window
    on one, then detach the other.

    **Expect:** lies in wait, same log line with the counts reversed.

25. **Known limitation:** rearranging two identical monitors in System Settings
    keeps the count the same and swaps which one the ordinal picks, so the window
    may move to the twin. Not detectable; confirm it is no worse than that.

---

## 7. Regression checks

The change touches `windowDidMove:`, `windowDidResize:`,
`screenParametersDidChange`, arrangement encoding, and the Window menu, so
sanity-check that nothing else broke with Lock Location *off*:

26. Windows drag, resize, and zoom normally.
27. Window arrangements save and restore as before.
28. Hotkey windows roll in and out normally.
29. Edge-attached and maximized windows still canonicalize correctly when moved
    between displays of different sizes.
30. Screen anchoring via a profile's Screen setting behaves as it did before.
