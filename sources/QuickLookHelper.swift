//
//  QuickLookHelper.swift
//  iTerm2
//
//  Created by George Nachman on 6/16/25.
//

import QuickLookUI

class QuickLookHelper: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookHelper()

    private var fileURLs: [URL] = []
    private var sourceRect: NSRect = .zero

    // Keep track of who we spliced out of the responder chain
    private weak var windowHoldingUs: NSWindow?
    private weak var originalNextResponder: NSResponder?

    /// Show Quick Look for the given URLs,
    /// animating out of the provided screen-coords rect.
    func showQuickLook(for urls: [URL],
                       from sourceRect: NSRect) {
        guard let window = NSApp.keyWindow else {
            return
        }

        self.fileURLs = urls
        self.sourceRect = sourceRect
        self.windowHoldingUs = window

        let contentView = window.contentView!
        originalNextResponder = contentView.nextResponder
        contentView.nextResponder = self

        QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSResponder “panel controller” plumbing

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self

        panel.reloadData()
        panel.currentPreviewItemIndex = 0
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        if let window = windowHoldingUs {
            window.contentView?.nextResponder = originalNextResponder
        }
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return fileURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!,
                      previewItemAt index: Int) -> QLPreviewItem! {
        return fileURLs[index] as QLPreviewItem
    }

    // MARK: - QLPreviewPanelDelegate (animation support)

    func previewPanel(_ panel: QLPreviewPanel!,
                      sourceFrameOnScreenFor previewItem: QLPreviewItem!) -> NSRect {
        return sourceRect
    }

    func previewPanel(_ panel: QLPreviewPanel!,
                      transitionImageFor previewItem: QLPreviewItem!) -> NSImage! {
        let idx = panel.currentPreviewItemIndex
        let url = fileURLs[idx]
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

extension QuickLookHelper {
    func sourceFrameOnScreen(for outlineView: NSOutlineView) -> NSRect {
        let indexes = outlineView.selectedRowIndexes
        // If nothing selected, fall back to entire outline view.
        guard !indexes.isEmpty else {
            guard let window = outlineView.window else {
                return .zero
            }
            let viewBounds = outlineView.bounds
            let rectInWindow = outlineView.convert(viewBounds, to: nil)
            return window.convertToScreen(rectInWindow)
        }

        // get the visible portion of the outline
        let visibleRect = outlineView.enclosingScrollView?
                            .contentView.bounds
                          ?? outlineView.bounds

        // union all selected & visible row rects
        var unionRect: NSRect?
        for row in indexes {
            let rowRect = outlineView.rect(ofRow: row)
            if visibleRect.intersects(rowRect) {
                if let existing = unionRect {
                    unionRect = existing.union(rowRect)
                } else {
                    unionRect = rowRect
                }
            }
        }

        // if we found some visible rows, zoom from their union
        if let selectedRect = unionRect {
            guard let window = outlineView.window else {
                return .zero
            }
            let rectInWindow = outlineView.convert(selectedRect, to: nil)
            return window.convertToScreen(rectInWindow)
        }

        // none of the selected rows are visible → fall back to full outline
        guard let window = outlineView.window else {
            return .zero
        }
        let viewBounds = outlineView.bounds
        let rectInWindow = outlineView.convert(viewBounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }
}
