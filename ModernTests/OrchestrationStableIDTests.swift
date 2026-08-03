//
//  OrchestrationStableIDTests.swift
//  iTerm2 ModernTests
//
//  The orchestrator's <workgroups> snapshot is where the model copies session
//  references from, and the synthetic "session:<...>" scope is what a granted
//  claim is keyed by. Both must carry the reload-durable stableID (not the
//  rotating guid) so a copied reference and a granted claim survive a shell
//  reload.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class OrchestrationStableIDTests: XCTestCase {
    func testSyntheticSummaryEmitsStableID() {
        let session = PTYSession(synthetic: false)!
        let summary = WorkgroupIntrospection.syntheticSummary(for: session)
        // The snapshot's session_guid field is the stableID, not the guid...
        XCTAssertEqual(summary.sessions.first?.sessionGuid, session.stableID)
        XCTAssertNotEqual(summary.sessions.first?.sessionGuid, session.guid)
        // ...and the synthetic workgroup/claim scope is "session:<stableID>".
        XCTAssertEqual(summary.workgroupID, "session:" + session.stableID)
    }

    func testStandaloneContextScopeUsesStableID() {
        let session = PTYSession(synthetic: false)!
        let ctx = WorkgroupIntrospection.context(for: session)
        XCTAssertEqual(ctx?.workgroupID, "session:" + session.stableID)
    }
}
