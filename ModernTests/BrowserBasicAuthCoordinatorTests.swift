//
//  BrowserBasicAuthCoordinatorTests.swift
//  ModernTests
//
//  The transition table of BrowserBasicAuthCoordinator, exercised as pure event ->
//  effect sequences with no WebKit, window, or password backend. Each test is one
//  of the scenarios measured with scratchpad/webkitauth and the guarantees / known
//  flaws documented on the coordinator.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class BrowserBasicAuthCoordinatorTests: XCTestCase {
    typealias Coord = BrowserBasicAuthCoordinator
    typealias Cred = BrowserBasicAuthCoordinator.Credential

    private func mainSpace(realm: String = "MainRealm") -> Coord.SpaceKey {
        Coord.SpaceKey(scheme: "https", host: "example.com", port: 443, realm: realm)
    }
    private func origin(_ host: String = "example.com", _ port: Int = 443, scheme: String = "https") -> Coord.Origin {
        Coord.Origin(scheme: scheme, host: host, port: port)
    }

    // A live main navigation to `space.origin` with a challenge for `space`.
    private func startMainNav(_ coord: Coord, to space: Coord.SpaceKey) {
        _ = coord.reduce(.mainProvisionalStarted(origin: space.origin))
    }

    // MARK: - Accept / reject of a saved main-document credential

    func testSavedAcceptedOnMainFrame2xxDoesNotPersistAndClearsRejection() {
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)

        let id = Coord.ChallengeID(1)
        let e1 = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                         savedLookupPossible: true, storeCanRemember: true))
        XCTAssertEqual(e1, [.lookupSaved(id: id, space: space, preferredUser: nil)])

        let saved = Cred(user: "alice", password: "secret")
        let e2 = coord.reduce(.savedLookupResult(id: id, credential: saved))
        XCTAssertEqual(e2, [.supply(id: id, saved)])

        // Server accepts. Nothing to persist (auto-fill is not a remember), no toast.
        let e3 = coord.reduce(.mainFrameResponse(origin: space.origin, status: 200))
        XCTAssertEqual(e3, [])
    }

    func testSavedRejectedOnMainFrame401MarksRejectedSoNextChallengePrompts() {
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)

        let id = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: true, storeCanRemember: true))
        _ = coord.reduce(.savedLookupResult(id: id, credential: Cred(user: "alice", password: "old")))
        // Rejected by the main-frame response.
        _ = coord.reduce(.mainFrameResponse(origin: space.origin, status: 401))

        // Next navigation to the same space must NOT auto-fill the rejected saved value.
        startMainNav(coord, to: space)
        let id2 = Coord.ChallengeID(2)
        let e = coord.reduce(.challenge(id: id2, space: space, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: true, storeCanRemember: true))
        guard case .prompt(let pid, _)? = e.first, pid == id2 else {
            return XCTFail("expected a prompt, got \(e)")
        }
    }

    // MARK: - In-navigation re-challenge is a rejection (loop prevention, guarantee 4)

    func testInNavReChallengeOfSavedMarksRejectedAndPromptsWithoutRefilling() {
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)

        let id = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: true, storeCanRemember: true))
        _ = coord.reduce(.savedLookupResult(id: id, credential: Cred(user: "alice", password: "old")))

        // WebKit re-challenges the same space in the same navigation (rejection).
        let id2 = Coord.ChallengeID(2)
        let e = coord.reduce(.challenge(id: id2, space: space, isBasic: true, proposedUser: "alice",
                                        savedLookupPossible: true, storeCanRemember: true))
        // We must prompt, not lookup/auto-fill again.
        guard case .prompt? = e.first else {
            return XCTFail("expected prompt on re-challenge, got \(e)")
        }
        XCTAssertFalse(e.contains { if case .lookupSaved = $0 { return true }; return false })
    }

    // MARK: - Typed + Remember persistence rules (guarantee 3)

    func testTypedRememberPersistsOnlyOn2xx() {
        for (status, shouldPersist) in [(200, true), (204, true), (302, false), (401, false), (503, false)] {
            let coord = Coord()
            let space = mainSpace()
            startMainNav(coord, to: space)
            let id = Coord.ChallengeID(1)
            _ = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: false, storeCanRemember: true))
            let typed = Cred(user: "bob", password: "pw")
            let e = coord.reduce(.promptResult(id: id, outcome: .submitted(typed, remember: true)))
            XCTAssertEqual(e, [.supply(id: id, typed)])

            let r = coord.reduce(.mainFrameResponse(origin: space.origin, status: status))
            if shouldPersist {
                XCTAssertEqual(r, [.persist(space: space, typed)], "status \(status)")
            } else {
                XCTAssertEqual(r, [], "status \(status)")
            }
        }
    }

    func testTypedRejectionDoesNotMarkSavedRejected() {
        // A typed rejection is private to the user; it must not poison the saved store.
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)
        let id = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: false, storeCanRemember: true))
        _ = coord.reduce(.promptResult(id: id, outcome: .submitted(Cred(user: "bob", password: "wrong"), remember: true)))
        _ = coord.reduce(.mainFrameResponse(origin: space.origin, status: 401))

        // Next visit: saved lookup should still be attempted (not suppressed by a typed rejection).
        startMainNav(coord, to: space)
        let id2 = Coord.ChallengeID(2)
        let e = coord.reduce(.challenge(id: id2, space: space, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: true, storeCanRemember: true))
        XCTAssertEqual(e, [.lookupSaved(id: id2, space: space, preferredUser: nil)])
    }

    func testTypedSuccessDoesNotReviveAKnownBadSavedCredential() {
        // A saved credential is rejected, then the user logs in with a DIFFERENT typed
        // credential without checking Remember. The typed success says nothing about the
        // still-bad saved value (which the store still holds), so it must not re-enable
        // auto-fill of the saved credential (guarantee 4).
        let coord = Coord()
        let space = mainSpace()

        // Nav 1: the saved credential is auto-filled and rejected.
        startMainNav(coord, to: space)
        let id1 = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id1, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: true, storeCanRemember: true))
        _ = coord.reduce(.savedLookupResult(id: id1, credential: Cred(user: "alice", password: "old")))
        _ = coord.reduce(.mainFrameResponse(origin: space.origin, status: 401))

        // Nav 2: the user types a correct credential with Remember OFF, and it succeeds.
        startMainNav(coord, to: space)
        let id2 = Coord.ChallengeID(2)
        _ = coord.reduce(.challenge(id: id2, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: true, storeCanRemember: true))
        _ = coord.reduce(.promptResult(id: id2, outcome: .submitted(Cred(user: "alice", password: "new"),
                                                                    remember: false)))
        _ = coord.reduce(.mainFrameResponse(origin: space.origin, status: 200))

        // Nav 3: because the saved value is still known-bad, we must PROMPT, not silently
        // re-auto-fill the saved credential.
        startMainNav(coord, to: space)
        let id3 = Coord.ChallengeID(3)
        let e = coord.reduce(.challenge(id: id3, space: space, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: true, storeCanRemember: true))
        guard case .prompt(let pid, _)? = e.first, pid == id3 else {
            return XCTFail("expected a prompt (saved credential still known-bad), got \(e)")
        }
        XCTAssertFalse(e.contains { if case .lookupSaved = $0 { return true }; return false })
    }

    // MARK: - Main vs subframe classification (known flaw A boundary)

    func testChallengeWhileProvisionalIsMainAndOffersRemember() {
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)   // provisional, not committed
        let id = Coord.ChallengeID(1)
        let e = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: false, storeCanRemember: true))
        guard case .prompt(_, let req)? = e.first else { return XCTFail("expected prompt") }
        XCTAssertTrue(req.offerRemember)
    }

    func testChallengeAfterCommitIsSubframeAndPromptsWithoutStore() {
        let coord = Coord()
        let mainOrigin = origin()
        _ = coord.reduce(.mainProvisionalStarted(origin: mainOrigin))
        _ = coord.reduce(.mainFrameResponse(origin: mainOrigin, status: 200))
        _ = coord.reduce(.mainCommitted)     // main document committed; now a subframe challenges

        // Same origin, different realm subframe. Subframes are prompt-only (flaw B): the user is
        // prompted so they can sign in, but nothing is auto-filled, remembered, or persisted.
        let sub = Coord.SpaceKey(scheme: "https", host: "example.com", port: 443, realm: "SubRealm")
        let id = Coord.ChallengeID(1)
        let e = coord.reduce(.challenge(id: id, space: sub, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: true, storeCanRemember: true))
        guard case .prompt(_, let req)? = e.first else { return XCTFail("expected a subframe prompt") }
        XCTAssertFalse(req.offerRemember)
        XCTAssertFalse(req.offerPasswordManager)
        // No auto-fill for a subframe even though a saved lookup was possible.
        XCTAssertFalse(e.contains { if case .lookupSaved = $0 { return true }; return false })

        // Supplying a typed credential answers this challenge but records no awaiting, so a later
        // main-frame response cannot persist it.
        let supply = coord.reduce(.promptResult(id: id, outcome: .submitted(Cred(user: "u", password: "p"),
                                                                            remember: true)))
        XCTAssertEqual(supply, [.supply(id: id, Cred(user: "u", password: "p"))])
    }

    func testCrossOriginChallengeDuringMainNavIsNotMainButStillPrompts() {
        // A challenge whose origin differs from the main provisional origin (e.g. a
        // subresource of the previous page still loading) must not be treated as main, but the
        // user is still prompted (prompt-only, no store).
        let coord = Coord()
        _ = coord.reduce(.mainProvisionalStarted(origin: origin("new.com")))
        let stale = Coord.SpaceKey(scheme: "https", host: "old.com", port: 443, realm: "R")
        let id = Coord.ChallengeID(1)
        let e = coord.reduce(.challenge(id: id, space: stale, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: true, storeCanRemember: true))
        guard case .prompt(_, let req)? = e.first else { return XCTFail("expected a prompt") }
        XCTAssertFalse(req.offerRemember)
        XCTAssertFalse(e.contains { if case .lookupSaved = $0 { return true }; return false })
    }

    // MARK: - Same-origin flaw-A ambiguity guard (finding 2)

    func testAmbiguousSameOriginMainChallengesDoNotPersist() {
        // The main document and a same-origin subframe (different realm) are both challenged
        // while provisional, so both are classified as main (flaw A). The main-frame 200 cannot
        // be attributed to either, so no credential is persisted even with Remember checked.
        let coord = Coord()
        let mainSpaceK = Coord.SpaceKey(scheme: "https", host: "example.com", port: 443, realm: "Main")
        let subSpaceK = Coord.SpaceKey(scheme: "https", host: "example.com", port: 443, realm: "Sub")
        _ = coord.reduce(.mainProvisionalStarted(origin: mainSpaceK.origin))

        let id1 = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id1, space: mainSpaceK, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: false, storeCanRemember: true))
        _ = coord.reduce(.promptResult(id: id1, outcome: .submitted(Cred(user: "a", password: "1"),
                                                                    remember: true)))
        let id2 = Coord.ChallengeID(2)
        _ = coord.reduce(.challenge(id: id2, space: subSpaceK, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: false, storeCanRemember: true))
        _ = coord.reduce(.promptResult(id: id2, outcome: .submitted(Cred(user: "b", password: "2"),
                                                                    remember: true)))

        // Ambiguous origin: two spaces challenged as main. Nothing may be persisted.
        let e = coord.reduce(.mainFrameResponse(origin: mainSpaceK.origin, status: 200))
        XCTAssertEqual(e, [])
    }

    // MARK: - Redirect chain resolves only the final origin (guarantee 5, flaw D)

    func testRedirectChainResolvesFinalOriginOnlyAndDoesNotRejectIntermediate() {
        let coord = Coord()
        let realmA = Coord.SpaceKey(scheme: "https", host: "a.example.com", port: 443, realm: "RealmA")
        let realmB = Coord.SpaceKey(scheme: "https", host: "b.example.com", port: 443, realm: "RealmB")

        _ = coord.reduce(.mainProvisionalStarted(origin: realmA.origin))
        let idA = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: idA, space: realmA, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: true, storeCanRemember: true))
        _ = coord.reduce(.savedLookupResult(id: idA, credential: Cred(user: "alice", password: "secret")))
        // Redirect to b (same main navigation, no new provisional start): the origin
        // updates but the pending supply is kept.
        _ = coord.reduce(.mainFrameRedirect(origin: realmB.origin))
        let idB = Coord.ChallengeID(2)
        _ = coord.reduce(.challenge(id: idB, space: realmB, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: true, storeCanRemember: true))
        _ = coord.reduce(.savedLookupResult(id: idB, credential: Cred(user: "carol", password: "bpass")))
        // Only the final response (b) is delivered, and it is a 401 (b rejected).
        _ = coord.reduce(.mainFrameResponse(origin: realmB.origin, status: 401))

        // realmA (accepted, intermediate) must NOT have been marked rejected.
        startMainNav(coord, to: realmA)
        let idA2 = Coord.ChallengeID(3)
        let e = coord.reduce(.challenge(id: idA2, space: realmA, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: true, storeCanRemember: true))
        XCTAssertEqual(e, [.lookupSaved(id: idA2, space: realmA, preferredUser: nil)],
                       "intermediate realmA was wrongly marked rejected")
    }

    // MARK: - Supersede: a late response for an abandoned nav is a no-op (guarantee 7)

    func testSupersededResponseIsNoOp() {
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)
        let id = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: false, storeCanRemember: true))
        _ = coord.reduce(.promptResult(id: id, outcome: .submitted(Cred(user: "x", password: "y"), remember: true)))

        // User navigates away before the response arrives.
        let other = Coord.SpaceKey(scheme: "https", host: "other.com", port: 443, realm: "R")
        _ = coord.reduce(.mainProvisionalStarted(origin: other.origin))

        // The late response for the old origin must resolve nothing (no persist).
        let e = coord.reduce(.mainFrameResponse(origin: space.origin, status: 200))
        XCTAssertEqual(e, [])
    }

    // MARK: - No lockout latch: cancel then revisit still auto-fills (guarantee 6)

    func testCancelledPromptLeavesNoLatchAndAutoFillStillHappens() {
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)
        let id = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: true, storeCanRemember: true))
        _ = coord.reduce(.savedLookupResult(id: id, credential: nil))    // nothing saved -> prompt
        let cancel = coord.reduce(.promptResult(id: id, outcome: .cancelled))
        XCTAssertEqual(cancel, [.cancel(id: id)])
        _ = coord.reduce(.mainFrameResponse(origin: space.origin, status: 401))  // 401 body rendered

        // A later visit with a saved credential present must auto-fill (no userTookOver latch).
        startMainNav(coord, to: space)
        let id2 = Coord.ChallengeID(2)
        let e = coord.reduce(.challenge(id: id2, space: space, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: true, storeCanRemember: true))
        XCTAssertEqual(e, [.lookupSaved(id: id2, space: space, preferredUser: nil)])
    }

    // MARK: - Picker with empty username re-prompts, prefilling what we know (finding 8)

    func testPickerEmptyUsernameRePromptsWithPrefill() {
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)
        let id = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: false, storeCanRemember: true))
        _ = coord.reduce(.promptResult(id: id, outcome: .openPasswordManager(typed: Cred(user: "typeduser", password: ""))))
        // Picker returns a password but no username.
        let e = coord.reduce(.pickerResult(id: id,
                                           chosen: Cred(user: "", password: "pickedpw"),
                                           typedFallback: Cred(user: "typeduser", password: "")))
        guard case .prompt(_, let req)? = e.first else { return XCTFail("expected re-prompt") }
        XCTAssertEqual(req.prefill?.user, "typeduser")
        XCTAssertEqual(req.prefill?.password, "pickedpw")
    }

    func testPickerValidCredentialIsSupplied() {
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)
        let id = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: false, storeCanRemember: true))
        _ = coord.reduce(.promptResult(id: id, outcome: .openPasswordManager(typed: nil)))
        let picked = Cred(user: "picked", password: "pw")
        let e = coord.reduce(.pickerResult(id: id, chosen: picked, typedFallback: nil))
        XCTAssertEqual(e, [.supply(id: id, picked)])
    }

    // MARK: - Save failure surfaces a toast; success clears rejection (finding 5)

    func testSaveFailureToasts() {
        let coord = Coord()
        let space = mainSpace()
        let e = coord.reduce(.saveResult(space: space, host: "example.com", success: false))
        XCTAssertEqual(e, [.toast("Could not save the password for example.com")])
    }

    func testSaveSuccessEmitsNothing() {
        let coord = Coord()
        let space = mainSpace()
        let e = coord.reduce(.saveResult(space: space, host: "example.com", success: true))
        XCTAssertEqual(e, [])
    }

    // MARK: - Digest / NTLM: prompt only, no remember, no picker

    func testNonBasicChallengePromptsWithoutRememberOrPicker() {
        let coord = Coord()
        let space = mainSpace(realm: "DigestRealm")
        startMainNav(coord, to: space)
        let id = Coord.ChallengeID(1)
        let e = coord.reduce(.challenge(id: id, space: space, isBasic: false, proposedUser: nil,
                                        savedLookupPossible: true, storeCanRemember: true))
        guard case .prompt(_, let req)? = e.first else { return XCTFail("expected prompt") }
        XCTAssertFalse(req.offerRemember)
        XCTAssertFalse(req.offerPasswordManager)
        // Must not attempt a saved lookup for a non-basic scheme.
        XCTAssertFalse(e.contains { if case .lookupSaved = $0 { return true }; return false })
    }

    // MARK: - devNull store cannot remember: no remember, no persistence

    func testStoreCannotRememberOffersNeitherRememberNorPicker() {
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)
        let id = Coord.ChallengeID(1)
        let e = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: false, storeCanRemember: false))
        guard case .prompt(_, let req)? = e.first else { return XCTFail("expected prompt") }
        XCTAssertFalse(req.offerRemember)
        XCTAssertFalse(req.offerPasswordManager)
    }

    // MARK: - A saved lookup that resolves after the navigation was superseded cancels the dead
    // challenge instead of surfacing an unsolicited prompt for a page the user already left.

    func testSupersededSavedLookupCancelsInsteadOfPrompting() {
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)
        let id = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: true, storeCanRemember: true))
        // User navigates away before the async saved lookup returns.
        let other = Coord.SpaceKey(scheme: "https", host: "other.com", port: 443, realm: "R")
        _ = coord.reduce(.mainProvisionalStarted(origin: other.origin))
        // The lookup finishes with nothing saved. The challenge is for a dead navigation: answer
        // it with cancel, do NOT prompt.
        let e = coord.reduce(.savedLookupResult(id: id, credential: nil))
        XCTAssertEqual(e, [.cancel(id: id)])
    }

    // MARK: - Remember checkbox default respects a prior explicit decline (finding 4)

    func testRememberDefaultsOffAfterUserDeclinedToRemember() {
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)
        let id = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: false, storeCanRemember: true))
        // User types a credential with Remember OFF, and it succeeds.
        _ = coord.reduce(.promptResult(id: id, outcome: .submitted(Cred(user: "bob", password: "pw"),
                                                                    remember: false)))
        _ = coord.reduce(.mainFrameResponse(origin: space.origin, status: 200))

        // Next visit prompts again. Remember must not be pre-checked just because the user typed
        // something last time (they explicitly declined). Their typed value is still prefilled.
        startMainNav(coord, to: space)
        let id2 = Coord.ChallengeID(2)
        let e = coord.reduce(.challenge(id: id2, space: space, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: false, storeCanRemember: true))
        guard case .prompt(_, let req)? = e.first else { return XCTFail("expected prompt") }
        XCTAssertFalse(req.rememberByDefault)
        XCTAssertEqual(req.prefill?.user, "bob")
    }

    func testRememberDefaultsOnAfterSavedCredentialWasRejected() {
        // When a saved credential was rejected, the correction prompt SHOULD default Remember on
        // so the user's fix can replace the known-bad stored value.
        let coord = Coord()
        let space = mainSpace()
        startMainNav(coord, to: space)
        let id = Coord.ChallengeID(1)
        _ = coord.reduce(.challenge(id: id, space: space, isBasic: true, proposedUser: nil,
                                    savedLookupPossible: true, storeCanRemember: true))
        _ = coord.reduce(.savedLookupResult(id: id, credential: Cred(user: "alice", password: "old")))
        _ = coord.reduce(.mainFrameResponse(origin: space.origin, status: 401))  // saved rejected

        startMainNav(coord, to: space)
        let id2 = Coord.ChallengeID(2)
        let e = coord.reduce(.challenge(id: id2, space: space, isBasic: true, proposedUser: nil,
                                        savedLookupPossible: true, storeCanRemember: true))
        guard case .prompt(_, let req)? = e.first else { return XCTFail("expected prompt") }
        XCTAssertTrue(req.rememberByDefault)
    }
}
