//
//  ScriptingPermissionsWindowController.swift
//  iTerm2SharedARC
//
//  The sheet opened by Manage Permissions in Settings > General > Magic. One tab lists the
//  websites scripts may control in a browser session; the other lists the remote hosts always
//  allowed to use the iTerm2 API over SSH integration.
//

import AppKit

@objc(iTermScriptingPermissionsWindowController)
final class ScriptingPermissionsWindowController: NSWindowController {
    /// Held while the sheet is up. A sheet does not retain its window controller, so without
    /// this the controller would be released as soon as presentSheet returned.
    private static var presented: ScriptingPermissionsWindowController?

    private let browserScripting = BrowserScriptingPermissionsViewController()
    private let hostGrants = IT2HostGrantsViewController(store: .shared)

    @objc(presentSheetFor:)
    static func presentSheet(for parent: NSWindow?) {
        guard let parent else {
            return
        }
        let controller = ScriptingPermissionsWindowController()
        presented = controller
        guard let sheet = controller.window else {
            return
        }
        parent.beginSheet(sheet) { _ in
            presented = nil
        }
    }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 460),
                              styleMask: [.titled, .resizable],
                              backing: .buffered,
                              defer: true)
        window.minSize = NSSize(width: 480, height: 340)
        super.init(window: window)
        buildContent(in: window)
        // A script may be approved while this is open.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowDidBecomeKey(_:)),
                                               name: NSWindow.didBecomeKeyNotification,
                                               object: window)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    private func buildContent(in window: NSWindow) {
        let content = NSView()
        window.contentView = content

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false

        let browserItem = NSTabViewItem(viewController: browserScripting)
        browserItem.label = String(localized: "ScriptingPermissions.BrowserTab",
                                   defaultValue: "Browser Scripting",
                                   comment: "Tab listing the websites on which scripts may load URLs or run JavaScript in a browser session")
        tabView.addTabViewItem(browserItem)

        let hostsItem = NSTabViewItem(viewController: hostGrants)
        hostsItem.label = String(localized: "ScriptingPermissions.APIOverSSHTab",
                                 defaultValue: "API Access over SSH",
                                 comment: "Tab listing the remote hosts always allowed to use the iTerm2 API over SSH integration")
        tabView.addTabViewItem(hostsItem)

        let done = NSButton(title: String(localized: "General.Done", defaultValue: "Done", comment: "Done button"),
                            target: self,
                            action: #selector(done(_:)))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(tabView)
        content.addSubview(done)
        let margin: CGFloat = 20
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: margin),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),

            done.topAnchor.constraint(equalTo: tabView.bottomAnchor, constant: 12),
            done.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -margin),
            done.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -margin),
            done.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        browserScripting.refresh()
        hostGrants.reload()
    }

    @objc private func done(_ sender: Any?) {
        guard let window, let parent = window.sheetParent else {
            window?.orderOut(nil)
            return
        }
        parent.endSheet(window)
    }
}
