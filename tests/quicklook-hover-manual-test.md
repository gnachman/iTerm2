# Web Quick Look on the browser engine, and on hover: manual test

Covers the Quick Look settings in Settings > Pointer > Quick Look: the browser
engine for web previews, and opening previews on hover.

Implementation: `sources/QuickLook/` (`iTermBrowserQuickLookViewController`,
`iTermQuickLookHoverController`, `iTermQuickLookHoverAdapter`,
`iTermQuickLookEngineSelector`) and the Quick Look sections of
`sources/TerminalView/PTYTextView+ARC.m`.

## 0. Setup

- Build and run with `make run` (it passes `-suite`). Never run without it.
- Install the iTerm2 Browser Plugin for section 1. Section 2 works with or
  without it.
- Test links: a Linear ticket, a GitHub PR, and a docs page. Print them as plain
  text and as OSC 8 hyperlinks whose text differs from the URL, for example:
  `printf '\e]8;;https://linear.app/\e\\Linear home\e]8;;\e\\\n'`
- A link long enough to wrap onto a second line.
- Claude Code (prints OSC 8 links and turns on mouse reporting) and `vim` with
  `:set mouse=a`.

## 1. Browser engine

1. Engine off: force press a web link (or right-click > Quick Look Link). The
   old popover appears, with only an “Open in <browser>” button.
2. Engine on, plugin installed: force press the Linear link. The new popover
   shows a bar with the URL, “Open in iTerm2 Browser”, “Open in <browser>” and a
   close button. The page loads.
3. Engine on, plugin not installed: the old popover appears, and Settings shows
   the “plugin not installed” note under the checkbox.
3a. Fallback: in the debug build, turn off Settings > Advanced “Enable
    browser-style profiles?” (`browserProfiles`) and restart. With the engine
    on, force press shows the old popover, and Settings > Pointer says
    “Enable browser-style profiles” is off instead of “plugin not installed”.
    Turn it back on afterwards.
4. Sign in to Linear with Google using a password. The Google window opens as a
   small panel, the second factor completes, the panel closes by itself and the
   popover is signed in.
5. Close the popover and preview the link again: still signed in.
6. Open the same site in a built-in browser tab: signed in there too.
7. Quit and relaunch: previews are still signed in.
8. “Open in iTerm2 Browser” opens the page (the current page, if you navigated)
   in a browser tab. With browser profiles unavailable it opens the default
   browser instead.
9. A `target=_blank` link inside the preview loads in the preview itself, not
   in a new window.
10. Escape, the close button and clicking elsewhere in the terminal each close
    the popover, and a sign-in panel still open closes with it.

## 2. Hover

Use Settings > Pointer > Quick Look. Defaults: delay 0.75s, close after 1.5s.

1. Mode Off: resting on links never opens anything. Mouse movement over output
   behaves exactly as before.
2. Mode Hover: rest on an OSC 8 Linear link. The preview opens after about
   0.75s. Moving across the link without resting does not open it.
3. Mode ⌘ + Hover: resting without Cmd does nothing. Hold Cmd while resting:
   opens after the delay. Pressing Cmd while already resting on the link also
   starts the delay. Releasing Cmd before it elapses cancels. Cmd + Option
   never opens.
4. Move from the link to anywhere outside the link and the popover: it closes
   about 1.5s later. Moving back onto the link or into the popover before then
   keeps it open.
5. Check “Never”: the popover stays open until closed by hand. Uncheck it: the
   field returns to 1.5.
6. Click into the popover and start signing in, then move the pointer away and
   switch to a password manager or authenticator app: the popover never
   auto-closes.
7. Opening on hover does not take keyboard focus: type right after it opens and
   the text goes to the terminal. Typing, clicking or scrolling while the delay
   is pending cancels it.
8. A wrapped link opens when resting on either line, and auto-close treats both
   lines as the link.
9. An OSC 8 link whose text differs from its URL previews the URL.
10. Hovering a second link while a preview is open replaces it after the
    delay. Resting on the open link again (or another occurrence of it) does
    nothing.
11. Allowlist `linear.app`: a Linear link opens on hover, a github.com link
    does not, but force press on the github.com link still previews it.
12. In Claude Code and in `vim` with `mouse=a`: hover still opens previews,
    and clicks, drags and mouse movement still reach the app.
13. Background window: with another app or another iTerm2 window focused,
    resting on a link in an unfocused window never opens a preview. Switching
    away while a hover preview is open (and not clicked) closes it.
14. Both engines: repeat 2, 4 and 6 with the browser engine off (old popover)
    and on.
15. Changing the mode, delay, close time or allowlist takes effect without a
    restart.
16. ⌘ + Hover auto-close: open a preview with Cmd held, release Cmd, then move
    the pointer off the link (staying inside the pane). The popover closes
    about 1.5s later, the same as in Hover mode.
17. Force press (or right-click > Quick Look Link) a link, then rest on another
    link in Hover mode, and in ⌘ + Hover with Cmd held. The force-press preview
    stays; hover never replaces or auto-closes it. After closing it, hover
    works again.
