//
//  MainMenuMangler.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

import Cocoa

/// Observes key-window and firstResponder changes and calls `updateMainMenu()` when either happens.
@objc(iTermMainMenuMangler)
class MainMenuMangler: NSObject {
    @objc static let instance = MainMenuMangler()
    private weak var observedWindow: NSWindow?
    private var web: NSMenuItem?

    // Store original key equivalents for web menu items
    private var originalWebKeyEquivalents: [(String, NSEvent.ModifierFlags)] = []
    
    // Store conflicting menu items that need their key equivalents restored
    private var conflictingMenuItems: [(menuItem: NSMenuItem, keyEquivalent: String, modifierMask: NSEvent.ModifierFlags)] = []

    private let iconMap = [
        // iTerm2 menu
        "Show Tip of the Day": "lightbulb",
        "Check For Updates…": "arrow.triangle.2.circlepath",
        "Toggle Debug Logging": "ladybug",
        "Copy Performance Stats": "hare",
        "Capture Metal Frame": "camera",
        "Preferences...": "gear",
        // "Services" menu item has no identifier in XIB
        "Hide iTerm2": "eye.slash",
        "Hide Others": "eye.slash.fill",
        "Show All": "eye",
        "Secure Keyboard Entry": "lock.badge.checkmark",
        "Make iTerm2 Default Term": "star.fill",
        "Make Terminal Default Term": "star",
        "Install Shell Integration": "square.and.arrow.down.fill",
        "Remove Recent Profiles from Dock Menu": "person.fill.xmark",
        "About iTerm2": "info.circle.fill",
        "Quit iTerm2": "power",

        // Shell menu
        "New Window": "plus",
        "New Window with Current Profile": "plus.app",
        "New Tab": "plus.rectangle.on.folder",
        "New Tab with Current Profile": "plus.rectangle.on.folder.fill",
        "Duplicate Tab": "document.on.document",
        "Duplicate Window": "document.on.document.fill",
        "Duplicate Session": "rectangle.on.rectangle",
        "Press Option for New Window": "option",
        "Split Horizontally with Current Profile": "square.split.1x2.fill",
        "Split Vertically with Current Profile": "square.split.2x1.fill",
        "Split Horizontally…": "square.split.1x2",
        "Split Vertically…": "square.split.2x1",
        "Log.SaveContents": "square.and.arrow.down",
        "Log.Toggle": "record.circle",
        // Log.Start and Log.Stop removed - no identifiers in XIB
        "Log.ImportRecording": "square.and.arrow.down",
        "Log.ExportRecording": "square.and.arrow.up",
        // Log.ExportCommandHistory removed - no identifier in XIB
        "Close": "xmark",
        "Close Terminal Window": "xmark.circle.fill",
        "Close All Panes in Tab": "xmark.circle",
        "Undo Close": "arrow.uturn.backward",
        "Broadcast Input.Send Input to Current Session Only": "person",
        "Broadcast Input.Broadcast Input to All Panes in All Tabs": "dot.radiowaves.right",
        "Broadcast Input.Broadcast Input to All Panes in Current Tab": "dot.radiowaves.right",
        "Broadcast Input.Toggle Broadcast Input to Current Session": "dot.radiowaves.right",
        "Broadcast Input.Show Background Pattern Indicator": "dot.radiowaves.up.forward",
        "tmux.Dashboard": "rectangle.grid.2x2",
        "tmux.Detach": "arrow.up.right.square",
        "tmux.Force Detach": "bolt.slash",
        "tmux.New Tmux Window": "plus.rectangle.on.rectangle",
        "tmux.New Tmux Tab": "plus.square.on.square",
        "trmux.Pause Pane": "pause.circle",
        // tmux.Pause Pane removed - no identifier in XIB
        // ssh menu items have individual identifiers, not a general one
        "ssh.Download Files": "arrow.down.doc",
        "ssh.Disconnect": "network.badge.xmark",
        // Print submenu items removed - no identifiers in XIB
        "Print.Selection": "printer",
        "Print.Buffer": "printer",
        "Print.Screen": "printer",
        "Page Setup...": "doc.text",

        // Edit menu
        "Undo": "arrow.uturn.backward",
        "Redo": "arrow.uturn.forward",
        "Cut": "scissors",
        "Copy": "document.on.document",
        "Copy with Styles": "document.on.document.fill",
        "Copy with Control Sequences": "document.on.document",
        "Copy Mode": "document.badge.plus",
        "Paste": "document.on.clipboard",
        "Paste Special.Advanced Paste…": "document.on.clipboard",
        "Paste Special.Paste Selection": "document.badge.plus",
        "Paste Special.Paste File Base64-Encoded": "document.badge.plus.fill",
        "Paste Special.Paste Faster": "hare",
        "Paste Special.Paste Slowly Faster": "hare.circle",
        "Paste Special.Paste Slower": "tortoise",
        "Paste Special.Paste Slowly Slower": "tortoise.circle",
        "Paste Special.Warn Before Multi-Line Paste": "exclamationmark.triangle",
        "Paste Special.Limit Multi-Line Paste Warning to Shell Prompt": "bolt.trianglebadge.exclamationmark.fill",
        "Paste Special.Prompt to Convert Tabs to Spaces when Pasting": "convertible.side",
        "Paste Special.Warn Before Pasting One Line Ending in a Newline at Shell Prompt": "exclamationmark.triangle.text.page",
        "Paste Special.Paste Slowly": "tortoise.fill",
        "Open Selection": "arrow.up.right",
        "Find.Jump to Selection": "arrow.turn.up.right",
        "Find.Find...": "magnifyingglass",
        "Find.Find Next": "arrow.down",
        "Find.Find Previous": "arrow.up",
        "Find.Use Selection for Find": "lasso.badge.sparkles",
        // Find.Jump Again removed - no identifier in XIB
        "Find.Find Globally...": "globe",
        "Find.Find URLs": "network",
        "Find.Pick Result To Open": "hand.tap",
        "Find.Filter": "line.3.horizontal.decrease.circle",
        "Find.Find All Smart Selection  Matches": "sparkle.magnifyingglass",
        "Find.ConvertMatchesToSelections": "checkmark.rectangle.stack",
        "Find.Clear Find": "xmark.circle",
        "Select All": "a.circle",
        "Selection Respects Soft Boundaries": "text.justify.leading",
        "Select Current Command": "text.cursor",
        "Select Output of Last Command": "text.line.last.and.arrowtriangle.forward",
        "Save Selected Text…": "square.and.arrow.down.on.square",
        "Open Autocomplete…": "text.badge.xmark",
        "Marks and Annotations.Set Mark": "bookmark",
        "Marks and Annotations.Add Annotation at Cursor": "pencil",
        "Marks and Annotations.Alerts.Alert on Next Mark": "bolt.badge.clock",
        "Marks and Annotations.Next Mark": "arrow.down",
        "Marks and Annotations.Previous Mark": "arrow.up",
        "Marks and Annotations.Next  Annotation": "arrow.down.circle",
        "Marks and Annotations.Previous  Annotation": "arrow.up.circle",
        "Marks and Annotations.Jump to Mark": "location",
        "Set Named Mark": "bookmark.fill",
        "Marks and Annotations.Alerts.Show Modal Alert Box": "exclamationmark.square",
        "Marks and Annotations.Alerts.Post Notification": "bell",
        "Marks and Notes.Alerts.Play a Sound": "speaker.wave.2",
        "Marks and Alerts.Alerts.Alert on Marks in Offscreen Sessions": "bell.badge",
        // Annotations navigation removed - no identifiers in XIB
        // Clear Transcript removed - no identifier in XIB
        "Clear Buffer": "xmark.rectangle",
        "Clear to Start of Selection": "arrow.up.left.and.arrow.down.right",
        "Clear to Last Mark": "bookmark",
        "Clear Scrollback Buffer": "xmark.diamond",
        "Fold Selected Lines": "text.line.first.and.arrowtriangle.forward",

        // View menu
        "Show Tabs in Fullscreen": "macwindow",
        "Toggle Full Screen": "arrow.up.left.and.arrow.down.right",
        "Use Transparency": "cube.transparent",
        "Zoom In on Selection": "rectangle.expand.diagonal",
        "Zoom Out": "arrow.down.left.and.arrow.up.right",
        "Find Cursor": "viewfinder",
        "Show Cursor Guide": "text.aligncenter",
        "Show Timestamps": "clock",
        "Show Annotations": "text.bubble",
        "Auto Command Completion": "text.badge.checkmark",
        "Open Quickly": "magnifyingglass",
        "Maximize Active Pane": "rectangle.compress.vertical",
        "Make Text Bigger": "textformat.size.larger",
        "Make Text Smaller": "textformat.size.smaller",
        "Make Text Normal Size": "textformat.size",
        "Start Instant Replay": "restart.circle",
        "Clear Instant Replay": "xmark.circle",
        "Pin Hotkey Window": "pin.fill",
        "Render Selection Natively": "square.dashed",
        "Replace Selection.Replace with Pretty-Printed JSON": "curlybraces.square",
        "Replace Selection.Replace with Base 64-Encoded Value": "arrow.up.to.line.compact",
        "Replace Selection.Replace with Base 64-Decoded Value": "arrow.down.to.line.compact",
        "Disable Transparency for Active Window": "cube.fill",
        // Pin Broadcast Input removed - no identifier in XIB

        // Session menu
        "Edit Session…": "wrench.and.screwdriver",
        "Run Coprocess…": "figure.run.square.stack",
        "Stop Coprocess": "figure.run",
        "Restart Session": "arrow.clockwise",
        "Open Command History…": "book.pages",
        "Open Recent Directories…": "folder",
        "Open Paste History…": "book.pages",
        // Open Trigger removed - no identifier in XIB
        "Reset": "restart",
        "Reset Character Set": "restart",
        // Log.Save Contents removed - no identifier in XIB
        // Log.Append to File removed - no identifier in XIB
        "Bury Session": "memories.badge.xmark",
        "Reset Terminal State": "arrow.clockwise",
        "Restore Text and Session Size": "arrow.counterclockwise",
        "Terminal State.Literal Mode": "textformat.abc",
        "Terminal State.Emulation Level.VT100": "display",
        "Terminal State.Emulation Level.VT200": "display",
        "Terminal State.Emulation Level.VT300": "display",
        "Terminal State.Emulation Level.VT400": "display",
        "Terminal State.Emulation Level.VT500": "display",
        "Terminal State.Raw Key Reporting": "keyboard.badge.ellipsis",
        "Terminal State.Standard Key Reporting": "keyboard",
        "Terminal State.Disambiguate Escape": "escape",
        "Terminal State.Report Modifiers like xterm 1": "keyboard.badge.1",
        "Terminal State.Report Modifiers like xterm 2": "keyboard.badge.2",
        "Terminal State.Report Modifiers with CSI u": "keyboard.badge.ellipsis",
        "Terminal State.Report All Event Types": "list.bullet.rectangle",
        "Terminal State.Report Alternate Keys": "keyboard.chevron.compact.left",
        "Terminal State.Report Associated Text": "text.badge.plus",
        "Terminal State.Report All Keys as Escape Codes": "keyboard.fill",
        "Application Keypad": "keyboard",
        "Application Cursor": "cursorarrow",
        "Mouse Reporting": "computermouse",
        "Focus Reporting": "target",
        "Paste Bracketing": "brackets",
        "Alternate Screen": "rectangle.badge.arrow.up.right",
        "Move Session to Window": "macwindow.badge.plus",
        "Move Session to Tab": "plus.rectangle.on.folder",
        "Move Session to Split Pane": "rectangle.split.2x1",
        "Lock Split Pane Width": "lock.rectangle",
        "Triggers.Enable All": "checkmark.circle",
        "Triggers.Disable All": "xmark.circle",
        "Edit Triggers": "pencil.circle",
        "Add Trigger": "plus.diamond",
        "Enable Triggers in Interactive Apps": "play.circle",
        "Auto Composer": "wand.and.stars",
        "Open AI Chat": "questionmark.bubble",
        "AI Chats": "bubble.left.and.bubble.right",
        "Engage Artificial Intelligence": "brain",
        "Explain Output with AI": "sparkles.rectangle.stack",
        "Open Interactive Window": "terminal",

        // Scripts menu
        // Manage removed - no identifier in XIB
        "New Python Script": "plus",
        // Open Python REPL removed - no identifier in XIB
        "Import Script": "square.and.arrow.down",
        "Export Script": "square.and.arrow.up",
        "Script Console": "greaterthan.square",
        "Reveal in Finder": "folder.circle",
        "Install Python Runtime": "arrow.down.circle",
        "Install Already-Downloaded Python Runtime": "arrow.down.circle.fill",
        "Manage Dependencies": "gearshape.2",
        // Reveal Scripts in Finder removed - no identifier in XIB

        // Profiles menu
        "Open Profiles…": "person",
        // Press Option to Show Alternate Profiles removed - no identifier in XIB
        "Open In New Window": "macwindow",
        "Change Profile in Arrangement…": "person.crop.rectangle",

        // Toolbelt menu
        "Show Toolbelt": "wrench.and.screwdriver",
        "Set Default Width": "guidepoint.horizontal",

        // Window menu
        "Minimize": "arrow.down.left.and.arrow.up.right",
        "Zoom": "arrow.up.left.and.arrow.down.right",
        "Edit Tab Title": "pencil",
        "Edit Window Title": "pencil",
        // Window Style removed - no identifier in XIB
        // Move Tab to New Window removed - no identifier in XIB
        "Merge All Windows": "macwindow.stack",
        "Arrange Split Panes Evenly": "rectangle.split.2x1",
        "Arrange Windows Horizontally": "square.split.2x1",
        "Bring All To Front": "macwindow",
        "Move Tab Left": "arrow.left.square",
        "Move Tab Right": "arrow.right.square",
        "Size Changes Update Profile": "arrow.up.and.down.and.arrow.left.and.right",
        "Window Style.FullHeight Right of Screen": "rectangle.righthalf.inset.filled",
        "Window Style..FullHeight Left of Screen": "rectangle.lefthalf.inset.filled",
        "Window Style.Right of Screen": "rectangle.righthalf.inset.filled",
        "Window Style.Left of Screen": "rectangle.lefthalf.inset.filled",
        "Window Style.Top of Screen": "rectangle.tophalf.inset.filled",
        "Window Style.Bottom of Screen": "rectangle.bottomhalf.inset.filled",
        "Window Style.FullWidth Bottom of Screen": "rectangle.bottomhalf.filled",
        "Window Style.FullWidth Top of Screen": "rectangle.tophalf.filled",
        "Window Style.Normal": "rectangle",
        "Window Style.Maximized": "rectangle.fill",
        "Window Style.Full Screen": "arrow.up.left.and.arrow.down.right",
        "Window Style.No Title Bar": "rectangle.dashed",
        "Save Window Arrangement": "square.and.arrow.down",
        "Save Current Window as Arrangement": "square.and.arrow.down",
        "Load Arrangement from File…": "doc.badge.arrow.up",
        "changeTabColorToMenuAction:": "paintpalette",
        // Arrangement as Tabs items removed - no identifiers in XIB
        // Name Window removed - no identifier in XIB
        "Select Split Pane.Select Pane Above": "arrow.up",
        "Select Split Pane.Select Pane Below": "arrow.down",
        "Select Split Pane.Select Pane Left": "arrow.left",
        "Select Split Pane.Select Pane Right": "arrow.right",
        "Select Split Pane.Next Pane": "arrow.right",
        "Select Split Pane.Previous Pane": "arrow.left",
        "Resize Split Pane.Move Divider Up": "arrow.up",
        "Resize Split Pane.Move Divider Down": "arrow.down",
        "Resize Split Pane.Move Divider Left": "arrow.left",
        "Resize Split Pane.Move Divider Right": "arrow.right",
        "Select Next Tab": "arrow.right",
        "Select Previous Tab": "arrow.left",
        "Resize Window.Decrease Height": "arrow.down.and.line.horizontal.and.arrow.up",
        "Resize Window.Increase Height": "arrow.up.and.line.horizontal.and.arrow.down",
        "Resize Window.Decrease Width": "arrow.right.and.line.vertical.and.arrow.left",
        "Resize Window.Increase Width": "arrow.left.and.line.vertical.and.arrow.right",
        "Password Manager": "lock",
        // Notifications removed - no identifier in XIB
        "Composer": "music.note.list",
        "GPU Renderer Availability": "cpu",

        // Help menu
        "iTerm2 Help": "questionmark.circle",
        "Copy Mode Shortcuts": "questionmark.circle",
        "Open Source Licenses": "info.circle"]

