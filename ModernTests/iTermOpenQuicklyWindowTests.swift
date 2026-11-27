//
//  iTermOpenQuicklyWindowTests.swift
//  ModernTests
//
//  Characterization tests for iTermOpenQuicklyWindow, the panel of the Open
//  Quickly window, named as a custom class in
//  iTermOpenQuicklyWindowController.xib. Its initializer adds
//  NSWindowStyleMaskNonactivatingPanel to the style mask and clears the
//  panel's hides-on-deactivate state; it can always become key, always
//  answers NO to hidesOnDeactivate, takes its resize animation time from an
//  advanced setting, and answers fixed values to the hotkey window and focus
//  follows mouse queries. The class is found by its runtime name, as nib
//  loading finds it. Nothing is put on screen: no panel is ever ordered in.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

// Selectors the tests send by name through AnyObject.
@objc private protocol OpenQuicklyWindowSelectors {
    @objc func autoHidesHotKeyWindow() -> Bool

    @objc(disableFocusFollowsMouse)
    func disablesFocusFollowsMouse() -> Bool

    @objc(implementsDisableFocusFollowsMouse)
    func implementsDisablingFocusFollowsMouse() -> Bool
}

// A panel class with no state of its own whose storedHidesOnDeactivate
// calls NSPanel's hidesOnDeactivate getter, which reports the state that
// -setHidesOnDeactivate: stores.
private final class StoredStateProbe: NSPanel {
    var storedHidesOnDeactivate: Bool {
        return super.hidesOnDeactivate
    }
}

final class iTermOpenQuicklyWindowTests: XCTestCase {
    private let unitClassName = "iTermOpenQuicklyWindow"

    private var windowClass: NSPanel.Type? {
        return NSClassFromString(unitClassName) as? NSPanel.Type
    }

