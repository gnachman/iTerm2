//
//  SessionTriggersNullabilityTests.swift
//  ModernTests
//
//  Documents the nullability claims of PTYSession, automatic profile
//  switching, the right gutter panel registry and triggers
//  that the nullability sanitizer found false (unit N9 of
//  docs/swift-migration/nullability-triage.md). The Objective-C code accepts
//  or produces nil by design; these tests pin what Swift sees. A test that
//  passes nil only compiles because the position is now optional, which is
//  how each of those failed before the change.
//

import XCTest
@testable import iTerm2SharedARC

// Stands in for a session whose profile is not set yet, as PTYSession is
// while -initSynthetic: runs, before -setProfile:.
private final class NilProfileSwitcherDelegate: NSObject, iTermAutomaticProfileSwitcherDelegate {
    var profile: [AnyHashable: Any]?
    var allProfiles: [[AnyHashable: Any]] = []
    private(set) var loadedProfiles: [[AnyHashable: Any]] = []

    func automaticProfileSwitcherLoad(_ savedProfile: iTermSavedProfile) {
        loadedProfiles.append(savedProfile.originalProfile)
        profile = savedProfile.originalProfile
    }

    func automaticProfileSwitcherCurrentProfile() -> [AnyHashable: Any]? {
        return profile
    }

    func automaticProfileSwitcherCurrentSavedProfile() -> iTermSavedProfile {
        let savedProfile = iTermSavedProfile()
        savedProfile.originalProfile = profile ?? [:]
        savedProfile.profile = profile
        return savedProfile
    }

    func automaticProfileSwitcherAllProfiles() -> [[AnyHashable: Any]] {
        return allProfiles
    }

    func automaticProfileSwitcherSessionName() -> String {
        return ""
    }
}

final class AutomaticProfileSwitcherNullabilityTests: XCTestCase {
    // -automaticProfileSwitcherCurrentProfile is nil before the session's
    // profile is set. The requirement is optional now, so a Swift conformer
    // can say so; before, a conformer returning an optional did not conform.
    // With no profiles to switch to, a nil current profile changes nothing.
    func testNilCurrentProfileWithNoCandidatesLoadsNothing() {
        let delegate = NilProfileSwitcherDelegate()
        let switcher = iTermAutomaticProfileSwitcher(delegate: delegate)
        // Marking it dirty skips the comparison with the previous values,
        // which would pass nil to -isEqualToString: on the first call.
        switcher.markDirty()
        switcher.setHostname("example.com",
                             username: "user",
                             path: "/tmp",
                             job: "zsh",
                             commandLine: nil,
                             expressionValueProvider: nil)
        XCTAssertTrue(delegate.loadedProfiles.isEmpty)
        XCTAssertNil(delegate.profile)
    }

    // PTYSession passes its apsContext, which is nil until
    // -setPreferencesFromAddressBookEntry: makes it. Rules without
    // expressions still match: the nil provider is only messaged by
    // expression rules, which then score 0.
    func testNilExpressionValueProviderStillMatchesHostRules() {
        let delegate = NilProfileSwitcherDelegate()
        delegate.profile = [KEY_NAME: "Initial", KEY_GUID: "initial"]
        // The host rule names a user too: iTermRule compares the session's
        // user name with the rule's, and a rule without one would pass nil
        // to -isEqualToString:, which the nullability sanitizer reports.
        let hostProfile: [AnyHashable: Any] = [KEY_NAME: "user@a", KEY_GUID: "a", KEY_BOUND_HOSTS: ["user@a"]]
        let expressionProfile: [AnyHashable: Any] = [KEY_NAME: "expression",
                                                    KEY_GUID: "e",
                                                    KEY_BOUND_HOSTS: ["{true}"]]
        delegate.allProfiles = [hostProfile, expressionProfile]
        let switcher = iTermAutomaticProfileSwitcher(delegate: delegate)
        switcher.markDirty()
        switcher.setHostname("a",
                             username: "user",
                             path: nil,
                             job: nil,
                             commandLine: nil,
                             expressionValueProvider: nil)
        XCTAssertEqual(delegate.loadedProfiles.count, 1)
        XCTAssertEqual(delegate.profile?[KEY_GUID] as? String, "a")
    }
}

final class PTYSessionNullabilityTests: XCTestCase {
    // +protoStyleForCharacter:externalAttributes: is called with eaIndex[i],
    // nil for a cell without external attributes. Its body only reads
    // properties of ea, so nil gives the same style as an empty attribute.
    func testProtoStyleWithNilExternalAttributesIsPlain() {
        let c = screen_char_t()
        let empty = iTermExternalAttribute(havingUnderlineColor: false,
                                           underlineColor: VT100TerminalColorValue(),
                                           url: nil,
                                           blockIDList: nil,
                                           controlCode: nil,
                                           dualModeForeground: iTermDualModeColor(),
                                           dualModeBackground: iTermDualModeColor())
        let withNil = PTYSession.protoStyle(forCharacter: c, externalAttributes: nil)
        let withEmpty = PTYSession.protoStyle(forCharacter: c, externalAttributes: empty)
        XCTAssertFalse(withNil.hasURL)
        XCTAssertFalse(withNil.hasUnderlineColor)
        XCTAssertEqual(withNil.blockId, "")
        XCTAssertEqual(withNil, withEmpty)
    }

