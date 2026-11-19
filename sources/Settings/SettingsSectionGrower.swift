//
//  SettingsSectionGrower.swift
//  iTerm2SharedARC
//
//  Makes room in a settings pane laid out by frame in Interface Builder, for
//  controls added in code.
//

import AppKit

@objc(iTermSettingsSectionGrower)
final class SettingsSectionGrower: NSObject {
    // Grows `section` downward by `delta`, keeping its contents where they
    // are relative to its top. Its superview grows by the same amount, and
    // every sibling above the section's bottom edge moves up, including ones
    // that overlap the section by a little, as Interface Builder layouts
    // often do. Views are moved explicitly rather than by autoresizing masks.
    @objc(growSection:atBottomBy:)
    static func grow(_ section: NSView, atBottomBy delta: CGFloat) {
        guard let container = section.superview else {
            return
        }
        let containerAutoresizes = container.autoresizesSubviews
        let sectionAutoresizes = section.autoresizesSubviews
        container.autoresizesSubviews = false
        section.autoresizesSubviews = false
        defer {
            container.autoresizesSubviews = containerAutoresizes
            section.autoresizesSubviews = sectionAutoresizes
        }
        let sectionBottom = section.frame.minY
        for view in container.subviews where view !== section && view.frame.minY > sectionBottom {
            view.setFrameOrigin(NSPoint(x: view.frame.minX, y: view.frame.minY + delta))
        }
        for view in section.subviews {
            view.setFrameOrigin(NSPoint(x: view.frame.minX, y: view.frame.minY + delta))
        }
        section.setFrameSize(NSSize(width: section.frame.width, height: section.frame.height + delta))
        container.setFrameSize(NSSize(width: container.frame.width, height: container.frame.height + delta))
        // Settings wraps a tall pane in a scroll view, which may already have
        // happened. Its document view grows too, so the bottom can be
        // scrolled to. Flipped or not, that keeps the pane where it was
        // relative to the document's top.
        // The container already grew, so the document mustn't autoresize it
        // again.
        if let document = container.superview,
           document === container.enclosingScrollView?.documentView {
            let documentAutoresizes = document.autoresizesSubviews
            document.autoresizesSubviews = false
            document.setFrameSize(NSSize(width: document.frame.width, height: document.frame.height + delta))
            document.autoresizesSubviews = documentAutoresizes
        }
        // A view loaded from a nib records its size in its own awakeFromNib,
        // which may come after its controller's. If it hasn't yet, it will
        // record the grown size then.
        if let sizeRememberingView = container as? iTermSizeRememberingView,
           sizeRememberingView.originalSize != .zero {
            var size = sizeRememberingView.originalSize
            size.height += delta
            sizeRememberingView.originalSize = size
        }
    }
}
