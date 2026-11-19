import Cocoa

// Swift overrides of AppKit members and a witness of an AppKit protocol.
@objc(iTermSwiftWindow)
class SwiftWindow: NSWindow {
    override var canBecomeMain: Bool { return true }
    override func cursorUpdate(with event: NSEvent) {
    }
    @objc func swiftUnusedWindowMethod() {
    }
}

@objc(iTermOutlineSource)
class OutlineSource: NSObject, NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        return 0
    }
}