    // -desiredRightExtra passes self.profile, nil while -setProfile: is still
    // running. A nil profile reads like an empty one: no adjacent timestamps,
    // and the registered panel width providers ignore the profile.
    func testDesiredRightExtraForNilProfileMatchesEmptyProfile() {
        XCTAssertEqual(PTYSession.desiredRightExtra(forProfile: nil, session: nil),
                       PTYSession.desiredRightExtra(forProfile: [:], session: nil))
    }

    func testDesiredPanelReservationForNilProfileMatchesEmptyProfile() {
        XCTAssertEqual(PTYSession.desiredPanelReservation(forProfile: nil, session: nil),
                       PTYSession.desiredPanelReservation(forProfile: [:], session: nil))
    }

    // The next three claims need a live session to call, and their bodies
    // only message the value or test it, so they are pinned at compile time.
    // Each closure compiles only with the claim made: a method taking a
    // non-optional does not convert to one taking an optional, and
    // guard let needs an optional.
    func testOptionalClaimsCompile() {
        // fg and bg come from profile lookups that can miss.
        let ansiColors: (PTYSession) -> ([AnyHashable: Any]?, [AnyHashable: Any]?, [AnyHashable: Any]) -> String? =
            PTYSession.ansiColors(matchingForeground:andBackground:inBookmark:)
        // The name comes from self.profile[KEY_NAME].
        let profileNameDidChange: (PTYSession) -> (String?) -> Void = PTYSession.profileNameDidChange(to:)
        // A terminal session returns its screen's named marks, which can be nil.
        let namedMarkCount: (PTYSession) -> Int = { session in
            guard let marks = session.namedMarks() else {
                return 0
            }
            return marks.count
        }
        XCTAssertNotNil(ansiColors as Any)
        XCTAssertNotNil(profileNameDidChange as Any)
        XCTAssertNotNil(namedMarkCount as Any)
    }
}

final class RightGutterPanelRegistryNullabilityTests: XCTestCase {
    // A session's budget is computed before its profile is set, so the
    // registry hands a nil profile to each width provider. The provider's
    // profile parameter is optional now; before, Swift received an empty
    // dictionary in its place.
    func testWidthProviderReceivesNilProfile() {
        let registry = iTermRightGutterPanelRegistry()
        var receivedProfiles: [[AnyHashable: Any]?] = []
        registry.registerPanelType("nullability-test",
                                   factory: { iTermClippingsGutterPanel() },
                                   widthProvider: { profile, _ in
            receivedProfiles.append(profile)
            return 7
        })
        XCTAssertEqual(registry.totalWidth(forProfile: nil, session: nil), 7)
        XCTAssertEqual(receivedProfiles.count, 1)
        XCTAssertNil(receivedProfiles.first ?? [:])
    }

    // The two width providers the app registers ignore the profile, and with
    // no session both answer 0.
    func testSharedRegistryAnswersTheSameForNilAndEmptyProfile() {
        let registry = iTermRightGutterPanelRegistry.sharedInstance()
        XCTAssertEqual(registry.totalWidth(forProfile: nil, session: nil),
                       registry.totalWidth(forProfile: [:], session: nil))
    }
}

// iTermPrintGuard is not visible to Swift; its claims are pinned in
// PrintGuardNullabilityTests.m.

final class TriggerNullabilityTests: XCTestCase {
    private func alertTriggerDict() -> [String: Any] {
        return [
            "action": "AlertTrigger",
            "regex": "x",
            "parameter": "test",
            "matchType": NSNumber(value: iTermTriggerMatchType.regex.rawValue)
        ]
    }

    // A trigger saved without a content regex has none. While the property
    // was claimed nonnull, Swift read the nil as an empty string, and this
    // assertion failed.
    func testContentRegexOfTriggerSavedWithoutOneIsNil() throws {
        let trigger = try XCTUnwrap(Trigger(fromUntrustedDict: alertTriggerDict()))
        XCTAssertNil(trigger.contentRegex)
    }

    func testContentRegexOfTriggerSavedWithOneIsKept() throws {
        var dict = alertTriggerDict()
        dict[kTriggerContentRegexKey] = "content"
        let trigger = try XCTUnwrap(Trigger(fromUntrustedDict: dict))
        XCTAssertEqual(trigger.contentRegex, "content")
    }

    // The screen passes the profile's triggers, nil for a profile without
    // any. Loading nil clears the triggers.
    func testLoadingNilProfileArrayClearsTriggers() {
        let evaluator = PTYTriggerEvaluator(queue: DispatchQueue.main)
        var dict = alertTriggerDict()
        dict[kTriggerContentRegexKey] = ""
        evaluator.load(fromProfileArray: [dict])
        XCTAssertEqual(evaluator.triggers.count, 1, "Precondition: a trigger loaded")
        evaluator.load(fromProfileArray: nil)
        XCTAssertEqual(evaluator.triggers.count, 0)
    }
}
