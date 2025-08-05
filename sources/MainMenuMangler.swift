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

    @objc func start(web: NSMenuItem) {
        if !iTermAdvancedSettingsModel.browserProfiles() {
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
