//
//  iTermBrowserContextMenuHelper.swift
//  iTerm2
//
//  Created by George Nachman on 6/30/25.
//

protocol iTermBrowserContextMenuHelperDelegate: AnyObject {
    func contextMenuAddNamedMark(at: NSPoint)
    func contextMenuConvertPointFromWindowToView(_ point: NSPoint) -> NSPoint
    func contextMenuViewSource()
    func contextMenuSavePageAs()
    func contextMenuCopyPageTitle()
    func contextMenuPrint()
    func contextMenuRemoveElement(at point: NSPoint)
}
class iTermBrowserContextMenuHelper {
    private(set) var contextMenuClickLocation: NSPoint?
    weak var delegate: iTermBrowserContextMenuHelperDelegate?

    func decorate(menu: NSMenu, event: NSEvent) {
        guard let converted = convertPointFromWindowToView(event.locationInWindow) else {
            return
        }
        // Store the click location in view coordinates for the named mark functionality
        contextMenuClickLocation = converted

        // Add separator before our custom items
        menu.addItem(NSMenuItem.separator())

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

    private func convertPointFromWindowToView(_ point: NSPoint) -> NSPoint? {
        return delegate?.contextMenuConvertPointFromWindowToView(point)
    }

    @objc private func addNamedMarkMenuClicked() {
        guard let clickLocation = contextMenuClickLocation,
              let convertedLocation = convertPointFromWindowToView(clickLocation) else {
            return
        }
        delegate?.contextMenuAddNamedMark(at: convertedLocation)
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
        if let contextMenuClickLocation {
        }
    }

}
