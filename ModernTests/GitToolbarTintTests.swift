//
//  GitToolbarTintTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

/// F-334: the workgroup git item tinted its ahead/behind arrows with
/// labelColor resolved against the app theme rather than the toolbar's own
/// appearance, so a dark Minimal toolbar in a light system got black arrows.
final class GitToolbarTintTests: XCTestCase {
    private func brightness(_ color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB)!
        return (rgb.redComponent + rgb.greenComponent + rgb.blueComponent) / 3
    }

    func testLabelColorFollowsTheGivenAppearance() throws {
        let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let light = try XCTUnwrap(NSAppearance(named: .aqua))
        // Resolve while the current drawing appearance is the opposite one, as
        // it would be when the app theme disagrees with the toolbar.
        var onDark = NSColor.black
        light.performAsCurrentDrawingAppearance {
            onDark = CCGitSessionToolbarItem.resolvedLabelColor(for: dark)
        }
        var onLight = NSColor.white
        dark.performAsCurrentDrawingAppearance {
            onLight = CCGitSessionToolbarItem.resolvedLabelColor(for: light)
        }
        XCTAssertGreaterThan(brightness(onDark), 0.5)
        XCTAssertLessThan(brightness(onLight), 0.5)
    }
}
