"""Provides interfaces for getting and changing preferences (excluding
per-profile preferences; see the profile submodule for that)"""

from __future__ import annotations

import enum
import json
from typing import TYPE_CHECKING, Any

from . import api_pb2
from .rpc import RPCException
from .rpc import async_get_preference as _rpc_async_get_preference
from .rpc import async_set_preference as _rpc_async_set_preference

if TYPE_CHECKING:
    from .connection import Connection


# pylint: disable=line-too-long
class PreferenceKey(enum.Enum):
    """Keys identifying particular preference settings.

    Integer values for modifier remapping settings (such as
    `LEFT_OPTION_REMAPPING`): 2=Left Option, 3=Right Option, 7=Left Command,
    8=Right Command, 10=fn, 11=Left Control, 12=Right Control.

    Integer values for switch-by-number settings (such as
    `SWITCH_TAB_MODIFIER`): 1=Control, 4=Command, 5=Option,
    6=Command+Option, 9=No shortcut.
    """

    _value_: str

    # Startup and quitting
    OPEN_PROFILES_WINDOW_AT_START = "OpenBookmark"  #: Open the profiles window at startup?  Mutually exclusive with OPEN_DEFAULT_ARRANGEMENT_AT_START and RESTORE_ONLY_HOTKEY_AT_START.  Takes a boolean.
    OPEN_DEFAULT_ARRANGEMENT_AT_START = "OpenArrangementAtStartup"  #: Open default arrangement at startup?  Mutually exclusive with OPEN_PROFILES_WINDOW_AT_START and RESTORE_ONLY_HOTKEY_AT_START.  Takes a boolean.
    RESTORE_ONLY_HOTKEY_AT_START = "OpenNoWindowsAtStartup"  #: Restore only hotkey window at startup?  Mutually exclusive with OPEN_PROFILES_WINDOW_AT_START and OPEN_DEFAULT_ARRANGEMENT_AT_START.  Takes a boolean.
    ALWAYS_OPEN_WINDOW_AT_START = "AlwaysOpenWindowAtStartup"  #: Always open at least one terminal window at startup?  Takes a boolean.
    RESTORE_WINDOWS_TO_SAME_SPACES = "RestoreWindowsToSameSpaces"  #: Restore windows to the same Spaces they were in?  Takes a boolean.
    QUIT_WHEN_ALL_WINDOWS_CLOSED = "QuitWhenAllWindowsClosed"  #: Quit automatically when all terminal windows are closed?  Takes a boolean.
    ONLY_WHEN_MORE_TABS = "OnlyWhenMoreTabs"  #: Confirm close window when there are multiple tabs?  Takes a boolean.
    PROMPT_ON_QUIT = "PromptOnQuit"  #: Prompt before quitting?  Takes a boolean.
    PROMPT_ON_QUIT_EVEN_IF_NO_WINDOWS = "PromptOnQuitEvenIfThereAreNoWindows"  #: If PROMPT_ON_QUIT, prompt even if there are no windows?  Takes a boolean.
    NEVER_BLOCK_SYSTEM_SHUTDOWN = "NeverBlockSystemShutdown"  #: Disable all confirmations on system shutdown, restart, and log out?  Takes a boolean.

    # General
    INSTANT_REPLAY_MEMORY_MB = "IRMemory"  #: Memory (in megabytes) to use per session for instant replay.  Takes a floating point value.
    SAVE_PASTE_HISTORY = "SavePasteHistory"  #: Should paste and command history be saved to disk?  Takes a boolean.
    #: Discover hosts with bonjour?  Takes a boolean.
    ENABLE_BONJOUR_DISCOVERY = "EnableRendezvous"
    NOTIFY_ONLY_FOR_CRITICAL_SHELL_INTEGRATION_UPDATES = "NotifyOnlyForCriticalShellIntegrationUpdates"  #: Ignore non-critical shell integration updates?  Takes a boolean.
    SOFTWARE_UPDATE_ENABLE_AUTOMATIC_CHECKS = "SUEnableAutomaticChecks"  #: Automatically check for new versions of iTerm2?  Takes a boolean.
    SOFTWARE_UPDATE_ENABLE_TEST_RELEASES = "CheckTestRelease"  #: Check for beta versions for auto update?  Takes a boolean.
    LOAD_PREFS_FROM_CUSTOM_FOLDER = "LoadPrefsFromCustomFolder"  #: Load prefs from a custom folder?  Takes a boolean.
    CUSTOM_FOLDER_TO_LOAD_PREFS_FROM = "PrefsCustomFolder"  #: If LOAD_PREFS_FROM_CUSTOM_FOLDER, gives the folder or URL to load prefs from.  Takes a string.
    USE_CUSTOM_SCRIPTS_FOLDER = "UseCustomScriptsFolder"  #: Use a custom folder for Python API scripts?  Takes a boolean.
    CUSTOM_SCRIPTS_FOLDER = "CustomScriptsFolder"  #: If USE_CUSTOM_SCRIPTS_FOLDER, gives the folder for Python API scripts.  Takes a string.
    ENABLE_BIDI = "Bidi"  #: Enable support for right-to-left scripts?  Takes a boolean.
    SSH_INTEGRATION_FOR_URLS = "SshIntegrationForURLs"  #: Use SSH integration when opening ssh: URLs?  Takes a boolean.

    # Selection
    #: Copy to pasteboard on selection?  Takes a boolean.
    COPY_TO_PASTEBOARD_ON_SELECTION = "CopySelection"
    INCLUDE_TRAILING_NEWLINE_WHEN_COPYING = "CopyLastNewline"  #: Include trailing newline when copying to pasteboard?  Takes a boolean.
    APPS_MAY_ACCESS_PASTEBOARD = "AllowClipboardAccess"  #: Allow terminal apps to access the pasteboard?  Takes a boolean.
    WORD_SELECTION_MODE = "WordSelectionMode"  #: How to decide which characters are part of a word for selection.  Takes an integer.  0=Use WORD_CHARACTERS, 1=Use WORD_SELECTION_REGEX.
    WORD_CHARACTERS = "WordCharacters"  #: Characters considered part of a word for selection, used when WORD_SELECTION_MODE is 0.  Takes a string.
    WORD_SELECTION_REGEX = "WordSelectionRegexPattern"  #: Regular expression matching characters considered part of a word for selection (in addition to alphanumerics), used when WORD_SELECTION_MODE is 1.  Takes a string.

    # Windows
    #: DEPRECATED - Use WINDOW_PLACEMENT instead.
    ENABLE_SMART_WINDOW_PLACEMENT = "SmartPlacement"
    WINDOW_PLACEMENT = "WindowPlacement"  #: How to place new windows.  Takes an integer.  0=Let macOS decide the position and use size from profile, 1=Smart window placement, 2=Remember size and position of previously closed windows, 3=Remember position of previously closed windows and use size from profile.
    ADJUST_WINDOW_FOR_FONT_SIZE_CHANGE = "AdjustWindowForFontSizeChange"  #: Change window size when font size changes?  Takes a boolean.
    MAX_VERTICALLY = "MaxVertically"  #: When maximizing a window, grow it only vertically?  Takes a boolean.
    #: Use native full screen window?  Takes a boolean.
    NATIVE_FULL_SCREEN_WINDOWS = "UseLionStyleFullscreen"
    SEPARATE_WINDOW_TITLE_PER_TAB = "SeparateWindowTitlePerTab"  #: May each tab have its own window title?  Takes a boolean.

    # tmux
    OPEN_TMUX_WINDOWS_IN = "OpenTmuxWindowsIn"  #: Specifies how to open tmux windows.  Takes an integer. 0=native windows, 1=tabs in a new window, 2=tabs in the attaching window.
    TMUX_DASHBOARD_LIMIT = "TmuxDashboardLimit"  #: Open tmux dashboard if there are more than this many windows.  Takes an integer.
    AUTO_HIDE_TMUX_CLIENT_SESSION = "AutoHideTmuxClientSession"  #: Automatically bury the tmux client session?  Takes a boolean.
    #: Use dedicated tmux profile. Takes a boolean.
    USE_TMUX_PROFILE = "TmuxUsesDedicatedProfile"
    USE_TMUX_STATUS_BAR = "UseTmuxStatusBar"  #: Status bar shows tmux status bar content instead of native components?  Takes a boolean.
    TMUX_PAUSE_MODE_AGE_LIMIT = "TmuxPauseModeAgeLimit"  #: Pause a tmux pane if it would take more than this many seconds to catch up.  Takes a nonnegative integer.
    TMUX_UNPAUSE_AUTOMATICALLY = "TmuxUnpauseAutomatically"  #: Automatically unpause tmux panes?  Takes a boolean.
    #: Warn before pausing a tmux pane?  Takes a boolean.
    TMUX_WARN_BEFORE_PAUSING = "TmuxWarnBeforePausing"
    TMUX_SYNC_CLIPBOARD = "TmuxSyncClipboard"  #: Mirror the tmux paste buffer to the local clipboard?  Takes a boolean.

    # GPU rendering and performance
    USE_METAL = "UseMetal"  #: Use the GPU renderer?  Takes a boolean.
    DISABLE_METAL_WHEN_UNPLUGGED = "disableMetalWhenUnplugged"  #: Disable the GPU renderer when not connected to power?  Takes a boolean.
    DISABLE_METAL_IN_LOW_POWER_MODE = "disableMetalInLowPowerMode"  #: Disable the GPU renderer when low power mode is on?  Takes a boolean.
    PREFER_INTEGRATED_GPU = "preferIntegratedGPU"  #: Prefer the integrated GPU over discrete, if available?  Takes a boolean.
    METAL_MAXIMIZE_THROUGHPUT = "metalMaximizeThroughput"  #: Deprecated. Use MAXIMIZE_THROUGHPUT (which is identical besides the name) instead.
    MAXIMIZE_THROUGHPUT = METAL_MAXIMIZE_THROUGHPUT  #: Maximize throughput vs framerate?  Takes a boolean.
    MAXIMUM_CONCURRENT_TOKEN_EXECUTIONS = "MaximumConcurrentTokenExecutions"  #: Maximum number of sessions that process output at the same time.  Takes a nonnegative integer.  0=Automatic.

    # Appearance
    THEME = "TabStyleWithAutomaticOption"  #: Theme.  Takes an integer.  0=Light, 1=Dark, 2=Light high contrast, 3=Dark high contrast, 4=Regular (follows system appearance), 5=Minimal, 6=Compact.
    TAP_BAR_POSTIION = "TabViewType"  #: Where the tab bar should be placed.  Takes an integer.  0=Top, 1=Bottom, 2=Left, 3=Right.
    TAB_BAR_POSITION = TAP_BAR_POSTIION  #: Where the tab bar should be placed.  Takes an integer.  0=Top, 1=Bottom, 2=Left, 3=Right.
    SIDE_MARGINS = "TerminalMargin"  #: Margin, in points, on the left and right of the terminal.  Takes an integer.
    TOP_BOTTOM_MARGINS = "TerminalVMargin"  #: Margin, in points, above and below the terminal.  Takes an integer.
    #: Hide tab bar when there is only one tab?  Takes a boolean.
    HIDE_TAB_BAR_WHEN_ONLY_ONE_TAB = "HideTab"
    HIDE_TAB_NUMBER = "HideTabNumber"  #: Hide the tab number?  Takes a boolean.
    #: DEPRECATED - Use TABS_HAVE_CLOSE_BUTTON instead.
    HIDE_TAB_CLOSE_BUTTON = "HideTabCloseButton"
    #: Do tabs have close buttons?  Takes a boolean.
    TABS_HAVE_CLOSE_BUTTON = "TabsHaveCloseButton"
    #: Hide the tab activity indicator?  Takes a boolean.
    HIDE_TAB_ACTIVITY_INDICATOR = "HideActivityIndicator"
    SHOW_TAB_NEW_OUTPUT_INDICATOR = "ShowNewOutputIndicator"  #: Show a “new output” indicator in tabs?  Takes a boolean.
    SHOW_PANE_TITLES = "ShowPaneTitles"  #: Show a per-pane title bar?  Takes a boolean.
    SHOW_PANE_TITLES_EVEN_IF_ONLY_ONE_PANE = "ShowPaneTitlesEvenIfOnlyOnePane"  #: If SHOW_PANE_TITLES, show the pane title bar even if there is only one pane?  Takes a boolean.
    STRETCH_TABS_TO_FILL_BAR = "StretchTabsToFillBar"  #: Stretch tabs horizontally to fill the tab bar?  Takes a boolean.
    SCROLLABLE_SIDE_TAB_BAR = "ScrollableSideTabBar"  #: Does a left or right tab bar scroll when its tabs don’t fit?  Takes a boolean.
    NEW_TABS_OPEN_AT_END_OF_TAB_BAR = "AddNewTabAtEndOfTabs"  #: Open new tabs at the end of the tab bar, rather than next to the current tab?  Takes a boolean.
    SHOW_TAB_SWITCHER_WHEN_CYCLING_TABS = "ShowTabSwitcherWhenCyclingTabs"  #: Show a list of tabs with a preview while cycling through tabs?  Takes a boolean.
    HIDE_MENU_BAR_IN_FULLSCREEN = "HideMenuBarInFullscreen"  #: Hide menu bar when in full screen?  Takes a boolean.
    HIDE_FROM_DOCK_AND_APP_SWITCHER = "HideFromDockAndAppSwitcher"  #: Exclude iTerm2 from dock and app switcher?  Takes a boolean.
    HIDE_FROM_DOCK_ONLY_IF_ALL_WINDOWS_ARE_HOTKEY_WINDOWS = "UIElementRequiresHotkeys"  #: If HIDE_FROM_DOCK_AND_APP_SWITCHER, hide only if all windows are hotkey windows?  Takes a boolean.
    #: Show an iTerm2 icon in the menu bar?  Takes a boolean.
    SHOW_MENU_BAR_ITEM = "ShowMenuBarItem"
    #: Text to show in the menu bar item.  Takes a string.
    MENU_BAR_ITEM_STRING = "MenuBarItemString"
    #: Show icons in menu items?  Takes a boolean.
    SHOW_MENU_ITEM_ICONS = "NSMenuEnableActionImages"
    #: Flash tab bar in full screen?  Takes a boolean.
    FLASH_TAB_BAR_IN_FULLSCREEN = "FlashTabBarInFullscreen"
    #: Show window number in title bar?  Takes a boolean.
    WINDOW_NUMBER = "WindowNumber"
    DIM_ONLY_TEXT = "DimOnlyText"  #: Dim only text when indicating inactive sessions?  Takes a boolean.
    SPLIT_PANE_DIMMING_AMOUNT = "SplitPaneDimmingAmount"  #: How much to dim inactive split panes or inactive windows.  Takes a floating point value in [0,1]
    #: Dim inactive split panes?  Takes a boolean.
    DIM_INACTIVE_SPLIT_PANES = "DimInactiveSplitPanes"
    DRAW_WINDOW_BORDER = "UseBorder"  #: Show a border around windows?  Takes a boolean.
    HIDE_SCROLLBAR = "HideScrollbar"  #: Hide scroll bars?  Takes a boolean.
    DISABLE_FULLSCREEN_TRANSPARENCY = "DisableFullscreenTransparency"  #: Disable transparency for full screen windows?  Takes a boolean.
    #: Draw a line under the tab bar?  Takes a boolean.
    ENABLE_DIVISION_VIEW = "EnableDivisionView"
    #: Show proxy icon in title bar?  Takes a boolean.
    ENABLE_PROXY_ICON = "EnableProxyIcon"
    #: Dim inactive windows?  Takes a boolean.
    DIM_BACKGROUND_WINDOWS = "DimBackgroundWindows"

    # Keys
    CONTROL_REMAPPING = "Control"  #: DEPRECATED - Use LEFT_CONTROL_REMAPPING and RIGHT_CONTROL_REMAPPING instead.
    LEFT_CONTROL_REMAPPING = "LeftControl"  #: Remap left control key.  Takes an integer.  See the class documentation for values.
    RIGHT_CONTROL_REMAPPING = "RightControl"  #: Remap right control key.  Takes an integer.  See the class documentation for values.
    LEFT_OPTION_REMAPPING = "LeftOption"  #: Remap left option key.  Takes an integer.  See the class documentation for values.
    RIGHT_OPTION_REMAPPING = "RightOption"  #: Remap right option key.  Takes an integer.  See the class documentation for values.
    LEFT_COMMAND_REMAPPING = "LeftCommand"  #: Remap left cmd key.  Takes an integer.  See the class documentation for values.
    RIGHT_COMMAND_REMAPPING = "RightCommand"  #: Remap right cmd key.  Takes an integer.  See the class documentation for values.
    FUNCTION_REMAPPING = "FunctionKey"  #: Remap fn key.  Takes an integer.  See the class documentation for values.
    REMAP_MODIFIERS_GLOBALLY = "RemapModifiersGlobally"  #: Apply modifier remapping in all apps while iTerm2 is running?  Takes a boolean.
    SWITCH_PANE_MODIFIER = "SwitchPaneModifier"  #: Modifiers to switch split pane with number.  Takes an integer.  See the class documentation for values.
    SWITCH_TAB_MODIFIER = "SwitchTabModifier"  #: Modifiers to switch tab by number.  Takes an integer.  See the class documentation for values.
    SWITCH_WINDOW_MODIFIER = "SwitchWindowModifier"  #: Modifiers to switch window with number.  Takes an integer.  See the class documentation for values.
    EMULATE_US_KEYBOARD = "UseVirtualKeyCodesForDetectingDigits"  #: Emulate US keyboard for the purposes of switching tabs/panes/windows by keyboard? Takes a boolean.
    LANGUAGE_AGNOSTIC_KEY_BINDINGS = "LanguageAgnosticKeyBindings"  #: Interpret key bindings based on physical key, ignoring input language?  Takes a boolean.
    ALLOW_SYMBOLIC_HOT_KEYS = "AllowSymbolicHotKeys"  #: Respect keyboard shortcuts from System Settings?  Takes a boolean.
    FORCE_KEYBOARD = "ForceKeyboard"  #: Force a particular keyboard input source when iTerm2 is active?  Takes a boolean.
    FORCE_KEYBOARD_ONCE_PER_SESSION = "ForceKeyboardOncePerSession"  #: If FORCE_KEYBOARD, force it only once per session, when the session first receives keyboard focus?  Takes a boolean.
    KEYBOARD_LOCALE = "KeyboardLocale"  #: If FORCE_KEYBOARD, the identifier of the input source to use.  Takes a string.
    HAPTIC_FEEDBACK_FOR_ESC = "HapticFeedbackForEsc"  #: Give haptic feedback when pressing esc on the touch bar?  Takes a boolean.
    SOUND_FOR_ESC = "SoundForEsc"  #: Play a sound when pressing esc on the touch bar?  Takes a boolean.
    VISUAL_INDICATOR_FOR_ESC = "VisualIndicatorForEsc"  #: Show a visual indicator when pressing esc on the touch bar?  Takes a boolean.

    # Pointer
    #: Enable semantic history?  Takes a boolean.
    ENABLE_SEMANTIC_HISTORY = "CommandSelection"
    PASS_ON_CONTROL_CLICK = "PassOnControlClick"  #: Pass control-click to mouse reporting?  Takes a boolean.
    REPORT_RIGHT_CLICK = "ReportRightClick"  #: Report right click to apps instead of opening the context menu?  Takes a boolean.
    #: Opt-click moves cursor?  Takes a boolean.
    OPTION_CLICK_MOVES_CURSOR = "OptionClickMovesCursor"
    THREE_FINGER_EMULATES = "ThreeFingerEmulates"  #: Three-finger tap emulates middle click?  Takes a boolean.
    FOCUS_FOLLOWS_MOUSE = "FocusFollowsMouse"  #: Focus follows mouse?  Takes a boolean.
    FOCUS_FOLLOWS_MOUSE_INCLUDING_SUBVIEWS = "FFM Including Subviews"  #: If FOCUS_FOLLOWS_MOUSE, also move focus to views like Find and Composer?  Takes a boolean.
    FOCUS_ON_RIGHT_OR_MIDDLE_CLICK = "FocusOnRightOrMiddleClick"  #: Focus window after right or middle click?  Takes a boolean.
    TRIPLE_CLICK_SELECTS_FULL_WRAPPED_LINES = "TripleClickSelectsFullWrappedLines"  #: Triple click selects full wrapped lines?  Takes a boolean.
    DOUBLE_CLICK_PERFORMS_SMART_SELECTION = "DoubleClickPerformsSmartSelection"  #: Double click performs smart selection?  Takes a boolean.
    ENTER_COPY_MODE_AUTOMATICALLY = "EnterCopyModeAutomatically"  #: Automatically enter copy mode on Shift+Arrow key when there is a selection?  Takes a boolean.
    CLICK_TO_SELECT_COMMAND = "ClickToSelectCommand"  #: Clicking on a command selects it to restrict Find and Filter?  Takes a boolean.
    WRAP_DROPPED_FILENAMES_IN_QUOTES = "WrapDroppedFilenamesInQuotesWhenPasting"  #: When pasting a dropped filename, wrap it in double quotes?  Takes a boolean.
    REPORT_HORIZONTAL_SCROLL_EVENTS = "ReportHorizontalScrollEvents"  #: Does mouse reporting include horizontal scrolling?  Takes a boolean.
    QUICK_LOOK_HOVER_MODE = "QuickLookHoverMode"  #: When to show a Quick Look preview of a link under the pointer.  Takes an integer.  0=Off, 1=On hover, 2=On hover while holding Command.
    QUICK_LOOK_HOVER_DELAY = "QuickLookHoverDelay"  #: Seconds to wait before showing a Quick Look preview on hover.  Takes a floating point value.
    QUICK_LOOK_HOVER_AUTO_CLOSE_DELAY = "QuickLookHoverAutoCloseDelay"  #: Seconds to wait before closing a Quick Look preview after the pointer leaves.  Takes a floating point value.
    QUICK_LOOK_HOVER_DOMAIN_ALLOWLIST = "QuickLookHoverDomainAllowlist"  #: Domains for which Quick Look previews may be shown on hover.  Takes a list of strings.
    QUICK_LOOK_HOVER_INCLUDES_PLAIN_TEXT_URLS = "QuickLookHoverIncludesPlainTextURLs"  #: Show Quick Look previews on hover for URLs in plain text, not only hyperlinks?  Takes a boolean.
    QUICK_LOOK_USES_BROWSER_ENGINE = "QuickLookUsesBrowserEngine"  #: Use the built-in web browser for Quick Look previews of web pages?  Takes a boolean.

    # Misc
    #: Last-used iTerm2 version. Do not set this.  Takes a string.
    ITERM_VERSION = "iTerm Version"
    AUTO_COMMAND_HISTORY = "AutoCommandHistory"  #: Enable autocomplete with command history?  Takes a boolean.
    AUTO_COMPOSER = "AutoComposer"  #: Automatically show the composer at the shell prompt?  Requires shell integration.  Takes a boolean.
    ALERT_ON_MARKS_IN_OFFSCREEN_SESSIONS = "Alert On Marks in Offscreen Sessions"  #: Post a notification when a mark is set in a session that is not visible?  Takes a boolean.

    # Advanced paste
    #: Default paste chunk size.  Takes a positive integer.
    PASTE_SPECIAL_CHUNK_SIZE = "PasteSpecialChunkSize"
    PASTE_SPECIAL_CHUNK_DELAY = "PasteSpecialChunkDelay"  #: Default delay between paste chunks.  Takes a floating point number.
    NUMBER_OF_SPACES_PER_TAB = "NumberOfSpacesPerTab"  #: Default number of spaces per tab when converting tabs when pasting.  Takes a positive integer.
    TAB_TRANSFORM = "TabTransform"  #: How to transform tabs to spaces by default when pasting.  Takes an integer.  0=No transformation, 1=Convert to spaces, 2=Escape with C-V
    ESCAPE_SHELL_CHARS_WITH_BACKSLASH = "EscapeShellCharsWithBackslash"  #: Escape shell characters with backslash when using advanced paste?  Takes a boolean.
    CONVERT_UNICODE_PUNCTUATION = "ConvertUnicodePunctuation"  #: Convert unicode punctuation to ascii when using advanced paste?  Takes a boolean.
    CONVERT_DOS_NEWLINES = "ConvertDosNewlines"  #: Convert DOS newlines to Unix when using advanced paste?  Takes a boolean.
    REMOVE_CONTROL_CODES = "RemoveControlCodes"  #: Remove control codes when using advanced paste?  Takes a boolean.
    BRACKETED_PASTE_MODE = "BracketedPasteMode"  #: Allow bracketed paste mode when using advanced paste?  Takes a boolean.
    PASTE_SPECIAL_USE_REGEX_SUBSTITUTION = "PasteSpecialUseRegexSubstitution"  #: Enable regex substitution when using advanced paste?  Takes a boolean.
    PASTE_SPECIAL_REGEX = "PasteSpecialRegex"  #: Regex pattern to use for substitution when using advanced paste?  Takes a string.
    PASTE_SPECIAL_SUBSTITUTION = "PasteSpecialSubstitution"  #: Value to use for regex substitution when using advanced paste?  Takes a string.
    PASTE_TAB_TO_STRING_TAB_STOP_SIZE = "PasteTabToStringTabStopSize"  #: When converting tabs to spaces, how many spaces to use?  Takes a nonnegative integer.

    # Layout
    #: Width of left-side tab bar.  Takes a floating point value.
    LEFT_TAB_BAR_WIDTH = "LeftTabBarWidth"
    #: Show tab bar in full screen?  Takes a boolean.
    SHOW_FULL_SCREEN_TAB_BAR = "ShowFullScreenTabBar"
    DEFAULT_TOOLBELT_WIDTH = "Default Toolbelt Width"  #: Width of toolbelt by default.  Takes a nonnegative integer.
    SIZE_CHANGES_AFFECT_PROFILE = "Size Changes Affect Profile"  #: DEPRECATED - Use TEXT_SIZE_CHANGES_AFFECT_PROFILE instead.
    STATUS_BAR_POSITION = "StatusBarPosition"  #: Where does the status bar go? Takes an integer. 0=top, 1=bottom.
    PRESERVE_WINDOW_SIZE_WHEN_TAB_BAR_VISIBILITY_CHANGES = "PreserveWindowSizeWhenTabBarVisibilityChanges"  #: Keep window size the same when tabbar shows/hides? Takes a boolean.
    PRESERVE_WINDOW_SIZE_ONLY_TO_KEEP_ON_SCREEN = "PreserveWindowSizeToKeepOnScreenWhenTabBarVisibilityChanges"  #: If PRESERVE_WINDOW_SIZE_WHEN_TAB_BAR_VISIBILITY_CHANGES, preserve it only if resizing would cause the window to go off-screen?  Takes a boolean.
    PER_PANE_BACKGROUND_IMAGE = "PerPaneBackgroundImage"  #: Should each split pane have a separate bg image, or one for the whole window? Takes a boolean.
    PER_PANE_STATUS_BAR = "SeparateStatusBarsPerPane"  #: Should each split pane have a separate status bar, or just one for the whole window? Takes a boolean.
    TEXT_SIZE_CHANGES_AFFECT_PROFILE = SIZE_CHANGES_AFFECT_PROFILE  #: Does increasing/decreasing text size update the backing profile? Takes a boolean.
    ACTIONS = "Actions"  #: Array of dictionaries defining actions.
    SNIPPETS = "Snippets"  #: Array of dictionaries defining snippets.
    HTML_TAB_TITLES = "HTMLTabTitles"  #: Support basic HTML tags in tab titles
    #: Force key window to be opaque?
    DISABLE_TRANSPARENCY_FOR_KEY_WINDOW = "DisableTransparencyForKeyWindow"

    # AI
    AI_PROMPT = "AI Prompt"  #: Prompt template used to generate a command with AI.  Takes a string.
    AI_TIMEOUT = "AI Timeout"  #: Seconds to wait for a response from an AI provider.  Takes a floating point value.
    AI_SAFETY_CHECK = "AI Safety Check"  #: Use AI to check the safety of commands before running them?  Takes a boolean.
    AI_ZERO_DATA_RETENTION = "AIZeroDataRetention"  #: Enable “zero data retention” (send the whole conversation every time)?  Takes a boolean.
    AI_MODEL_UPDATES_ENABLED = "AIModelUpdatesEnabled"  #: Automatically update the list of available AI models from an online database?  Takes a boolean.
    AI_PERMISSION_CHECK_TERMINAL_STATE = "AIPermissionCheckTerminalState"  #: May AI chat check terminal state?  Takes an integer.  0=Ask each time, 1=Always allow, 2=Never allow.
    AI_PERMISSION_RUN_COMMANDS = "AIPermissionRunCommands"  #: May AI chat run commands?  Takes an integer.  0=Ask each time, 1=Always allow, 2=Never allow.
    AI_PERMISSION_VIEW_HISTORY = "AIPermissionViewHistory"  #: May AI chat view command history?  Takes an integer.  0=Ask each time, 1=Always allow, 2=Never allow.
    AI_PERMISSION_WRITE_TO_CLIPBOARD = "AIPermissionWriteToClipboard"  #: May AI chat write to the clipboard?  Takes an integer.  0=Ask each time, 1=Always allow, 2=Never allow.
    AI_PERMISSION_CONTROL_TERMINAL = "AIPermissionTypeForYou"  #: May AI chat type into the terminal for you?  Takes an integer.  0=Ask each time, 1=Always allow, 2=Never allow.
    AI_PERMISSION_VIEW_MANPAGES = "AIPermissionViewManpages"  #: May AI chat view man pages?  Takes an integer.  0=Ask each time, 1=Always allow, 2=Never allow.
    AI_PERMISSION_WRITE_TO_FILESYSTEM = "AIPermissionWriteToFilesystem"  #: May AI chat write to the filesystem?  Takes an integer.  0=Ask each time, 1=Always allow, 2=Never allow.
    AI_PERMISSION_ACT_IN_WEB_BROWSER = "AIPermissionActInWebBrowser"  #: May AI chat act in the web browser?  Takes an integer.  0=Ask each time, 1=Always allow, 2=Never allow.


