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
    private var onPanelClosed: (() -> Void)?

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
    
    /// Show Quick Look with initial URLs and support for progressive additions
    func showQuickLook(for initialUrls: [URL],
                       from sourceRect: NSRect,
                       onPanelClosed: @escaping () -> Void) {
        self.onPanelClosed = onPanelClosed
        showQuickLook(for: initialUrls, from: sourceRect)
    }
    
    /// Add a new file URL to the existing QuickLook panel
    func addFileURL(_ url: URL) {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else {
            return
        }
        
        fileURLs.append(url)
        panel.reloadData()
    }
    
    /// Show QuickLook with support for downloading remote URLs
    func showQuickLookWithDownloads(for urls: [URL], from sourceRect: NSRect) {
        // Separate local and web URLs
        let localUrls = urls.filter { $0.isFileURL }
        let remoteUrls = urls.filter { !$0.isFileURL }
        
        // Show QuickLook immediately with local files
        showQuickLook(for: localUrls, from: sourceRect) { [weak self] in
            // Cancel downloads when QuickLook is closed
            self?.cancelDownloads()
        }
        
        // Start downloading remote URLs and add them as they complete
        if !remoteUrls.isEmpty {
            downloadUrlsProgressively(remoteUrls)
        }
    }
    
    private var downloadTasks: [Task<Void, Never>] = []
    
    private func downloadUrlsProgressively(_ urls: [URL]) {
        for url in urls {
            let task = Task { [weak self] in
                if let localUrl = await self?.downloadUrlToTemporaryFile(url) {
                    await MainActor.run {
                        self?.addFileURL(localUrl)
                    }
                }
            }
            downloadTasks.append(task)
        }
    }
    
    private func cancelDownloads() {
        for task in downloadTasks {
            task.cancel()
        }
        downloadTasks.removeAll()
    }
    
    private func downloadUrlToTemporaryFile(_ url: URL) async -> URL? {
        guard url.scheme == "http" || url.scheme == "https" else {
            return url
        }
        
        do {
            // Check for cancellation before starting download
            try Task.checkCancellation()
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // Check for cancellation after download but before file operations
            try Task.checkCancellation()
            
            let mimeType = response.mimeType ?? "application/octet-stream"
            let fileExtension = MimeTypeUtilities.extensionForMimeType(mimeType)
            
            let tempDirectory = FileManager.default.temporaryDirectory
            let filename = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
            let sanitizedFilename = sanitizeFilename(filename)
            let finalFilename = "\(sanitizedFilename).\(fileExtension)"
            let tempFileUrl = tempDirectory.appendingPathComponent(finalFilename)
            
            try data.write(to: tempFileUrl)
            DLog("Downloaded \(url) to \(tempFileUrl)")
            return tempFileUrl
        } catch is CancellationError {
            DLog("Download cancelled for \(url)")
            return nil
        } catch {
            DLog("Failed to download \(url): \(error)")
            return nil
        }
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
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
        
        // Notify that the panel was closed
        onPanelClosed?()
        onPanelClosed = nil
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
