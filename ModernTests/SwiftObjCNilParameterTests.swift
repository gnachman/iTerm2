//
//  SwiftObjCNilParameterTests.swift
//  ModernTests
//
//  Objective-C passes nil to six Swift @objc methods whose parameters were
//  declared non-optional (unit N5 of docs/swift-migration/nullability-triage.md).
//  The parameters are now optional and each body substitutes what the bridge
//  used to: an empty string, array or dictionary, or "not present" for a class
//  reference. These tests call each method with nil the way Objective-C does,
//  through its implementation, because Swift cannot pass nil to a
//  non-optional parameter, and pin the result, which is the same before and
//  after the change.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class SwiftObjCNilParameterTests: XCTestCase {
    private func implementation<T>(of selector: Selector,
                                   in cls: AnyClass,
                                   as type: T.Type,
                                   file: StaticString = #filePath,
                                   line: UInt = #line) throws -> T {
        let method = try XCTUnwrap(class_getInstanceMethod(cls, selector),
                                   "\(NSStringFromSelector(selector)) not found",
                                   file: file,
                                   line: line)
        return unsafeBitCast(method_getImplementation(method), to: type)
    }

    // PTYSession passes the profile's triggers, which are nil when the profile
    // has none. The bridge gave [], so the evaluator cleared its triggers.
    func testLoadFromProfileArrayWithNilClearsTriggers() throws {
        let evaluator = EventTriggerEvaluator(sessionDescription: "nil parameter test")
        let dict: [String: Any] = [
            "action": "AlertTrigger",
            "regex": "",
            // Without it, +[Trigger triggerFromUntrustedDict:] stores nil in the
            // nonnull contentRegex, which the nullability sanitizer reports.
            kTriggerContentRegexKey: "",
            "parameter": "test",
            "matchType": NSNumber(value: iTermTriggerMatchType.eventNotificationPosted.rawValue),
            "disabled": NSNumber(value: false),
            "eventParams": [String: Any]()
        ]
        evaluator.loadFromProfileArray([dict])
        XCTAssertTrue(evaluator.hasEventTriggers, "Precondition: a trigger loaded")

        typealias Load = @convention(c) (AnyObject, Selector, NSArray?) -> Void
        let selector = NSSelectorFromString("loadFromProfileArray:")
        let load = try implementation(of: selector, in: EventTriggerEvaluator.self, as: Load.self)
        load(evaluator, selector, nil)

        XCTAssertFalse(evaluator.hasEventTriggers)
    }

    // PseudoTerminal asks before its tab bar accessory exists. The answer for
    // nil is "not present".
    func testHasWithNilIsFalse() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled, .miniaturizable],
                              backing: .buffered,
                              defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let windowController = NSWindowController(window: window)
        let nanny = iTermTitlebarAccessoryNanny()
        nanny.windowController = windowController
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        nanny.add(viewController: accessory)
        XCTAssertTrue(nanny.has(viewController: accessory), "Precondition: an accessory is present")

        typealias Has = @convention(c) (AnyObject, Selector, NSTitlebarAccessoryViewController?) -> Bool
        let selector = NSSelectorFromString("has:")
        let has = try implementation(of: selector, in: iTermTitlebarAccessoryNanny.self, as: Has.self)
        XCTAssertFalse(has(nanny, selector, nil))

        // Without a window the answer is also "not present".
        XCTAssertFalse(has(iTermTitlebarAccessoryNanny(), selector, nil))
    }

    // The toolbelt forwards the current session's named marks, which are nil
    // for a session without them. The bridge gave [], an empty list.
    func testSetNamedMarksWithNilShowsNoMarks() throws {
        let tool = ToolNamedMarks(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
        tool.set(marks: [NamedMarkStandIn(name: "a", sort: 1), NamedMarkStandIn(name: "b", sort: 2)])
        XCTAssertEqual(tool.numberOfRows(in: NSTableView()), 2, "Precondition: marks are shown")

        typealias SetMarks = @convention(c) (AnyObject, Selector, NSArray?) -> Void
        let selector = NSSelectorFromString("setNamedMarks:")
        let setMarks = try implementation(of: selector, in: ToolNamedMarks.self, as: SetMarks.self)
        setMarks(tool, selector, nil)

        XCTAssertEqual(tool.numberOfRows(in: NSTableView()), 0)
    }

    // PTYSession forwards a nil command for an aborted command. The bridge gave
    // "", which is not a valid open command, so the detector stays at ground.
    // With secure input off, as in tests, the method returns before looking at
    // the command, so this only shows that nil is accepted; that the body
    // substitutes "" is established by reading it.
    func testDidExecuteCommandWithNilStaysAtGround() throws {
        let detector = AppSwitchingPreventionDetector()
        typealias DidExecute = @convention(c) (AnyObject, Selector, NSString?) -> Void
        let selector = NSSelectorFromString("didExecuteCommand:")
        let didExecute = try implementation(of: selector,
                                            in: AppSwitchingPreventionDetector.self,
                                            as: DidExecute.self)
        didExecute(detector, selector, nil)

        let state = try XCTUnwrap(Mirror(reflecting: detector).descendant("state"))
        XCTAssertEqual(String(describing: state), "ground")
    }

    // PseudoTerminal passes the profile's GUID, which is nil for a window made
    // without a profile. The bridge gave "", which the positioner uses as its
    // allocation key and in its frame names.
    @MainActor
    func testInitWithNilProfileGUIDUsesTheEmptyString() throws {
        typealias Init = @convention(c) (Unmanaged<AnyObject>,
                                         Selector,
                                         Int32,
                                         Bool,
                                         NSString?,
                                         AnyObject?) -> Unmanaged<AnyObject>?
        let selector = NSSelectorFromString("initWithScreenNumberFromFirstProfile:disableAutoFrame:profileGUID:delegate:")
        let initialize = try implementation(of: selector, in: WindowInitialPositioner.self, as: Init.self)
        // +alloc returns an owned reference, which the initializer consumes; it
        // returns an owned reference in turn.
        let allocated = try XCTUnwrap((WindowInitialPositioner.self as AnyObject).perform(NSSelectorFromString("alloc")))
        let delegate = NSObject()
        let result = try XCTUnwrap(initialize(allocated, selector, -1, false, nil, delegate))
        let positioner = try XCTUnwrap(result.takeRetainedValue() as? WindowInitialPositioner)

        let profileGUID = try XCTUnwrap(Mirror(reflecting: positioner).descendant("profileGUID") as? String)
        XCTAssertEqual(profileGUID, "")
        XCTAssertEqual(positioner.screenNumberFromFirstProfile, -1)
    }

    // TmuxController passes its tab group parents, which are nil until tab
    // groups are saved. The bridge gave [:], so the result was empty.
    func testParentsByPruningWithNilIsEmpty() throws {
        typealias Prune = @convention(c) (AnyObject, Selector, NSDictionary?, NSDictionary) -> NSDictionary
        let selector = NSSelectorFromString("parentsByPruning:toGroupsOfMemberships:")
        let method = try XCTUnwrap(class_getClassMethod(iTermTmuxTabGroups.self, selector))
        let prune = unsafeBitCast(method_getImplementation(method), to: Prune.self)
        let memberships: NSDictionary = [
            NSNumber(value: 1): iTermTmuxTabGroupMembership(groupID: "P", name: nil, color: nil, collapsed: false)
        ]

        let result = prune(iTermTmuxTabGroups.self, selector, nil, memberships)

        XCTAssertEqual(result.count, 0)
    }
}

// Stands in for a named mark; ToolNamedMarks reads only these properties
// while setting and counting marks.
private final class NamedMarkStandIn: NSObject, iTermGenericNamedMarkReading {
    let name: String?
    let namedMarkSort: Int
    let guid = UUID().uuidString

    init(name: String, sort: Int) {
        self.name = name
        self.namedMarkSort = sort
    }
}
