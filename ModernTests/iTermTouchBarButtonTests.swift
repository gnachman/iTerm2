//
//  iTermTouchBarButtonTests.swift
//  ModernTests
//
//  Characterization tests for iTermTouchBarButton, the NSButton subclass that
//  the window's touch bar uses for its buttons. It adds one property,
//  keyBindingAction, a copied dictionary that describes what the button does
//  (a key binding action's dictionary, or one holding a man page command or
//  a color preset name), which the touch bar code sets to nil when a button
//  no longer has an action. The
//  touch bar code makes these buttons with NSButton's class factories
//  +buttonWithTitle:target:action: and +buttonWithImage:target:action:.
//  Everything goes through the Objective-C runtime: the class is found by
//  name and its accessors are sent by selector, as Objective-C reaches them.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

// The selectors of the button's property accessors and of NSButton's class
// factories, sent by name through AnyObject.
@objc private protocol TouchBarButtonSelectors {
    @objc(keyBindingAction)
    func keyBindingActionBySelector() -> NSDictionary?

    @objc(setKeyBindingAction:)
    func setKeyBindingActionBySelector(_ dictionary: NSDictionary?)

    @objc(buttonWithTitle:target:action:)
    func buttonBySelector(title: String, target: AnyObject?, action: Selector?) -> NSButton

    @objc(buttonWithImage:target:action:)
    func buttonBySelector(image: NSImage, target: AnyObject?, action: Selector?) -> NSButton
}

// An object that the tests watch with a weak reference to see when the
// button's dictionary lets go of it.
private final class TouchBarButtonWitness: NSObject {}

final class iTermTouchBarButtonTests: XCTestCase {
    private let unitClassName = "iTermTouchBarButton"
    private let frame = NSRect(x: 0, y: 0, width: 40, height: 20)

    private func buttonClass() throws -> NSButton.Type {
        return try XCTUnwrap(NSClassFromString(unitClassName) as? NSButton.Type)
    }

