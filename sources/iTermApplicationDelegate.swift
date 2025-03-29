//
//  iTermApplicationDelegate.swift
//  iTerm2
//
//  Created by George Nachman on 3/28/25.
//

@objc
extension iTermApplicationDelegate {
    @objc
    func registerMenuTips() {
        struct Tip {
            var identifier: String
            var imageName: String?
            var text: String
        }

        let toolbeltText = """
        The **Toolbelt** provides a versatile, dockable sidebar that offers quick access to frequently used features and information. It supports multiple panels that can be displayed simultaneously, including clipboard history, recently opened directories, command history, a scratchpad for notes, and more.
        """

        let tips = [
            Tip(identifier: "Toolbelt",
                imageName: "Toolbelt-Screenshot",
                text: toolbeltText),
            Tip(identifier: "Show Toolbelt",
                imageName: "Toolbelt-Screenshot",
                text: toolbeltText),
            Tip(identifier: "Split Vertically with Current Profile",
                imageName: "VerticalSplit",
                text: "Splits the current session vertically, placing a new session in the right half. The new session inherits the profile of the current session, including any changes made in `Session > Edit Session`."),
            Tip(identifier: "Split Horizontally with Current Profile",
                imageName: "HorizontalSplit",
                text: "Splits the current session horizontally, placing a new session in the bottom half. The new session inherits the profile of the current session, including any changes made in `Session > Edit Session`."),
            Tip(identifier: "Split Vertically…",
                imageName: "VerticalSplit",
                text: "Prompts you to select a profile and then splits the current session vertically, placing the new session in the right half."),
            Tip(identifier: "Split Horizontally…",
                imageName: "HorizontalSplit",
                text: "Prompts you to select a profile and then splits the current session horizontally, placing the new session in the bottom half."),
            Tip(identifier: "tmux.Dashboard",
                imageName: "TmuxDashboard",
                text: "The **tmux Dashboard** helps you switch between tmux sessions, show and hide windows, and administer other features of tmux without needing to use tmux’s commands."),
            Tip(identifier: "Paste Special.Advanced Paste…",
                imageName: "AdvancedPaste",
                text: "**Advanced Paste** lets you edit text before pasting, remove control characters, convert tabs, base64-encode, and perform regular expression substitutions. It also lets you fine-tune how quickly pasted text is sent."),
            Tip(identifier: "Render Selection Natively",
                imageName: "RenderNatively",
                text: "**Render Natively** shows a nicely formatted, syntax-highlighted rendition of a document. For example, Markdown renders beautifully. It also allows for horizontal scrolling, making it a convenient way to view log files."),
            Tip(identifier: "Paste Special.Warn Before Multi-Line Paste",
                text: "You’ll be prompted any time you paste text containing a newline. See also **Limit Multi-Line Paste Warning to Shell Prompt**."),
            Tip(identifier: "Paste Special.Limit Multi-Line Paste Warning to Shell Prompt",
                text: "This is effective only when **Warn Before Multi-Line Paste** is enabled. It also requires Shell Integration. When enabled, it suppresses confirmation when pasting text containing a newline if you are not at a shell prompt."),
            Tip(identifier: "Paste Special.Warn Before Pasting One Line Ending in a Newline at Shell Prompt",
                text: "If enabled, you’ll be prompted to confirm that you wish to send a newline when pasting a single line of text ending in a newline. Shell Integration is required."),
            Tip(identifier: "Engage Artificial Intelligence",
                imageName: "AIMenuTip",
                text: "When selected at a shell prompt (provided Shell Integration is installed) or in the Composer, it sends the current command to the configured AI system along with a prompt for it to generate a command. If no input is provided, you’ll be asked to give instructions. The generated command goes into the Composer."),
            Tip(identifier: "Explain Output with AI",
                imageName: "AIExplainTip",
                text: "This is meant to be used at the shell prompt after executing a command. It requires Shell Integration. The output of the preceding (or selected) command is sent to AI, which annotates the output and opens a chat window for further discussion."),
            Tip(identifier: "Edit.Snippets",
                imageName: "SnippetsTip",
                text: "Snippets are pieces of text that you save to reuse later. They’re great for frequently used commands, hard-to-remember directories, and much more."),
            Tip(identifier: "Edit.Actions",
                imageName: "ActionsMenuTip",
                text: "Actions are saved instructions for iTerm2. For example, you could create an action that opens a new window and then creates a split pane."),
            Tip(identifier: "Set Default Width",
                text: "Records the current width of the toolbelt for use in newly created windows."),
            Tip(identifier: "Toolbelt.Actions",
                imageName: "ActionsMenuTip",
                text: "Actions are saved instructions for iTerm2. For example, you could create an action that opens a new window and then creates a split pane."),
            Tip(identifier: "Selection Respects Soft Boundaries",
                imageName: "SelectionRespectsSoftBoundariesMenuTip",
                text: "When enabled, dividers rendered by programs like vim or emacs are detected, and text selection wraps around them."),
            Tip(identifier: "Find.Filter",
                imageName: "FilterMenuTip",
                text: "**Filter** allows you to hide any lines that do not match a search query, which can be a substring or regular expression. It updates live as new text arrives."),
            Tip(identifier: "Marks and Annotations.Set Mark",
                text: "A **Mark** appears as a blue triangle in the left margin. You can easily navigate among marks using **Jump to Mark**, **Next Mark**, and **Previous Mark**. If Shell Integration is enabled, a Mark is automatically added at each shell prompt."),
            Tip(identifier: "Set Named Mark",
                text: "A **Named Mark** appears as a blue triangle in the left margin. In addition to being easy to navigate with **Next Mark** and **Previous Mark**, you can also find Named Marks in the Toolbelt’s **Named Marks** tool."),
            Tip(identifier: "Toolbelt.Named Marks",
                text: "A **Named Mark** appears as a blue triangle in the left margin. In addition to being easy to navigate with **Next Mark** and **Previous Mark**, you can also find Named Marks in this Toolbelt tool."),
            Tip(identifier: "Fold Selected Lines",
                imageName: "FoldMenuTip",
                text: "**Fold** lets you collapse multiple lines into a single line to hide distracting text. You can always unfold it by clicking the arrow in the margin, selecting the text and using **Edit > Unfold in Selection**, or right-clicking and choosing **Unfold**."),
            Tip(identifier: "Toolbelt.Captured Output",
                imageName: "CapturedOutputMenuTip",
                text: "**Captured Output** works in conjunction with a Trigger to detect interesting text in the terminal and make it easy to find. The Toolbelt tool shows a list of captured text. You can click to navigate to it or double-click to enter a programmable command. This is useful for finding errors in the output of a build command, for example. It requires Shell Integration."),
            Tip(identifier: "Toolbelt.Codecierge",
                imageName: "CodeciergeMenuTip",
                text: "**Codecierge** uses AI to help you achieve a goal. Tell it what you want to do, and it can watch your terminal to interpret output and suggest commands. Shell Integration is required."),
            Tip(identifier: "Toolbelt.Command History",
                text: "If Shell Integration is installed, **Command History** shows a searchable list of recently run commands on the current host."),
            Tip(identifier: "Toolbelt.Notes",
                imageName: "NotesMenuTip",
                text: "**Notes** is a single, persistent notepad in your Toolbelt. It’s useful for keeping track of what you’re doing or composing messages."),
            Tip(identifier: "Toolbelt.Paste History",
                text: "**Paste History** shows text that you have copied and pasted in iTerm2. You can configure it to be saved long term."),
            Tip(identifier: "Toolbelt.Profiles",
                text: "Shows a list of your profiles so you can create new sessions easily."),
            Tip(identifier: "Toolbelt.Recent Directories",
                text: "Shows your most used directories, sorted by a combination of frequency and recency of use. Requires Shell Integration."),
            Tip(identifier: "Toolbelt.Snippets",
                imageName: "SnippetsTip",
                text: "Snippets are pieces of text that you save to reuse later. They’re great for frequently used commands, hard-to-remember directories, and much more."),
            Tip(identifier: "Zoom In on Selection",
                text: "Hides everything except the lines of selected text to remove distractions."),
            Tip(identifier: "Find Cursor",
                imageName: "FindCursorMenuTip",
                text: "Highlights the location of the cursor and unhides it if it is currently hidden."),
            Tip(identifier: "Show Annotations",
                imageName: "AnnotationsMenuTip",
                text: "Annotations are inline markup. When closed, they appear as a yellow underline; when open, they look like yellow stickies where you can write memos about content in the terminal window."),
            Tip(identifier: "Composer",
                imageName: "ComposerMenuTip",
                text: "The Composer is a window within the terminal where you can edit text using macOS-native controls. It does syntax highlighting, command and filename completion—even over SSH (provided you use SSH Integration). If AI features are enabled, you can also get AI-powered suggestions. You can even have multiple cursors! When you're ready, you can send the whole buffer or just a line at a time to your shell."),
            Tip(identifier: "Auto Composer",
                imageName: "AutoComposerMenuTip",
                text: "**Auto Composer** replaces your shell prompt with a macOS-native text field. It does syntax highlighting and command and filename completion. You can also enable AI-powered suggestions. Shell Integration is required."),
            Tip(identifier: "Open Quickly",
                imageName: "OpenQuicklyMenuTip",
                text: "**Open Quickly** provides quick access to many common actions. You can use it to find a session by typing its name, directory, hostname, or recent command. You can also use it to switch profiles or create a new window by typing the name of a profile. Restore an arrangement by entering its name. Press `/` to get tips for quick commands."),
            Tip(identifier: "Start Instant Replay",
                imageName: "InstantReplayMenuTip",
                text: "**Instant Replay** lets you review recent terminal history. It’s handy if something just disappeared from the screen and it isn’t in scrollback history."),
            Tip(identifier: "Run Coprocess…",
                imageName: "CoprocessMenuTip",
                text: "A **Coprocess** is a program that automates interactions in the terminal. Input to the terminal is redirected to stdin of the coprocess, and its output is sent back to the terminal as though the coprocess were typing."),
            Tip(identifier: "Stop Coprocess",
                imageName: "CoprocessMenuTip",
                text: "Stops the active coprocess. Input to the terminal is no longer redirected to the coprocess, and its output ceases."),
            Tip(identifier: "Triggers",
                imageName: "TriggersMenuTip",
                text: "**Triggers** are actions the terminal performs automatically when text matching a regular expression is received. For example, you can highlight text or display an alert."),
            Tip(identifier: "Terminal State.Literal Mode",
                text: "When enabled, control characters are displayed visually rather than being interpreted as usual."),
            Tip(identifier: "Terminal State.Report Modifiers with CSI u",
                text: "This mode is generally not recommended. **Disambiguate Escape** is a more modern approach."),
            Tip(identifier: "Bury Session",
                imageName: "BurySessionMenuTip",
                text: "Buried sessions are hidden in the **Buried Sessions** menu below and do not appear in any window. These are particularly useful for the session where you initiate tmux integration by running `tmux -CC`."),
            Tip(identifier: "Open Interactive Window",
                text: "The Python REPL opens a window running a special Python interpreter that lets you experiment with iTerm2’s Python API. You can use `await` at the top level of the interpreter."),
            Tip(identifier: "Manage Dependencies",
                text: "Opens a UI where you can add, update, or remove pip dependencies of a Python API script."),
            Tip(identifier: "Install Python Runtime",
                text: "iTerm2’s Python Runtime is a large binary package (hundreds of MBs) that enables the Python API by installing a pre-built Python environment that scripts can use."),
            Tip(identifier: "Import Script",
                text: "Use **Import** to install scripts others have shared with you. These scripts have the `.its` extension."),
            Tip(identifier: "Export Script",
                text: "If you want to share Python API scripts, you can export them to an `.its` file. If you have a code signing certificate and private key in your Keychain, you can also sign the `.its` file."),
            Tip(identifier: "Script Console",
                text: "View errors and low-level communication between Python API scripts and iTerm2 here.\n\nThe Inspector can be accessed from the Console. It allows you to browse variables in sessions, tabs, and windows."),
            Tip(identifier: "Arrangements",
                imageName: "ArrangementsMenuTip",
                text: "**Window Arrangements** are a saved record of one or more windows, their tabs, and split panes, including how each pane is configured. They do not include content. They’re a quick way to create a working environment with multiple sessions in various configurations."),
            Tip(identifier: "Password Manager",
                imageName: "PasswordManagerMenuTip",
                text: "The **Password Manager** helps you keep track of your passwords securely. By default, it stores them in the macOS Keychain, but it can also use 1Password or LastPass."),
            Tip(identifier: "AI Chats",
                imageName: "AIChatMenuTip",
                text: "**AI Chats** opens a chat window where you can interact with AI. It can optionally view and control the terminal if you grant it permission."),
            Tip(identifier: "Pin Hotkey Window",
                text: "A **pinned** Hotkey Window does not close automatically when it loses keyboard focus."),
            Tip(identifier: "GPU Renderer Availability",
                text: "Checks whether the GPU Renderer is currently being used in the active session. This is sometimes useful for debugging."),
            Tip(identifier: "Secure Keyboard Entry",
                text: "**Secure Keyboard Entry** prevents other programs from intercepting your keystrokes in the terminal. However, it also breaks some functionality: other programs cannot activate their windows while this is enabled. For example, the `open` command will still open an app, but it won’t be activated."),
            Tip(identifier: "Install Shell Integration",
                text: "**Shell Integration** consists of shell scripts that run when you log in. They inform iTerm2 of where your shell prompt is. This enables dozens of useful features such as command history, directory history, AI features, and more."),
            Tip(identifier: "Toggle Debug Logging",
                text: "Debug logs are saved in memory while this setting is enabled and written to `/tmp/debuglog.txt` when you turn it off. They use a circular buffer, so no more than 200MB of memory will ever be used by debug logs."),
            Tip(identifier: "Broadcast Input.Broadcast Input to All Panes in All Tabs",
                text: "When enabled, anything you type in this window is sent to all sessions in this window."),
            Tip(identifier: "Broadcast Input.Broadcast Input to All Panes in Current Tab",
                text: "When enabled, anything you type in this tab is sent to all sessions in this tab."),
            Tip(identifier: "Broadcast Input.Toggle Broadcast Input to Current Session",
                text: "Adds or removes this session from the set of sessions in this window that have broadcast enabled. When you type in a session with broadcast enabled, the keystrokes are sent to all other sessions in the same window that have broadcast enabled."),
            Tip(identifier: "Broadcast Input.Show Background Pattern Indicator",
                imageName: "BroadcastStripesMenuTip",
                text: "When enabled, prominent red lines are drawn in the background to indicate that text you type is being broadcast to other sessions.")
        ]
        var index = [String: NSMenuItem]()
        func makeIndex(menu: NSMenu) {
            for item in menu.items {
                if let identifier = item.identifier?.rawValue, !identifier.isEmpty {
                    index[identifier] = item
                }
                if let sub = item.submenu {
                    makeIndex(menu: sub)
                }
            }
        }
        makeIndex(menu: NSApp.mainMenu!)
        let controller = MenuItemTipController.instance
        for tip in tips {
            let item = index[tip.identifier]!
            controller.registerTip(forMenuItem: item,
                                   image: tip.imageName.map { NSImage.it_imageNamed($0, for: Self.self) },
            attributedString: NSAttributedString.attributedString(markdown: tip.text,
                                                                  font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                                                                  paragraphStyle: NSParagraphStyle.default)!)
        }
    }
}
