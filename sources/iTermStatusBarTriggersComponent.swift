//
//  iTermStatusBarTriggersComponent.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/2/21.
//

import Foundation

@objc(iTermTriggersDataSource)
protocol TriggersDataSource {
    var numberOfTriggers: Int { get }
    var triggerNames: [String] { get }
    var enabledTriggerIndexes: NSIndexSet { get }
    @objc(toggleTriggerAtIndex:) func toggleTrigger(index: Int)
    @objc(addTrigger) func addTrigger()
    @objc(editTriggers) func editTriggers()
}

@objc(iTermStatusBarTriggersComponent)
class StatusBarTriggersComponent: iTermStatusBarTextComponent {
    private var dataSource: TriggersDataSource? {
        return delegate?.statusBarComponentTriggersDataSource(self)
    }

    override func statusBarComponentIcon() -> NSImage {
        return NSImage.it_cacheableImageNamed("StatusBarIconTriggers", for: Self.self)
    }

    override func statusBarComponentShortDescription() -> String {
        return "Triggers Menu"
    }

    override func statusBarComponentDetailedDescription() -> String {
        return "When clicked, opens a menu of triggers. You can use it to enable or disable triggers."
    }

    override func statusBarComponentExemplar(withBackgroundColor backgroundColor: NSColor, textColor: NSColor) -> Any {
        return "Triggers…"
    }

    override func statusBarComponentCanStretch() -> Bool {
        return true
    }

    private var stringValue: String {
        return "Triggers…"
    }

    override func stringValueForCurrentWidth() -> String? {
        return stringValue
    }

    override var stringVariants: [String]? {
        return [ stringValue ]
    }

    override func statusBarComponentHandlesClicks() -> Bool {
        return true
    }

    override func statusBarComponentIsEmpty() -> Bool {
        return (dataSource?.numberOfTriggers ?? 0) > 0
    }

    override func statusBarComponentDidClick(with view: NSView) {
        openMenu(view)
    }

    override func statusBarComponentMouseDown(with view: NSView) {
        openMenu(view)
    }

    override func statusBarComponentHandlesMouseDown() -> Bool {
        return true
    }

    private func openMenu(_ view: NSView) {
        guard let containingView = view.superview,
              let enabledIndexes = dataSource?.enabledTriggerIndexes else {
            return
        }
        let menu = NSMenu()
        for (index, triggerName) in (dataSource?.triggerNames ?? []).enumerated() {
            let item = NSMenuItem(title: triggerName, action: #selector(toggleTrigger(_:)), keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier("\(index)")
            item.target = self
            item.state = enabledIndexes.contains(index) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Add Trigger…", action: #selector(addTrigger(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Edit Triggers…", action: #selector(editTriggers(_:)), keyEquivalent: ""))

        menu.popUp(positioning: menu.items.first!, at: NSPoint.zero, in: containingView)
    }

    @objc(toggleTrigger:)
    public func toggleTrigger(_ sender: NSMenuItem) {
        guard let identifier = sender.identifier,
              let index = Int(identifier.rawValue),
              let count = dataSource?.numberOfTriggers,
              index >= 0 && index < count else {
            return
        }

        dataSource?.toggleTrigger(index: index)
    }

    @objc(addTrigger:)
    public func addTrigger(_ sender: Any) {
        dataSource?.addTrigger()
    }

    @objc(editTriggers:)
    public func editTriggers(_ sender: Any) {
        dataSource?.editTriggers()
    }
}
