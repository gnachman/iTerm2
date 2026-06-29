//
//  CompanionTerminalFrameSource.swift
//  iTerm2
//
//  The live frame source for a real terminal session: renders the visible grid
//  (the bottom `height` rows, i.e. the live viewport, not scrollback) via the
//  same renderer-independent offscreen CoreGraphics path the screenshot feature
//  uses. Works for sessions that are not on screen by temporarily re-attaching
//  the textview's data source, mirroring handleFetchSessionContent.
//
//  Must be used on the main thread (PTYTextView rendering is main-thread only).
//

import AppKit
import Foundation

final class CompanionTerminalFrameSource: CompanionFrameSource {
    private let session: PTYSession

    init(session: PTYSession) {
        self.session = session
    }

    var columns: Int { Int(session.columns) }
    var rows: Int { Int(session.screen.height()) }
    var scale: Double { Double(session.textview?.window?.backingScaleFactor ?? 2.0) }

    func renderCurrentScreen() -> CGImage? {
        guard let textview = session.textview, textview.frame.width > 0 else {
            return nil
        }
        // The live viewport is the bottom `height` rows: [numberOfScrollbackLines,
        // numberOfScrollbackLines + height).
        let scrollback = Int(session.screen.numberOfScrollbackLines())
        let height = Int(session.screen.height())
        guard height > 0 else { return nil }
        let range = NSRange(location: scrollback, length: height)
        let background = session.processedBackgroundColor ?? .black

        // Buried/peer/parked sessions detach the data source, which would make the
        // renderer see zero lines; re-attach for the render and restore after.
        let wasDetached = textview.dataSource == nil
        if wasDetached {
            textview.dataSource = session.screen
        }
        defer {
            if wasDetached {
                textview.dataSource = nil
            }
        }

        guard let image = textview.renderImage(withLines: range,
                                               includeMargins: false,
                                               backgroundColor: background,
                                               showCursor: true) else {
            return nil
        }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