    private func ownMethods(_ cls: AnyClass) -> [String: String] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            return [:]
        }
        defer { free(methods) }
        return Dictionary(uniqueKeysWithValues: (0..<Int(count)).map {
            (NSStringFromSelector(method_getName(methods[$0])),
             method_getTypeEncoding(methods[$0]).map { String(cString: $0) } ?? "")
        })
    }

    private func encoding(_ cls: AnyClass, _ selector: String) -> String? {
        guard let method = class_getInstanceMethod(cls, NSSelectorFromString(selector)),
              let types = method_getTypeEncoding(method) else {
            return nil
        }
        return String(cString: types)
    }

    private func makePanel(_ styleMask: NSWindow.StyleMask) -> NSPanel? {
        guard let cls = windowClass else {
            XCTFail("no class")
            return nil
        }
        let panel = cls.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                             styleMask: styleMask,
                             backing: .buffered,
                             defer: true)
        panel.isReleasedWhenClosed = false
        return panel
    }

    // NSPanel's own hidesOnDeactivate, which reports the state that
    // -setHidesOnDeactivate: stores, whatever a subclass's getter answers.
    // The panel's class is replaced by the probe's for the duration of the
    // call; neither class adds instance variables to NSPanel's.
    private func storedHidesOnDeactivate(_ panel: NSPanel) -> Bool? {
        guard let originalClass = object_getClass(panel) else {
            XCTFail("no class")
            return nil
        }
        object_setClass(panel, StoredStateProbe.self)
        defer { object_setClass(panel, originalClass) }
        return (panel as? StoredStateProbe)?.storedHidesOnDeactivate
    }

    func testClassExistsUnderItsNameWithItsSuperclass() {
        guard let cls = windowClass else {
            XCTFail("no class")
            return
        }
        XCTAssertTrue(class_getSuperclass(cls) === NSPanel.self)
    }

    func testSelectorsAndEncodings() {
        guard let cls = windowClass else {
            XCTFail("no class")
            return
        }
        let methods = ownMethods(cls)
        for selector in ["initWithContentRect:styleMask:backing:defer:",
                         "canBecomeKeyWindow",
                         "hidesOnDeactivate",
                         "animationResizeTime:"] {
            XCTAssertNotNil(methods[selector], selector)
            XCTAssertEqual(methods[selector], encoding(NSPanel.self, selector), selector)
        }
        XCTAssertEqual(methods["autoHidesHotKeyWindow"], "B16@0:8")
        XCTAssertEqual(methods["disableFocusFollowsMouse"], "B16@0:8")
        XCTAssertEqual(methods["implementsDisableFocusFollowsMouse"], "B16@0:8")
    }

    func testInitializerAddsNonactivatingPanelAndKeepsTheRest() {
        guard let titled = makePanel([.titled, .closable]),
              let borderless = makePanel([]) else {
            return
        }
        XCTAssertEqual(titled.styleMask, [.titled, .closable, .nonactivatingPanel])
        XCTAssertEqual(borderless.styleMask, [.nonactivatingPanel])
        XCTAssertFalse(titled.isVisible)
        XCTAssertFalse(borderless.isVisible)
    }

    func testInitializerKeepsTheContentRect() {
        guard let panel = makePanel([.borderless]) else {
            return
        }
        XCTAssertEqual(panel.contentRect(forFrameRect: panel.frame).size, NSSize(width: 200, height: 100))
    }

    func testInitializerClearsTheStoredHidesOnDeactivate() {
        guard let panel = makePanel([.titled]) else {
            return
        }
        let plain = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                            styleMask: [.titled],
                            backing: .buffered,
                            defer: true)
        XCTAssertEqual(storedHidesOnDeactivate(plain), true)
        XCTAssertEqual(storedHidesOnDeactivate(panel), false)
    }

    func testHidesOnDeactivateIsAlwaysNo() {
        guard let panel = makePanel([.titled]) else {
            return
        }
        XCTAssertFalse(panel.hidesOnDeactivate)
        panel.hidesOnDeactivate = true
        XCTAssertFalse(panel.hidesOnDeactivate)
    }

    // Setting hidesOnDeactivate still reaches NSPanel's stored state.
    func testSettingHidesOnDeactivateStoresTheValue() {
        guard let panel = makePanel([.titled]) else {
            return
        }
        panel.hidesOnDeactivate = true
        XCTAssertEqual(storedHidesOnDeactivate(panel), true)
        panel.hidesOnDeactivate = false
        XCTAssertEqual(storedHidesOnDeactivate(panel), false)
    }

    // A plain borderless panel cannot become key; this one can.
    func testCanBecomeKeyEvenWhenBorderless() {
        guard let titled = makePanel([.titled]),
              let borderless = makePanel([.borderless]) else {
            return
        }
        XCTAssertTrue(titled.canBecomeKey)
        XCTAssertTrue(borderless.canBecomeKey)
        let plain = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                            styleMask: [.borderless],
                            backing: .buffered,
                            defer: true)
        XCTAssertFalse(plain.canBecomeKey)
    }

    func testAnimationResizeTimeIsTheAdvancedSettingClampedAtZero() {
        guard let panel = makePanel([.titled]) else {
            return
        }
        let setting = iTermAdvancedSettingsModel.openQuicklyAnimationDuration()
        let expected = setting > 0 ? setting : 0
        let far = NSRect(x: 0, y: 0, width: 2000, height: 2000)
        XCTAssertEqual(panel.animationResizeTime(far), expected)
        XCTAssertEqual(panel.animationResizeTime(panel.frame), expected)
    }

    func testDoesNotAutoHideTheHotKeyWindow() {
        guard let panel = makePanel([.titled]) else {
            return
        }
        XCTAssertTrue(panel.responds(to: NSSelectorFromString("autoHidesHotKeyWindow")))
        XCTAssertEqual((panel as AnyObject).autoHidesHotKeyWindow?(), false)
    }

    func testDisablesFocusFollowsMouse() {
        guard let panel = makePanel([.titled]) else {
            return
        }
        XCTAssertEqual((panel as AnyObject).disablesFocusFollowsMouse?(), true)
        XCTAssertEqual((panel as AnyObject).implementsDisablingFocusFollowsMouse?(), true)
        let plain = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        XCTAssertEqual((plain as AnyObject).disablesFocusFollowsMouse?(), false)
        XCTAssertEqual((plain as AnyObject).implementsDisablingFocusFollowsMouse?(), false)
    }

    func testTheNibMakesThePanelWithThisClass() {
        guard let nib = NSNib(nibNamed: "iTermOpenQuicklyWindowController", bundle: nil) else {
            XCTFail("no nib")
            return
        }
        var objects: NSArray?
        XCTAssertTrue(nib.instantiate(withOwner: nil, topLevelObjects: &objects))
        let windows = (objects as? [Any] ?? []).compactMap { $0 as? NSWindow }
        XCTAssertEqual(windows.map { NSStringFromClass(type(of: $0)) }, [unitClassName])
        guard let window = windows.first else {
            return
        }
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(window.hidesOnDeactivate)
        XCTAssertTrue(window.canBecomeKey)
    }
}