18. Browser engine on: in a hover preview, start a Google sign-in so its panel
    opens, and play a page with audio (a video). Close the preview each way:
    hover another link (replace), press Escape, and let it auto-close. Each
    time the sign-in panel closes with it and the audio stops.
19. A page that calls `alert()` (and `confirm()`) on load, opened by hover with
    the browser engine on: no dialog appears, and the terminal keeps focus.
    Click into the preview and trigger an alert from the page: now it shows.
    Force press the same page: the dialog shows as before.
20. Settings > Pointer seconds fields with a comma-decimal region (System
    Settings > General > Language & Region, for example Germany): the delay
    shows as 0,75; typing 0,5 stores half a second and leaves “Never”
    unchecked; typing 0.5 works too.
21. Plain-text web addresses, default settings (“Also preview web addresses
    that aren’t hyperlinks” off): resting on a plain-text URL, and on the
    `printf '\e]8;;https://linear.app/\e\\Linear home...'` command line itself,
    opens nothing. Resting on the OSC 8 link that command prints opens it.
22. Check “Also preview web addresses that aren’t hyperlinks”: resting on a
    plain-text URL now opens it after the delay. Uncheck it again: it stops,
    without a restart.
23. With the checkbox off, force press (or right-click > Quick Look Link) a
    plain-text URL: it still previews.
24. The checkbox is disabled while the mode is Off and enabled in Hover and
    ⌘ + Hover.
25. Hover cue, mode Hover: move the pointer onto an OSC 8 link. The link gets
    the solid underline and its URL shows in the bar at the bottom of the pane
    the instant the pointer enters it, with no pause (as with Cmd-hover), and
    both go away the instant it leaves; sweep across a line of several links
    and the underline follows the pointer link by link. The pointer stays the
    I-beam. With the plain-text checkbox on, plain-text URLs still get the cue
    only after the pointer rests about 0.1s. When the
    preview opens, the bottom URL bar hides (the preview’s own bar shows the
    URL) and the underline stays for as long as the preview is open, including
    the moment it opens (watch the link as the popover appears: it must not
    flash or lose the underline), while the pointer moves into the preview or
    off the link, and after clicking into the preview and back into the
    terminal. Repeat with a page that focuses a text field on load.
26. Drag-select starting on and across a link with the cue showing, before the
    preview opens: the text selects as usual and the cue goes away on the click.
27. Before the preview opens, the cue clears when the pointer moves off the
    link, and when you type, click or scroll. Once the preview is open, the
    underline clears when it closes: auto-close, Escape or its close button,
    clicking elsewhere, or switching apps. Hovering another link until its
    preview replaces the open one moves the underline to that link. No leftover
    underline or URL bar in any case.
28. No cue with mode Off, in ⌘ + Hover without Cmd (Cmd-hover looks as
    before), on plain-text URLs with the plain-text checkbox off, or on links
    outside the domain allowlist.
29. Hyperlink inside a shell prompt (shell integration on, advanced setting
    “⌘-click in the prompt shows the Command Info window” on, the default):
    put an OSC 8 link in the prompt, for example
    `PS1=$'\e]8;;https://example.com/\e\\link\e]8;;\e\\ %% '` in zsh, and
    run a command so the prompt has one. Mode Hover: resting on that link
    shows no underline and opens nothing, matching ⌘-click, which shows the
    Command Info window there. A link in the command’s output still gets the
    cue and opens. With the advanced setting off, the prompt link behaves like
    any other link.
30. Split the window into two panes. Mode Hover: rest on a link in the
    focused pane until the cue shows, then before the preview opens press
    ⌘] (or ⌘⌥ and an arrow) to focus the other pane. The cue goes away and
    does not come back when you later move the pointer over plain text in the
    first pane. With a hover preview open, switching panes the same way keeps
    the link underlined until the preview closes.
31. Hover while output scrolls: in a profile with a small scrollback
    (Settings > Profiles > Terminal, for example 100 lines), print a link,
    then run `while true; do date; sleep 0.2; done`. Mode Hover, with a long
    hover delay.
    a. At the bottom: rest on the link and keep the pointer still. Each new
       line moves different text under the pointer, so its underline and
       bottom URL bar go away and no preview opens, neither of the link that
       scrolled away nor of a link that scrolls under the still pointer.
    b. Scrolled back: scroll up so the link stays on screen while the output
       keeps arriving, and rest on it. The underline and URL bar stay, the
       URL bar anchored to the link, and the preview opens after the delay,
       both before and after lines start dropping off the top of the full
       scrollback.
    c. Repeat a and b with a plain-text URL (print one without OSC 8) and
       “Also preview web addresses that aren’t hyperlinks” on. Same
       results: never opens at the bottom, opens after the delay when
       scrolled back.
    With a hover preview already open, the scrolling leaves its link
    underlined. Press Ctrl-C to stop.
