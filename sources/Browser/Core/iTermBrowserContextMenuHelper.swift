//
//  iTermBrowserContextMenuHelper.swift
//  iTerm2
//
//  Created by George Nachman on 6/30/25.
//

enum iTermBrowserSplitPaneAction {
    case splitPaneVertically
    case splitPaneHorizontally
    case movePane
    case moveBrowserToTab
    case moveBrowserToWindow
    case swapSessions
}

protocol iTermBrowserContextMenuHelperDelegate: AnyObject {
    func contextMenuAddNamedMark(at: NSPoint)
    func contextMenuConvertPointFromWindowToView(_ point: NSPoint) -> NSPoint
    func contextMenuViewSource()
    func contextMenuSavePageAs()
    func contextMenuCopyPageTitle()
    func contextMenuPrint()
    func contextMenuRemoveElement(at point: NSPoint)
    func contextMenuCurrentSelection() -> String?
    func contextMenuCopy(string: String)
    func contextMenuCopy(data: Data)
    func contextMenuSearchEngineName() -> String?
    func contextMenuSearch(for query: String)
    func contextMenuSmartSelectionMatches(forText text: String) -> [WebSmartMatch]
    func contextMenuCurrentURL() -> URL?
    func contextMenuPerformSmartSelectionAction(payload: SmartSelectionActionPayload)
    func contextMenuScope() -> (iTermVariableScope, iTermObject)?
    func contextMenuInterpolateSmartSelectionParameters() -> Bool
    func contextMenuPerformSplitPaneAction(action: iTermBrowserSplitPaneAction)
    func contextMenuCurrentTabHasMultipleSessions() -> Bool
}

class SmartSelectionActionPayload: NSObject {
    var actionDict: [String: Any]
    var captureComponents: [String]
    var useInterpolation: Bool

    init(actionDict: [String: Any],
         captureComponents: [String],
         useInterpolation: Bool) {
        self.actionDict = actionDict
        self.captureComponents = captureComponents
        self.useInterpolation = useInterpolation
        super.init()
    }
}

class iTermBrowserContextMenuHelper: NSObject {
    private(set) var contextMenuClickLocation: NSPoint?
    weak var delegate: iTermBrowserContextMenuHelperDelegate?

