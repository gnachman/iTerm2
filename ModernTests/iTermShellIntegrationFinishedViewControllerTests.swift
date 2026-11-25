//
//  iTermShellIntegrationFinishedViewControllerTests.swift
//  ModernTests
//
//  Characterization tests for iTermShellIntegrationFinishedViewController, the
//  shell integration installer's last page: an NSViewController that adopts
//  iTermShellIntegrationInstallerViewController with an empty -setBusy:, and
//  that iTermShellIntegrationWindowController.xib instantiates by class name.
//  Written against the Objective-C runtime so they run unchanged against a
//  Swift class with the same runtime name.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class iTermShellIntegrationFinishedViewControllerTests: XCTestCase {
    private let finishedClassName = "iTermShellIntegrationFinishedViewController"

    private func finishedClass() -> AnyClass? {
        return NSClassFromString(finishedClassName)
    }

    func testClassExistsUnderItsObjectiveCNameWithItsSuperclass() {
        guard let cls = finishedClass() else {
            XCTFail("no class")
            return
        }
        XCTAssertTrue(class_getSuperclass(cls) === NSViewController.self)
    }

    func testConformsToTheInstallerViewControllerProtocol() {
        guard let cls = finishedClass(),
              let proto = NSProtocolFromString("iTermShellIntegrationInstallerViewController") else {
            XCTFail("no class or protocol")
            return
        }
        XCTAssertTrue(class_conformsToProtocol(cls, proto))
    }

    func testSetBusySelectorAndEncoding() {
        guard let cls = finishedClass() else {
            XCTFail("no class")
            return
        }
        let selector = NSSelectorFromString("setBusy:")
        guard let method = class_getInstanceMethod(cls, selector),
              let encoding = method_getTypeEncoding(method) else {
            XCTFail("no method")
            return
        }
#if arch(arm64)
        XCTAssertEqual(String(cString: encoding), "v20@0:8B16")
#else
        XCTAssertEqual(String(cString: encoding), "v20@0:8c16")
#endif
        // Implemented by the class itself, not inherited.
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            XCTFail("no method list")
            return
        }
        defer { free(methods) }
        let own = (0..<Int(count)).map { method_getName(methods[$0]) }
        XCTAssertTrue(own.contains(selector))
    }

    // -setBusy: does nothing: it neither loads the view nor changes it.
    func testSetBusyDoesNothing() {
        guard let cls = finishedClass() as? NSViewController.Type else {
            XCTFail("no class")
            return
        }
        let controller = cls.init(nibName: nil, bundle: nil)
        guard let installerController = controller as? iTermShellIntegrationInstallerViewController else {
            XCTFail("does not conform")
            return
        }
        installerController.setBusy(true)
        installerController.setBusy(false)
        XCTAssertFalse(controller.isViewLoaded)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        controller.view = view
        installerController.setBusy(true)
        XCTAssertTrue(controller.view === view)
        XCTAssertEqual(view.subviews.count, 0)
        XCTAssertEqual(view.frame, NSRect(x: 0, y: 0, width: 10, height: 10))
    }

    // The xib names the class (customClass) and connects its view outlet; the
    // window controller holds it in its finishedViewController outlet.
    func testXibInstantiatesTheClassAndConnectsItsView() {
        guard let nib = NSNib(nibNamed: "iTermShellIntegrationWindowController",
                              bundle: Bundle(for: iTermShellIntegrationWindowController.self)) else {
            XCTFail("no nib")
            return
        }
        let owner = iTermShellIntegrationWindowController(window: nil)
        var topLevelObjects: NSArray?
        XCTAssertTrue(nib.instantiate(withOwner: owner, topLevelObjects: &topLevelObjects))
        let finished = (topLevelObjects as? [Any] ?? []).filter {
            NSStringFromClass(type(of: $0 as AnyObject)) == finishedClassName
        }
        XCTAssertEqual(finished.count, 1)
        guard let controller = finished.first as? NSViewController else {
            XCTFail("not a view controller")
            return
        }
        XCTAssertTrue(controller.isViewLoaded)
        XCTAssertTrue(owner.value(forKey: "finishedViewController") as AnyObject === controller)
        (owner.window)?.orderOut(nil)
    }
}
