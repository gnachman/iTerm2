//
//  iTermSettingsTruncationChecker.swift
//  iTerm2
//
//  Debug-only diagnostic that walks the Settings window's control hierarchy and
//  reports controls whose (localized) text does not fit in the space allotted to
//  them and would therefore render truncated (with an ellipsis). Findings are
//  written to stderr in the form:
//
//      CONTROLFIT: Settings > General > AI > Features > "Chat Permissions:"  [label]
//
//  The whole file compiles out of release builds via ITERM_DEBUG.
//

#if ITERM_DEBUG
import AppKit

@objc(iTermSettingsTruncationChecker)
class iTermSettingsTruncationChecker: NSObject {
    // Slack in points so sub-pixel rounding doesn't create false positives.
    private static let tolerance: CGFloat = 1.0
    // A finite "infinity" for unconstrained layout measurements.
    private static let unbounded: CGFloat = 1_000_000
    private static var reportCount = 0

    // MARK: - Report lifecycle (called by the orchestrator)

    @objc static func beginReport() {
        reportCount = 0
        let uiLocale = Bundle.main.preferredLocalizations.first ?? "?"
        log("CONTROLFIT: ===== Begin truncation check (UI locale \(uiLocale), system \(Locale.current.identifier)) =====")
    }

    @objc static func endReport() {
        log("CONTROLFIT: ===== Done. \(reportCount) truncated control(s) found. =====")
    }

    // MARK: - Public entry point

    /// Recursively walks `root`, reporting any truncated control it finds. `path`
    /// is the breadcrumb accumulated so far, e.g. ["General", "AI"].
    @objc static func check(_ root: NSView, path: [String]) {
        walk(root, path: path)
    }

    // MARK: - Walking

    private static func walk(_ view: NSView, path: [String]) {
        guard !view.isHidden, view.alphaValue > 0.01 else {
            return
        }

        // Nested tab views: measure every tab, not just the visible one. (The
        // Settings window nests these several levels deep.)
        if let tabView = view as? NSTabView {
            walkTabView(tabView, path: path)
            return
        }

        // Measure this view itself if it's a kind of control we understand.
        measure(view, path: path)

        // Boxes contribute their title as a breadcrumb for everything inside them.
        let childPath: [String]
        if let box = view as? NSBox,
           box.titlePosition != .noTitle,
           !box.title.isEmpty {
            childPath = path + [box.title]
        } else {
            childPath = path
        }

        for sub in view.subviews {
            walk(sub, path: childPath)
        }
    }

    private static func walkTabView(_ tabView: NSTabView, path: [String]) {
        let savedDelegate = tabView.delegate
        // Detach the delegate so selecting a tab doesn't kick off an animated
        // window resize that would leave geometry in a transient state.
        tabView.delegate = nil
        let saved = tabView.selectedTabViewItem
        for item in tabView.tabViewItems {
            tabView.selectTabViewItem(item)
            tabView.window?.contentView?.layoutSubtreeIfNeeded()
            if let itemView = item.view {
                walk(itemView, path: path + [tabLabel(item)])
            }
        }
        if let saved {
            tabView.selectTabViewItem(saved)
        }
        tabView.delegate = savedDelegate
    }

    private static func tabLabel(_ item: NSTabViewItem) -> String {
        let label = item.label
        return label.isEmpty ? "(untitled tab)" : label
    }

    // MARK: - Per-control measurement

    private static func measure(_ view: NSView, path: [String]) {
        // Order matters: NSPopUpButton and NSSearchField are subclasses of the
        // more general types checked further down.
        if let popup = view as? NSPopUpButton {
            measurePopUp(popup, path: path)
        } else if let button = view as? NSButton {
            measureButton(button, path: path)
        } else if let segmented = view as? NSSegmentedControl {
            measureSegmented(segmented, path: path)
        } else if let field = view as? NSTextField {
            measureTextField(field, path: path)
        }
    }

