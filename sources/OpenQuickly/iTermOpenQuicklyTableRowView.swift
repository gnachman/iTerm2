import AppKit

// The Open Quickly table's row views. Both are always emphasized, so a table
// that is not key can still have a blue selection. The window controller
// makes iTermOpenQuicklyTableRowView_BigSur in -tableView:rowViewForRow:.
@objc(iTermOpenQuicklyTableRowView)
class iTermOpenQuicklyTableRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set { super.isEmphasized = newValue }
    }

    // Only calls super, but keep it: AppKit may choose how it draws the
    // selection by whether a subclass overrides this, and it is the one
    // difference from the _BigSur class.
    override func drawSelection(in dirtyRect: NSRect) {
        super.drawSelection(in: dirtyRect)
    }
}

@objc(iTermOpenQuicklyTableRowView_BigSur)
class iTermOpenQuicklyTableRowView_BigSur: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set { super.isEmphasized = newValue }
    }
}
