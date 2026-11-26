//
//  iTermFocusablePanelTests.swift
//  ModernTests
//
//  Characterization tests for iTermFocusablePanel, an NSPanel subclass that
//  can become key and main and accepts first responder, named as a window's
//  customClass in several xibs and made directly by Objective-C and Swift.
//  Written against the Objective-C runtime so they run unchanged against a
//  Swift class with the same runtime name. No panel is ordered in.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class iTermFocusablePanelTests: XCTestCase {
    private let unitClassName = "iTermFocusablePanel"
    private let selectorNames = ["canBecomeKeyWindow", "canBecomeMainWindow", "acceptsFirstResponder"]

    private func panelClass() -> NSPanel.Type? {
        return NSClassFromString(unitClassName) as? NSPanel.Type
    }

    // Borderless, so that NSPanel's own answers would be NO for key and main.
    private func makePanel() -> NSPanel? {
        guard let cls = panelClass() else {
            return nil
        }
        let panel = cls.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: true)
        panel.isReleasedWhenClosed = false
        return panel
    }

    func testClassExistsUnderItsObjectiveCNameWithItsSuperclass() {
        guard let cls = panelClass() else {
            XCTFail("no class")
            return
        }
        XCTAssertTrue(class_getSuperclass(cls) === NSPanel.self)
    }

    func testSelectorsAndEncodings() {
        guard let cls = panelClass() else {
            XCTFail("no class")
            return
        }
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            XCTFail("no method list")
            return
        }
        defer { free(methods) }
        let own = Dictionary(uniqueKeysWithValues: (0..<Int(count)).map {
            (NSStringFromSelector(method_getName(methods[$0])),
             method_getTypeEncoding(methods[$0]).map { String(cString: $0) } ?? "")
        })
        for name in selectorNames {
            XCTAssertEqual(own[name], "B16@0:8", name)
        }
    }

    func testCanBecomeKeyWindow() {
        guard let panel = makePanel() else {
            XCTFail("no panel")
            return
        }
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.isVisible)
    }

    func testCanBecomeMainWindow() {
        guard let panel = makePanel() else {
            XCTFail("no panel")
            return
        }
        XCTAssertTrue(panel.canBecomeMain)
    }

    func testAcceptsFirstResponder() {
        guard let panel = makePanel() else {
            XCTFail("no panel")
            return
        }
        XCTAssertTrue(panel.acceptsFirstResponder)
    }

    // The xib names the class as its window's customClass; the window is not
    // visible at launch, so instantiating the nib orders nothing in. No owner:
    // only the File's Owner outlets go unconnected.
    func testXibInstantiatesTheClass() {
        guard let nib = NSNib(nibNamed: "iTermStatusBarSetupConfigureComponentWindowController",
                              bundle: Bundle(for: iTermShellIntegrationWindowController.self)) else {
            XCTFail("no nib")
            return
        }
        var topLevelObjects: NSArray?
        XCTAssertTrue(nib.instantiate(withOwner: nil, topLevelObjects: &topLevelObjects))
        let panels = (topLevelObjects as? [Any] ?? []).filter {
            NSStringFromClass(type(of: $0 as AnyObject)) == unitClassName
        }
        XCTAssertEqual(panels.count, 1)
        guard let panel = panels.first as? NSPanel else {
            XCTFail("not a panel")
            return
        }
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
        XCTAssertTrue(panel.acceptsFirstResponder)
    }
}