    @available(macOS 26, *)
    @objc func setIcons() {
        // Find all menu items by traversing the main menu
        if let mainMenu = NSApp.mainMenu {
            setIcons(map: iconMap, in: mainMenu)
        }
    }

    @objc func checkIcons() {
        checkIcons(map: iconMap, in: NSApp.mainMenu!)
    }

    private func checkIcons(map iconMap: [String: String], in menu: NSMenu) {
        let keys = Set(iconMap.keys)
        let identifiers = allIdentifiers(in: NSApp.mainMenu!)
        if !keys.isSubset(of: identifiers) {
            NSFuckingLog("%@", "Some keys have wrong identifiers: \(keys.subtracting(identifiers))")
            it_fatalError()
        }
        let bad = identifiers.subtracting(keys).filter { !$0.hasPrefix("_NS") }.subtracting(Set(["bogus", "sendSnippet:"]))
        if !bad.isEmpty {
            NSFuckingLog("%@", "These identifiers lack icons: \(bad)")
        }
    }

    private func allIdentifiers(in menu: NSMenu) -> Set<String> {
        var result = Set<String>()
        for item in menu.items {
            if item.isSeparatorItem {
                continue
            }
            if !item.hasSubmenu, let identifier = item.identifier?.rawValue {
                result.insert(identifier)
            }
            if item.hasSubmenu, let submenu = item.submenu {
                result.formUnion(allIdentifiers(in: submenu))
            }
        }
        return result
    }

