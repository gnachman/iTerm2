//
//  iTermShellIntegrationPanelTests.swift
//  ModernTests
//
//  Characterization tests for iTermShellIntegrationPanel, the empty NSPanel subclass that
//  iTermShellIntegrationWindowController.xib names as its window's custom class. The xib
//  declares a plain window, so this class is what makes the installer's window an NSPanel,
//  and windowDidLoad depends on that (it sends setFloatingPanel:). The class is reached only
//  through the runtime and the nib, never by name in code, so these tests run unchanged
//  against the Objective-C class and against its Swift port.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermShellIntegrationPanelTests: XCTestCase {
    private static let className = "iTermShellIntegrationPanel"
    private static let nibName = "iTermShellIntegrationWindowController"

    private var controller: iTermShellIntegrationWindowController?

    override func tearDown() {
        if let controller {
            controller.shellIntegrationInstallerCancelExpectations()
            if controller.isWindowLoaded {
                controller.window?.orderOut(nil)
            }
        }
        controller = nil
        super.tearDown()
    }

    // The xib finds the class by this bare name, and its superclass is exactly NSPanel.
    func testClassResolvesByNameAndIsADirectSubclassOfNSPanel() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(Self.className))
        XCTAssertEqual(NSStringFromClass(cls), Self.className)
        let superclass: AnyClass = try XCTUnwrap(class_getSuperclass(cls))
        XCTAssertTrue(superclass === NSPanel.self, "superclass is \(NSStringFromClass(superclass))")
    }

    // Loads the installer's window the way -[PTYTextView installShellIntegration:] does: the
    // window controller is the nib's owner and the nib loads on the first read of window.
    func testInstallerWindowLoadsAsThisClass() throws {
        let controller = iTermShellIntegrationWindowController(windowNibName: Self.nibName)
        self.controller = controller
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(NSStringFromClass(type(of: window)), Self.className)
        XCTAssertTrue(type(of: window) === NSClassFromString(Self.className))
        let panel = try XCTUnwrap(window as? NSPanel, "the window is not an NSPanel")
        // The xib's delegate outlet connects the window to File's Owner.
        XCTAssertTrue(panel.delegate === controller)
        XCTAssertTrue(panel.windowController === controller)
        // Set by windowDidLoad through the NSPanel-only setFloatingPanel:.
        XCTAssertTrue(panel.isFloatingPanel)
        // visibleAtLaunch is NO in the xib, so loading puts nothing on screen.
        XCTAssertFalse(panel.isVisible)
    }
}
