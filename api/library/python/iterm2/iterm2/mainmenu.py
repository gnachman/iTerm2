"""Defines interfaces for accessing menu items."""
import enum
import iterm2.api_pb2
import iterm2.rpc
import typing

class MenuItemException(Exception):
    """A problem was encountered while selecting a menu item."""


class MenuItemState:
    """Describes the current state of a menu item."""
    def __init__(self, checked: bool, enabled: bool):
        self.__checked = checked
        self.__enabled = enabled

    @property
    def checked(self):
        """Is the menu item checked? A `bool` property."""
        return self.__checked

    @property
    def enabled(self):
        """
        Is the menu item enabled (i.e., it can be selected)? A `bool`
        property.
        """
        return self.__enabled

class MenuItemIdentifier:
    def __init__(self, title, identifier):
        self.__title = title
        self.__identifier = identifier

    def __repr__(self):
        return f'[MenuItemIdentifier title={self.title} id={self.identifier}]'

    @property
    def title(self) -> str:
        return self.__title

    @property
    def identifier(self) -> typing.Optional[str]:
        return self.__identifier

    def _encode(self):
        # Encodes to a key binding parameter.
        if self.__identifier is None:
            return self.__title
        return self.__title + "\n" + self.__identifier

class MainMenu:
    """Represents the app's main menu."""

    @staticmethod
    async def async_select_menu_item(connection, identifier: str):
        """Selects a menu item.

        :param identifier: A string. See list of identifiers in :doc:`menu_ids`

        :throws MenuItemException: if something goes wrong.

        .. seealso:: Example ":ref:`zoom_on_screen_example`"
        """
        response = await iterm2.rpc.async_menu_item(
            connection, identifier, False)
        status = response.menu_item_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.MenuItemResponse.Status.Value("OK"):
            raise MenuItemException(
                iterm2.api_pb2.MenuItemResponse.Status.Name(status))

    @staticmethod
    async def async_get_menu_item_state(
            connection, identifier: str) -> MenuItemState:
        """Queries a menu item for its state.

        :param identifier: A string. See list of identifiers in :doc:`menu_ids`

        :throws MenuItemException: if something goes wrong.
        """
        response = await iterm2.rpc.async_menu_item(
            connection, identifier, True)
        status = response.menu_item_response.status
        # pylint: disable=no-member
        if status != iterm2.api_pb2.MenuItemResponse.Status.Value("OK"):
            raise MenuItemException(
                iterm2.api_pb2.MenuItemResponse.Status.Name(status))
        return iterm2.MenuItemState(
            response.menu_item_response.checked,
            response.menu_item_response.enabled)

    class iTerm2(enum.Enum):
        ABOUT_ITERM2 = MenuItemIdentifier("About iTerm2", "About iTerm2")
        SHOW_TIP_OF_THE_DAY = MenuItemIdentifier("Show Tip of the Day", "Show Tip of the Day")
        CHECK_FOR_UPDATES = MenuItemIdentifier("Check For Updates…", "Check For Updates…")
        TOGGLE_DEBUG_LOGGING = MenuItemIdentifier("Toggle Debug Logging", "Toggle Debug Logging")
        COPY_PERFORMANCE_STATS = MenuItemIdentifier("Copy Performance Stats", "Copy Performance Stats")
        CAPTURE_GPU_FRAME = MenuItemIdentifier("Capture GPU Frame", "Capture Metal Frame")
        PREFERENCES = MenuItemIdentifier("Preferences...", "Preferences...")
        HIDE_ITERM2 = MenuItemIdentifier("Hide iTerm2", "Hide iTerm2")
        HIDE_OTHERS = MenuItemIdentifier("Hide Others", "Hide Others")
        SHOW_ALL = MenuItemIdentifier("Show All", "Show All")
        SECURE_KEYBOARD_ENTRY = MenuItemIdentifier("Secure Keyboard Entry", "Secure Keyboard Entry")
        MAKE_ITERM2_DEFAULT_TERM = MenuItemIdentifier("Make iTerm2 Default Term", "Make iTerm2 Default Term")
        MAKE_TERMINAL_DEFAULT_TERM = MenuItemIdentifier("Make Terminal Default Term", "Make Terminal Default Term")
        INSTALL_SHELL_INTEGRATION = MenuItemIdentifier("Install Shell Integration", "Install Shell Integration")
        QUIT_ITERM2 = MenuItemIdentifier("Quit iTerm2", "Quit iTerm2")

    class Shell(enum.Enum):
        NEW_WINDOW = MenuItemIdentifier("New Window", "New Window")
        NEW_WINDOW_WITH_CURRENT_PROFILE = MenuItemIdentifier("New Window with Current Profile", "New Window with Current Profile")
        NEW_TAB = MenuItemIdentifier("New Tab", "New Tab")
        NEW_TAB_WITH_CURRENT_PROFILE = MenuItemIdentifier("New Tab with Current Profile", "New Tab with Current Profile")
        DUPLICATE_TAB = MenuItemIdentifier("Duplicate Tab", "Duplicate Tab")
        SPLIT_HORIZONTALLY_WITH_CURRENT_PROFILE = MenuItemIdentifier("Split Horizontally with Current Profile", "Split Horizontally with Current Profile")
        SPLIT_VERTICALLY_WITH_CURRENT_PROFILE = MenuItemIdentifier("Split Vertically with Current Profile", "Split Vertically with Current Profile")
        SPLIT_HORIZONTALLY = MenuItemIdentifier("Split Horizontally…", "Split Horizontally…")
        SPLIT_VERTICALLY = MenuItemIdentifier("Split Vertically…", "Split Vertically…")
        SAVE_SELECTED_TEXT = MenuItemIdentifier("Save Selected Text…", "Save Selected Text…")
        CLOSE = MenuItemIdentifier("Close", "Close")
        CLOSE_TERMINAL_WINDOW = MenuItemIdentifier("Close Terminal Window", "Close Terminal Window")
        CLOSE_ALL_PANES_IN_TAB = MenuItemIdentifier("Close All Panes in Tab", "Close All Panes in Tab")
        UNDO_CLOSE = MenuItemIdentifier("Undo Close", "Undo Close")

        class BroadcastInput(enum.Enum):
            SEND_INPUT_TO_CURRENT_SESSION_ONLY = MenuItemIdentifier("Send Input to Current Session Only", "Broadcast Input.Send Input to Current Session Only")
            BROADCAST_INPUT_TO_ALL_PANES_IN_ALL_TABS = MenuItemIdentifier("Broadcast Input to All Panes in All Tabs", "Broadcast Input.Broadcast Input to All Panes in All Tabs")
            BROADCAST_INPUT_TO_ALL_PANES_IN_CURRENT_TAB = MenuItemIdentifier("Broadcast Input to All Panes in Current Tab", "Broadcast Input.Broadcast Input to All Panes in Current Tab")
            TOGGLE_BROADCAST_INPUT_TO_CURRENT_SESSION = MenuItemIdentifier("Toggle Broadcast Input to Current Session", "Broadcast Input.Toggle Broadcast Input to Current Session")
            SHOW_BACKGROUND_PATTERN_INDICATOR = MenuItemIdentifier("Show Background Pattern Indicator", "Broadcast Input.Show Background Pattern Indicator")


        class tmux(enum.Enum):
            DETACH = MenuItemIdentifier("Detach", "tmux.Detach")
            FORCE_DETACH = MenuItemIdentifier("Force Detach", "tmux.Force Detach")
            NEW_TMUX_WINDOW = MenuItemIdentifier("New Tmux Window", "tmux.New Tmux Window")
            NEW_TMUX_TAB = MenuItemIdentifier("New Tmux Tab", "tmux.New Tmux Tab")
            PAUSE_PANE = MenuItemIdentifier("Pause Pane", "trmux.Pause Pane")
            DASHBOARD = MenuItemIdentifier("Dashboard", "tmux.Dashboard")

        PAGE_SETUP = MenuItemIdentifier("Page Setup...", "Page Setup...")

        class Print(enum.Enum):
            SCREEN = MenuItemIdentifier("Screen", "Print.Screen")
            SELECTION = MenuItemIdentifier("Selection", "Print.Selection")
            BUFFER = MenuItemIdentifier("Buffer", "Print.Buffer")


    class Edit(enum.Enum):
        UNDO = MenuItemIdentifier("Undo", "Undo")
        REDO = MenuItemIdentifier("Redo", "Redo")
        CUT = MenuItemIdentifier("Cut", "Cut")
        COPY = MenuItemIdentifier("Copy", "Copy")
        COPY_WITH_STYLES = MenuItemIdentifier("Copy with Styles", "Copy with Styles")
        COPY_WITH_CONTROL_SEQUENCES = MenuItemIdentifier("Copy with Control Sequences", "Copy with Control Sequences")
        COPY_MODE = MenuItemIdentifier("Copy Mode", "Copy Mode")
        PASTE = MenuItemIdentifier("Paste", "Paste")

        class PasteSpecial(enum.Enum):
            ADVANCED_PASTE = MenuItemIdentifier("Advanced Paste…", "Paste Special.Advanced Paste…")
            PASTE_SELECTION = MenuItemIdentifier("Paste Selection", "Paste Special.Paste Selection")
            PASTE_FILE_BASE64ENCODED = MenuItemIdentifier("Paste File Base64-Encoded", "Paste Special.Paste File Base64-Encoded")
            PASTE_SLOWLY = MenuItemIdentifier("Paste Slowly", "Paste Special.Paste Slowly")
            PASTE_FASTER = MenuItemIdentifier("Paste Faster", "Paste Special.Paste Faster")
            PASTE_SLOWLY_FASTER = MenuItemIdentifier("Paste Slowly Faster", "Paste Special.Paste Slowly Faster")
            PASTE_SLOWER = MenuItemIdentifier("Paste Slower", "Paste Special.Paste Slower")
            PASTE_SLOWLY_SLOWER = MenuItemIdentifier("Paste Slowly Slower", "Paste Special.Paste Slowly Slower")
            WARN_BEFORE_MULTILINE_PASTE = MenuItemIdentifier("Warn Before Multi-Line Paste", "Paste Special.Warn Before Multi-Line Paste")
            PROMPT_TO_CONVERT_TABS_TO_SPACES_WHEN_PASTING = MenuItemIdentifier("Prompt to Convert Tabs to Spaces when Pasting", "Paste Special.Prompt to Convert Tabs to Spaces when Pasting")
            LIMIT_MULTILINE_PASTE_WARNING_TO_SHELL_PROMPT = MenuItemIdentifier("Limit Multi-Line Paste Warning to Shell Prompt", "Paste Special.Limit Multi-Line Paste Warning to Shell Prompt")
            WARN_BEFORE_PASTING_ONE_LINE_ENDING_IN_A_NEWLINE_AT_SHELL_PROMPT = MenuItemIdentifier("Warn Before Pasting One Line Ending in a Newline at Shell Prompt", "Paste Special.Warn Before Pasting One Line Ending in a Newline at Shell Prompt")

        OPEN_SELECTION = MenuItemIdentifier("Open Selection", "Open Selection")
        JUMP_TO_SELECTION = MenuItemIdentifier("Jump to Selection", "Find.Jump to Selection")
        SELECT_ALL = MenuItemIdentifier("Select All", "Select All")
        SELECTION_RESPECTS_SOFT_BOUNDARIES = MenuItemIdentifier("Selection Respects Soft Boundaries", "Selection Respects Soft Boundaries")
        SELECT_OUTPUT_OF_LAST_COMMAND = MenuItemIdentifier("Select Output of Last Command", "Select Output of Last Command")
        SELECT_CURRENT_COMMAND = MenuItemIdentifier("Select Current Command", "Select Current Command")

        class Find(enum.Enum):
            FIND = MenuItemIdentifier("Find...", "Find.Find...")
            FIND_NEXT = MenuItemIdentifier("Find Next", "Find.Find Next")
            FIND_PREVIOUS = MenuItemIdentifier("Find Previous", "Find.Find Previous")
            USE_SELECTION_FOR_FIND = MenuItemIdentifier("Use Selection for Find", "Find.Use Selection for Find")
            FIND_GLOBALLY = MenuItemIdentifier("Find Globally...", "Find.Find Globally...")
            FIND_URLS = MenuItemIdentifier("Find URLs", "Find.Find URLs")


        class MarksandAnnotations(enum.Enum):
            SET_MARK = MenuItemIdentifier("Set Mark", "Marks and Annotations.Set Mark")
            JUMP_TO_MARK = MenuItemIdentifier("Jump to Mark", "Marks and Annotations.Jump to Mark")
            NEXT_MARK = MenuItemIdentifier("Next Mark", "Marks and Annotations.Next Mark")
            PREVIOUS_MARK = MenuItemIdentifier("Previous Mark", "Marks and Annotations.Previous Mark")
            ADD_ANNOTATION_AT_CURSOR = MenuItemIdentifier("Add Annotation at Cursor", "Marks and Annotations.Add Annotation at Cursor")
            NEXT_ANNOTATION = MenuItemIdentifier("Next Annotation", "Marks and Annotations.Next  Annotation")
            PREVIOUS_ANNOTATION = MenuItemIdentifier("Previous Annotation", "Marks and Annotations.Previous  Annotation")

            class Alerts(enum.Enum):
                ALERT_ON_NEXT_MARK = MenuItemIdentifier("Alert on Next Mark", "Marks and Annotations.Alerts.Alert on Next Mark")
                SHOW_MODAL_ALERT_BOX = MenuItemIdentifier("Show Modal Alert Box", "Marks and Annotations.Alerts.Show Modal Alert Box")
                POST_NOTIFICATION = MenuItemIdentifier("Post Notification", "Marks and Annotations.Alerts.Post Notification")


        CLEAR_BUFFER = MenuItemIdentifier("Clear Buffer", "Clear Buffer")
        CLEAR_SCROLLBACK_BUFFER = MenuItemIdentifier("Clear Scrollback Buffer", "Clear Scrollback Buffer")
        CLEAR_TO_START_OF_SELECTION = MenuItemIdentifier("Clear to Start of Selection", "Clear to Start of Selection")
        CLEAR_TO_LAST_MARK = MenuItemIdentifier("Clear to Last Mark", "Clear to Last Mark")

    class View(enum.Enum):
        SHOW_TABS_IN_FULLSCREEN = MenuItemIdentifier("Show Tabs in Fullscreen", "Show Tabs in Fullscreen")
        TOGGLE_FULL_SCREEN = MenuItemIdentifier("Toggle Full Screen", "Toggle Full Screen")
        USE_TRANSPARENCY = MenuItemIdentifier("Use Transparency", "Use Transparency")
        ZOOM_IN_ON_SELECTION = MenuItemIdentifier("Zoom In on Selection", "Zoom In on Selection")
        ZOOM_OUT = MenuItemIdentifier("Zoom Out", "Zoom Out")
        FIND_CURSOR = MenuItemIdentifier("Find Cursor", "Find Cursor")
        SHOW_CURSOR_GUIDE = MenuItemIdentifier("Show Cursor Guide", "Show Cursor Guide")
        SHOW_TIMESTAMPS = MenuItemIdentifier("Show Timestamps", "Show Timestamps")
        SHOW_ANNOTATIONS = MenuItemIdentifier("Show Annotations", "Show Annotations")
        AUTO_COMMAND_COMPLETION = MenuItemIdentifier("Auto Command Completion", "Auto Command Completion")
        COMPOSER = MenuItemIdentifier("Composer", "Composer")
        OPEN_QUICKLY = MenuItemIdentifier("Open Quickly", "Open Quickly")
        MAXIMIZE_ACTIVE_PANE = MenuItemIdentifier("Maximize Active Pane", "Maximize Active Pane")
        MAKE_TEXT_BIGGER = MenuItemIdentifier("Make Text Bigger", "Make Text Bigger")
        MAKE_TEXT_NORMAL_SIZE = MenuItemIdentifier("Make Text Normal Size", "Make Text Normal Size")
        RESTORE_TEXT_AND_SESSION_SIZE = MenuItemIdentifier("Restore Text and Session Size", "Restore Text and Session Size")
        MAKE_TEXT_SMALLER = MenuItemIdentifier("Make Text Smaller", "Make Text Smaller")
        SIZE_CHANGES_UPDATE_PROFILE = MenuItemIdentifier("Size Changes Update Profile", "Size Changes Update Profile")
        START_INSTANT_REPLAY = MenuItemIdentifier("Start Instant Replay", "Start Instant Replay")

    class Session(enum.Enum):
        EDIT_SESSION = MenuItemIdentifier("Edit Session…", "Edit Session…")
        RUN_COPROCESS = MenuItemIdentifier("Run Coprocess…", "Run Coprocess…")
        STOP_COPROCESS = MenuItemIdentifier("Stop Coprocess", "Stop Coprocess")
        RESTART_SESSION = MenuItemIdentifier("Restart Session", "Restart Session")
        OPEN_AUTOCOMPLETE = MenuItemIdentifier("Open Autocomplete…", "Open Autocomplete…")
        OPEN_COMMAND_HISTORY = MenuItemIdentifier("Open Command History…", "Open Command History…")
        OPEN_RECENT_DIRECTORIES = MenuItemIdentifier("Open Recent Directories…", "Open Recent Directories…")
        OPEN_PASTE_HISTORY = MenuItemIdentifier("Open Paste History…", "Open Paste History…")

        class Triggers(enum.Enum):
            ADD_TRIGGER = MenuItemIdentifier("Add Trigger…", "Add Trigger")
            EDIT_TRIGGERS = MenuItemIdentifier("Edit Triggers", "Edit Triggers")
            ENABLE_TRIGGERS_IN_INTERACTIVE_APPS = MenuItemIdentifier("Enable Triggers in Interactive Apps", "Enable Triggers in Interactive Apps")
            ENABLE_ALL = MenuItemIdentifier("Enable All", "Triggers.Enable All")
            DISABLE_ALL = MenuItemIdentifier("Disable All", "Triggers.Disable All")

        RESET = MenuItemIdentifier("Reset", "Reset")
        RESET_CHARACTER_SET = MenuItemIdentifier("Reset Character Set", "Reset Character Set")

        class Log(enum.Enum):
            LOG_TO_FILE = MenuItemIdentifier("Log to File", "Log.Toggle")
            IMPORT_RECORDING = MenuItemIdentifier("Import Recording", "Log.ImportRecording")
            EXPORT_RECORDING = MenuItemIdentifier("Export Recording", "Log.ExportRecording")
            SAVE_CONTENTS = MenuItemIdentifier("Save Contents…", "Log.SaveContents")


        class TerminalState(enum.Enum):
            ALTERNATE_SCREEN = MenuItemIdentifier("Alternate Screen", "Alternate Screen")
            FOCUS_REPORTING = MenuItemIdentifier("Focus Reporting", "Focus Reporting")
            MOUSE_REPORTING = MenuItemIdentifier("Mouse Reporting", "Mouse Reporting")
            PASTE_BRACKETING = MenuItemIdentifier("Paste Bracketing", "Paste Bracketing")
            APPLICATION_CURSOR = MenuItemIdentifier("Application Cursor", "Application Cursor")
            APPLICATION_KEYPAD = MenuItemIdentifier("Application Keypad", "Application Keypad")
            STANDARD_KEY_REPORTING_MODE = MenuItemIdentifier("Standard Key Reporting Mode", "Terminal State.Standard Key Reporting")
            MODIFYOTHERKEYS_MODE_1 = MenuItemIdentifier("modifyOtherKeys Mode 1", "Terminal State.Report Modifiers like xterm 1")
            MODIFYOTHERKEYS_MODE_2 = MenuItemIdentifier("modifyOtherKeys Mode 2", "Terminal State.Report Modifiers like xterm 2")
            CSI_U_MODE = MenuItemIdentifier("CSI u Mode", "Terminal State.Report Modifiers with CSI u")
            RAW_KEY_REPORTING_MODE = MenuItemIdentifier("Raw Key Reporting Mode", "Terminal State.Raw Key Reporting")
            RESET = MenuItemIdentifier("Reset", "Reset Terminal State")

        BURY_SESSION = MenuItemIdentifier("Bury Session", "Bury Session")

    class Scripts(enum.Enum):
        class Manage(enum.Enum):
            NEW_PYTHON_SCRIPT = MenuItemIdentifier("New Python Script", "New Python Script")
            OPEN_PYTHON_REPL = MenuItemIdentifier("Open Python REPL", "Open Interactive Window")
            MANAGE_DEPENDENCIES = MenuItemIdentifier("Manage Dependencies…", "Manage Dependencies")
            INSTALL_PYTHON_RUNTIME = MenuItemIdentifier("Install Python Runtime", "Install Python Runtime")
            REVEAL_SCRIPTS_IN_FINDER = MenuItemIdentifier("Reveal Scripts in Finder", "Reveal in Finder")
            IMPORT = MenuItemIdentifier("Import…", "Import Script")
            EXPORT = MenuItemIdentifier("Export…", "Export Script")
            CONSOLE = MenuItemIdentifier("Console", "Script Console")


    class Profiles(enum.Enum):
        OPEN_PROFILES = MenuItemIdentifier("Open Profiles…", "Open Profiles…")
        PRESS_OPTION_FOR_NEW_WINDOW = MenuItemIdentifier("Press Option for New Window", "Press Option for New Window")
        OPEN_IN_NEW_WINDOW = MenuItemIdentifier("Open In New Window", "Open In New Window")

    class Toolbelt(enum.Enum):
        SHOW_TOOLBELT = MenuItemIdentifier("Show Toolbelt", "Show Toolbelt")
        SET_DEFAULT_WIDTH = MenuItemIdentifier("Set Default Width", "Set Default Width")

    class Window(enum.Enum):
        MINIMIZE = MenuItemIdentifier("Minimize", "Minimize")
        ZOOM = MenuItemIdentifier("Zoom", "Zoom")
        EDIT_TAB_TITLE = MenuItemIdentifier("Edit Tab Title", "Edit Tab Title")
        EDIT_WINDOW_TITLE = MenuItemIdentifier("Edit Window Title", "Edit Window Title")

        class WindowStyle(enum.Enum):
            NORMAL = MenuItemIdentifier("Normal", "Window Style.Normal")
            FULL_SCREEN = MenuItemIdentifier("Full Screen", "Window Style.Full Screen")
            MAXIMIZED = MenuItemIdentifier("Maximized", "Window Style.Maximized")
            NO_TITLE_BAR = MenuItemIdentifier("No Title Bar", "Window Style.No Title Bar")
            FULLWIDTH_BOTTOM_OF_SCREEN = MenuItemIdentifier("Full-Width Bottom of Screen", "Window Style.FullWidth Bottom of Screen")
            FULLWIDTH_TOP_OF_SCREEN = MenuItemIdentifier("Full-Width Top of Screen", "Window Style.FullWidth Top of Screen")
            FULLHEIGHT_LEFT_OF_SCREEN = MenuItemIdentifier("Full-Height Left of Screen", "Window Style..FullHeight Left of Screen")
            FULLHEIGHT_RIGHT_OF_SCREEN = MenuItemIdentifier("Full-Height Right of Screen", "Window Style.FullHeight Right of Screen")
            BOTTOM_OF_SCREEN = MenuItemIdentifier("Bottom of Screen", "Window Style.Bottom of Screen")
            TOP_OF_SCREEN = MenuItemIdentifier("Top of Screen", "Window Style.Top of Screen")
            LEFT_OF_SCREEN = MenuItemIdentifier("Left of Screen", "Window Style.Left of Screen")
            RIGHT_OF_SCREEN = MenuItemIdentifier("Right of Screen", "Window Style.Right of Screen")

        MERGE_ALL_WINDOWS = MenuItemIdentifier("Merge All Windows", "Merge All Windows")
        ARRANGE_WINDOWS_HORIZONTALLY = MenuItemIdentifier("Arrange Windows Horizontally", "Arrange Windows Horizontally")
        ARRANGE_SPLIT_PANES_EVENLY = MenuItemIdentifier("Arrange Split Panes Evenly", "Arrange Split Panes Evenly")
        MOVE_SESSION_TO_WINDOW = MenuItemIdentifier("Move Session to Window", "Move Session to Window")
        SAVE_WINDOW_ARRANGEMENT = MenuItemIdentifier("Save Window Arrangement", "Save Window Arrangement")
        SAVE_CURRENT_WINDOW_AS_ARRANGEMENT = MenuItemIdentifier("Save Current Window as Arrangement", "Save Current Window as Arrangement")

        class SelectSplitPane(enum.Enum):
            SELECT_PANE_ABOVE = MenuItemIdentifier("Select Pane Above", "Select Split Pane.Select Pane Above")
            SELECT_PANE_BELOW = MenuItemIdentifier("Select Pane Below", "Select Split Pane.Select Pane Below")
            SELECT_PANE_LEFT = MenuItemIdentifier("Select Pane Left", "Select Split Pane.Select Pane Left")
            SELECT_PANE_RIGHT = MenuItemIdentifier("Select Pane Right", "Select Split Pane.Select Pane Right")
            NEXT_PANE = MenuItemIdentifier("Next Pane", "Select Split Pane.Next Pane")
            PREVIOUS_PANE = MenuItemIdentifier("Previous Pane", "Select Split Pane.Previous Pane")


        class ResizeSplitPane(enum.Enum):
            MOVE_DIVIDER_UP = MenuItemIdentifier("Move Divider Up", "Resize Split Pane.Move Divider Up")
            MOVE_DIVIDER_DOWN = MenuItemIdentifier("Move Divider Down", "Resize Split Pane.Move Divider Down")
            MOVE_DIVIDER_LEFT = MenuItemIdentifier("Move Divider Left", "Resize Split Pane.Move Divider Left")
            MOVE_DIVIDER_RIGHT = MenuItemIdentifier("Move Divider Right", "Resize Split Pane.Move Divider Right")


        class ResizeWindow(enum.Enum):
            DECREASE_HEIGHT = MenuItemIdentifier("Decrease Height", "Resize Window.Decrease Height")
            INCREASE_HEIGHT = MenuItemIdentifier("Increase Height", "Resize Window.Increase Height")
            DECREASE_WIDTH = MenuItemIdentifier("Decrease Width", "Resize Window.Decrease Width")
            INCREASE_WIDTH = MenuItemIdentifier("Increase Width", "Resize Window.Increase Width")

        SELECT_NEXT_TAB = MenuItemIdentifier("Select Next Tab", "Select Next Tab")
        SELECT_PREVIOUS_TAB = MenuItemIdentifier("Select Previous Tab", "Select Previous Tab")
        MOVE_TAB_LEFT = MenuItemIdentifier("Move Tab Left", "Move Tab Left")
        MOVE_TAB_RIGHT = MenuItemIdentifier("Move Tab Right", "Move Tab Right")
        PASSWORD_MANAGER = MenuItemIdentifier("Password Manager", "Password Manager")
        PIN_HOTKEY_WINDOW = MenuItemIdentifier("Pin Hotkey Window", "Pin Hotkey Window")
        BRING_ALL_TO_FRONT = MenuItemIdentifier("Bring All To Front", "Bring All To Front")

    class Help(enum.Enum):
        ITERM2_HELP = MenuItemIdentifier("iTerm2 Help", "iTerm2 Help")
        COPY_MODE_SHORTCUTS = MenuItemIdentifier("Copy Mode Shortcuts", "Copy Mode Shortcuts")
        OPEN_SOURCE_LICENSES = MenuItemIdentifier("Open Source Licenses", "Open Source Licenses")
        GPU_RENDERER_AVAILABILITY = MenuItemIdentifier("GPU Renderer Availability", "GPU Renderer Availability")

