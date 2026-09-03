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
        guard let mainMenu = NSApp.mainMenu else {
            return
        }
        struct Tip {
            var identifier: String
            var imageName: String?
            var text: String
        }

        let toolbeltText = String(localized: "TOOLBELT_TIP", defaultValue: """
        The **Toolbelt** provides a versatile, dockable sidebar that offers quick access to frequently used features and information. It supports multiple panels that can be displayed simultaneously, including clipboard history, recently opened directories, command history, a scratchpad for notes, and more.
        """, comment: "Tip describing the Toolbelt and the panels that it provides")

        let tips = [
            Tip(identifier: "Toolbelt",
                imageName: "Toolbelt-Screenshot",
                text: toolbeltText),
            Tip(identifier: "Show Toolbelt",
                imageName: "Toolbelt-Screenshot",
                text: toolbeltText),
            Tip(identifier: "Split Vertically with Current Profile",
                imageName: "VerticalSplit",
                text: String(localized: "ApplicationDelegate_SplitsTheCurrentSessionVerticallyPlacingA", defaultValue: "Splits the current session vertically, placing a new session in the right half. The new session inherits the profile of the current session, including any changes made in `Session > Edit Session`.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Split Horizontally with Current Profile",
                imageName: "HorizontalSplit",
                text: String(localized: "ApplicationDelegate_SplitsTheCurrentSessionHorizontallyPlacingA", defaultValue: "Splits the current session horizontally, placing a new session in the bottom half. The new session inherits the profile of the current session, including any changes made in `Session > Edit Session`.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Split Vertically…",
                imageName: "VerticalSplit",
                text: String(localized: "ApplicationDelegate_PromptsYouToSelectAProfileAndSplitsVertically", defaultValue: "Prompts you to select a profile and then splits the current session vertically, placing the new session in the right half.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Split Horizontally…",
                imageName: "HorizontalSplit",
                text: String(localized: "ApplicationDelegate_PromptsYouToSelectAProfileAndSplitsHorizontally", defaultValue: "Prompts you to select a profile and then splits the current session horizontally, placing the new session in the bottom half.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "tmux.Dashboard",
                imageName: "TmuxDashboard",
                text: String(localized: "ApplicationDelegate_TheTmuxDashboardHelpsYouSwitchBetween", defaultValue: "The **tmux Dashboard** helps you switch between tmux sessions, show and hide windows, and administer other features of tmux without needing to use tmux’s commands.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Paste Special.Advanced Paste…",
                imageName: "AdvancedPaste",
                text: String(localized: "ApplicationDelegate_AdvancedPasteLetsYouEditTextBefore", defaultValue: "**Advanced Paste** lets you edit text before pasting, remove control characters, convert tabs, base64-encode, and perform regular expression substitutions. It also lets you fine-tune how quickly pasted text is sent.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Render Selection Natively",
                imageName: "RenderNatively",
                text: String(localized: "ApplicationDelegate_RenderNativelyShowsANicelyFormattedSyntax", defaultValue: "**Render Natively** shows a nicely formatted, syntax-highlighted rendition of a document. For example, Markdown renders beautifully. It also allows for horizontal scrolling, making it a convenient way to view log files.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Paste Special.Warn Before Multi-Line Paste",
                text: String(localized: "ApplicationDelegate_YouLlBePromptedAnyTimeYou", defaultValue: "You’ll be prompted any time you paste text containing a newline. See also **Limit Multi-Line Paste Warning to Shell Prompt**.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Paste Special.Limit Multi-Line Paste Warning to Shell Prompt",
                text: String(localized: "ApplicationDelegate_ThisIsEffectiveOnlyWhenWarnBefore", defaultValue: "This is effective only when **Warn Before Multi-Line Paste** is enabled. It also requires Shell Integration. When enabled, it suppresses confirmation when pasting text containing a newline if you are not at a shell prompt.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Paste Special.Warn Before Pasting One Line Ending in a Newline at Shell Prompt",
                text: String(localized: "ApplicationDelegate_IfEnabledYouLlBePromptedTo", defaultValue: "If enabled, you’ll be prompted to confirm that you wish to send a newline when pasting a single line of text ending in a newline. Shell Integration is required.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Engage Artificial Intelligence",
                imageName: "AIMenuTip",
                text: String(localized: "ApplicationDelegate_WhenSelectedAtAShellPromptProvided", defaultValue: "When selected at a shell prompt (provided Shell Integration is installed) or in the Composer, it sends the current command to the configured AI system along with a prompt for it to generate a command. If no input is provided, you’ll be asked to give instructions. The generated command goes into the Composer.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Explain Output with AI",
                imageName: "AIExplainTip",
                text: String(localized: "ApplicationDelegate_ThisIsMeantToBeUsedAt", defaultValue: "This is meant to be used at the shell prompt after executing a command. It requires Shell Integration. The output of the preceding (or selected) command is sent to AI, which annotates the output and opens a chat window for further discussion.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Edit.Snippets",
                imageName: "SnippetsTip",
                text: String(localized: "ApplicationDelegate_SnippetsArePiecesOfTextThatYou", defaultValue: "Snippets are pieces of text that you save to reuse later. They’re great for frequently used commands, hard-to-remember directories, and much more.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Edit.Actions",
                imageName: "ActionsMenuTip",
                text: String(localized: "ApplicationDelegate_ActionsAreSavedInstructionsForITerm2", defaultValue: "Actions are saved instructions for iTerm2. For example, you could create an action that opens a new window and then creates a split pane.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Set Default Width",
                text: String(localized: "ApplicationDelegate_RecordsTheCurrentWidthOfTheToolbelt", defaultValue: "Records the current width of the toolbelt for use in newly created windows.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toolbelt.Actions",
                imageName: "ActionsMenuTip",
                text: String(localized: "ApplicationDelegate_ActionsAreSavedInstructionsForITerm2", defaultValue: "Actions are saved instructions for iTerm2. For example, you could create an action that opens a new window and then creates a split pane.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Selection Respects Soft Boundaries",
                imageName: "SelectionRespectsSoftBoundariesMenuTip",
                text: String(localized: "ApplicationDelegate_WhenEnabledDividersRenderedByProgramsLike", defaultValue: "When enabled, dividers rendered by programs like vim or emacs are detected, and text selection wraps around them.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Find.Filter",
                imageName: "FilterMenuTip",
                text: String(localized: "ApplicationDelegate_FilterAllowsYouToHideAnyLines", defaultValue: "**Filter** allows you to hide any lines that do not match a search query, which can be a substring or regular expression. It updates live as new text arrives.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Marks and Annotations.Set Mark",
                text: String(localized: "ApplicationDelegate_AMarkAppearsAsABlueTriangle", defaultValue: "A **Mark** appears as a blue triangle in the left margin. You can easily navigate among marks using **Jump to Mark**, **Next Mark**, and **Previous Mark**. If Shell Integration is enabled, a Mark is automatically added at each shell prompt.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Set Named Mark",
                text: String(localized: "ApplicationDelegate_ANamedMarkAppearsAsABlue", defaultValue: "A **Named Mark** appears as a blue triangle in the left margin. In addition to being easy to navigate with **Next Mark** and **Previous Mark**, you can also find Named Marks in the Toolbelt’s **Named Marks** tool.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toolbelt.Named Marks",
                text: String(localized: "ApplicationDelegate_ANamedMarkAppearsInThisTool", defaultValue: "A **Named Mark** appears as a blue triangle in the left margin. In addition to being easy to navigate with **Next Mark** and **Previous Mark**, you can also find Named Marks in this Toolbelt tool.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Fold Selected Lines",
                imageName: "FoldMenuTip",
                text: String(localized: "ApplicationDelegate_FoldLetsYouCollapseMultipleLinesInto", defaultValue: "**Fold** lets you collapse multiple lines into a single line to hide distracting text. You can always unfold it by clicking the arrow in the margin, selecting the text and using **Edit > Unfold in Selection**, or right-clicking and choosing **Unfold**.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toolbelt.Captured Output",
                imageName: "CapturedOutputMenuTip",
                text: String(localized: "ApplicationDelegate_CapturedOutputWorksInConjunctionWithA", defaultValue: "**Captured Output** works in conjunction with a Trigger to detect interesting text in the terminal and make it easy to find. The Toolbelt tool shows a list of captured text. You can click to navigate to it or double-click to enter a programmable command. This is useful for finding errors in the output of a build command, for example. It requires Shell Integration.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toolbelt.Codecierge",
                imageName: "CodeciergeMenuTip",
                text: String(localized: "ApplicationDelegate_CodeciergeUsesAiToHelpYouAchieve", defaultValue: "**Codecierge** uses AI to help you achieve a goal. Tell it what you want to do, and it can watch your terminal to interpret output and suggest commands. Shell Integration is required.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toolbelt.Command History",
                text: String(localized: "ApplicationDelegate_IfShellIntegrationIsInstalledCommandHistory", defaultValue: "If Shell Integration is installed, **Command History** shows a searchable list of recently run commands on the current host.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toolbelt.Notes",
                imageName: "NotesMenuTip",
                text: String(localized: "ApplicationDelegate_NotesIsASinglePersistentNotepadIn", defaultValue: "**Notes** is a single, persistent notepad in your Toolbelt. It’s useful for keeping track of what you’re doing or composing messages.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toolbelt.Paste History",
                text: String(localized: "ApplicationDelegate_PasteHistoryShowsTextThatYouHave", defaultValue: "**Paste History** shows text that you have copied and pasted in iTerm2. You can configure it to be saved long term.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toolbelt.Profiles",
                text: String(localized: "ApplicationDelegate_ShowsAListOfYourProfilesSo", defaultValue: "Shows a list of your profiles so you can create new sessions easily.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toolbelt.Recent Directories",
                text: String(localized: "ApplicationDelegate_ShowsYourMostUsedDirectoriesSortedBy", defaultValue: "Shows your most used directories, sorted by a combination of frequency and recency of use. Requires Shell Integration.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toolbelt.Snippets",
                imageName: "SnippetsTip",
                text: String(localized: "ApplicationDelegate_SnippetsArePiecesOfTextThatYou", defaultValue: "Snippets are pieces of text that you save to reuse later. They’re great for frequently used commands, hard-to-remember directories, and much more.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Zoom In on Selection",
                text: String(localized: "ApplicationDelegate_HidesEverythingExceptTheLinesOfSelected", defaultValue: "Hides everything except the lines of selected text to remove distractions.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Find Cursor",
                imageName: "FindCursorMenuTip",
                text: String(localized: "ApplicationDelegate_HighlightsTheLocationOfTheCursorAnd", defaultValue: "Highlights the location of the cursor and unhides it if it is currently hidden.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Show Annotations",
                imageName: "AnnotationsMenuTip",
                text: String(localized: "ApplicationDelegate_AnnotationsAreInlineMarkupWhenClosedThey", defaultValue: "Annotations are inline markup. When closed, they appear as a yellow underline; when open, they look like yellow stickies where you can write memos about content in the terminal window.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Composer",
                imageName: "ComposerMenuTip",
                text: String(localized: "ApplicationDelegate_TheComposerIsAWindowWithinThe", defaultValue: "The Composer is a window within the terminal where you can edit text using macOS-native controls. It does syntax highlighting, command and filename completion—even over SSH (provided you use SSH Integration). If AI features are enabled, you can also get AI-powered suggestions. You can even have multiple cursors! When you're ready, you can send the whole buffer or just a line at a time to your shell.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Auto Composer",
                imageName: "AutoComposerMenuTip",
                text: String(localized: "ApplicationDelegate_AutoComposerReplacesYourShellPromptWith", defaultValue: "**Auto Composer** replaces your shell prompt with a macOS-native text field. It does syntax highlighting and command and filename completion. You can also enable AI-powered suggestions. Shell Integration is required.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Open Quickly",
                imageName: "OpenQuicklyMenuTip",
                text: String(localized: "ApplicationDelegate_OpenQuicklyProvidesQuickAccessToMany", defaultValue: "**Open Quickly** provides quick access to many common actions. You can use it to find a session by typing its name, directory, hostname, or recent command. You can also use it to switch profiles or create a new window by typing the name of a profile. Restore an arrangement by entering its name. Press `/` to get tips for quick commands.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Start Instant Replay",
                imageName: "InstantReplayMenuTip",
                text: String(localized: "ApplicationDelegate_InstantReplayLetsYouReviewRecentTerminal", defaultValue: "**Instant Replay** lets you review recent terminal history. It’s handy if something just disappeared from the screen and it isn’t in scrollback history.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Run Coprocess…",
                imageName: "CoprocessMenuTip",
                text: String(localized: "ApplicationDelegate_ACoprocessIsAProgramThatAutomates", defaultValue: "A **Coprocess** is a program that automates interactions in the terminal. Input to the terminal is redirected to stdin of the coprocess, and its output is sent back to the terminal as though the coprocess were typing.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Stop Coprocess",
                imageName: "CoprocessMenuTip",
                text: String(localized: "ApplicationDelegate_StopsTheActiveCoprocessInputToThe", defaultValue: "Stops the active coprocess. Input to the terminal is no longer redirected to the coprocess, and its output ceases.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Triggers",
                imageName: "TriggersMenuTip",
                text: String(localized: "ApplicationDelegate_TriggersAreActionsTheTerminalPerformsAutomatically", defaultValue: "**Triggers** are actions the terminal performs automatically when text matching a regular expression is received. For example, you can highlight text or display an alert.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Terminal State.Literal Mode",
                text: String(localized: "ApplicationDelegate_WhenEnabledControlCharactersAreDisplayedVisually", defaultValue: "When enabled, control characters are displayed visually rather than being interpreted as usual.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Terminal State.Report Modifiers with CSI u",
                text: String(localized: "ApplicationDelegate_ThisModeIsGenerallyNotRecommendedDisambiguate", defaultValue: "This mode is generally not recommended. **Disambiguate Escape** is a more modern approach.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Bury Session",
                imageName: "BurySessionMenuTip",
                text: String(localized: "ApplicationDelegate_BuriedSessionsAreHiddenInTheBuried", defaultValue: "Buried sessions are hidden in the **Buried Sessions** menu below and do not appear in any window. These are particularly useful for the session where you initiate tmux integration by running `tmux -CC`.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Open Interactive Window",
                text: String(localized: "ApplicationDelegate_ThePythonReplOpensAWindowRunning", defaultValue: "The Python REPL opens a window running a special Python interpreter that lets you experiment with iTerm2’s Python API. You can use `await` at the top level of the interpreter.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Manage Dependencies",
                text: String(localized: "ApplicationDelegate_OpensAUiWhereYouCanAdd", defaultValue: "Opens a UI where you can add, update, or remove pip dependencies of a Python API script.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Install Python Runtime",
                text: String(localized: "ApplicationDelegate_ITerm2SPythonRuntimeIsA", defaultValue: "iTerm2’s Python Runtime is a large binary package (hundreds of MBs) that enables the Python API by installing a pre-built Python environment that scripts can use.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Import Script",
                text: String(localized: "ApplicationDelegate_UseImportToInstallScriptsOthersHave", defaultValue: "Use **Import** to install scripts others have shared with you. These scripts have the `.its` extension.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Export Script",
                text: String(localized: "ApplicationDelegate_IfYouWantToSharePythonApi", defaultValue: "If you want to share Python API scripts, you can export them to an `.its` file. If you have a code signing certificate and private key in your Keychain, you can also sign the `.its` file.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Script Console",
                text: String(localized: "ApplicationDelegate_ViewErrorsAndLowLevelCommunicationBetween", defaultValue: "View errors and low-level communication between Python API scripts and iTerm2 here.\n\nThe Inspector can be accessed from the Console. It allows you to browse variables in sessions, tabs, and windows.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Arrangements",
                imageName: "ArrangementsMenuTip",
                text: String(localized: "ApplicationDelegate_WindowArrangementsAreASavedRecordOf", defaultValue: "**Window Arrangements** are a saved record of one or more windows, their tabs, and split panes, including how each pane is configured. They do not include content. They’re a quick way to create a working environment with multiple sessions in various configurations.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Password Manager",
                imageName: "PasswordManagerMenuTip",
                text: String(localized: "ApplicationDelegate_ThePasswordManagerHelpsYouKeepTrack", defaultValue: "The **Password Manager** helps you keep track of your passwords securely. By default, it stores them in the macOS Keychain, but it can also use 1Password or LastPass.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "AI Chats",
                imageName: "AIChatMenuTip",
                text: String(localized: "ApplicationDelegate_AiChatsOpensAChatWindowWhere", defaultValue: "**AI Chats** opens a chat window where you can interact with AI. It can optionally view and control the terminal if you grant it permission.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Pin Hotkey Window",
                text: String(localized: "ApplicationDelegate_APinnedHotkeyWindowDoesNotClose", defaultValue: "A **pinned** Hotkey Window does not close automatically when it loses keyboard focus.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "GPU Renderer Availability",
                text: String(localized: "ApplicationDelegate_ChecksWhetherTheGpuRendererIsCurrently", defaultValue: "Checks whether the GPU Renderer is currently being used in the active session. This is sometimes useful for debugging.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Secure Keyboard Entry",
                text: String(localized: "ApplicationDelegate_SecureKeyboardEntryPreventsOtherProgramsFrom", defaultValue: "**Secure Keyboard Entry** prevents other programs from intercepting your keystrokes in the terminal. However, it also breaks some functionality: other programs cannot activate their windows while this is enabled. For example, the `open` command will still open an app, but it won’t be activated.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Install Shell Integration",
                text: String(localized: "ApplicationDelegate_ShellIntegrationConsistsOfShellScriptsThat", defaultValue: "**Shell Integration** consists of shell scripts that run when you log in. They inform iTerm2 of where your shell prompt is. This enables dozens of useful features such as command history, directory history, AI features, and more.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toggle Debug Logging",
                text: String(localized: "ApplicationDelegate_DebugLogsAreSavedInMemoryWhile", defaultValue: "Debug logs are saved in memory while this setting is enabled and written to `/tmp/debuglog.txt` when you turn it off. Memory use is capped at about 200MB; if the log grows past that, the oldest entries are discarded so the most recent activity is always kept.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Broadcast Input.Broadcast Input to All Panes in All Tabs",
                text: String(localized: "ApplicationDelegate_WhenEnabledAnythingYouTypeInThisWindow", defaultValue: "When enabled, anything you type in this window is sent to all sessions in this window.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Broadcast Input.Broadcast Input to All Panes in Current Tab",
                text: String(localized: "ApplicationDelegate_WhenEnabledAnythingYouTypeInThisTab", defaultValue: "When enabled, anything you type in this tab is sent to all sessions in this tab.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Broadcast Input.Toggle Broadcast Input to Current Session",
                text: String(localized: "ApplicationDelegate_AddsOrRemovesThisSessionFromThe", defaultValue: "Adds or removes this session from the set of sessions in this window that have broadcast enabled. When you type in a session with broadcast enabled, the keystrokes are sent to all other sessions in the same window that have broadcast enabled.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Broadcast Input.Show Background Pattern Indicator",
                imageName: "BroadcastStripesMenuTip",
                text: String(localized: "ApplicationDelegate_WhenEnabledProminentRedLinesAreDrawn", defaultValue: "When enabled, prominent red lines are drawn in the background to indicate that text you type is being broadcast to other sessions.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Broadcast Input.Current Session is Broadcast Source",
                text: String(localized: "ApplicationDelegate_WhenEnabledTypingInThisSessionIs", defaultValue: "When enabled, typing in this session is broadcast to other sessions in the same broadcast domain. Typing in other sessions sends input only to those sessions.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Lock Size",
                text: String(localized: "ApplicationDelegate_LockedWindowsResistBeingResizedThisCan", defaultValue: "Locked windows resist being resized. This can be useful when macOS screws up your windows when connecting or disconnecting displays.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Lock Layout",
                text: String(localized: "ApplicationDelegate_WhenAWindowSLayoutIsLocked", defaultValue: "When a window’s layout is locked, its tabs and panes can’t be added, closed, reordered, dragged, or moved to another window, so a stray click or drag can’t rearrange it. Resizing panes, opening new windows, and closing the window still work. This is an alternative to Lock Size; turning one on turns the other off.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Notify on Status Change",
                text: String(localized: "ApplicationDelegate_WhenEnabledTheNextTimeAnySession", defaultValue: "When enabled, the next time any session in this window changes its status (such as waiting, idle, or busy) an alert is shown and this setting turns itself back off. This is the same toggle as the bell button in the **Session Status** toolbelt tool, which must be open for this to be available.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toggle Buffer Input", text: String(localized: "ApplicationDelegate_WhileBufferInputIsTurnedOnKeyboard", defaultValue: "While Buffer Input is turned on, keyboard input is stored in a buffer. It will be sent when Buffer Input is turned off. You can also configure a trigger to change the Buffer Input setting.", comment: "Menu tip shown in registerMenuTips")),
            Tip(identifier: "Toolbelt.Session Status",
                imageName: "TabStatus",
                text: String(localized: "ApplicationDelegate_TheSessionStatusToolShowsTheStatus", defaultValue: "The **Session Status** tool shows the status of sessions across all tabs. Statuses can be set by the **Set Tab Status** trigger or by programs using a control sequence. Each entry shows the session name, a colored indicator dot, status text, and a keyboard shortcut to jump to that session.", comment: "Menu tip shown in registerMenuTips")),
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
        makeIndex(menu: mainMenu)
        let controller = MenuItemTipController.instance
        for tip in tips {
            if let item = index[tip.identifier] {
                controller.registerTip(forMenuItem: item,
                                       image: tip.imageName.compactMap { NSImage.it_imageNamed($0, for: Self.self) },
                                       attributedString: NSAttributedString.attributedString(markdown: tip.text,
                                                                                             font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                                                                                             paragraphStyle: NSParagraphStyle.default)!)
            } else {
                #if(DEBUG)
                it_fatalError("Index missing \(tip.identifier)")
                #endif
            }
        }
    }
}

@objc
extension iTermApplicationDelegate {
    @IBAction func restoreArchive(_ sender: Any?) {
        ArchivesMenuBuilder.shared?.restoreArchive(nil)
    }
}

@objc
extension iTermApplicationDelegate {
    @IBAction func revealCockpit(_ sender: Any?) {
        CockpitWindowController.shared.showAndFocusCommand()
    }
}
