//
//  TerminalRenderer.swift
//  ModernTests
//
//  Renders a terminal session to a PNG file for automated visual testing.
//  Uses iTermHeadlessWindowController and session creation from the main target.
//

import Foundation
import XCTest
@testable import iTerm2SharedARC

enum TerminalRendererError: Error {
    case profileNotFound
    case renderFailed
    case metalUnavailable
    case metalRenderFailed
}

class TerminalRenderer {
    /// Renders a terminal session to a PNG file.
    static func render(
        rows: Int,
        columns: Int,
        profileGUID: String,
        data: Data,
        path: String,
        gpu: Bool
    ) throws {
        guard let profile = ProfileModel.sharedInstance()?.bookmark(withGuid: profileGUID) else {
            throw TerminalRendererError.profileNotFound
        }

        let fontTable = FontTable.fontTable(forProfile: profile)
        let hSpacing = iTermProfilePreferences.double(forKey: KEY_HORIZONTAL_SPACING, inProfile: profile)
        let vSpacing = iTermProfilePreferences.double(forKey: KEY_VERTICAL_SPACING, inProfile: profile)
        let charSize = PTYTextView.charSize(
            for: fontTable.fontForCharacterSizeCalculations,
            horizontalSpacing: CGFloat(hSpacing),
            verticalSpacing: CGFloat(vSpacing))
        let sideMargins = CGFloat(iTermPreferences.int(forKey: kPreferenceKeySideMargins))
        let topBottomMargins = CGFloat(iTermPreferences.int(forKey: kPreferenceKeyTopBottomMargins))
        let frameSize = NSSize(
            width: CGFloat(columns) * charSize.width + sideMargins * 2,
            height: CGFloat(rows) * charSize.height + topBottomMargins * 2)

        let session = PTYSession(synthetic: true)!
        session.profile = profile
        let parent = iTermHeadlessWindowController(frame: NSRect(origin: .zero, size: frameSize))
        session.setScreenSize(frameSize, parent: parent)
        session.setPreferencesFromAddressBookEntry(profile)
        session.loadInitialColorTableAndResetCursorGuide()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        if !data.isEmpty {
            session.inject(data)
            session.screen.performBlock(joinedThreads: { _, _, _ in })
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }

        if gpu {
            try renderWithMetal(session: session, frameSize: frameSize, path: path)
        } else {
            let image = try renderWithLegacy(session: session, rows: rows)
            image.saveAsPNG(to: path)
        }
    }

    private static func renderWithLegacy(session: PTYSession, rows: Int) throws -> NSImage {
        let scrollbackLines = Int(session.screen.numberOfScrollbackLines())
        session.textview.setDrawingHelperIsRetina((NSScreen.main?.backingScaleFactor ?? 2.0) > 1)
        guard let image = session.textview.renderLines(toImage: NSRange(location: scrollbackLines, length: rows)) else {
            throw TerminalRendererError.renderFailed
        }
        return image
    }

    private static func renderWithMetal(session: PTYSession, frameSize: NSSize, path: String) throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw TerminalRendererError.metalUnavailable
        }
        guard let screen = NSScreen.main else {
            throw TerminalRendererError.metalRenderFailed
        }
        let window = NSWindow(
            contentRect: NSRect(origin: screen.frame.origin, size: frameSize),
            styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.contentView = session.view
        window.orderFront(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        session.useMetal = true
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2.0))
        session.updateMetalDriver()

        guard let image = session.view.drawMetalFrameToImage() else {
            window.orderOut(nil)
            throw TerminalRendererError.metalRenderFailed
        }
        image.saveAsPNG(to: path)
        window.orderOut(nil)
    }
}
