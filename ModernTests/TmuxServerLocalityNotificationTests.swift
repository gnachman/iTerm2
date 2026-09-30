//
//  TmuxServerLocalityNotificationTests.swift
//  ModernTests
//
//  A tmux pane session fetches its pane pid only when the server is known to be local, and it
//  asks exactly once, when it becomes a client. If the locality lookup has not settled by then
//  (the first sysctl for a local server can miss), nothing ever asked again and the pane had no
//  job detection for the life of the connection. The controller now announces when locality
//  settles so pane sessions can ask again.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxServerLocalityNotificationTests: XCTestCase {
    private func makeController() -> TmuxController {
        return TmuxController(gateway: nil, clientName: "test", profile: [:], profileModel: nil)!
    }

    // Our own pid resolves to a name (not "tmux", so the server reads as remote, which is beside
    // the point): locality is known the moment the identity reply is parsed.
    func testSettlingLocalityPostsNotification() {
        let controller = makeController()
        let posted = expectation(forNotification: .tmuxControllerServerLocalityDidBecomeKnown,
                                 object: controller)
        controller.didLoadServerIdentity("/tmp/sock,\(getpid())")
        wait(for: [posted], timeout: 1)
        XCTAssertTrue(controller.serverLocalityKnown)
    }

    // A pid the kernel cannot name leaves locality unknown, and nothing is announced yet.
    func testUnresolvedPidPostsNothing() {
        let controller = makeController()
        let posted = expectation(forNotification: .tmuxControllerServerLocalityDidBecomeKnown,
                                 object: controller)
        posted.isInverted = true
        controller.didLoadServerIdentity("/tmp/sock,999999")
        wait(for: [posted], timeout: 0.2)
        XCTAssertFalse(controller.serverLocalityKnown)
    }
}
