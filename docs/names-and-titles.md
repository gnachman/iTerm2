# Names and Titles in iTerm2

This document explains how names and titles work in iTerm2, including profiles, sessions, tabs, and windows.

## Overview

iTerm2 has multiple overlapping naming systems:

| Concept | Where It Appears | Primary Source |
|---------|------------------|----------------|
| Profile Name | Profiles panel, menus | User-defined in preferences |
| Session Name | Session title view, tab (default) | Computed from variables |
| Tab Title | Tab bar | Session name or override |
| Window Title | macOS title bar | Active session or override |

## 1. Profile Name

The simplest concept. Stored in the profile dictionary under `KEY_NAME` ("Name").

**Settings UI:** Settings > Profiles > General > "Name" (text field at top of panel)

- User-facing identifier in Profiles preferences
- Default value for `session.profileName` variable
- Used as a fallback in title computation
- Stored with profile GUID in `ProfileModel`

**Key files:** `ITAddressBookMgr.h`, `ProfileModel.m`

## 2. Session Name

The most complex concept. Session name is computed by `iTermSessionNameController` and exposed as `presentationSessionTitle`.

### Variables Involved

| Variable | Description |
|----------|-------------|
| `session.name` | The presentation name (what's displayed) |
| `session.autoNameFormat` | Swifty string format for automatic naming |
| `session.autoName` | Evaluated result of autoNameFormat |
| `session.profileName` | Name of the current profile |
| `session.iconName` | Set by OSC 1 escape sequence |
| `session.windowName` | Set by OSC 0/2 escape sequences |

### autoNameFormat and autoName

`autoNameFormat` is a "swifty string" (interpolated string with variable substitution) that determines the session's automatic name:

```
Default: profile name
Then: most recent of (manually-set name, icon name from escape sequence)
```

The evaluated result becomes `autoName`. Cycle detection prevents infinite loops (displays "[Cycle detected]").

### Title Components

Profile setting `KEY_TITLE_COMPONENTS` is a bitfield (`iTermTitleComponents`) selecting what to include.

**Settings UI:** Settings > Profiles > General > "Title:" (dropdown menu)

The dropdown shows combinations of these components:

- `iTermTitleComponentsSessionName` - Auto-generated session name
- `iTermTitleComponentsJob` - Current foreground job
- `iTermTitleComponentsWorkingDirectory` - Current directory
- `iTermTitleComponentsTTY` - TTY device
- `iTermTitleComponentsProfileName` - Profile name
- `iTermTitleComponentsProfileAndSessionName` - Both
- `iTermTitleComponentsUser` - Username
- `iTermTitleComponentsHost` - Hostname
- `iTermTitleComponentsCommandLine` - Full command line
- `iTermTitleComponentsSize` - Terminal dimensions
- `iTermTitleComponentsCustom` - Custom string (mutually exclusive)

Custom title functions registered via the iTerm2 Python API also appear in this dropdown.

### Title Providers

Sessions can use:

1. **Built-in title provider** (default): Uses `iterm2.private.session_title()` function
2. **Custom title provider**: Script-provided via iTerm2 API (`KEY_TITLE_FUNC`)

**Settings UI:** Custom title providers appear in the Settings > Profiles > General > "Title:" dropdown alongside the built-in component options. When a Python script registers a title provider, it shows up as a selectable option.

**Key files:** `iTermSessionNameController.m`, `iTermSessionTitleBuiltInFunction.m`, `iTermVariableScope+Session.m`

## 3. Tab Title (aka "Icon Title")

What appears in the tab bar. Managed by `PTYTab`.

### Priority Order

1. `titleOverride` (if set) - a swifty string
2. Active session's `presentationSessionTitle`
3. For tmux: `tmuxWindowName` is also available

### Tab Title Variables

| Variable | Description |
|----------|-------------|
| `tab.title` | Computed effective tab title |
| `tab.titleOverride` | Direct override string |
| `tab.titleOverrideFormat` | Format for the override |
| `tab.tmuxWindowName` | Tmux window name |

### Profile Settings

**Settings UI:** Settings > Profiles > General > "Tab Title:" (text field)

- `KEY_CUSTOM_TAB_TITLE` - Custom tab title (evaluated as swifty string)
- Placeholder text: "Tab Title (Interpolated String)"
- Supports variable interpolation like `\(session.name)` or `\(session.path)`

**Key files:** `PTYTab.h`, `PTYTab.m`

## 4. Window Title

What appears in the macOS window title bar. Managed by `PseudoTerminal`.

**Settings UI:** Settings > Profiles > General > "Window Title:" (text field)

- `KEY_CUSTOM_WINDOW_TITLE` - Custom window title (evaluated as swifty string)
- Placeholder text: "Interpolated string. If empty, use tab title."
- If left empty, the tab title is used for the window title

### Composition

The window title comes from the active session's `windowTitle` property, which returns `_nameController.presentationWindowTitle`.

Priority:
1. OSC 0/2 window title (if set by escape sequence)
2. Custom title provider result
3. Built-in title computation
4. Fallback: "Unnamed"

### Window Title Variables

| Variable | Description |
|----------|-------------|
| `window.title` | Computed window title |
| `window.titleOverride` | Direct override |
| `window.titleOverrideFormat` | Format for override |

### Title Stacks

Window and icon titles support push/pop stacks (standard xterm behavior):

```objc
- pushWindowTitle  // Save current title
- popWindowTitle   // Restore saved title
- pushIconTitle
- popIconTitle
```

These are used by escape sequences for temporary title changes.

**Key files:** `PseudoTerminal.m`, `iTermSessionNameController.m`

## 5. Escape Sequences

### OSC 0 / OSC 2 (Window and Icon Title)

Sets both icon name and window title. Stored in `session.windowName`.

```
ESC ] 0 ; title BEL   // Set both window and icon title
ESC ] 2 ; title BEL   // Set window title
```

Values are escaped with zero-width space (`\u200B`) to prevent injection.

### OSC 1 (Icon Title Only)

Sets just the icon/tab title. Stored in `session.iconName`.

```
ESC ] 1 ; title BEL   // Set icon title only
```

### OSC 81 (Pane Title - tmux)

Sets the pane title for tmux integration.

**Key files:** `PTYSession.m`, `VT100ScreenDelegate.h`

## 6. Tmux Integration

Tmux adds additional title concepts:

| Source | Description |
|--------|-------------|
| `tmuxWindowName` | From `#{window_name}` - current process or rename-window result |
| `tmuxWindowTitle` | From `#{T:set-titles-string}` if `set-titles on` |
| `tmuxPaneTitle` | From `#{pane_title}` - set via `select-pane -T` |

### Title Priority in Tmux Sessions

```
tmuxWindowTitle (if set) > windowName > tmuxWindowName > tmuxPaneTitle
```

The `%window-renamed` notification triggers updates when tmux renames a window.

**Key files:** `TmuxController.h`, `iTermSessionTitleBuiltInFunction.m`

## Architecture

### Class Responsibilities

```
PseudoTerminal (Window Controller)
  └─ setWindowTitle: → updates macOS window title bar
      │
      └─ PTYSession.windowTitle
          │
          └─ iTermSessionNameController
              ├─ presentationWindowTitle (for window)
              ├─ presentationSessionTitle (for session/tab)
              ├─ _windowTitleStack (push/pop)
              └─ _iconTitleStack (push/pop)

PTYTab
  ├─ titleOverride (if set, use this)
  └─ activeSession.presentationSessionTitle (fallback)
```

### Variable Scope Chain

```
Session Scope
  ├─ session.name
  ├─ session.autoNameFormat
  ├─ session.autoName
  ├─ session.windowName (from OSC)
  ├─ session.iconName (from OSC)
  └─ Tab Scope
      ├─ tab.title
      ├─ tab.titleOverride
      └─ Window Scope
          ├─ window.title
          └─ window.titleOverride
```

### Data Flow

1. Profile created with `KEY_NAME`
2. Session inherits profile, sets `session.profileName`
3. `autoNameFormat` defaults to profile name
4. Escape sequences can set `windowName`/`iconName`
5. `iTermSessionNameController` evaluates title format
6. Computes `presentationSessionTitle` and `presentationWindowTitle`
7. `PTYTab.title` uses override or session's presentation title
8. `PseudoTerminal` updates macOS window bar from active session

## Settings UI Reference

All title-related profile settings are located in **Settings > Profiles > General**:

| Setting | UI Control | Key | Description |
|---------|------------|-----|-------------|
| Name | Text field (top) | `KEY_NAME` | Profile's display name |
| Title: | Dropdown | `KEY_TITLE_COMPONENTS` | Components to include in session title |
| Title: | Dropdown | `KEY_TITLE_FUNC` | Custom title provider (if registered) |
| Tab Title: | Text field | `KEY_CUSTOM_TAB_TITLE` | Interpolated string for tab title |
| Window Title: | Text field | `KEY_CUSTOM_WINDOW_TITLE` | Interpolated string for window title |

The Tab Title and Window Title fields accept "swifty strings" with variable interpolation:
- `\(session.name)` - Session name
- `\(session.path)` - Current directory
- `\(session.username)` - Username
- `\(session.hostname)` - Hostname
- `\(session.jobName)` - Current job

## Key Source Files

| File | Purpose |
|------|---------|
| `iTermSessionNameController.m` | Central title computation and caching |
| `iTermSessionTitleBuiltInFunction.m` | Default title computation logic |
| `PTYSession.m` | Session model, title stack delegation |
| `PTYTab.m` | Tab model, titleOverride handling |
| `PseudoTerminal.m` | Window controller, macOS title bar |
| `ITAddressBookMgr.h` | Profile key definitions |
| `iTermVariables.h` | Variable key definitions |
| `iTermVariableScope+Session.m` | Session variable accessors |
| `TmuxController.h` | Tmux title integration |

## Summary Diagram

```
┌─────────────────────────────────────────────────────────┐
│                 macOS Window Title Bar                  │
│         PseudoTerminal.setWindowTitle:                  │
│                        ↑                                │
│         PTYSession.windowTitle                          │
│                        ↑                                │
│  iTermSessionNameController.presentationWindowTitle     │
│         ↑              ↑              ↑                 │
│    Built-in      OSC 0/2         Custom                 │
│    Function      Override        Provider               │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                      Tab Bar                            │
│                  PTYTab.title                           │
│                        ↑                                │
│         ┌──────────────┴──────────────┐                 │
│    titleOverride              activeSession             │
│    (if set)              .presentationSessionTitle      │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│               Session Name Computation                  │
│                        ↑                                │
│    ┌───────────────────┼───────────────────┐            │
│    │                   │                   │            │
│ autoNameFormat    "Title:" dropdown   Custom Provider   │
│ (swifty string)   (components)        (Python API)      │
│    │                   │                                │
│ Profile name      Job, Path, Host,                      │
│ + overrides       User, TTY, etc.                       │
└─────────────────────────────────────────────────────────┘
```
