//
//  iTermSetFindStringNotificationTests.swift
//  ModernTests
//
//  Characterization tests for iTermSetFindStringNotification, a subclass of
//  iTermBaseNotification that carries one string. The notes tool and the AI
//  chat input post it when the user chooses “Use Selection for Find”. The
//  base class delivers a post synchronously, on the posting thread, to each
//  block subscribed through the posting instance's own class, and only while
//  the block's owner is alive. The class methods are also sent by selector
//  through AnyObject, the way Objective-C reaches them.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

// The class methods of the notification's class, sent by name through
// AnyObject.
@objc private protocol SetFindStringNotificationSelectors {
    @objc(notificationWithString:)
    func notification(withString string: NSString) -> AnyObject

    @objc(subscribe:block:)
    func subscribe(_ owner: NSObject,
                   block: @escaping (iTermSetFindStringNotification) -> Void)
}

// A subclass that adds nothing, used to show that the factory makes an
// instance of the class it is sent to and that posts are delivered by class.
private class SetFindStringNotificationSubclass: iTermSetFindStringNotification {}

final class iTermSetFindStringNotificationTests: XCTestCase {
    private let unitClassName = "iTermSetFindStringNotification"

    private func classMethodEncoding(_ cls: AnyClass, _ name: String) -> String? {
        guard let method = class_getClassMethod(cls, NSSelectorFromString(name)),
              let encoding = method_getTypeEncoding(method) else {
            return nil
        }
        return String(cString: encoding)
    }

    private func instanceMethodEncoding(_ cls: AnyClass, _ name: String) -> String? {
        guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)),
              let encoding = method_getTypeEncoding(method) else {
            return nil
        }
        return String(cString: encoding)
    }

    // The class object, typed as the protocol above so that its class
    // methods can be sent by selector.
    private func selectors(of cls: AnyClass) -> SetFindStringNotificationSelectors {
        return unsafeBitCast(cls as AnyObject, to: SetFindStringNotificationSelectors.self)
    }

    // MARK: - The runtime interface

    func testClassIsFoundByItsRuntimeName() {
        let cls: AnyClass? = NSClassFromString(unitClassName)
        XCTAssertNotNil(cls)
        XCTAssertTrue(cls?.superclass() === iTermBaseNotification.self)
    }

    func testSelectorsAndEncodings() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(unitClassName))
        XCTAssertEqual(classMethodEncoding(cls, "notificationWithString:"), "@24@0:8@16")
        XCTAssertEqual(classMethodEncoding(cls, "subscribe:block:"), "v32@0:8@16@?24")
        XCTAssertEqual(instanceMethodEncoding(cls, "string"), "@16@0:8")
    }

    func testStringIsReadOnly() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(unitClassName))
        XCTAssertNil(class_getInstanceMethod(cls, NSSelectorFromString("setString:")))
        let property = try XCTUnwrap(class_getProperty(cls, "string"))
        let attributes = try XCTUnwrap(property_getAttributes(property))
        XCTAssertTrue(String(cString: attributes).split(separator: ",").contains("R"))
    }

    // MARK: - The factory and the string

    func testFactoryKeepsTheString() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(unitClassName))
        let made = selectors(of: cls).notification(withString: "needle")
        let notification = try XCTUnwrap(made as? iTermSetFindStringNotification)
        XCTAssertTrue(type(of: notification) == iTermSetFindStringNotification.self)
        XCTAssertEqual(notification.string, "needle")
    }

    func testSwiftInitializerKeepsTheString() {
        let notification = iTermSetFindStringNotification(string: "héllo wörld")
        XCTAssertEqual(notification.string, "héllo wörld")
    }

    func testEmptyStringIsKept() {
        XCTAssertEqual(iTermSetFindStringNotification(string: "").string, "")
    }

    func testFactorySentToASubclassMakesAnInstanceOfTheSubclass() throws {
        let made = selectors(of: SetFindStringNotificationSubclass.self)
            .notification(withString: "sub")
        let notification = try XCTUnwrap(made as? iTermSetFindStringNotification)
        XCTAssertTrue(type(of: notification) == SetFindStringNotificationSubclass.self)
        XCTAssertEqual(notification.string, "sub")
    }

    // A mutable string handed in from Objective-C and changed afterwards must
    // not change the notification's string.
    func testMutableStringIsCopied() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(unitClassName))
        let mutable = NSMutableString(string: "before")
        let made = selectors(of: cls).notification(withString: mutable)
        let notification = try XCTUnwrap(made as? iTermSetFindStringNotification)
        mutable.setString("after")
        XCTAssertEqual(notification.string, "before")
    }

    // MARK: - Subscribing and posting

    func testPostReachesSubscriberSynchronouslyWithThePostedInstance() {
        let owner = NSObject()
        var received = [iTermSetFindStringNotification]()
        iTermSetFindStringNotification.subscribe(owner) { received.append($0) }
        let notification = iTermSetFindStringNotification(string: "find me")
        notification.post()
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(received.first === notification)
        XCTAssertEqual(received.first?.string, "find me")
        withExtendedLifetime(owner) {}
    }

    func testSubscribeBySelectorReachesSubscriber() throws {
        let cls: AnyClass = try XCTUnwrap(NSClassFromString(unitClassName))
        let owner = NSObject()
        var strings = [String]()
        selectors(of: cls).subscribe(owner) { strings.append($0.string) }
        iTermSetFindStringNotification(string: "one").post()
        iTermSetFindStringNotification(string: "two").post()
        XCTAssertEqual(strings, ["one", "two"])
        withExtendedLifetime(owner) {}
    }

    func testSubscriberIsNotCalledAfterItsOwnerIsGone() {
        var calls = 0
        weak var weakOwner: NSObject?
        autoreleasepool {
            let owner = NSObject()
            weakOwner = owner
            iTermSetFindStringNotification.subscribe(owner) { _ in calls += 1 }
        }
        XCTAssertNil(weakOwner)
        iTermSetFindStringNotification(string: "nobody").post()
        XCTAssertEqual(calls, 0)
    }

    // Posts are delivered to the blocks subscribed through the posting
    // instance's own class, so subscribing through a subclass hears only that
    // subclass's posts, and subscribing through this class does not hear the
    // subclass's.
    func testSubscriptionsAreByTheReceivingClass() {
        let baseOwner = NSObject()
        let subclassOwner = NSObject()
        var heardByBase = [String]()
        var heardBySubclass = [String]()
        iTermSetFindStringNotification.subscribe(baseOwner) { heardByBase.append($0.string) }
        SetFindStringNotificationSubclass.subscribe(subclassOwner) {
            heardBySubclass.append($0.string)
            XCTAssertTrue(type(of: $0) == SetFindStringNotificationSubclass.self)
        }
        iTermSetFindStringNotification(string: "base").post()
        SetFindStringNotificationSubclass(string: "subclass").post()
        XCTAssertEqual(heardByBase, ["base"])
        XCTAssertEqual(heardBySubclass, ["subclass"])
        withExtendedLifetime([baseOwner, subclassOwner]) {}
    }
}
