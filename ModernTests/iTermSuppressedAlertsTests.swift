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
    private let announcementKey = "NoSyncTestSuppressedAnnouncement"

    override func setUp() {
        cleanUp()
    }

    override func tearDown() {
        cleanUp()
    }

    private func cleanUp() {
        // Reset the singleton's in-memory catalog (it is authoritative and persists
        // across tests) and clear any silence keys we set. Don't use unsuppressAll here:
        // the catalog starts out with the host's real entries, and it would delete them.
        iTermSuppressedAlerts.sharedInstance.resetForTesting()
        iTermWarning.showRememberedAlerts = false
        let ud = iTermUserDefaults.userDefaults()
        for identifier in [identifierA, identifierB] {
            ud.removeObject(forKey: identifier)
            ud.removeObject(forKey: identifier + "_selection")
            ud.removeObject(forKey: identifier + "_SilenceUntil")
        }
        ud.removeObject(forKey: announcementKey)
        ud.removeObject(forKey: catalogKey)
    }

    private func announcement(in array: [iTermSuppressedAlert]) -> iTermSuppressedAlert? {
        return array.first { $0.identifier.hasPrefix("Announcement:") }
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

    // MARK: - Announcements

    func testAnnouncementWithSavedChoiceAppears() throws {
        let registry = iTermSuppressedAlerts.sharedInstance
        iTermUserDefaults.userDefaults().set(false, forKey: announcementKey)
        registry.recordAnnouncementSuppression(userDefaultsKey: announcementKey,
                                               title: "Turn it off?",
                                               response: "_Never")
        registry.recordAnnouncementSuppression(userDefaultsKey: announcementKey,
                                               title: "Turn it off?",
                                               response: "_Never")

        XCTAssertEqual(registry.count(), 1)
        let entry = try XCTUnwrap(announcement(in: registry.currentlySuppressedAlerts()))
        XCTAssertEqual(entry.title, "Turn it off?")
        XCTAssertNil(entry.heading)
        XCTAssertEqual(entry.selectionLabel, "Never", "keyboard-shortcut underscores are removed")
        XCTAssertEqual(entry.count, 2)
    }

    func testAnnouncementWithoutSavedChoiceIsNotRecorded() {
        let registry = iTermSuppressedAlerts.sharedInstance
        registry.recordAnnouncementSuppression(userDefaultsKey: announcementKey,
                                               title: "t",
                                               response: nil)
        XCTAssertEqual(registry.count(), 0)
    }

    func testHiddenAnnouncementHasAResponse() throws {
        let registry = iTermSuppressedAlerts.sharedInstance
        iTermUserDefaults.userDefaults().set(true, forKey: announcementKey)
        registry.recordAnnouncementSuppression(userDefaultsKey: announcementKey,
                                               title: "t",
                                               response: nil)
        let entry = try XCTUnwrap(announcement(in: registry.currentlySuppressedAlerts()))
        XCTAssertFalse(entry.selectionLabel.isEmpty)
    }

    func testAnnouncementLapsesWhenSavedChoiceChanges() throws {
        let registry = iTermSuppressedAlerts.sharedInstance
        let ud = iTermUserDefaults.userDefaults()
        ud.set(true, forKey: announcementKey)
        registry.recordAnnouncementSuppression(userDefaultsKey: announcementKey,
                                               title: "t",
                                               response: nil)
        XCTAssertEqual(registry.count(), 1)

        // Changed some other way, e.g. in Advanced Settings.
        ud.set(false, forKey: announcementKey)
        XCTAssertEqual(registry.count(), 0)

        // A new choice starts a new count.
        registry.recordAnnouncementSuppression(userDefaultsKey: announcementKey,
                                               title: "t",
                                               response: "Never")
        let entry = try XCTUnwrap(announcement(in: registry.currentlySuppressedAlerts()))
        XCTAssertEqual(entry.count, 1)
    }

    func testUnsuppressAnnouncementRemovesSavedChoice() throws {
        let registry = iTermSuppressedAlerts.sharedInstance
        iTermUserDefaults.userDefaults().set(true, forKey: announcementKey)
        registry.recordAnnouncementSuppression(userDefaultsKey: announcementKey,
                                               title: "t",
                                               response: nil)
        let entry = try XCTUnwrap(announcement(in: registry.currentlySuppressedAlerts()))

        registry.unsuppressIdentifier(entry.identifier)

        XCTAssertEqual(registry.count(), 0)
        XCTAssertNil(iTermUserDefaults.userDefaults().object(forKey: announcementKey))
    }

    func testUnsuppressAllIncludesAnnouncements() {
        let registry = iTermSuppressedAlerts.sharedInstance
        silence(identifierA, selection: 1)
        registry.recordSuppression(withIdentifier: identifierA, title: "a", heading: nil, selectionLabel: "No")
        iTermUserDefaults.userDefaults().set(true, forKey: announcementKey)
        registry.recordAnnouncementSuppression(userDefaultsKey: announcementKey,
                                               title: "t",
                                               response: nil)
        XCTAssertEqual(registry.count(), 2)

        registry.unsuppressAll()

        XCTAssertEqual(registry.count(), 0)
        XCTAssertFalse(iTermWarning.identifierIsSilenced(identifierA))
        XCTAssertNil(iTermUserDefaults.userDefaults().object(forKey: announcementKey))
    }

    func testUnsuppressAllKeepsNewerChoiceForLapsedAnnouncement() {
        let registry = iTermSuppressedAlerts.sharedInstance
        let ud = iTermUserDefaults.userDefaults()
        ud.set(true, forKey: announcementKey)
        registry.recordAnnouncementSuppression(userDefaultsKey: announcementKey,
                                               title: "t",
                                               response: "Always")
        // Changed elsewhere (e.g., in Advanced Settings) before the entry is pruned.
        ud.set(false, forKey: announcementKey)

        registry.unsuppressAll()

        XCTAssertEqual(ud.object(forKey: announcementKey) as? Bool, false)
    }

    func testShouldSuppressAnnouncementRecordsIt() throws {
        let registry = iTermSuppressedAlerts.sharedInstance
        iTermUserDefaults.userDefaults().set(true, forKey: announcementKey)

        XCTAssertTrue(registry.shouldSuppressAnnouncement(userDefaultsKey: announcementKey,
                                                          title: "t",
                                                          response: nil))

        XCTAssertNotNil(announcement(in: registry.currentlySuppressedAlerts()))
    }

    func testShouldSuppressAnnouncementIsFalseWhenShowingRememberedAlerts() {
        let registry = iTermSuppressedAlerts.sharedInstance
        iTermUserDefaults.userDefaults().set(true, forKey: announcementKey)
        iTermWarning.showRememberedAlerts = true

        XCTAssertFalse(registry.shouldSuppressAnnouncement(userDefaultsKey: announcementKey,
                                                           title: "t",
                                                           response: nil))

        XCTAssertNil(announcement(in: registry.currentlySuppressedAlerts()))
        XCTAssertEqual(iTermUserDefaults.userDefaults().object(forKey: announcementKey) as? Bool, true)
    }

    func testShouldSuppressAnnouncementIsFalseWithoutSavedChoice() {
        let registry = iTermSuppressedAlerts.sharedInstance

        XCTAssertFalse(registry.shouldSuppressAnnouncement(userDefaultsKey: announcementKey,
                                                           title: "t",
                                                           response: nil),
                       "an announcement that can't be listed must not be hidden")
        XCTAssertEqual(registry.count(), 0)
    }

    func testSavedAlwaysOrNeverChoice() throws {
        let suppression = AnnouncementSuppression(userDefaultsKey: announcementKey, title: "Turn it off?")
        let ud = iTermUserDefaults.userDefaults()
        XCTAssertEqual(suppression.savedAlwaysOrNeverChoice(), .ask)
        XCTAssertEqual(iTermSuppressedAlerts.sharedInstance.count(), 0)

        ud.set(true, forKey: announcementKey)
        XCTAssertEqual(suppression.savedAlwaysOrNeverChoice(), .always)
        let always = try XCTUnwrap(announcement(in: iTermSuppressedAlerts.sharedInstance.currentlySuppressedAlerts()))
        XCTAssertEqual(always.title, "Turn it off?")
        XCTAssertEqual(always.selectionLabel, AnnouncementSuppression.alwaysLabel)

        ud.set(false, forKey: announcementKey)
        XCTAssertEqual(suppression.savedAlwaysOrNeverChoice(), .never)
        let never = try XCTUnwrap(announcement(in: iTermSuppressedAlerts.sharedInstance.currentlySuppressedAlerts()))
        XCTAssertEqual(never.selectionLabel, AnnouncementSuppression.neverLabel)
    }

    func testSavedAlwaysOrNeverChoiceAsksWhenShowingRememberedAlerts() {
        let suppression = AnnouncementSuppression(userDefaultsKey: announcementKey, title: "t")
        iTermUserDefaults.userDefaults().set(true, forKey: announcementKey)
        iTermWarning.showRememberedAlerts = true

        XCTAssertEqual(suppression.savedAlwaysOrNeverChoice(), .ask)
        XCTAssertEqual(iTermSuppressedAlerts.sharedInstance.count(), 0)
    }

    func testRecordChoiceListsItRightAway() throws {
        let suppression = AnnouncementSuppression(userDefaultsKey: announcementKey, title: "t")
        iTermWarning.showRememberedAlerts = true

        suppression.saveAlwaysOrNeverChoice(false)

        let entry = try XCTUnwrap(announcement(in: iTermSuppressedAlerts.sharedInstance.currentlySuppressedAlerts()))
        XCTAssertEqual(entry.selectionLabel, AnnouncementSuppression.neverLabel)
        XCTAssertEqual(entry.count, 0, "answering isn't an automatic suppression")
        XCTAssertEqual(iTermUserDefaults.userDefaults().object(forKey: announcementKey) as? Bool, false)
    }

    func testRememberedSelectionDoesNotCountAsAutoAnswer() throws {
        let registry = iTermSuppressedAlerts.sharedInstance
        silence(identifierA, selection: 1)
        registry.recordRememberedSelection(withIdentifier: identifierA, title: "a", heading: nil, selectionLabel: "No")
        XCTAssertEqual(try XCTUnwrap(alert(identifierA, in: registry.currentlySuppressedAlerts())).count, 0)

        registry.recordSuppression(withIdentifier: identifierA, title: "a", heading: nil, selectionLabel: "No")
        XCTAssertEqual(try XCTUnwrap(alert(identifierA, in: registry.currentlySuppressedAlerts())).count, 1)
    }
}