    private static func measureButton(_ button: NSButton, path: [String]) {
        guard let cell = button.cell as? NSButtonCell else {
            return
        }
        let bounds = button.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            return
        }
        let title = button.title
        guard !title.isEmpty else {
            // Image-only buttons have nothing to truncate.
            return
        }
        // Some image buttons keep a non-empty title (used for accessibility) that
        // is never drawn because the image replaces it. Measuring that title
        // against the button width produces false positives, so skip those.
        if button.imagePosition == .imageOnly {
            return
        }
        if isSingleLine(cell) {
            // cellSize accounts for the checkbox/radio image and bezel padding,
            // so it's a reliable "does the whole thing fit on one line" test.
            if ceil(cell.cellSize.width) > bounds.width + tolerance {
                report(button, path: path, content: title, kind: "button")
            }
        } else {
            // Wrapping button: check whether the title needs more lines than fit.
            let titleRect = cell.titleRect(forBounds: bounds)
            let width = titleRect.width > 1 ? titleRect.width : bounds.width
            if wrappedHeight(button.attributedTitle, width: width) > titleRect.height + tolerance {
                report(button, path: path, content: title, kind: "button")
            }
        }
    }

    private static func measurePopUp(_ popup: NSPopUpButton, path: [String]) {
        guard let cell = popup.cell as? NSPopUpButtonCell else {
            return
        }
        let bounds = popup.bounds
        guard bounds.width > 1 else {
            return
        }
        guard let title = popup.titleOfSelectedItem ?? popup.selectedItem?.title,
              !title.isEmpty else {
            return
        }
        let attr: NSAttributedString
        if let attributed = popup.selectedItem?.attributedTitle, attributed.length > 0 {
            attr = attributed
        } else {
            attr = string(title, font: popup.font)
        }
        // titleRect on NSPopUpButtonCell excludes the disclosure arrows; if it
        // comes back suspiciously close to the full width, fall back to a fixed
        // allowance for the arrow well and insets.
        let titleRect = cell.titleRect(forBounds: bounds)
        var available = titleRect.width
        if available <= 1 || available >= bounds.width - 4 {
            available = bounds.width - 30
        }
        if ceil(attr.size().width) > available + tolerance {
            report(popup, path: path, content: title, kind: "popup")
        }
    }

    private static func measureTextField(_ field: NSTextField, path: [String]) {
        guard let cell = field.cell as? NSTextFieldCell else {
            return
        }
        let bounds = field.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            return
        }
        // drawingRect gives the interior text area (inside any bezel/border).
        var interior = cell.drawingRect(forBounds: bounds)
        if interior.width <= 1 || interior.height <= 1 {
            interior = bounds
        }

        let attr: NSAttributedString
        let content: String
        let kind: String
        if field.stringValue.isEmpty {
            // Empty field: the placeholder is what's on screen.
            guard let placeholder = placeholderAttributed(field), placeholder.length > 0 else {
                return
            }
            attr = placeholder
            content = placeholder.string
            kind = "placeholder"
        } else {
            attr = field.attributedStringValue
            content = field.stringValue
            kind = "label"
        }

        if isSingleLine(cell) {
            if ceil(attr.size().width) > interior.width + tolerance {
                report(field, path: path, content: content, kind: kind)
            }
        } else {
            if wrappedHeight(attr, width: interior.width) > interior.height + tolerance {
                report(field, path: path, content: content, kind: kind)
            }
        }
    }

    private static func measureSegmented(_ segmented: NSSegmentedControl, path: [String]) {
        let font = segmented.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        for index in 0..<segmented.segmentCount {
            guard let label = segmented.label(forSegment: index), !label.isEmpty else {
                continue
            }
            let width = segmented.width(forSegment: index)
            // A width of 0 means the segment auto-sizes to its content, so it
            // can never truncate.
            guard width > 0 else {
                continue
            }
            let needed = ceil(string(label, font: font).size().width)
            // Segments have internal margins on both sides of the label.
            if needed > (width - 8) + tolerance {
                report(segmented, path: path, content: label, kind: "segment")
            }
        }
    }

    // MARK: - Helpers

    private static func isSingleLine(_ cell: NSCell) -> Bool {
        if cell.usesSingleLineMode {
            return true
        }
        switch cell.lineBreakMode {
        case .byWordWrapping, .byCharWrapping:
            return false
        default:
            return true
        }
    }

    private static func wrappedHeight(_ attr: NSAttributedString, width: CGFloat) -> CGFloat {
        guard width > 1 else {
            return .greatestFiniteMagnitude
        }
        let rect = attr.boundingRect(with: NSSize(width: width, height: unbounded),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(rect.height)
    }

    private static func placeholderAttributed(_ field: NSTextField) -> NSAttributedString? {
        if let attributed = field.placeholderAttributedString, attributed.length > 0 {
            return attributed
        }
        if let placeholder = field.placeholderString, !placeholder.isEmpty {
            return string(placeholder, font: field.font)
        }
        return nil
    }

    private static func string(_ text: String, font: NSFont?) -> NSAttributedString {
        let resolved = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return NSAttributedString(string: text, attributes: [.font: resolved])
    }

    private static func report(_ view: NSView, path: [String], content: String, kind: String) {
        reportCount += 1
        let breadcrumb = (["Settings"] + path).joined(separator: " > ")
        // Collapse newlines so each finding stays on a single stderr line.
        let flattened = content.replacingOccurrences(of: "\n", with: " ")
        log("CONTROLFIT: \(breadcrumb) > \"\(flattened)\"  [\(kind)]")
        outline(view)
    }

    // Give a truncated view a red outline so it's easy to spot on screen. If the
    // view is layer-backed we just set a border on its layer (which tracks the
    // bounds automatically). Otherwise we add a click-through overlay subview
    // sized to fill the view, pinned with flexible autoresizing so it keeps
    // matching the view's frame as the window resizes.
    private static func outline(_ view: NSView) {
        if let layer = view.layer {
            layer.borderWidth = 2
            layer.borderColor = NSColor.systemRed.cgColor
            return
        }
        if view.subviews.contains(where: { $0 is TruncationOutlineView }) {
            return
        }
        let overlay = TruncationOutlineView(frame: view.bounds)
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(overlay)
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

// A non-interactive red outline drawn atop a truncated control.
private final class TruncationOutlineView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.systemRed.cgColor
    }

    required init?(coder: NSCoder) {
        it_fatalError("TruncationOutlineView is never unarchived")
    }

    // Let clicks fall through to the control underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
#endif
