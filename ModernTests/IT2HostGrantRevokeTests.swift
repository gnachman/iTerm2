//
//  IT2HostGrantRevokeTests.swift
//  iTerm2 ModernTests
//
//  Taking an "Always Allow This Host" grant away (Phase 3d): from Settings, where the sheet
//  revokes, and from the session menu, where switching it2 access off must also forget the
//  grant so the next connection does not quietly let the host back in.
//

import XCTest
@testable import iTerm2SharedARC

private final class RevokeMemoryBacking: IT2HostGrantBacking {
    var data: Data?
    func loadGrantData() -> Data? { data }
    func saveGrantData(_ data: Data?) { self.data = data }
}

@MainActor
final class IT2HostGrantRevokeTests: XCTestCase {
    private var registered = [Conductor]()

    override func tearDown() {
        MainActor.assumeIsolated {
            for conductor in registered {
                ConductorRegistry.instance.remove(conductorGUID: conductor.guid,
                                                  sshIdentity: conductor.sshIdentity)
            }
            registered = []
            Conductor.hostGrantStoreForTesting = nil
        }
        super.tearDown()
    }

    /// A live conductor in the shared registry, under a host name no other test uses.
    private func registeredConductor(host: String) -> Conductor {
        let conductor = Conductor(host, boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
        ConductorRegistry.instance.addConductor(conductor, for: conductor.sshIdentity)
        registered.append(conductor)
        return conductor
    }

    private func uniqueHost() -> String {
        return "revoke-\(UUID().uuidString.lowercased().prefix(8))"
    }

    private func grant(for host: String, granted: Date = Date()) -> IT2HostGrant {
        return IT2HostGrant(host: host, id: "id", secretSHA256: "hash", granted: granted)
    }

    // MARK: - revoke

    func testRevokeRemovesTheRecord() {
        let store = IT2HostGrantStore(backing: RevokeMemoryBacking())
        let conductor = registeredConductor(host: uniqueHost())
        let host = conductor.sshIdentity.stringIdentifier
        store.add(grant(for: host))
        store.revoke(host: host)
        XCTAssertNil(store.grant(forHost: host))
    }

    // A connection the grant let in must ask again on its next command, not stay allowed until
    // it reconnects.
    func testRevokeMakesAGrantedLiveConnectionAskAgain() {
        let store = IT2HostGrantStore(backing: RevokeMemoryBacking())
        let conductor = registeredConductor(host: uniqueHost())
        let host = conductor.sshIdentity.stringIdentifier
        store.add(grant(for: host))
        conductor.it2Authorized = true
        store.revoke(host: host)
        XCTAssertNil(conductor.it2Authorized)
    }

    // Revoking takes trust away; it must not turn an explicit refusal back into a question.
    func testRevokeLeavesADeniedConnectionDenied() {
        let store = IT2HostGrantStore(backing: RevokeMemoryBacking())
        let conductor = registeredConductor(host: uniqueHost())
        let host = conductor.sshIdentity.stringIdentifier
        store.add(grant(for: host))
        conductor.it2Authorized = false
        store.revoke(host: host)
        XCTAssertEqual(conductor.it2Authorized, false)
    }

    func testRevokeLeavesOtherHostsAlone() {
        let store = IT2HostGrantStore(backing: RevokeMemoryBacking())
        let revoked = registeredConductor(host: uniqueHost())
        let other = registeredConductor(host: uniqueHost())
        store.add(grant(for: revoked.sshIdentity.stringIdentifier))
        store.add(grant(for: other.sshIdentity.stringIdentifier))
        revoked.it2Authorized = true
        other.it2Authorized = true

        store.revoke(host: revoked.sshIdentity.stringIdentifier)

        XCTAssertNotNil(store.grant(forHost: other.sshIdentity.stringIdentifier))
        XCTAssertEqual(other.it2Authorized, true)
    }

    // MARK: - The session menu

    // Switching it2 off from the menu must also forget the grant, or the host would be let back
    // in on its very next connection and the switch would seem not to have worked.
    func testDenyingFromTheMenuForgetsTheGrant() {
        let store = IT2HostGrantStore(backing: RevokeMemoryBacking())
        Conductor.hostGrantStoreForTesting = store
        let conductor = registeredConductor(host: uniqueHost())
        let host = conductor.sshIdentity.stringIdentifier
        store.add(grant(for: host))

        conductor.setIT2AuthorizationFromMenu(false)

        XCTAssertNil(store.grant(forHost: host))
        XCTAssertEqual(conductor.it2Authorized, false)
    }

    // Switching it2 off in one connection takes the grant away from every live connection to
    // the host, as removing it in Settings does. Otherwise a second connection let in only by
    // the grant would keep working with no prompt after the grant is gone.
    func testDenyingFromTheMenuRevokesForOtherLiveConnections() {
        let store = IT2HostGrantStore(backing: RevokeMemoryBacking())
        Conductor.hostGrantStoreForTesting = store
        let host = uniqueHost()
        let switched = registeredConductor(host: host)
        let sibling = registeredConductor(host: host)
        XCTAssertEqual(switched.sshIdentity.stringIdentifier, sibling.sshIdentity.stringIdentifier)
        store.add(grant(for: switched.sshIdentity.stringIdentifier))
        switched.it2Authorized = true
        sibling.it2Authorized = true

        switched.setIT2AuthorizationFromMenu(false)

        XCTAssertEqual(switched.it2Authorized, false)
        XCTAssertNil(sibling.it2Authorized, "the sibling must ask again on its next command")
    }

    // With no grant on record there is nothing to take back from other connections: each
    // connection's own Allow is its own business.
    func testDenyingFromTheMenuWithoutAGrantLeavesOtherConnectionsAlone() {
        let store = IT2HostGrantStore(backing: RevokeMemoryBacking())
        Conductor.hostGrantStoreForTesting = store
        let host = uniqueHost()
        let switched = registeredConductor(host: host)
        let sibling = registeredConductor(host: host)
        switched.it2Authorized = true
        sibling.it2Authorized = true

        switched.setIT2AuthorizationFromMenu(false)

        XCTAssertEqual(switched.it2Authorized, false)
        XCTAssertEqual(sibling.it2Authorized, true)
    }

    func testAllowingFromTheMenuKeepsTheGrant() {
        let store = IT2HostGrantStore(backing: RevokeMemoryBacking())
        Conductor.hostGrantStoreForTesting = store
        let conductor = registeredConductor(host: uniqueHost())
        let host = conductor.sshIdentity.stringIdentifier
        store.add(grant(for: host))

        conductor.setIT2AuthorizationFromMenu(true)

        XCTAssertNotNil(store.grant(forHost: host))
        XCTAssertEqual(conductor.it2Authorized, true)
    }

    // MARK: - The Settings sheet

    func testSheetListsHostsSorted() {
        let store = IT2HostGrantStore(backing: RevokeMemoryBacking())
        store.add(grant(for: "u@zeta"))
        store.add(grant(for: "u@alpha"))
        store.add(grant(for: "u@host10"))
        store.add(grant(for: "u@host9"))
        let sheet = IT2HostGrantsWindowController(store: store)
        XCTAssertEqual(sheet.displayedHosts, ["u@alpha", "u@host9", "u@host10", "u@zeta"])
        XCTAssertFalse(sheet.isShowingEmptyState)
    }

    func testSheetShowsTheEmptyState() {
        let sheet = IT2HostGrantsWindowController(store: IT2HostGrantStore(backing: RevokeMemoryBacking()))
        XCTAssertEqual(sheet.displayedHosts, [])
        XCTAssertTrue(sheet.isShowingEmptyState)
        XCTAssertFalse(sheet.canRemove, "nothing to remove")
    }

    // Remove revokes rather than merely deleting, so a live connection asks again.
    func testRemovingFromTheSheetRevokes() {
        let store = IT2HostGrantStore(backing: RevokeMemoryBacking())
        let conductor = registeredConductor(host: uniqueHost())
        let host = conductor.sshIdentity.stringIdentifier
        store.add(grant(for: host))
        store.add(grant(for: "zzz-kept"))
        conductor.it2Authorized = true
        let sheet = IT2HostGrantsWindowController(store: store)
        XCTAssertEqual(sheet.displayedHosts.first, host)
        XCTAssertFalse(sheet.canRemove, "nothing selected yet")

        sheet.removeRows(IndexSet(integer: 0))

        XCTAssertNil(store.grant(forHost: host))
        XCTAssertNil(conductor.it2Authorized)
        XCTAssertEqual(sheet.displayedHosts, ["zzz-kept"])
        XCTAssertFalse(sheet.canRemove, "the removed rows are no longer selected")
    }

    func testRemovingEveryHostShowsTheEmptyState() {
        let store = IT2HostGrantStore(backing: RevokeMemoryBacking())
        store.add(grant(for: "u@a"))
        store.add(grant(for: "u@b"))
        let sheet = IT2HostGrantsWindowController(store: store)
        sheet.removeRows(IndexSet([0, 1]))
        XCTAssertEqual(store.all, [])
        XCTAssertTrue(sheet.isShowingEmptyState)
    }
}
