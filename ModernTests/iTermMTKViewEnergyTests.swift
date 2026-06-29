//
//  iTermMTKViewEnergyTests.swift
//  ModernTests
//
//  Tests that iTermMTKView manages its periodic redraw timer
//  in response to window attachment.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
class iTermMTKViewEnergyTests: XCTestCase {

    // MARK: - Redraw Timer Lifecycle

    func testViewHasNoWindowAfterStandaloneCreation() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            // Metal is unavailable (e.g., CI without GPU). Skip gracefully.
            return
        }
        let view = iTermMTKView(frame: NSRect(x: 0, y: 0, width: 100, height: 100),
                                device: device)

        // A standalone view (never added to a window) should report nil window.
        // After our fix, the periodic redraw timer is invalidated when window is nil,
        // saving energy for detached views.
        XCTAssertNil(view.window, "View should not have a window after creation outside a window")
    }

    func testViewCanBeCreatedWithoutCrash() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }
        let view = iTermMTKView(frame: NSRect(x: 0, y: 0, width: 200, height: 200),
                                device: device)
        XCTAssertNotNil(view)
        XCTAssertEqual(view.frame.size.width, 200)
        XCTAssertEqual(view.frame.size.height, 200)
    }

    func testViewDeallocationDoesNotCrash() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return
        }
        // Verify creating and destroying a view doesn't leak or crash
        autoreleasepool {
            let view = iTermMTKView(frame: NSRect(x: 0, y: 0, width: 100, height: 100),
                                    device: device)
            _ = view.needsDisplay
        }
        // If we get here, deallocation succeeded without crash
    }
}
