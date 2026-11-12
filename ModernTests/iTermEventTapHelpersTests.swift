//
//  iTermEventTapHelpersTests.swift
//  ModernTests
//
//  Bookkeeping the keyboard event taps need now that they aren't always filtering on the main
//  thread (issue 12645): which events the modifier remapper handled, and whether a flags-changed
//  event the app received was already reported to observers by the tap.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermRecentEventLogTests: XCTestCase {
    private func keyEvent(_ keyCode: CGKeyCode, down: Bool, timestamp: CGEventTimestamp) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)!
        event.timestamp = timestamp
        return event
    }

    // The remapper identifies events it handled without writing to them, since other tools tag
    // their synthetic events in kCGEventSourceUserData.
    func testRecognizesRecordedEventWithoutModifyingIt() {
        let log = iTermRecentEventLog(capacity: 4)
        let event = keyEvent(0, down: true, timestamp: 1000)
        XCTAssertFalse(log.contains(event))
        log.record(event)
        XCTAssertTrue(log.contains(event))
        XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), 0)
    }

    // Remapping can change the keycode (Fn translation), so it isn't part of an event's identity.
    func testMatchesOnTimestampAndType() {
        let log = iTermRecentEventLog(capacity: 4)
        log.record(keyEvent(0, down: true, timestamp: 1_000_000))
        XCTAssertTrue(log.contains(keyEvent(1, down: true, timestamp: 1_000_000)))
        XCTAssertFalse(log.contains(keyEvent(0, down: false, timestamp: 1_000_000)))
        XCTAssertFalse(log.contains(keyEvent(0, down: true, timestamp: 1_010_000)))
    }

    // The app's copy may have passed through NSEvent's timestamp in seconds.
    func testToleratesSubmicrosecondTimestampDifferences() {
        let log = iTermRecentEventLog(capacity: 4)
        log.record(keyEvent(0, down: true, timestamp: 1_000_000))
        XCTAssertTrue(log.contains(keyEvent(0, down: true, timestamp: 1_000_400)))
        XCTAssertTrue(log.contains(keyEvent(0, down: true, timestamp: 999_600)))
    }

    func testForgetsOldestBeyondCapacity() {
        let log = iTermRecentEventLog(capacity: 2)
        let a = keyEvent(0, down: true, timestamp: 1_000_000)
        let b = keyEvent(0, down: true, timestamp: 2_000_000)
        let c = keyEvent(0, down: true, timestamp: 3_000_000)
        log.record(a)
        log.record(b)
        log.record(c)
        XCTAssertFalse(log.contains(a))
        XCTAssertTrue(log.contains(b))
        XCTAssertTrue(log.contains(c))
    }
}

final class iTermFlagsChangedLedgerTests: XCTestCase {
    // The tap told observers synchronously, so the app must not tell them again.
    func testSynchronousDeliverySuppressesInjection() {
        let ledger = iTermFlagsChangedLedger()
        ledger.eventTapDidDeliverEvent()
        XCTAssertFalse(ledger.appReceivedEventShouldInject())
    }

    // The tap never saw the event, so the app must tell observers.
    func testInjectsWhenTapMissedEvent() {
        XCTAssertTrue(iTermFlagsChangedLedger().appReceivedEventShouldInject())
    }

    // Each received event consumes the tap's deliveries so a later missed event is injected.
    func testResetsAfterEachReceivedEvent() {
        let ledger = iTermFlagsChangedLedger()
        ledger.eventTapDidDeliverEvent()
        XCTAssertFalse(ledger.appReceivedEventShouldInject())
        XCTAssertTrue(ledger.appReceivedEventShouldInject())
    }

    func testResetClearsDeliveries() {
        let ledger = iTermFlagsChangedLedger()
        ledger.eventTapDidDeliverEvent()
        ledger.reset()
        XCTAssertTrue(ledger.appReceivedEventShouldInject())
    }

    // Around activation the tap defers delivery from the filter thread. If the app receives the
    // event before the deferred delivery runs, it must not inject a second copy, and the deferred
    // delivery, already accounted for, must not suppress the next event.
    func testPendingDeferredDeliverySuppressesInjection() {
        let ledger = iTermFlagsChangedLedger()
        ledger.eventTapWillDeliverEventLater()
        XCTAssertFalse(ledger.appReceivedEventShouldInject())
        ledger.eventTapDidDeliverDeferredEvent()
        XCTAssertTrue(ledger.appReceivedEventShouldInject())
    }

    // If the deferred delivery runs first, it counts like a synchronous one.
    func testCompletedDeferredDeliverySuppressesInjection() {
        let ledger = iTermFlagsChangedLedger()
        ledger.eventTapWillDeliverEventLater()
        ledger.eventTapDidDeliverDeferredEvent()
        XCTAssertFalse(ledger.appReceivedEventShouldInject())
        XCTAssertTrue(ledger.appReceivedEventShouldInject())
    }

    // Deliveries deferred while iTerm2 was inactive, for events the app never receives, must not
    // be mistaken for pending ones forever.
    func testDeferredDeliveriesForEventsNeverReceivedAreSettledByReset() {
        let ledger = iTermFlagsChangedLedger()
        ledger.eventTapWillDeliverEventLater()
        ledger.eventTapDidDeliverDeferredEvent()
        ledger.reset()
        XCTAssertTrue(ledger.appReceivedEventShouldInject())
    }
}