    private func setIcons(map iconMap: [String: String], in menu: NSMenu) {
        for item in menu.items {
            if let identifier = item.identifier?.rawValue,
               let iconName = iconMap[identifier] {
                #if(DEBUG)
                if item.hasSubmenu {
                    it_fatalError("Submenus should not have icons: \(identifier)")
                }
                #endif
                item.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            }
            if item.hasSubmenu, let submenu = item.submenu {
                setIcons(map: iconMap, in: submenu)
            }
        }
    }

    @objc func start(web: NSMenuItem) {
        if !iTermBrowserGateway.browserAllowed(checkIfNo: false) {
            if NSApp.mainMenu?.items.contains(web) ?? false {
                NSApp.mainMenu?.removeItem(web)
            }
            return
        }
        self.web = web
        
        // Store original web menu key equivalents and scan for conflicts
        scanForKeyEquivalentConflicts()
        
        // Watch for any window becoming or resigning key
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(currentTerminalDidChange(_:)),
            name: Notification.Name("iTermWindowBecameKey"),
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(currentSessionDidChange(_:)),
            name: Notification.Name(rawValue: iTermCurrentSessionDidChange),
            object: nil)
        update()
    }

    deinit {
        stopObserving()
    }

    // MARK: – Notification handlers

    @objc private func currentTerminalDidChange(_ note: Notification) {
        update()
    }

    @objc private func currentSessionDidChange(_ note: Notification) {
        updateMainMenu()
    }

    private func update() {
        let currentTerminalWindow = iTermController.sharedInstance().currentTerminal?.window()
        if currentTerminalWindow == observedWindow {
            return
        }
        stopObserving()
        if let currentTerminalWindow {
            startObserving(window: currentTerminalWindow)
        }
    }

    // MARK: – KVO for firstResponder

    private func startObserving(window: NSWindow) {
        // If it’s already our observed window, nothing to do
        guard observedWindow !== window else { return }

        // Tear down old observation
        stopObserving()

        // Begin observing the new window’s firstResponder
        observedWindow = window
        DLog("Start observing \(window)")
        window.addObserver(
            self,
            forKeyPath: "firstResponder",
            options: [.old, .new],
            context: nil)

        // Trigger one update immediately
        updateMainMenu()
    }

    private func stopObserving() {
        if let window = observedWindow {
            DLog("Stop observing \(window)")
            window.removeObserver(self, forKeyPath: "firstResponder")
            observedWindow = nil
        }
        updateMainMenu()
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?) {
        // Only care about firstResponder changes on our observed window
        if keyPath == "firstResponder",
           let win = object as? NSWindow,
           win === observedWindow {
            updateMainMenu()
        } else {
            super.observeValue(forKeyPath: keyPath,
                               of: object,
                               change: change,
                               context: context)
        }
    }

    // MARK: – Key equivalent conflict management
    
    private func scanForKeyEquivalentConflicts() {
        guard let web = web, let webSubmenu = web.submenu else { return }
        
        // Store original web menu key equivalents
        originalWebKeyEquivalents = webSubmenu.items.map { 
            ($0.keyEquivalent, $0.keyEquivalentModifierMask) 
        }
        
        // Find conflicting menu items in the main menu
        conflictingMenuItems.removeAll()
        
        guard let mainMenu = NSApp.mainMenu else { return }
        
        for webMenuItem in webSubmenu.items {
            let webKeyEquiv = webMenuItem.keyEquivalent
            let webModifiers = webMenuItem.keyEquivalentModifierMask
            
            // Skip empty key equivalents
            if webKeyEquiv.isEmpty { continue }
            
            // Search through all main menu items for conflicts
            scanMenuForConflicts(menu: mainMenu, 
                                webKeyEquiv: webKeyEquiv, 
                                webModifiers: webModifiers)
        }
    }
    
    private func scanMenuForConflicts(menu: NSMenu, webKeyEquiv: String, webModifiers: NSEvent.ModifierFlags) {
        for item in menu.items {
            // Check if this item conflicts with the web key equivalent
            if item.keyEquivalent == webKeyEquiv && item.keyEquivalentModifierMask == webModifiers {
                conflictingMenuItems.append((
                    menuItem: item,
                    keyEquivalent: item.keyEquivalent,
                    modifierMask: item.keyEquivalentModifierMask
                ))
            }
            
            // Recursively check submenus
            if let submenu = item.submenu {
                scanMenuForConflicts(menu: submenu, webKeyEquiv: webKeyEquiv, webModifiers: webModifiers)
            }
        }
    }
    
    private func restoreWebKeyEquivalents() {
        guard let web = web, let webSubmenu = web.submenu else { return }
        
        // Restore original key equivalents for web menu items
        for (index, item) in webSubmenu.items.enumerated() {
            if index < originalWebKeyEquivalents.count {
                let (keyEquiv, modifiers) = originalWebKeyEquivalents[index]
                item.keyEquivalent = keyEquiv
                item.keyEquivalentModifierMask = modifiers
            }
        }
    }
    
    private func restoreConflictingMenuItems() {
        for conflict in conflictingMenuItems {
            conflict.menuItem.keyEquivalent = conflict.keyEquivalent
            conflict.menuItem.keyEquivalentModifierMask = conflict.modifierMask
        }
    }

    // MARK: – Hook for your menu-modification logic

    private var existingWebIndex: Int? {
        return web.compactMap { NSApp.mainMenu?.items.firstIndex(of: $0) }
    }

    func updateMainMenu() {
        guard let web else {
            return
        }
        let currentSessionIsWeb: Bool
        if let term = NSApp.keyWindow?.delegate as? PseudoTerminal {
            currentSessionIsWeb = term.checkFirstResponder() == nil
        } else {
            currentSessionIsWeb = false
        }

        if currentSessionIsWeb {
            if existingWebIndex == nil, let menu = NSApp.mainMenu {
                DLog("Show web menu")
                // Clear conflicting key equivalents before adding web menu
                for conflict in conflictingMenuItems {
                    conflict.menuItem.keyEquivalent = ""
                    conflict.menuItem.keyEquivalentModifierMask = []
                }
                if let i = menu.items.firstIndex(where: { $0.identifier?.rawValue == "Session" }) {
                    menu.insertItem(web, at: i + 1)
                }

                // Restore web menu key equivalents after adding to menu
                restoreWebKeyEquivalents()
            }
        } else if existingWebIndex != nil {
            DLog("Remove web menu")
            NSApp.mainMenu?.removeItem(web)
            
            // Restore conflicting menu items' key equivalents when web menu is removed
            restoreConflictingMenuItems()
        }
    }
}
