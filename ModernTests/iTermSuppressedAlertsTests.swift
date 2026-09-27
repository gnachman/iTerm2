//
//  iTermSuppressedAlertsTests.swift
//  iTerm2 ModernTests
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class iTermSuppressedAlertsTests: XCTestCase {
    private let identifierA = "NoSyncTestSuppressedAlertA"
    private let identifierB = "NoSyncTestSuppressedAlertB"
    private let catalogKey = "NoSyncSuppressedAlertsCatalog"

    override func setUp() {
        cleanUp()
    }

    override func tearDown() {
        cleanUp()
    }

    private func cleanUp() {
        // Reset the singleton's in-memory catalog (it is authoritative and persists
        // across tests) and clear any silence keys we set.
        iTermSuppressedAlerts.sharedInstance.unsuppressAll()
        let ud = iTermUserDefaults.userDefaults()
        for identifier in [identifierA, identifierB] {
            ud.removeObject(forKey: identifier)
            ud.removeObject(forKey: identifier + "_selection")
            ud.removeObject(forKey: identifier + "_SilenceUntil")
        }
        ud.removeObject(forKey: catalogKey)
    }

    // Mark an identifier as permanently silenced with the given selection, as
    // iTermWarning does when the user checks "remember my choice".
    private func silence(_ identifier: String, selection: Int) {
        let ud = iTermUserDefaults.userDefaults()
        ud.set(true, forKey: identifier)
        ud.set(selection, forKey: identifier + "_selection")
    }

    // Mirror a temporary silence with a specific expiry, so tests can create
    // distinct silence episodes.
    private func temporarilySilence(_ identifier: String, until: TimeInterval) {
        let ud = iTermUserDefaults.userDefaults()
        ud.set(until, forKey: identifier + "_SilenceUntil")
        ud.set(0, forKey: identifier + "_selection")
    }

    private func alert(_ identifier: String,
                       in array: [iTermSuppressedAlert]) -> iTermSuppressedAlert? {
        return array.first { $0.identifier == identifier }
    }

    func testRecordedAndSilencedAlertAppears() throws {
        let registry = iTermSuppressedAlerts.sharedInstance
        silence(identifierA, selection: 1)
        registry.recordSuppression(withIdentifier: identifierA,
                                   title: "Allow the thing?",
                                   heading: "Confirm Thing",
                                   selectionLabel: "No")

        XCTAssertEqual(registry.count(), 1)
        let alert = try XCTUnwrap(self.alert(identifierA, in: registry.currentlySuppressedAlerts()))
        XCTAssertEqual(alert.title, "Allow the thing?")
        XCTAssertEqual(alert.heading, "Confirm Thing")
        XCTAssertEqual(alert.selectionLabel, "No")
        XCTAssertEqual(alert.count, 1)
        XCTAssertNotNil(registry.mostRecentSuppression())
    }

    func testCatalogedButNotSilencedIsExcluded() {
        let registry = iTermSuppressedAlerts.sharedInstance
        // Record without silencing: the alert is in the catalog but is not
        // currently being suppressed, so it must not be reported.
        registry.recordSuppression(withIdentifier: identifierA,
                                   title: "Allow the thing?",
                                   heading: nil,
                                   selectionLabel: "No")
        XCTAssertEqual(registry.count(), 0)
        XCTAssertNil(alert(identifierA, in: registry.currentlySuppressedAlerts()))
        XCTAssertNil(registry.mostRecentSuppression())
    }

    func testRepeatedSuppressionIncrementsCount() throws {
        let registry = iTermSuppressedAlerts.sharedInstance
        silence(identifierA, selection: 0)
        for _ in 0..<3 {
            registry.recordSuppression(withIdentifier: identifierA,
                                       title: "t",
                                       heading: nil,
                                       selectionLabel: "Yes")
        }
        XCTAssertEqual(registry.count(), 1)
        let alert = try XCTUnwrap(self.alert(identifierA, in: registry.currentlySuppressedAlerts()))
        XCTAssertEqual(alert.count, 3)
    }

    func testLapsedSilenceIsPrunedAndCountResets() throws {
        let registry = iTermSuppressedAlerts.sharedInstance
        silence(identifierA, selection: 1)
        registry.recordSuppression(withIdentifier: identifierA, title: "t", heading: nil, selectionLabel: "No")
        registry.recordSuppression(withIdentifier: identifierA, title: "t", heading: nil, selectionLabel: "No")
        XCTAssertEqual(registry.count(), 1)

        // Simulate a silence lapsing by other means (e.g. a temporary silence
        // expiring) without going through unsuppressIdentifier:.
        let ud = iTermUserDefaults.userDefaults()
        ud.removeObject(forKey: identifierA)
        ud.removeObject(forKey: identifierA + "_SilenceUntil")

        // The lapsed entry must not be reported, and querying prunes it.
        XCTAssertEqual(registry.count(), 0)

        // A fresh silence episode starts the count over rather than continuing from
        // the pruned entry's stale value.
        silence(identifierA, selection: 1)
        registry.recordSuppression(withIdentifier: identifierA, title: "t", heading: nil, selectionLabel: "No")
        let alert = try XCTUnwrap(self.alert(identifierA, in: registry.currentlySuppressedAlerts()))
        XCTAssertEqual(alert.count, 1)
    }

    func testCountResetsOnNewEpisodeWithoutIntermediateQuery() throws {
        let registry = iTermSuppressedAlerts.sharedInstance
        let now = Date().timeIntervalSinceReferenceDate
        temporarilySilence(identifierA, until: now + 600)
        registry.recordSuppression(withIdentifier: identifierA, title: "t", heading: nil, selectionLabel: "OK")
        registry.recordSuppression(withIdentifier: identifierA, title: "t", heading: nil, selectionLabel: "OK")

        // Begin a distinct silence episode (new expiry) with no query in between,
        // so pruning never runs. The count must still restart at 1 rather than
        // continue from the prior episode.
        temporarilySilence(identifierA, until: now + 601)
        registry.recordSuppression(withIdentifier: identifierA, title: "t", heading: nil, selectionLabel: "OK")

        let alert = try XCTUnwrap(self.alert(identifierA, in: registry.currentlySuppressedAlerts()))
        XCTAssertEqual(alert.count, 1)
    }

    func testUnsuppressRemovesItAndUnsilences() {
        let registry = iTermSuppressedAlerts.sharedInstance
        silence(identifierA, selection: 1)
        registry.recordSuppression(withIdentifier: identifierA, title: "t", heading: nil, selectionLabel: "No")
        XCTAssertEqual(registry.count(), 1)
        XCTAssertTrue(iTermWarning.identifierIsSilenced(identifierA))

        registry.unsuppressIdentifier(identifierA)

        XCTAssertEqual(registry.count(), 0)
        XCTAssertFalse(iTermWarning.identifierIsSilenced(identifierA),
                       "un-suppressing must clear the silence so the alert is shown again")
    }

    func testUnsuppressAll() {
        let registry = iTermSuppressedAlerts.sharedInstance
        silence(identifierA, selection: 1)
        silence(identifierB, selection: 0)
        registry.recordSuppression(withIdentifier: identifierA, title: "a", heading: nil, selectionLabel: "No")
        registry.recordSuppression(withIdentifier: identifierB, title: "b", heading: nil, selectionLabel: "Yes")
        XCTAssertEqual(registry.count(), 2)

        registry.unsuppressAll()

        XCTAssertEqual(registry.count(), 0)
        XCTAssertFalse(iTermWarning.identifierIsSilenced(identifierA))
        XCTAssertFalse(iTermWarning.identifierIsSilenced(identifierB))
    }
}