    func decorate(menu: NSMenu, event: NSEvent) {
        DLog("decorate menu")
        guard let converted = convertPointFromWindowToView(event.locationInWindow) else {
            return
        }
        // Store the click location in view coordinates for the named mark functionality
        contextMenuClickLocation = converted

        // Add separator before our custom items
        menu.addItem(NSMenuItem.separator())

        var i = 0
        if let unstrippedSelectedText = delegate?.contextMenuCurrentSelection(), !unstrippedSelectedText.isEmpty {
            let selectedText = unstrippedSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if selectedText.count < 200 {
                for synonym in selectedText.helpfulSynonyms {
                    let item = NSMenuItem()
                    item.title = synonym.firstObject! as String
                    item.representedObject = synonym.secondObject
                    item.target = self
                    item.action = #selector(copyRepresentedObject(_:))
                    menu.insertItem(item, at: i)
                    i += 1
                }
                if iTermContextMenuUtilities.addMenuItem(forColors: selectedText, menu: menu, index: i) {
                    i += 1
                }
                if iTermContextMenuUtilities.addMenuItem(forBase64Encoded: selectedText, menu: menu, index: i, selector: #selector(copyData(_:)), target: self) {
                    i += 1
                }
            }
            if selectedText.count < 1_000_000 {
                i = iTermContextMenuUtilities.addMenuItems(forNumericConversions: selectedText, menu: menu, index: i, selector: #selector(copyString(_:)), target: self)
                i = iTermContextMenuUtilities.addMenuItems(toCopyBase64: unstrippedSelectedText, menu: menu, index: i, selectorForString: #selector(copyString(_:)), selectorForData: #selector(copyData(_:)), target: self)
            }
            // TODO: Replacements
            if i > 0 {
                menu.insertItem(NSMenuItem.separator(), at: i)
                i += 1
            }

            if unstrippedSelectedText.count < kMaxSelectedTextLengthForCustomActions {
                let before = i
                i = addCustomActions(toMenu: menu,
                                     matchingText: unstrippedSelectedText,
                                     index: i)
                if i > before {
                    menu.insertItem(NSMenuItem.separator(), at: i)
                    i += 1
                }
            }
        }

        // TODO: Add API-defined context menu items
        func add(title: String, selector: Selector, i: inout Int) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: i)
            i += 1
        }
        add(title: "Split Pane Vertically",
            selector: #selector(splitPaneVertically(_:)),
            i: &i)
        add(title: "Split Pane Horizontally",
            selector: #selector(splitPaneHorizontally(_:)),
            i: &i)
        add(title: "Move Browser to Split Pane",
            selector: #selector(movePane(_:)),
            i: &i)
        if delegate?.contextMenuCurrentTabHasMultipleSessions() ?? false {
            add(title: "Move Browser to Tab",
                selector: #selector(moveBrowserToTab(_:)),
                i: &i)
            add(title: "Move Browser to Window",
                selector: #selector(moveBrowserToWindow(_:)),
                i: &i)
        }
        add(title: "Swap With Session…",
            selector: #selector(swapSessions(_:)),
            i: &i)

        menu.insertItem(NSMenuItem.separator(), at: i)
        i += 1


        // Replace websearch item
        if let searchEngineName = delegate?.contextMenuSearchEngineName(),
           let i = menu.items.firstIndex(where: { $0.identifier == NSUserInterfaceItemIdentifier(rawValue: "WKMenuItemIdentifierSearchWeb") }) {
            menu.removeItem(at: i)
            let item = NSMenuItem(title: "Search with \(searchEngineName)",
                                  action: #selector(search(_:)),
                                  keyEquivalent: "")
            item.target = self
            menu.insertItem(item, at: i)
        }

        // TODO: Add Trigger…


        // Add Named Mark menu item
        let addMarkItem = NSMenuItem(title: "Add Named Mark…", action: #selector(addNamedMarkMenuClicked), keyEquivalent: "")
        addMarkItem.target = self
        menu.addItem(addMarkItem)

        menu.addItem(NSMenuItem.separator())

        // Add Save Page As menu item
        let savePageItem = NSMenuItem(title: "Save Page As…", action: #selector(savePageAsMenuClicked), keyEquivalent: "")
        savePageItem.target = self
        menu.addItem(savePageItem)

        // Add Print Page menu item
        let printPageItem = NSMenuItem(title: "Print…", action: #selector(printMenuClicked), keyEquivalent: "")
        printPageItem.target = self
        menu.addItem(printPageItem)

        // Add Copy Page Title menu item
        let copyTitleItem = NSMenuItem(title: "Copy Page Title", action: #selector(copyPageTitleMenuClicked), keyEquivalent: "")
        copyTitleItem.target = self
        menu.addItem(copyTitleItem)

        menu.addItem(NSMenuItem.separator())

        // Add View Source menu item
        let viewSourceItem = NSMenuItem(title: "View Source", action: #selector(viewSourceMenuClicked), keyEquivalent: "")
        viewSourceItem.target = self
        menu.addItem(viewSourceItem)

        let removeElement = NSMenuItem(title: "Remove Element", action: #selector(removeElementMenuClicked), keyEquivalent: "")
        removeElement.target = self
        menu.addItem(removeElement)

    }

    private func addCustomActions(toMenu menu: NSMenu,
                                  matchingText text: String,
                                  index: Int) -> Int {
        let interpolate = delegate?.contextMenuInterpolateSmartSelectionParameters() ?? false
        var i = index
        for match in delegate?.contextMenuSmartSelectionMatches(forText: text) ?? [] {
            for action in match.rule.actions {
                let payload = SmartSelectionActionPayload(
                    actionDict: action,
                    captureComponents: match.components,
                    useInterpolation: interpolate)
                addItemForSmartSelectionAction(payload: payload,
                                               to: menu,
                                               index: i)
                i += 1
            }
        }
        return i
    }

    private func addItemForSmartSelectionAction(payload: SmartSelectionActionPayload,
                                                to menu: NSMenu,
                                                index: Int) {
        let url = delegate?.contextMenuCurrentURL()
        let remoteHost: VT100RemoteHost?
        if let url {
            remoteHost = VT100RemoteHost(username: url.user,
                                         hostname: url.host)
        } else {
            remoteHost = nil
        }
        let title: String = ContextMenuActionPrefsController.title(
            forActionDict: payload.actionDict,
            withCaptureComponents: payload.captureComponents,
            workingDirectory: nil,
            remoteHost: remoteHost)

        let item = NSMenuItem(title: title,
                              action: #selector(performSmartSelectionAction(_:)),
                              keyEquivalent: "")
        item.representedObject = payload
        item.target = self
        menu.insertItem(item, at: index)
    }

    @objc private func performSmartSelectionAction(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else {
            return
        }
        guard let payload = menuItem.representedObject as? SmartSelectionActionPayload else {
            return
        }
        delegate?.contextMenuPerformSmartSelectionAction(payload: payload)
    }

    private func convertPointFromWindowToView(_ point: NSPoint) -> NSPoint? {
        return delegate?.contextMenuConvertPointFromWindowToView(point)
    }

    @objc private func search(_ sender: Any?) {
        if let selection = delegate?.contextMenuCurrentSelection() {
            delegate?.contextMenuSearch(for: selection)
        }
    }

    @objc private func copyData(_ sender: Any?) {
        if let menuItem = sender as? NSMenuItem,
           let data = menuItem.representedObject as? NSData {
            delegate?.contextMenuCopy(data: data as Data)
        }
    }

    @objc private func copyString(_ sender: Any?) {
        if let menuItem = sender as? NSMenuItem,
           let string = menuItem.representedObject as? String {
            delegate?.contextMenuCopy(string: string)
        }
    }

    @objc private func addNamedMarkMenuClicked() {
        guard let clickLocation = contextMenuClickLocation,
              let convertedLocation = convertPointFromWindowToView(clickLocation) else {
            return
        }
        delegate?.contextMenuAddNamedMark(at: convertedLocation)
    }


    @objc private func splitPaneVertically(_ sender: Any?) {
        delegate?.contextMenuPerformSplitPaneAction(action: .splitPaneVertically)
    }

    @objc private func splitPaneHorizontally(_ sender: Any?) {
        delegate?.contextMenuPerformSplitPaneAction(action: .splitPaneHorizontally)
    }

    @objc private func movePane(_ sender: Any?) {
        delegate?.contextMenuPerformSplitPaneAction(action: .movePane)
    }

    @objc private func moveBrowserToTab(_ sender: Any?) {
        delegate?.contextMenuPerformSplitPaneAction(action: .moveBrowserToTab)
    }

    @objc private func moveBrowserToWindow(_ sender: Any?) {
        delegate?.contextMenuPerformSplitPaneAction(action: .moveBrowserToWindow)
    }

    @objc private func swapSessions(_ sender: Any?) {
        delegate?.contextMenuPerformSplitPaneAction(action: .swapSessions)
    }

    @objc private func viewSourceMenuClicked() {
        delegate?.contextMenuViewSource()
    }

    @objc private func savePageAsMenuClicked() {
        delegate?.contextMenuSavePageAs()
    }

    @objc private func copyPageTitleMenuClicked() {
        delegate?.contextMenuCopyPageTitle()
    }

    // https://stackoverflow.com/questions/46777468/swift-mac-os-blank-page-printed-when-i-try-to-print-webview-wkwebview
    @objc private func printMenuClicked(_ sender: Any?) {
        delegate?.contextMenuPrint()
    }

    @objc private func removeElementMenuClicked() {
        guard let clickLocation = contextMenuClickLocation,
              let convertedLocation = convertPointFromWindowToView(clickLocation) else {
            return
        }
        delegate?.contextMenuRemoveElement(at: convertedLocation)
    }

    @objc private func copyRepresentedObject(_ sender: Any) {
        if let menuItem = sender as? NSMenuItem, let string = menuItem.representedObject as? String {
            delegate?.contextMenuCopy(string: string)
        }
    }
}
