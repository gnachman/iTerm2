"""Provides interfaces for getting and changing preferences (excluding
per-profile preferences; see the profile submodule for that)"""
import enum
import iterm2.rpc
import json
import typing

class PreferenceKey(enum.Enum):
    """Keys identifying particular preference settings."""
    OPEN_PROFILES_WINDOW_AT_START = "OpenBookmark"  #: Open the profiles window at startup?  Mutually exclusive with OPEN_DEFAULT_ARRANGEMENT_AT_START and RESTORE_ONLY_HOTKEY_AT_START.  Takes a boolean.
    OPEN_DEFAULT_ARRANGEMENT_AT_START = "OpenArrangementAtStartup"  #: Open default arrangement at startup?  Mutually exclusive with OPEN_PROFILES_WINDOW_AT_START and RESTORE_ONLY_HOTKEY_AT_START.  Takes a boolean.
    RESTORE_ONLY_HOTKEY_AT_START = "OpenNoWindowsAtStartup"  #: Restore only hotkey window at startup?  Mutually exclusive with OPEN_PROFILES_WINDOW_AT_START and OPEN_DEFAULT_ARRANGEMENT_AT_START.  Takes a boolean.
    QUIT_WHEN_ALL_WINDOWS_CLOSED = "QuitWhenAllWindowsClosed"  #: Quit automatically when all terminal windows are closed?  Takes a boolean.
    ONLY_WHEN_MORE_TABS = "OnlyWhenMoreTabs"  #: Confirm close window when there are multiple tabs?  Takes a boolean.
    PROMPT_ON_QUIT = "PromptOnQuit"  #: Prompt before quitting?  Takes a boolean.
    INSTANT_REPLAY_MEMORY_MB = "IRMemory"  #: Memory (in megabytes) to use per session for instant replay.  Takes a floating point value.
    SAVE_PASTE_HISTORY = "SavePasteHistory"  #: Should paste and command history be saved to disk?  Takes a boolean.
    ENABLE_BONJOUR_DISCOVERY = "EnableRendezvous"  #: Discover hosts with bonjour?  Takes a boolean.
    SOFTWARE_UPDATE_ENABLE_AUTOMATIC_CHECKS = "SUEnableAutomaticChecks"  #: Automatically check for new versions of iTerm2?  Takes a boolean.
    SOFTWARE_UPDATE_ENABLE_TEST_RELEASES = "CheckTestRelease"  #: Check for beta versions for auto update?  Takes a boolean.
    LOAD_PREFS_FROM_CUSTOM_FOLDER = "LoadPrefsFromCustomFolder"  #: Load prefs from a custom folder?  Takes a boolean.
    CUSTOM_FOLDER_TO_LOAD_PREFS_FROM = "PrefsCustomFolder"  #: If LOAD_PREFS_FROM_CUSTOM_FOLDER, gives the folder or URL to load prefs from.  Takes a string.
    COPY_TO_PASTEBOARD_ON_SELECTION = "CopySelection"  #: Copy to pasteboard on selection?  Takes a boolean.
    INCLUDE_TRAILING_NEWLINE_WHEN_COPYING = "CopyLastNewline"  #: Include trailing newline when copying to pasteboard?  Takes a boolean.
    APPS_MAY_ACCESS_PASTEBOARD = "AllowClipboardAccess"  #: Allow terminal apps to access the pasteboard?  Takes a boolean.
    WORD_CHARACTERS = "WordCharacters"  #: Characters considered part of a word for selection.  Takes a string.
    ENABLE_SMART_WINDOW_PLACEMENT = "SmartPlacement"  #: Enable smart window placement?  Takes a boolean.
    ADJUST_WINDOW_FOR_FONT_SIZE_CHANGE = "AdjustWindowForFontSizeChange"  #: Change window size when font size changes?  Takes a boolean.
    MAX_VERTICALLY = "MaxVertically"  #: When maximizing a window, grow it only vertically?  Takes a boolean.
    NATIVE_FULL_SCREEN_WINDOWS = "UseLionStyleFullscreen"  #: Use native full screen window?  Takes a boolean.
    OPEN_TMUX_WINDOWS_IN = "OpenTmuxWindowsIn"  #: Specifies how to open tmux windows.  Takes an integer. 0=native windows, 1=new window, 2=tabs in existing window.
    TMUX_DASHBOARD_LIMIT = "TmuxDashboardLimit"  #: Open tmux dashboard if there are more than this many windows.  Takes an integer.
    AUTO_HIDE_TMUX_CLIENT_SESSION = "AutoHideTmuxClientSession"  #: Automatically bury the tmux client session?  Takes a boolean.
    USE_TMUX_PROFILE = "TmuxUsesDedicatedProfile"  #: Use dedicated tmux profile. Takes a boolean.
    USE_METAL = "UseMetal"  #: Use the GPU renderer?  Takes a boolean.
    DISABLE_METAL_WHEN_UNPLUGGED = "disableMetalWhenUnplugged"  #: Disable the GPU renderer when not connected to power?  Takes a boolean.
    PREFER_INTEGRATED_GPU = "preferIntegratedGPU"  #: Prefer the integrated GPU over discrete, if available?  Takes a boolean.
    METAL_MAXIMIZE_THROUGHPUT = "metalMaximizeThroughput"  #: Maximize throughput for GPU renderer, vs framerate?  Takes a boolean.
    THEME = "TabStyleWithAutomaticOption"  #: Theme.  Takes an integer.  0 = Light, 1 = Dark, 2 = Light high contrast, 3 = Dark high contrast, 4 = Automatic (10.14+), 5 = Minimal (10.14+).
    TAP_BAR_POSTIION = "TabViewType"  #: Where the tab bar should be placed.  Takes an integer.  0=Top, 1=Bottom, 2=Left.
    HIDE_TAB_BAR_WHEN_ONLY_ONE_TAB = "HideTab"  #: Hide tab bar when there is only one tab?  Takes a boolean.
    HIDE_TAB_NUMBER = "HideTabNumber"  #: Hide the tab number?  Takes a boolean.
    HIDE_TAB_CLOSE_BUTTON = "HideTabCloseButton"  #: Hide the tab close button?  Takes a boolean.
    HIDE_TAB_ACTIVITY_INDICATOR = "HideActivityIndicator"  #: Hide the tab activity indicator?  Takes a boolean.
    SHOW_TAB_NEW_OUTPUT_INDICATOR = "ShowNewOutputIndicator"  #: Show a "new output" indicator in tabs?  Takes a boolean.
    SHOW_PANE_TITLES = "ShowPaneTitles"  #: Show a per-pane title bar?  Takes a boolean.
    STRETCH_TABS_TO_FILL_BAR = "StretchTabsToFillBar"  #: Stretch tabs horizontally to fill the tab bar?  Takes a boolean.
    HIDE_MENU_BAR_IN_FULLSCREEN = "HideMenuBarInFullscreen"  #: Hide menu bar when in full screen?  Takes a boolean.
    HIDE_FROM_DOCK_AND_APP_SWITCHER = "HideFromDockAndAppSwitcher"  #: Exclude iTerm2 from dock and app switcher?  Takes a boolean.
    FLASH_TAB_BAR_IN_FULLSCREEN = "FlashTabBarInFullscreen"  #: Flash tab bar in full screen?  Takes a boolean.
    WINDOW_NUMBER = "WindowNumber"  #: Show window number in title bar?  Takes a boolean.
    DIM_ONLY_TEXT = "DimOnlyText"  #: Dim only text when indicating inactive sessions?  Takes a boolean.
    SPLIT_PANE_DIMMING_AMOUNT = "SplitPaneDimmingAmount"  #: How much to dim inactive split panes or inactive windows.  Takes a floating point value in [0,1]
    DIM_INACTIVE_SPLIT_PANES = "DimInactiveSplitPanes"  #: Dim inactive split panes?  Takes a boolean.
    DRAW_WINDOW_BORDER = "UseBorder"  #: Show a border around windows?  Takes a boolean.
    HIDE_SCROLLBAR = "HideScrollbar"  #: Hide scroll bars?  Takes a boolean.
    DISABLE_FULLSCREEN_TRANSPARENCY = "DisableFullscreenTransparency"  #: Disable transparency for full screen windows?  Takes a boolean.
    ENABLE_DIVISION_VIEW = "EnableDivisionView"  #: Draw a line under the tab bar?  Takes a boolean.
    ENABLE_PROXY_ICON = "EnableProxyIcon"  #: Show proxy icon in title bar?  Takes a boolean.
    DIM_BACKGROUND_WINDOWS = "DimBackgroundWindows"  #: Dim inactive windows?  Takes a boolean.
    CONTROL_REMAPPING = "Control"  #: Remap control key.  Takes an integer.  1=Control, 2=Left option, 3=Right option, 7=Left Cmd, 8=Right Cmd.
    LEFT_OPTION_REMAPPING = "LeftOption"  #: Remap left option key.  Takes an integer.  1=Control, 2=Left option, 3=Right option, 7=Left Cmd, 8=Right Cmd.
    RIGHT_OPTION_REMAPPING = "RightOption"  #: Remap right option key.  Takes an integer.  1=Control, 2=Left option, 3=Right option, 7=Left Cmd, 8=Right Cmd.
    LEFT_COMMAND_REMAPPING = "LeftCommand"  #: Remap left cmd key.  Takes an integer.  1=Control, 2=Left option, 3=Right option, 7=Left Cmd, 8=Right Cmd.
    RIGHT_COMMAND_REMAPPING = "RightCommand"  #: Remap right cmd key.  Takes an integer.  1=Control, 2=Left option, 3=Right option, 7=Left Cmd, 8=Right Cmd.
    SWITCH_PANE_MODIFIER = "SwitchPaneModifier"  #: Modifiers to switch split pane with number.  Takes an integer.  3=Cmd, 6=Cmd+Option, 5=Option, 9=Disable switching.
    SWITCH_TAB_MODIFIER = "SwitchTabModifier"  #: Modifiers to switch tab by number.  Takes an integer.  3=Cmd, 6=Cmd+Option, 5=Option, 9=Disable switching.
    SWITCH_WINDOW_MODIFIER = "SwitchWindowModifier"  #: Modifiers to switch window with number.  Takes an integer.  3=Cmd, 6=Cmd+Option, 5=Option, 9=Disable switching.
    ENABLE_SEMANTIC_HISTORY = "CommandSelection"  #: Enable semantic history?  Takes a boolean.
    PASS_ON_CONTROL_CLICK = "PassOnControlClick"  #: Pass control-click to mouse reporting?  Takes a boolean.
    OPTION_CLICK_MOVES_CURSOR = "OptionClickMovesCursor"  #: Opt-click moves cursor?  Takes a boolean.
    THREE_FINGER_EMULATES = "ThreeFingerEmulates"  #: Three-finger tap emulates middle click?  Takes a boolean.
    FOCUS_FOLLOWS_MOUSE = "FocusFollowsMouse"  #: Focus follows mouse?  Takes a boolean.
    TRIPLE_CLICK_SELECTS_FULL_WRAPPED_LINES = "TripleClickSelectsFullWrappedLines"  #: Triple click selects full wrapped lines?  Takes a boolean.
    DOUBLE_CLICK_PERFORMS_SMART_SELECTION = "DoubleClickPerformsSmartSelection"  #: Double click performs smart selection?  Takes a boolean.
    ITERM_VERSION = "iTerm Version"  #: Last-used iTerm2 version. Do not set this.  Takes a string.
    AUTO_COMMAND_HISTORY = "AutoCommandHistory"  #: Enable autocomplete with command history?  Takes a boolean.
    PASTE_SPECIAL_CHUNK_SIZE = "PasteSpecialChunkSize"  #: Default paste chunk size.  Takes a positive integer.
    PASTE_SPECIAL_CHUNK_DELAY = "PasteSpecialChunkDelay"  #: Default delay between paste chunks.  Takes a floating point number.
    NUMBER_OF_SPACES_PER_TAB = "NumberOfSpacesPerTab"  #: Default number of spaces per tab when converting tabs when pasting.  Takes a positive integer.
    TAB_TRANSFORM = "TabTransform"  #: How to ransform tabs to space by default when pasting Takes an integer.  0=No transformation, 1=Convert to spaces, 2=Escape with C-V
    ESCAPE_SHELL_CHARS_WITH_BACKSLASH = "EscapeShellCharsWithBackslash"  #: Escape shell characters with backslash when using advanced paste?  Takes a boolean.
    CONVERT_UNICODE_PUNCTUATION = "ConvertUnicodePunctuation"  #: Convert unicode punctuation to ascii when using advanced paste?  Takes a boolean.
    CONVERT_DOS_NEWLINES = "ConvertDosNewlines"  #: Convert DOS newlines to Unix when using advanced paste?  Takes a boolean.
    REMOVE_CONTROL_CODES = "RemoveControlCodes"  #: Remove control codes when using advanced paste?  Takes a boolean.
    BRACKETED_PASTE_MODE = "BracketedPasteMode"  #: Allow bracketed paste mode when using advanced paste?  Takes a boolean.
    PASTE_SPECIAL_USE_REGEX_SUBSTITUTION = "PasteSpecialUseRegexSubstitution"  #: Enable regex substitution when using advanced paste?  Takes a boolean.
    PASTE_SPECIAL_REGEX = "PasteSpecialRegex"  #: Regex pattern to use for substitution when using advanced paste?  Takes a string.
    PASTE_SPECIAL_SUBSTITUTION = "PasteSpecialSubstitution"  #: Value to use for regex substitution when using advanced paste?  Takes a string.
    LEFT_TAB_BAR_WIDTH = "LeftTabBarWidth"  #: Width of left-side tab bar.  Takes a floating point value.
    PASTE_TAB_TO_STRING_TAB_STOP_SIZE = "PasteTabToStringTabStopSize"  #: When converting tabs to spaces, how many spaces to use?  Takes a nonnegative integer.
    SHOW_FULL_SCREEN_TAB_BAR = "ShowFullScreenTabBar"  #: Show tab bar in full screen?  Takes a boolean.
    DEFAULT_TOOLBELT_WIDTH = "Default Toolbelt Width"  #: Width of toolbelt by default.  Takes a nonnegative integer.
    SIZE_CHANGES_AFFECT_PROFILE = "Size Changes Affect Profile"  #: Does changing text size with cmd-+ and cmd-- affect only the session or also its profile?
    STATUS_BAR_POSITION = "StatusBarPosition"  #: Where does the status bar go? Takes an integer. 0=top, 1=bottom.
    PRESERVE_WINDOW_SIZE_WHEN_TAB_BAR_VISIBILITY_CHANGES = "PreserveWindowSizeWhenTabBarVisibilityChanges"  #: Keep window size the same when tabbar shows/hides? Takes a boolean.
    PER_PANE_BACKGROUND_IMAGE = "PerPaneBackgroundImage"  #: Should each split pane have a separate bg image, or one for the whole window? Takes a boolean.
    PER_PANE_STATUS_BAR = "SeparateStatusBarsPerPane"  #: Should each split pane have a separate status bar, or just one for the whole window? Takes a boolean.
    EMULATE_US_KEYBOARD = "UseVirtualKeyCodesForDetectingDigits"  #: Emulate US keyboard for the purposes of switching tabs/panes/windows by keyboard? Takes a boolean.
    TEXT_SIZE_CHANGES_AFFECT_PROFILE = "Size Changes Affect Profile"  #: Does increasing/decreasing text size update the backing profile? Takes a boolean.



async def async_get_preference(connection, key: PreferenceKey) -> typing.Union[None, typing.Any]:
    """
    Gets a preference by key.

    :param key: The preference key, from the `PreferenceKey` enum.
    :returns: An object with the preferences value, or `None` if unset and no default exists.
    """
    proto = await iterm2.rpc.async_get_preference(connection, key.value)
    j = proto.preferences_response.results[0].get_preference_result.json_value
    return json.loads(j)