    private func instanceMethodEncoding(_ cls: AnyClass, _ name: String) -> String? {
        guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)),
              let encoding = method_getTypeEncoding(method) else {
            return nil
        }
        return String(cString: encoding)
    }

    private func keyBindingAction(of button: NSButton) -> NSDictionary? {
        return (button as AnyObject).keyBindingActionBySelector?() ?? nil
    }

    private func setKeyBindingAction(_ dictionary: NSDictionary?, on button: NSButton) {
        (button as AnyObject).setKeyBindingActionBySelector?(dictionary)
    }

    @objc private func touchBarButtonTestAction(_ sender: Any?) {}

    // MARK: - The runtime interface

    func testClassIsFoundByItsRuntimeNameWithItsSuperclass() throws {
        let cls = try buttonClass()
        XCTAssertTrue(class_getSuperclass(cls) === NSButton.self)
    }

    func testAccessorSelectorsAndEncodings() throws {
        let cls = try buttonClass()
        XCTAssertEqual(instanceMethodEncoding(cls, "keyBindingAction"), "@16@0:8")
        XCTAssertEqual(instanceMethodEncoding(cls, "setKeyBindingAction:"), "v24@0:8@16")
    }

    // The property is a readwrite, nonatomic, copied NSDictionary.
    func testPropertyAttributes() throws {
        let cls = try buttonClass()
        let property = try XCTUnwrap(class_getProperty(cls, "keyBindingAction"))
        let attributes = try XCTUnwrap(property_getAttributes(property))
        let parts = String(cString: attributes).split(separator: ",").map(String.init)
        XCTAssertEqual(parts.first, "T@\"NSDictionary\"")
        XCTAssertTrue(parts.contains("C"), parts.joined(separator: ","))
        XCTAssertTrue(parts.contains("N"), parts.joined(separator: ","))
        XCTAssertFalse(parts.contains("R"), parts.joined(separator: ","))
    }

    // MARK: - The property

    func testKeyBindingActionIsNilInitially() throws {
        let button = try buttonClass().init(frame: frame)
        XCTAssertNil(keyBindingAction(of: button))
    }

    func testKeyBindingActionRoundTrips() throws {
        let button = try buttonClass().init(frame: frame)
        setKeyBindingAction(["command": "man ls"] as NSDictionary, on: button)
        XCTAssertEqual(keyBindingAction(of: button), ["command": "man ls"] as NSDictionary)
        setKeyBindingAction(["presetName": "Solarized"] as NSDictionary, on: button)
        XCTAssertEqual(keyBindingAction(of: button), ["presetName": "Solarized"] as NSDictionary)
    }

    // The touch bar code clears the action of the man page button by setting
    // nil.
    func testKeyBindingActionCanBeSetBackToNil() throws {
        let button = try buttonClass().init(frame: frame)
        setKeyBindingAction(["command": "man ls"] as NSDictionary, on: button)
        setKeyBindingAction(nil, on: button)
        XCTAssertNil(keyBindingAction(of: button))
    }

    // A mutable dictionary changed after it was assigned must not change the
    // button's action.
    func testKeyBindingActionCopiesAMutableDictionary() throws {
        let button = try buttonClass().init(frame: frame)
        let mutable = NSMutableDictionary(dictionary: ["presetName": "Light"])
        setKeyBindingAction(mutable, on: button)
        mutable["presetName"] = "Dark"
        mutable["extra"] = 1
        XCTAssertEqual(keyBindingAction(of: button), ["presetName": "Light"] as NSDictionary)
    }

    // The value that a key binding stores under its keys is handed back as it
    // was, whatever its class.
    func testKeyBindingActionKeepsValuesOfAnyClass() throws {
        let button = try buttonClass().init(frame: frame)
        let witness = TouchBarButtonWitness()
        setKeyBindingAction(["action": 12, "object": witness] as NSDictionary, on: button)
        let stored = try XCTUnwrap(keyBindingAction(of: button))
        XCTAssertEqual(stored["action"] as? NSNumber, 12)
        XCTAssertTrue(stored["object"] as AnyObject === witness)
    }

    // MARK: - Construction

    func testButtonWithTitleMakesThisClass() throws {
        let cls = try buttonClass()
        let made = try XCTUnwrap((cls as AnyObject).buttonBySelector?(
            title: "F1", target: self, action: #selector(touchBarButtonTestAction(_:))))
        XCTAssertTrue(type(of: made) == cls)
        XCTAssertEqual(made.title, "F1")
        XCTAssertTrue(made.target === self)
        XCTAssertEqual(made.action, #selector(touchBarButtonTestAction(_:)))
        XCTAssertNil(keyBindingAction(of: made))
        setKeyBindingAction(["presetName": "Dark"] as NSDictionary, on: made)
        XCTAssertEqual(keyBindingAction(of: made), ["presetName": "Dark"] as NSDictionary)
    }

    func testButtonWithImageMakesThisClass() throws {
        let cls = try buttonClass()
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let made = try XCTUnwrap((cls as AnyObject).buttonBySelector?(
            image: image, target: self, action: #selector(touchBarButtonTestAction(_:))))
        XCTAssertTrue(type(of: made) == cls)
        XCTAssertTrue(made.image === image)
        XCTAssertNil(keyBindingAction(of: made))
    }

    func testPlainInitializersMakeThisClass() throws {
        let cls = try buttonClass()
        let byInit = (cls as NSObject.Type).init()
        XCTAssertTrue(type(of: byInit) == cls)
        let byFrame = cls.init(frame: frame)
        XCTAssertTrue(type(of: byFrame) == cls)
        XCTAssertEqual(byFrame.frame, frame)
    }

    // MARK: - Lifetime

    // The button holds its dictionary until the button itself goes away, and
    // then releases it, together with the values inside it.
    func testDictionaryIsReleasedWithTheButton() throws {
        let cls = try buttonClass()
        weak var weakButton: NSButton?
        weak var weakWitness: TouchBarButtonWitness?
        autoreleasepool {
            let witness = TouchBarButtonWitness()
            weakWitness = witness
            let button = (cls as AnyObject).buttonBySelector?(title: "F2", target: nil, action: nil)
            weakButton = button
            if let button {
                setKeyBindingAction(NSMutableDictionary(dictionary: ["object": witness]), on: button)
            }
        }
        XCTAssertNil(weakButton)
        XCTAssertNil(weakWitness)
    }

    // Replacing the dictionary releases the one it replaces.
    func testReplacedDictionaryIsReleased() throws {
        let button = try buttonClass().init(frame: frame)
        weak var weakWitness: TouchBarButtonWitness?
        autoreleasepool {
            let witness = TouchBarButtonWitness()
            weakWitness = witness
            setKeyBindingAction(NSMutableDictionary(dictionary: ["object": witness]), on: button)
            setKeyBindingAction(["command": "man ls"] as NSDictionary, on: button)
        }
        XCTAssertNil(weakWitness)
        XCTAssertEqual(keyBindingAction(of: button), ["command": "man ls"] as NSDictionary)
    }
}
