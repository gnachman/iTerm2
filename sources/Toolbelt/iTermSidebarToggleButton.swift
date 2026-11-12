import AppKit

/// A quiet, persistent corner control whose state follows the panel it toggles.
@objcMembers final class iTermSidebarToggleButton: NSButton {
    private let leftSidebar: Bool
    private var hovered = false
    private var hoverTrackingArea: NSTrackingArea?
    var foregroundColor: NSColor = .labelColor {
        didSet {
            if oldValue != foregroundColor { updateTint(); needsDisplay = true }
        }
    }

    init(leftSidebar: Bool) {
        self.leftSidebar = leftSidebar
        super.init(frame: .zero)
        setButtonType(.pushOnPushOff)
        isBordered = false
        imagePosition = .imageOnly
        focusRingType = .none
        refusesFirstResponder = true
        image = NSImage(systemSymbolName: (leftSidebar ? SFSymbol.sidebarLeft : SFSymbol.sidebarRight).rawValue,
                        accessibilityDescription: nil)
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        setExpanded(false)
    }

    required init?(coder: NSCoder) { it_fatalError("init(coder:) has not been implemented") }

    func setExpanded(_ expanded: Bool) {
        let newState: NSControl.StateValue = expanded ? .on : .off
        if state != newState { state = newState; needsDisplay = true }
        let label: String
        if leftSidebar {
            label = expanded
                ? String(localized: "Projects.HideSidebar", defaultValue: "Hide Project Sidebar", comment: "Tooltip for the top-left sidebar button when projects are visible")
                : String(localized: "Projects.ShowSidebar", defaultValue: "Show Project Sidebar", comment: "Tooltip for the top-left sidebar button when projects are collapsed")
        } else {
            label = expanded
                ? String(localized: "FileTree.HideSidebar", defaultValue: "Hide File Tree", comment: "Tooltip for the top-right sidebar button when the file tree is visible")
                : String(localized: "FileTree.ShowSidebar", defaultValue: "Show File Tree", comment: "Tooltip for the top-right sidebar button when the file tree is collapsed")
        }
        if toolTip != label {
            toolTip = label
            setAccessibilityLabel(label)
        }
        updateTint()
    }

    private func updateTint() {
        let tint = foregroundColor.withAlphaComponent(state == .on || hovered ? 1 : 0.7)
        if contentTintColor != tint { contentTintColor = tint }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateTint()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateTint()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovered || state == .on {
            foregroundColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        super.draw(dirtyRect)
    }
}
