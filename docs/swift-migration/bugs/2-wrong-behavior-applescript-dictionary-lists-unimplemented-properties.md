# The AppleScript dictionary offers window and session properties that fail when a script uses them

**Where:** `iTerm2.sdef`. Class window: `position`, `origin`, `size` and `frame` (near lines 206 to 236, cocoa keys `scriptPosition`, `scriptOrigin`, `scriptSize`, `scriptFrame`). Class session: `use underline color` (near line 679, cocoa key `useUnderlineColor`).

**What happens:** Script Editor's dictionary shows these properties, but no class implements their keys, so a script that reads or sets one gets an error. Eleven further properties are declared read-write but have no setter, so setting them fails. By cocoa key: application `currentScriptingWindow`; window `scriptFrontmost`, `currentTab`, `currentSession`, `isHotkeyWindow`, `hotkeyWindowProfile`; tab `indexOfTab`, `title`; session `isProcessing`, `isAtShellPrompt`, `text`.

**Why:** the window properties were added to the dictionary in 2015 and `use underline color` later, without the accessors. A search of `sources/` finds no method named for any of the five keys.

**How to see it:** `tell application "iTerm2" to get position of window 1` should fail with an error about an unknown key. Not run. `BindingTests.testScriptingDefinition` lists all of these in its table of known failures.

**Suggested fix:** implement the accessors (for the window, `NSWindow`'s frame converted to the screen coordinates the descriptions name), or remove the properties from the dictionary and mark the eleven as read-only.

**Found:** 2026-11-20, by the binding tests.

**Checked against the tree:** 2026-11-27. The five cocoa keys are still in `iTerm2.sdef`, and no file under `sources/` mentions any of them.
