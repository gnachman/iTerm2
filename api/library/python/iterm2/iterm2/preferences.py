"""Provides interfaces for getting and changing preferences (excluding
per-profile preferences; see the profile submodule for that)"""
import enum
import iterm2.rpc
import json

class PreferenceKeys(enum.Enum):
    """Open the profiles window at startup?

    Mutually exclusive with OPEN_DEFAULT_ARRANGEMENT_AT_START and RESTORE_ONLY_HOTKEY_AT_START.

    Takes a boolean."""
    OPEN_PROFILES_WINDOW_AT_START            = "OpenBookmark"

    """Open default arrangement at startup?

    Mutually exclusive with OPEN_PROFILES_WINDOW_AT_START and RESTORE_ONLY_HOTKEY_AT_START.

    Takes a boolean."""
    OPEN_DEFAULT_ARRANGEMENT_AT_START        = "OpenArrangementAtStartup"

    """Restore only hotkey window at startup?

    Mutually exclusive with OPEN_PROFILES_WINDOW_AT_START and OPEN_DEFAULT_ARRANGEMENT_AT_START.

    Takes a boolean."""
    RESTORE_ONLY_HOTKEY_AT_START             = "OpenNoWindowsAtStartup"

    """Quit automatically when all terminal windows are closed?

    Takes a boolean."""
    QUIT_WHEN_ALL_WINDOWS_CLOSED             = "QuitWhenAllWindowsClosed"

    """Confirm close window when there are multiple tabs?

    Takes a boolean."""
    ONLY_WHEN_MORE_TABS                      = "OnlyWhenMoreTabs"

    """Prompt before quitting?

    Takes a boolean."""
    PROMPT_ON_QUIT                           = "PromptOnQuit"

    """Memory (in megabytes) to use per session for instant replay.

    Takes a floating point value."""
    INSTANT_REPLAY_MEMORY_MB                 = "IRMemory"

    """Should paste and command history be saved to disk?

    Takes a boolean."""
    SAVE_PASTE_HISTORY                       = "SavePasteHistory"

    """Discover hosts with bonjour?

    Takes a boolean."""
    ENABLE_BONJOUR_DISCOVERY                 = "EnableRendezvous"

    """Automatically check for new versions of iTerm2?

    Takes a boolean."""
    SOFTWARE_UPDATE_ENABLE_AUTOMATIC_CHECKS  = "SUEnableAutomaticChecks"

    """Check for beta versions for auto update?

    Takes a boolean."""
    SOFTWARE_UPDATE_ENABLE_TEST_RELEASES     = "CheckTestRelease"

    """Load prefs from a custom folder?

    Takes a boolean."""
    LOAD_PREFS_FROM_CUSTOM_FOLDER            = "LoadPrefsFromCustomFolder"

    """If LOAD_PREFS_FROM_CUSTOM_FOLDER, gives the folder or URL to load prefs from.

    Takes a string."""
    CUSTOM_FOLDER_TO_LOAD_PREFS_FROM         = "PrefsCustomFolder"

    """Copy to pasteboard on selection?

    Takes a boolean."""
    COPY_TO_PASTEBOARD_ON_SELECTION          = "CopySelection"

    """Include trailing newline when copying to pasteboard?

    Takes a boolean."""
    INCLUDE_TRAILING_NEWLINE_WHEN_COPYING    = "CopyLastNewline"

    """Allow terminal apps to access the pasteboard?

    Takes a boolean."""
    APPS_MAY_ACCESS_PASTEBOARD               = "AllowClipboardAccess"

    """Characters considered part of a word for selection.

    Takes a string."""
    WORD_CHARACTERS                          = "WordCharacters"

    """Enable smart window placement?

    Takes a boolean."""
    ENABLE_SMART_WINDOW_PLACEMENT            = "SmartPlacement"

    """Change window size when font size changes?

    Takes a boolean."""
    ADJUST_WINDOW_FOR_FONT_SIZE_CHANGE       = "AdjustWindowForFontSizeChange"

    """When maximizing a window, grow it only vertically?

    Takes a boolean."""
    MAX_VERTICALLY                           = "MaxVertically"

    """Use native full screen window?

    Takes a boolean."""
    NATIVE_FULL_SCREEN_WINDOWS               = "UseLionStyleFullscreen"

    """Specifies how to open tmux windows.

    Takes an integer. 0=native windows, 1=new window, 2=tabs in existing window."""
    OPEN_TMUX_WINDOWS_IN                     = "OpenTmuxWindowsIn"

    """Open tmux dashboard if there are more than this many windows.

    Takes an integer."""
    TMUX_DASHBOARD_LIMIT                     = "TmuxDashboardLimit"

    """Automatically bury the tmux client session?

    Takes a boolean."""
    AUTO_HIDE_TMUX_CLIENT_SESSION            = "AutoHideTmuxClientSession"

    """Use the GPU renderer?

    Takes a boolean."""
    USE_METAL                                = "UseMetal"

    """Disable the GPU renderer when not connected to power?

    Takes a boolean."""
    DISABLE_METAL_WHEN_UNPLUGGED             = "disableMetalWhenUnplugged"

    """Prefer the integrated GPU over discrete, if available?

    Takes a boolean."""
    PREFER_INTEGRATED_GPU                    = "preferIntegratedGPU"

    """Maximize throughput for GPU renderer, vs framerate?

    Takes a boolean."""
    METAL_MAXIMIZE_THROUGHPUT                = "metalMaximizeThroughput"

    """Theme.

    Takes an integer.
    0 = Light, 1 = Dark, 2 = Light high contrast, 3 = Dark high contrast, 4 = Automatic (10.14+), 5 = Minimal (10.14+)."""
    THEME                                    = "TabStyleWithAutomaticOption"

    """Where the tab bar should be placed.

    Takes an integer.
    0=Top, 1=Bottom, 2=Left."""
    TAP_BAR_POSTIION                         = "TabViewType"

    """Hide tab bar when there is only one tab?

    Takes a boolean."""
    HIDE_TAB_BAR_WHEN_ONLY_ONE_TAB           = "HideTab"

    """Hide the tab number?

    Takes a boolean."""
    HIDE_TAB_NUMBER                          = "HideTabNumber"

    """Hide the tab close button?

    Takes a boolean."""
    HIDE_TAB_CLOSE_BUTTON                    = "HideTabCloseButton"

    """Hide the tab activity indicator?

    Takes a boolean."""
    HIDE_TAB_ACTIVITY_INDICATOR              = "HideActivityIndicator"

    """Show a "new output" indicator in tabs?

    Takes a boolean."""
    SHOW_TAB_NEW_OUTPUT_INDICATOR            = "ShowNewOutputIndicator"

    """Show a per-pane title bar?

    Takes a boolean."""
    SHOW_PANE_TITLES                         = "ShowPaneTitles"

    """Stretch tabs horizontally to fill the tab bar?

    Takes a boolean."""
    STRETCH_TABS_TO_FILL_BAR                 = "StretchTabsToFillBar"

    """Hide menu bar when in full screen?

    Takes a boolean."""
    HIDE_MENU_BAR_IN_FULLSCREEN              = "HideMenuBarInFullscreen"

    """Exclude iTerm2 from dock and app switcher?

    Takes a boolean."""
    HIDE_FROM_DOCK_AND_APP_SWITCHER          = "HideFromDockAndAppSwitcher"

    """Flash tab bar in full screen?

    Takes a boolean."""
    FLASH_TAB_BAR_IN_FULLSCREEN              = "FlashTabBarInFullscreen"

    """Show window number in title bar?

    Takes a boolean."""
    WINDOW_NUMBER                            = "WindowNumber"

    """Dim only text when indicating inactive sessions?

    Takes a boolean."""
    DIM_ONLY_TEXT                            = "DimOnlyText"

    """How much to dim inactive split panes or inactive windows.

    Takes a floating point value in [0,1]"""
    SPLIT_PANE_DIMMING_AMOUNT                = "SplitPaneDimmingAmount"

    """Dim inactive split panes?

    Takes a boolean."""
    DIM_INACTIVE_SPLIT_PANES                 = "DimInactiveSplitPanes"

    """Show a border around windows?

    Takes a boolean."""
    DRAW_WINDOW_BORDER                       = "UseBorder"

    """Hide scroll bars?

    Takes a boolean."""
    HIDE_SCROLLBAR                           = "HideScrollbar"

    """Disable transparency for full screen windows?

    Takes a boolean."""
    DISABLE_FULLSCREEN_TRANSPARENCY          = "DisableFullscreenTransparency"

    """Draw a line under the tab bar?

    Takes a boolean."""
    ENABLE_DIVISION_VIEW                     = "EnableDivisionView"

    """Show proxy icon in title bar?

    Takes a boolean."""
    ENABLE_PROXY_ICON                        = "EnableProxyIcon"

    """Dim inactive windows?

    Takes a boolean."""
    DIM_BACKGROUND_WINDOWS                   = "DimBackgroundWindows"

    """Remap control key.

    Takes an integer.
    1=Control, 2=Left option, 3=Right option, 7=Left Cmd, 8=Right Cmd."""
    CONTROL_REMAPPING                        = "Control"

    """Remap left option key.

    Takes an integer.
    1=Control, 2=Left option, 3=Right option, 7=Left Cmd, 8=Right Cmd."""
    LEFT_OPTION_REMAPPING                    = "LeftOption"

    """Remap right option key.

    Takes an integer.
    1=Control, 2=Left option, 3=Right option, 7=Left Cmd, 8=Right Cmd."""
    RIGHT_OPTION_REMAPPING                   = "RightOption"

    """Remap left cmd key.

    Takes an integer.
    1=Control, 2=Left option, 3=Right option, 7=Left Cmd, 8=Right Cmd."""
    LEFT_COMMAND_REMAPPING                   = "LeftCommand"

    """Remap right cmd key.

    Takes an integer.
    1=Control, 2=Left option, 3=Right option, 7=Left Cmd, 8=Right Cmd."""
    RIGHT_COMMAND_REMAPPING                  = "RightCommand"

    """Modifiers to switch split pane with number.

    Takes an integer.
    3=Cmd, 6=Cmd+Option, 5=Option, 9=Disable switching."""
    SWITCH_PANE_MODIFIER                     = "SwitchPaneModifier"

    """Modifiers to switch tab by number.

    Takes an integer.
    3=Cmd, 6=Cmd+Option, 5=Option, 9=Disable switching."""
    SWITCH_TAB_MODIFIER                      = "SwitchTabModifier"

    """Modifiers to switch window with number.

    Takes an integer.
    3=Cmd, 6=Cmd+Option, 5=Option, 9=Disable switching."""
    SWITCH_WINDOW_MODIFIER                   = "SwitchWindowModifier"

    """Enable semantic history?

    Takes a boolean."""
    ENABLE_SEMANTIC_HISTORY                  = "CommandSelection"

    """Pass control-click to mouse reporting?

    Takes a boolean."""
    PASS_ON_CONTROL_CLICK                    = "PassOnControlClick"

    """Opt-click moves cursor?

    Takes a boolean."""
    OPTION_CLICK_MOVES_CURSOR                = "OptionClickMovesCursor"

    """Three-finger tap emulates middle click?

    Takes a boolean."""
    THREE_FINGER_EMULATES                    = "ThreeFingerEmulates"


    """Focus follows mouse?

    Takes a boolean."""
    FOCUS_FOLLOWS_MOUSE                      = "FocusFollowsMouse"


    """Triple click selects full wrapped lines?

    Takes a boolean."""
    TRIPLE_CLICK_SELECTS_FULL_WRAPPED_LINES  = "TripleClickSelectsFullWrappedLines"

    """Double click performs smart selection?

    Takes a boolean."""
    DOUBLE_CLICK_PERFORMS_SMART_SELECTION    = "DoubleClickPerformsSmartSelection"

    """Last-used iTerm2 version. Do not set this.

    Takes a string."""
    ITERM_VERSION                            = "iTerm Version"

    """Enable autocomplete with command history?

    Takes a boolean."""
    AUTO_COMMAND_HISTORY                     = "AutoCommandHistory"

    """Default paste chunk size.

    Takes a positive integer."""
    PASTE_SPECIAL_CHUNK_SIZE                 = "PasteSpecialChunkSize"

    """Default delay between paste chunks.

    Takes a floating point number."""
    PASTE_SPECIAL_CHUNK_DELAY                = "PasteSpecialChunkDelay"

    """Default number of spaces per tab when converting tabs when pasting.

    Takes a positive integer."""
    NUMBER_OF_SPACES_PER_TAB                 = "NumberOfSpacesPerTab"

    """How to ransform tabs to space by default when pasting

    Takes an integer.
    0=No transformation, 1=Convert to spaces, 2=Escape with C-V"""
    TAB_TRANSFORM                            = "TabTransform"

    """Escape shell characters with backslash when using advanced paste?

    Takes a boolean."""
    ESCAPE_SHELL_CHARS_WITH_BACKSLASH        = "EscapeShellCharsWithBackslash"

    """Convert unicode punctuation to ascii when using advanced paste?

    Takes a boolean."""
    CONVERT_UNICODE_PUNCTUATION              = "ConvertUnicodePunctuation"

    """Convert DOS newlines to Unix when using advanced paste?

    Takes a boolean."""
    CONVERT_DOS_NEWLINES                     = "ConvertDosNewlines"

    """Remove control codes when using advanced paste?

    Takes a boolean."""
    REMOVE_CONTROL_CODES                     = "RemoveControlCodes"

    """Allow bracketed paste ode when using advanced paste?

    Takes a boolean."""
    BRACKETED_PASTE_MODE                     = "BracketedPasteMode"

    """Enable regex substitution when using advanced paste?

    Takes a boolean."""
    PASTE_SPECIAL_USE_REGEX_SUBSTITUTION     = "PasteSpecialUseRegexSubstitution"

    """Regex pattern to use for substitution when using advanced paste?

    Takes a string."""
    PASTE_SPECIAL_REGEX                      = "PasteSpecialRegex"

    """Value to use for regex substitution when using advanced paste?

    Takes a string."""
    PASTE_SPECIAL_SUBSTITUTION               = "PasteSpecialSubstitution"

    """Width of left-side tab bar.

    Takes a floating point value."""
    LEFT_TAB_BAR_WIDTH                       = "LeftTabBarWidth"

    """When converting tabs to spaces, how many spaces to use?

    Takes a nonnegative integer."""
    PASTE_TAB_TO_STRING_TAB_STOP_SIZE        = "PasteTabToStringTabStopSize"

    """Show tab bar in full screen?

    Takes a boolean."""
    SHOW_FULL_SCREEN_TAB_BAR                 = "ShowFullScreenTabBar"

    """Width of toolbelt by default.

    Takes a nonnegative integer."""
    DEFAULT_TOOLBELT_WIDTH                   = "Default Toolbelt Width"

async def async_get_preference(connection, key):
    """
    Gets a preference by key.

    :param key: The preference key, from the `PreferenceKeys` enum.
    :returns: An object with the preferences value, or None if unset and no default exists.
    """
    proto = await iterm2.rpc.async_get_preference(connection, key.value)
    j = proto.preferences_response.results[0].get_preference_result.json_value
    return json.loads(j)

