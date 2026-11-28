//
//  iTermHamburgerButtonTests.swift
//  ModernTests
//
//  Characterization tests for iTermHamburgerButton, the borderless button
//  with an ellipsis image that the session title bar and the toolbelt use to
//  open a menu. The button is made with a block that returns the menu, and
//  its cell, iTermHamburgerButtonCell, answers a mouse down by popping up
//  that menu as a context menu centered on the cell instead of tracking the
//  mouse. The cell asks its control view for the menu through the
//  iTermHamburgerButtonCellControl protocol and falls back to NSButtonCell's
//  tracking for a control view that does not adopt it.
//
//  Nothing is put on screen. While a test drives the cell, NSMenu's
//  +popUpContextMenu:withEvent:forView: and NSButtonCell's
//  -trackMouse:inRect:ofView:untilMouseUp: are replaced by implementations
//  that record their arguments, and the originals are put back afterwards.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

// This protocol declares the button's selectors so that the tests can send
// them by name through AnyObject.
@objc private protocol HamburgerButtonSelectors {
    @objc(menuProvider)
    func menuProviderBySelector() -> (@convention(block) () -> NSMenu?)?

    @objc(setMenuProvider:)
    func setMenuProviderBySelector(_ block: @escaping @convention(block) () -> NSMenu?)

    @objc(hamburgerMenu)
    func hamburgerMenuBySelector() -> NSMenu?
}

// One call of NSMenu's +popUpContextMenu:withEvent:forView: as the
// replacement recorded it.
private struct HamburgerPopUpCall {
    var menu: NSMenu?
    var event: NSEvent?
    var view: NSView?
}

// One call of NSButtonCell's -trackMouse:inRect:ofView:untilMouseUp: as the
// replacement recorded it.
private struct HamburgerSuperTrackCall {
    var cell: AnyObject
    var event: NSEvent?
    var rect: NSRect
    var view: NSView?
    var untilMouseUp: Bool
}

private final class HamburgerRecorder {
    var popUps = [HamburgerPopUpCall]()
    var superTracks = [HamburgerSuperTrackCall]()
    // What the replacement of NSButtonCell's tracking returns.
    var superTrackResult = false
}

// An object that the tests watch with a weak reference to see when the
// button lets go of its menu provider.
private final class HamburgerWitness: NSObject {}

final class iTermHamburgerButtonTests: XCTestCase {
    private let buttonClassName = "iTermHamburgerButton"
    private let cellClassName = "iTermHamburgerButtonCell"
    private let protocolName = "iTermHamburgerButtonCellControl"
    private let trackSelector = #selector(NSCell.trackMouse(with:in:of:untilMouseUp:))

