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
        "Quit iTerm2": "power",

        // Shell menu
        "New Window": "plus",
        "New Window with Current Profile": "plus.app",
        "New Tab": "plus.rectangle.on.folder",
        "New Tab with Current Profile": "plus.rectangle.on.folder.fill",
        "Duplicate Tab": "document.on.document",
        "Duplicate Window": "document.on.document.fill",
        "Split Horizontally with Current Profile": "square.split.1x2.fill",
        "Split Vertically with Current Profile": "square.split.2x1.fill",
        "Split Horizontally…": "square.split.1x2",
        "Split Vertically…": "square.split.2x1",
        "Log.SaveContents": "square.and.arrow.down",
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
        "tmux.Dashboard": "rectangle.split.3x3",
        "tmux.Detach": "rectangle.split.3x3",
        "tmux.Force Detach": "rectangle.split.3x3",
        "tmux.New Tmux Window": "rectangle.split.3x3",
        "tmux.New Tmux Tab": "rectangle.split.3x3",
        // tmux.Pause Pane removed - no identifier in XIB
        // ssh menu items have individual identifiers, not a general one
        // Print submenu items removed - no identifiers in XIB

        // Edit menu
        "Undo": "arrow.uturn.backward",
        "Redo": "arrow.uturn.forward",
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
        "Open Selection": "arrow.up.right",
        "Find.Jump to Selection": "arrow.turn.up.right",
        "Find.Find...": "magnifyingglass",
        "Find.Find Next": "arrow.down",
        "Find.Find Previous": "arrow.up",
        "Find.Use Selection for Find": "lasso.badge.sparkles",
        // Find.Jump Again removed - no identifier in XIB
        "Find.Find Globally...": "globe",
        "Find.Find URLs": "network",
        "Select All": "a.circle",
        "Selection Respects Soft Boundaries": "text.justify.leading",
        "Open Autocomplete…": "text.badge.xmark",
        "Marks and Annotations.Set Mark": "bookmark",
        "Marks and Annotations.Add Annotation at Cursor": "pencil",
        "Marks and Annotations.Alerts.Alert on Next Mark": "bolt.badge.clock",
        "Marks and Annotations.Next Mark": "arrow.down",
        "Marks and Annotations.Previous Mark": "arrow.up",
        // Annotations navigation removed - no identifiers in XIB
        // Clear Transcript removed - no identifier in XIB
        "Clear Buffer": "xmark.rectangle",
        "Clear to Start of Selection": "arrow.up.left.and.arrow.down.right",
        "Clear to Last Mark": "bookmark",
        "Clear Scrollback Buffer": "xmark.diamond",

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
        // Pin Broadcast Input removed - no identifier in XIB

        // Session menu
        "Edit Session…": "wrench.and.screwdriver",
        "Run Coprocess…": "figure.run.square.stack",
        "Stop Coprocess": "figure.run",
        "Restart Session": "restart",
        "Open Command History…": "book.pages",
        "Open Recent Directories…": "folder",
        "Open Paste History…": "book.pages",
        // Open Trigger removed - no identifier in XIB
        "Reset": "restart",
        "Reset Character Set": "restart",
        // Log.Save Contents removed - no identifier in XIB
        // Log.Append to File removed - no identifier in XIB
        "Bury Session": "memories.badge.xmark",

        // Scripts menu
        // Manage removed - no identifier in XIB
        "New Python Script": "plus",
        // Open Python REPL removed - no identifier in XIB
        "Import Script": "square.and.arrow.down",
        "Export Script": "square.and.arrow.up",
        "Script Console": "greaterthan.square",
        // Reveal Scripts in Finder removed - no identifier in XIB

        // Profiles menu
        "Open Profiles…": "person",
        // Press Option to Show Alternate Profiles removed - no identifier in XIB
        "Open In New Window": "macwindow",

        // Toolbelt menu
        "Show Toolbelt": "wrench.and.screwdriver",
        "Set Default Width": "line.3.horizontal.decrease",

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
        "Arrangements": "folder",
        "Save Window Arrangement": "square.and.arrow.down",
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
        "Resize Window.Decrease Height": "arrow.up.and.down.and.arrow.left.and.right",
        "Resize Window.Increase Height": "arrow.up.and.down.and.arrow.left.and.right",
        "Resize Window.Decrease Width": "arrow.up.and.down.and.arrow.left.and.right",
        "Resize Window.Increase Width": "arrow.up.and.down.and.arrow.left.and.right",
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
        NSFuckingLog("%@", "These identifiers lack icons: \(identifiers.subtracting(keys))")
    }

    private func allIdentifiers(in menu: NSMenu) -> Set<String> {
        var result = Set<String>()
        for item in menu.items {
            if let identifier = item.identifier?.rawValue {
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