# pylint: enable=line-too-long


async def async_get_preference(
    connection: Connection, key: PreferenceKey
) -> Any | None:
    """
    Gets a preference by key.

    :param key: The preference key, from the `PreferenceKey` enum.
    :returns: An object with the preferences value, or `None` if unset and no
        default exists.
    """
    proto = await _rpc_async_get_preference(connection, key.value)
    j = proto.preferences_response.results[0].get_preference_result.json_value
    return json.loads(j)


async def async_set_preference(
    connection: Connection, key: PreferenceKey | str, value: Any | None
) -> None:
    """
    Set a preference by key.

    :param key: The preference key, either from the `PreferenceKey` enum or a
        string. Note that older versions of the API expect a `str` here. You
        may want to use the `PreferenceKey`'s `value` for backward
        compatibility.
    :param value: An object with the preference value, or `None` to unset.
    """
    key_value = key.value if isinstance(key, PreferenceKey) else key
    proto = await _rpc_async_set_preference(connection, key_value, json.dumps(value))
    status = proto.preferences_response.results[0].set_preference_result.status
    if status == api_pb2.PreferencesResponse.Result.SetPreferenceResult.Status.Value(
        "OK"
    ):
        return
    raise RPCException(
        api_pb2.PreferencesResponse.Result.SetPreferenceResult.Status.Name(status)
    )