    private func instanceMethodEncoding(_ cls: AnyClass, _ name: String) -> String? {
        guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)),
              let encoding = method_getTypeEncoding(method) else {
            return nil
        }
        return String(cString: encoding)
    }

    private func makeButton(_ menu: NSMenu) -> NSButton {
        return iTermHamburgerButton(menuProvider: { menu })
    }

    private func cell(of button: NSButton) throws -> NSButtonCell {
        return try XCTUnwrap(button.cell as? NSButtonCell)
    }

    private func hamburgerMenu(of object: AnyObject) -> NSMenu? {
        return object.hamburgerMenuBySelector?() ?? nil
    }

    private func mouseDown() throws -> NSEvent {
        return try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown,
                                                location: NSPoint(x: 1, y: 2),
                                                modifierFlags: [.option, .shift],
                                                timestamp: 1234.5,
                                                windowNumber: 0,
                                                context: nil,
                                                eventNumber: 77,
                                                clickCount: 2,
                                                pressure: 0.25))
    }

    // Runs body while NSMenu's context menu class method and NSButtonCell's
    // mouse tracking are replaced by recorders, and puts the originals back.
    private func recording(_ recorder: HamburgerRecorder, _ body: () throws -> Void) throws {
        let popUpSelector = #selector(NSMenu.popUpContextMenu(_:with:for:))
        let popUpMethod = try XCTUnwrap(class_getClassMethod(NSMenu.self, popUpSelector))
        let trackMethod = try XCTUnwrap(class_getInstanceMethod(NSButtonCell.self, trackSelector))
        // NSButtonCell must implement the method itself, or replacing the
        // implementation would change NSCell's for every cell.
        let own = trackMethod != class_getInstanceMethod(NSCell.self, trackSelector)
        XCTAssertTrue(own)
        guard own else {
            return
        }

        let popUp: @convention(block) (AnyObject, NSMenu?, NSEvent?, NSView?) -> Void = { _, menu, event, view in
            recorder.popUps.append(HamburgerPopUpCall(menu: menu, event: event, view: view))
        }
        let track: @convention(block) (AnyObject, NSEvent?, NSRect, NSView?, Bool) -> Bool = { cell, event, rect, view, untilMouseUp in
            recorder.superTracks.append(HamburgerSuperTrackCall(cell: cell,
                                                                event: event,
                                                                rect: rect,
                                                                view: view,
                                                                untilMouseUp: untilMouseUp))
            return recorder.superTrackResult
        }
        let popUpIMP = imp_implementationWithBlock(popUp)
        let trackIMP = imp_implementationWithBlock(track)
        let originalPopUp = method_setImplementation(popUpMethod, popUpIMP)
        let originalTrack = method_setImplementation(trackMethod, trackIMP)
        defer {
            method_setImplementation(popUpMethod, originalPopUp)
            method_setImplementation(trackMethod, originalTrack)
            imp_removeBlock(popUpIMP)
            imp_removeBlock(trackIMP)
        }
        try body()
    }

    // MARK: - The runtime interface

    func testClassesAreFoundByTheirRuntimeNamesWithTheirSuperclasses() throws {
        let buttonClass: AnyClass = try XCTUnwrap(NSClassFromString(buttonClassName))
        XCTAssertTrue(class_getSuperclass(buttonClass) === NSButton.self)
        let cellClass: AnyClass = try XCTUnwrap(NSClassFromString(cellClassName))
        XCTAssertTrue(class_getSuperclass(cellClass) === NSButtonCell.self)
    }

    func testSelectorsAndEncodings() throws {
        let buttonClass: AnyClass = try XCTUnwrap(NSClassFromString(buttonClassName))
        XCTAssertEqual(instanceMethodEncoding(buttonClass, "initWithMenuProvider:"), "@24@0:8@?16")
        XCTAssertEqual(instanceMethodEncoding(buttonClass, "menuProvider"), "@?16@0:8")
        XCTAssertEqual(instanceMethodEncoding(buttonClass, "setMenuProvider:"), "v24@0:8@?16")
        XCTAssertEqual(instanceMethodEncoding(buttonClass, "hamburgerMenu"), "@16@0:8")
        let cellClass: AnyClass = try XCTUnwrap(NSClassFromString(cellClassName))
        XCTAssertEqual(instanceMethodEncoding(cellClass, "trackMouse:inRect:ofView:untilMouseUp:"),
                       "B68@0:8@16{CGRect={CGPoint=dd}{CGSize=dd}}24@56B64")
    }

    // The property is a readwrite, nonatomic block.
    func testPropertyAttributes() throws {
        let buttonClass: AnyClass = try XCTUnwrap(NSClassFromString(buttonClassName))
        let property = try XCTUnwrap(class_getProperty(buttonClass, "menuProvider"))
        let attributes = try XCTUnwrap(property_getAttributes(property))
        let parts = String(cString: attributes).split(separator: ",").map(String.init)
        XCTAssertEqual(parts.first, "T@?")
        XCTAssertTrue(parts.contains("N"), parts.joined(separator: ","))
        XCTAssertFalse(parts.contains("R"), parts.joined(separator: ","))
    }

    // The button adopts the protocol through which its cell asks for the
    // menu, and the protocol inherits NSObject's.
    func testButtonConformsToTheCellControlProtocol() throws {
        let proto = try XCTUnwrap(NSProtocolFromString(protocolName))
        XCTAssertTrue(protocol_conformsToProtocol(proto, NSObjectProtocol.self))
        let button = makeButton(NSMenu(title: "M"))
        XCTAssertTrue(button.conforms(to: proto))
        XCTAssertFalse(NSButton(frame: .zero).conforms(to: proto))
    }

    // MARK: - Initialization

    func testInitializerSetsUpABorderlessImageOnlyButtonWithTheHamburgerCell() throws {
        let button = makeButton(NSMenu(title: "M"))
        let buttonClass: AnyClass = try XCTUnwrap(NSClassFromString(buttonClassName))
        XCTAssertTrue(type(of: button) == buttonClass)
        XCTAssertEqual(button.frame, .zero)
        let cell = try cell(of: button)
        XCTAssertEqual(NSStringFromClass(type(of: cell)), cellClassName)
        XCTAssertTrue(cell.controlView === button)
        XCTAssertEqual(button.bezelStyle, .flexiblePush)
        XCTAssertFalse(button.isBordered)
        XCTAssertEqual(button.imagePosition, .imageOnly)
        let image = try XCTUnwrap(button.image)
        let reference = try XCTUnwrap(NSImage.it_hamburger(for: buttonClass))
        XCTAssertEqual(image.accessibilityDescription, "Menu")
        XCTAssertEqual(image.size, reference.size)
    }

    // MARK: - The menu provider

    func testHamburgerMenuReturnsWhatTheProviderReturnsEachTime() throws {
        var calls = 0
        let first = NSMenu(title: "First")
        let second = NSMenu(title: "Second")
        let button = iTermHamburgerButton(menuProvider: {
            calls += 1
            return calls == 1 ? first : second
        })
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(hamburgerMenu(of: button) === first)
        XCTAssertTrue(hamburgerMenu(of: button) === second)
        XCTAssertEqual(calls, 2)
    }

    // The session title bar's provider returns its delegate's menu, which is
    // nil when there is no delegate.
    func testHamburgerMenuIsNilWhenTheProviderReturnsNil() throws {
        let button = makeButton(NSMenu(title: "M"))
        (button as AnyObject).setMenuProviderBySelector?({ nil })
        XCTAssertNil(hamburgerMenu(of: button))
    }

    func testMenuProviderCanBeReadAndReplaced() throws {
        let original = NSMenu(title: "Original")
        let replacement = NSMenu(title: "Replacement")
        let button = makeButton(original)
        let provider = try XCTUnwrap((button as AnyObject).menuProviderBySelector?() ?? nil)
        XCTAssertTrue(provider() === original)
        (button as AnyObject).setMenuProviderBySelector?({ replacement })
        XCTAssertTrue(hamburgerMenu(of: button) === replacement)
        let newProvider = try XCTUnwrap((button as AnyObject).menuProviderBySelector?() ?? nil)
        XCTAssertTrue(newProvider() === replacement)
    }

    // The button keeps its provider, and what the provider captured, until
    // the button goes away.
    func testProviderIsReleasedWithTheButton() throws {
        weak var weakButton: NSButton?
        weak var weakWitness: HamburgerWitness?
        autoreleasepool {
            let witness = HamburgerWitness()
            weakWitness = witness
            let menu = NSMenu(title: "M")
            let button = iTermHamburgerButton(menuProvider: {
                _ = witness
                return menu
            })
            weakButton = button
            XCTAssertNotNil(weakWitness)
        }
        XCTAssertNil(weakButton)
        XCTAssertNil(weakWitness)
    }

    // MARK: - Mouse tracking

    // A mouse down pops up the provider's menu for the button with a copy of
    // the event moved to the center of the cell frame, in the coordinates of
    // the top of the view hierarchy, and reports that tracking is done
    // without calling NSButtonCell's tracking.
    func testTrackMousePopsUpTheMenuAtTheCenterOfTheCellFrame() throws {
        let menu = NSMenu(title: "Hamburger")
        let button = makeButton(menu)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        container.addSubview(button)
        button.frame = NSRect(x: 30, y: 40, width: 20, height: 10)
        XCTAssertTrue(button.isFlipped)
        XCTAssertFalse(container.isFlipped)
        let event = try mouseDown()
        let recorder = HamburgerRecorder()
        var result = false
        try recording(recorder) {
            result = try cell(of: button).trackMouse(with: event,
                                                     in: NSRect(x: 2, y: 3, width: 10, height: 4),
                                                     of: button,
                                                     untilMouseUp: false)
        }
        XCTAssertTrue(result)
        XCTAssertEqual(recorder.superTracks.count, 0)
        XCTAssertEqual(recorder.popUps.count, 1)
        let call = try XCTUnwrap(recorder.popUps.first)
        XCTAssertTrue(call.menu === menu)
        XCTAssertTrue(call.view === button)
        let fake = try XCTUnwrap(call.event)
        XCTAssertFalse(fake === event)
        // The center of the cell frame is (7, 5) in the flipped button,
        // which is (30 + 7, 40 + 10 - 5) in the unflipped container.
        XCTAssertEqual(fake.locationInWindow.x, 37, accuracy: 1e-9)
        XCTAssertEqual(fake.locationInWindow.y, 45, accuracy: 1e-9)
        XCTAssertEqual(fake.type, .leftMouseDown)
        XCTAssertEqual(fake.modifierFlags.intersection(.deviceIndependentFlagsMask), [.option, .shift])
        XCTAssertEqual(fake.timestamp, 1234.5)
        XCTAssertEqual(fake.windowNumber, 0)
        XCTAssertEqual(fake.eventNumber, 77)
        XCTAssertEqual(fake.clickCount, 2)
        XCTAssertEqual(fake.pressure, 0.25)
    }

    // The event's type is copied: a right mouse down stays one.
    func testTrackMouseCopiesTheEventType() throws {
        let button = makeButton(NSMenu(title: "M"))
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown,
                                                     location: .zero,
                                                     modifierFlags: [],
                                                     timestamp: 5,
                                                     windowNumber: 0,
                                                     context: nil,
                                                     eventNumber: 1,
                                                     clickCount: 1,
                                                     pressure: 1))
        let recorder = HamburgerRecorder()
        try recording(recorder) {
            _ = try cell(of: button).trackMouse(with: event, in: button.bounds, of: button, untilMouseUp: true)
        }
        XCTAssertEqual(recorder.popUps.first?.event?.type, .rightMouseDown)
        XCTAssertEqual(recorder.popUps.first?.event?.clickCount, 1)
    }

    // A provider that returns nil still leads to the pop-up call, with nil
    // for the menu.
    func testTrackMousePassesANilMenuThrough() throws {
        let button = makeButton(NSMenu(title: "M"))
        (button as AnyObject).setMenuProviderBySelector?({ nil })
        let event = try mouseDown()
        let recorder = HamburgerRecorder()
        var result = false
        try recording(recorder) {
            result = try cell(of: button).trackMouse(with: event, in: button.bounds, of: button, untilMouseUp: false)
        }
        XCTAssertTrue(result)
        XCTAssertEqual(recorder.popUps.count, 1)
        XCTAssertNil(recorder.popUps.first?.menu)
        XCTAssertTrue(recorder.popUps.first?.view === button)
        XCTAssertEqual(recorder.superTracks.count, 0)
    }

    // Each mouse down asks the provider again.
    func testEachMouseDownAsksTheProviderAgain() throws {
        var calls = 0
        let menu = NSMenu(title: "M")
        let button = iTermHamburgerButton(menuProvider: {
            calls += 1
            return menu
        })
        let event = try mouseDown()
        let recorder = HamburgerRecorder()
        try recording(recorder) {
            let cell = try cell(of: button)
            _ = cell.trackMouse(with: event, in: button.bounds, of: button, untilMouseUp: false)
            _ = cell.trackMouse(with: event, in: button.bounds, of: button, untilMouseUp: false)
        }
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(recorder.popUps.count, 2)
    }

    // A control view that does not adopt the protocol gets NSButtonCell's
    // own tracking with the same arguments, and its answer is returned.
    func testTrackMouseInAnotherViewUsesNSButtonCellTracking() throws {
        let button = makeButton(NSMenu(title: "M"))
        let cell = try cell(of: button)
        let otherView = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let event = try mouseDown()
        let rect = NSRect(x: 1, y: 2, width: 30, height: 40)
        for expected in [false, true] {
            let recorder = HamburgerRecorder()
            recorder.superTrackResult = expected
            var result = !expected
            try recording(recorder) {
                result = cell.trackMouse(with: event, in: rect, of: otherView, untilMouseUp: expected)
            }
            XCTAssertEqual(result, expected)
            XCTAssertEqual(recorder.popUps.count, 0)
            XCTAssertEqual(recorder.superTracks.count, 1)
            let call = try XCTUnwrap(recorder.superTracks.first)
            XCTAssertTrue(call.cell === cell)
            XCTAssertTrue(call.event === event)
            XCTAssertEqual(call.rect, rect)
            XCTAssertTrue(call.view === otherView)
            XCTAssertEqual(call.untilMouseUp, expected)
        }
    }
}
