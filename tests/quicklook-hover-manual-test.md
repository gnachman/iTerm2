# Web Quick Look on the browser engine, and on hover: manual test

Covers Settings > Pointer > Preview links on hover and the sheet its Configure…
button opens: the browser engine for web previews, hover timing, and the hover
domain list.

Implementation: `sources/QuickLook/` (`iTermWebQuickLookCoordinator`,
`iTermBrowserQuickLookViewController`, `iTermQuickLookHoverController`,
`iTermQuickLookDomainAllowlist`, `iTermQuickLookEngineSelector`) and
`sources/Settings/iTermQuickLookSettingsWindowController.swift`.

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
2. Engine on, plugin installed, iTerm2 not your browser: force press the
   Linear link. The new popover shows a bar with the URL, “Open in iTerm2
   Browser”, “Open in <browser>” and a close button. The page loads.
2a. Make links open in iTerm2 (set iTerm2 as the default browser, or answer
    “Open in iTerm2” with “Remember my choice” to the prompt a link click shows).
    The bar now has “Open in Window”, “Open in Tab” and, to their left,
    “Open in <browser>”. The first two open the page in the built-in browser;
    the third opens your system browser. With iTerm2 as the system default
    browser there is no “Open in <browser>” button, since it would open iTerm2.
2b. Set the advanced setting for a custom browser (`browserBundleID`) to
    Firefox’s bundle ID with Safari as the system default. The button says
    “Open in Firefox” and opens Firefox. With “always open in iTerm2” chosen at
    the prompt but iTerm2 not the default, “Open in <browser>” (if shown) opens
    the external browser, never an iTerm2 tab or the plugin prompt.
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

Use Settings > Pointer > Preview links on hover, and its Configure… sheet for
the rest. Defaults: delay 0.75s, close after 1.5s, no domains listed.

0a. With no domains listed and “Preview links to any domain on hover” off,
    resting on any link opens nothing and shows no cue.
0b. Add linear.app, then add “*.github.com” and “https://example.com/x”: they
    show as github.com and example.com. Editing a row in place normalizes it
    the same way; an entry that isn’t a domain is refused with a message.
    Undo (⌘Z) restores the list.
0c. Check “Preview links to any domain on hover”: an administrator password
    prompt appears. Cancel it: the box stays unchecked. Enter the password:
    links to any public domain now preview, but
    `printf '\e]8;;http://192.168.1.1/\e\\router\e]8;;\e\\\n'` and a
    localhost link still don’t until you list them. While it is checked the
    domain table and its + and − buttons are disabled. Unchecking needs no
    password and enables them again.
    Close and reopen the sheet: the table’s state still matches the checkbox.
0g. Offer to allow: with only linear.app listed and allow-all off, rest on a
    github.com link for the hover delay. An announcement offers “Allow
    github.com”. Merely passing over the link shows nothing. Click Allow: the
    domain appears in the Configure… sheet (even if the sheet is open) and the
    link previews the next time you rest on it. Rest on www.example.com: the
    offer names example.com. Rest on the same unlisted link again in the same
    pane: no second offer. Dismiss with the close button: nothing is saved.
    “Don’t Ask Again” stops offers in every pane; remove
    `NoSyncQuickLookHoverNeverOfferToAllowDomain` from the suite’s defaults to
    get them back. In ⌘ + Hover mode the offer only comes while Cmd is held.
0d. Hover preview of a site you are signed in to in the built-in browser (with
    the engine on): the preview is signed out. Force press the same link: it
    is signed in.
0e. A listed link that redirects to an unlisted host (for example a t.co or
    google.com/url link, with only that domain listed): the preview stays
    blank instead of following the redirect. Click into it and follow a link
    to another site: now it navigates.
0f. A page that asks for the camera or microphone, opened by hover: no prompt
    until you click into the preview.

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
14. Hover previews always use the new popover, whatever the engine setting;
    force press follows the engine setting.
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
20. The sheet’s seconds fields with a comma-decimal region (System
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
24. The sheet’s settings can be changed with the mode Off and take effect
    when hover is turned on.
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
    d. Force press any link so its preview stays open, then repeat b on a
       different link: the hover preview does not open (the force-press
       preview is kept), and while output streams the link’s underline and
       URL bar stay steady, without flickering on each new line. Move the
       pointer to another link: it gets its own cue as usual.
    e. Alternate screen, with a hover delay of several seconds: print a
       link, run `sleep 2; vim`, and at once rest the pointer on the link
       until the cue shows. When vim takes over the screen under the still
       pointer, the cue goes away and the old link does not open.
    With a hover preview already open, the scrolling leaves its link
    underlined. Press Ctrl-C to stop.
32. Pop-ups and non-web addresses, browser engine on. Serve a page that calls
    `window.open("https://example.com")` on load (for example
    `printf '<script>window.open("https://example.com")</script>' > /tmp/p.html`
    and `python3 -m http.server -d /tmp 8000`, then print
    `http://localhost:8000/p.html` as a link).
    a. Rest on the link: the preview opens and no pop-up window appears.
    b. Click into the preview, then start a Google sign-in on a real site
       (as in 4): its pop-up panel opens and sign-in completes.
    c. Force press the same link: the pop-up opens on load, as before.
    d. In a preview, follow a link to a `file:` URL (or one that redirects to
       a custom scheme such as `zoommtg:`): the preview stays on its page.
       “Open in iTerm2 Browser” and “Open in <browser>” then open the last
       web page shown, never the other address.
    e. Rest on the link of 32a, make the preview's window key without clicking
       into the page (for example with Accessibility keyboard navigation), and
       press Tab: pop-ups then work as after a click.
33. Leaving a preview for somewhere the pane gets no events. Two panes side by
    side; rest on a link near the divider in the left pane, move into the
    preview without clicking, then leave it over the right pane and rest: the
    preview closes after the close delay. Repeat leaving it over the desktop
    or another app’s window where the popover overhangs the terminal window,
    and over the tab bar. Leave it over the right pane and come straight back
    into the preview: it stays open.
34. The view leaves its window while an open is pending. Split panes; focus
    pane A, rest on a listed link in pane B until the cue shows, and before the
    preview opens press ⌘⇧] (or another tab-switch key equivalent): no crash
    and no preview. Same with a session that ends by itself while the pointer
    rests on a link (`sleep 0.5; exit` in a profile that closes on exit): no
    crash. With a preview open, switching tabs closes it.
