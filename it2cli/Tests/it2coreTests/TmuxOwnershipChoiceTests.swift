import XCTest
@testable import it2core

/// Choosing which advertised iTerm2 to talk to, and making the socket and the AppleScript cookie
/// target come from the SAME choice.
///
/// Picking them separately is how a call connects to one instance's socket and then asks a
/// different instance for a cookie, which the first instance rejects. Seen live 2026-09-27 and
/// again 2026-09-28: a tmux server started by an older build hands every pane its stale
/// IT2_APP_PATH, the socket is chosen correctly from the live @it2_client_* record, and the cookie
/// is requested from a build that has since quit. The command fails with "Authentication failed"
/// having done nothing.
final class TmuxOwnershipChoiceTests: XCTestCase {
    private func record(suite: String, app: String? = nil) -> [String: String] {
        var r = ["suite": suite]
        if let app {
            r["app"] = app
        }
        return r
    }

    private func path(forSuite suite: String) -> String {
        return "/sockets/\(suite)"
    }

    // MARK: - Choosing the record

    func testChoosesTheFirstRecordWhoseSocketExists() throws {
        let records = [record(suite: "alt7", app: "/A.app"),
                       record(suite: "main", app: "/B.app")]
        let chosen = TmuxOwnership.chooseRecord(records,
                                                socketPathForSuite: path(forSuite:),
                                                socketExists: { _ in true })
        XCTAssertEqual(chosen?.record["suite"], "alt7", "newest attacher first is the caller's order")
        XCTAssertEqual(chosen?.socketPath, "/sockets/alt7")
    }

    // An advertiser whose iTerm2 quit without pruning its record: skip it, do not fail the call.
    // The next one down may well be live.
    func testSkipsARecordWhoseSocketIsGone() throws {
        let records = [record(suite: "dead", app: "/Dead.app"),
                       record(suite: "live", app: "/Live.app")]
        let chosen = TmuxOwnership.chooseRecord(records,
                                                socketPathForSuite: path(forSuite:),
                                                socketExists: { $0 == "/sockets/live" })
        XCTAssertEqual(chosen?.record["suite"], "live")
        XCTAssertEqual(chosen?.record["app"], "/Live.app",
                       "the app must come from the same record as the socket")
    }

    func testReturnsNilWhenNoAdvertiserIsLive() throws {
        let records = [record(suite: "dead", app: "/Dead.app")]
        XCTAssertNil(TmuxOwnership.chooseRecord(records,
                                                socketPathForSuite: path(forSuite:),
                                                socketExists: { _ in false }))
    }

    func testIgnoresRecordsWithNoSuite() throws {
        let records = [["app": "/NoSuite.app"], ["suite": "", "app": "/Empty.app"],
                       record(suite: "good", app: "/Good.app")]
        let chosen = TmuxOwnership.chooseRecord(records,
                                                socketPathForSuite: path(forSuite:),
                                                socketExists: { _ in true })
        XCTAssertEqual(chosen?.record["suite"], "good")
    }

    // A remote record carries sock/nonce and no suite, so it must not be mistaken for a local one.
    func testIgnoresARemoteRecord() throws {
        let records = [["sock": "/tmp/x.sock", "nonce": "abc"], record(suite: "local")]
        let chosen = TmuxOwnership.chooseRecord(records,
                                                socketPathForSuite: path(forSuite:),
                                                socketExists: { _ in true })
        XCTAssertEqual(chosen?.record["suite"], "local")
    }

    // MARK: - Which iTerm2 to ask for a cookie

    // The defect: the record wins over the variable the pane inherited from the tmux server.
    func testRecordAppBeatsTheInheritedVariable() {
        XCTAssertEqual(CookieAuth.appTarget(recordAppPath: "/Live.app", inheritedAppPath: "/Stale.app"),
                       "application \"/Live.app\"")
    }

    // Older iTerm2s advertise a record with no "app" key, so the variable is still the fallback.
    func testInheritedVariableIsUsedWhenTheRecordHasNoApp() {
        XCTAssertEqual(CookieAuth.appTarget(recordAppPath: nil, inheritedAppPath: "/Inherited.app"),
                       "application \"/Inherited.app\"")
    }

    func testPlainTargetWhenNeitherIsPresent() {
        XCTAssertEqual(CookieAuth.appTarget(recordAppPath: nil, inheritedAppPath: nil),
                       "application \"iTerm2\"")
    }

    // MARK: - Routing to the client that can actually place the pane

    private func clientLine(_ name: String, created: Int, session: String?) -> String {
        var line = "IT2CLIENT\t\(name)\t1\t\(created)"
        if let session {
            line += "\t\(session)"
        }
        return line
    }

    private func optionLine(_ name: String, _ json: String) -> String {
        let hex = { (s: String) in s.utf8.map { String(format: "%02x", $0) }.joined() }
        return "@it2_client_\(hex(name)) c_\(hex(json))"
    }

    // The 2026-09-28 failure, on the local side. Two clients on one server driving different
    // tmux sessions; the pane is in $9, held by the OLDER client. Newest-first alone routed
    // every call to the one that cannot place it.
    func testClientShowingThePaneIsPreferredOverTheNewest() {
        let output = [clientLine("/dev/pts/3", created: 100, session: "$9"),
                      clientLine("/dev/pts/4", created: 200, session: "$10"),
                      optionLine("/dev/pts/3", "{\"suite\":\"holds-the-pane\"}"),
                      optionLine("/dev/pts/4", "{\"suite\":\"newest\"}"),
                      "IT2PANESESSION\t$9"].joined(separator: "\n")
        let records = TmuxOwnership.records(inServerOutput: output)
        XCTAssertEqual(records.first?["suite"], "holds-the-pane")
        XCTAssertEqual(records.count, 2, "the other stays as a fallback")
        XCTAssertEqual(records.last?["suite"], "newest")
    }

    // A window can be linked into two sessions, so both clients can hold the pane.
    func testNewestFirstStillBreaksTiesWithinThePreferredGroup() {
        let output = [clientLine("/dev/pts/3", created: 100, session: "$9"),
                      clientLine("/dev/pts/4", created: 200, session: "$9"),
                      optionLine("/dev/pts/3", "{\"suite\":\"older\"}"),
                      optionLine("/dev/pts/4", "{\"suite\":\"newer\"}"),
                      "IT2PANESESSION\t$9"].joined(separator: "\n")
        XCTAssertEqual(TmuxOwnership.records(inServerOutput: output).map { $0["suite"] },
                       ["newer", "older"])
    }

    // Old tmux, a stale pane, or a failed display-message: the previous rule is the fallback.
    func testFallsBackToNewestWhenThePaneSessionIsUnknown() {
        let output = [clientLine("/dev/pts/3", created: 100, session: "$9"),
                      clientLine("/dev/pts/4", created: 200, session: "$10"),
                      optionLine("/dev/pts/3", "{\"suite\":\"older\"}"),
                      optionLine("/dev/pts/4", "{\"suite\":\"newer\"}")].joined(separator: "\n")
        XCTAssertEqual(TmuxOwnership.records(inServerOutput: output).map { $0["suite"] },
                       ["newer", "older"])
    }

    // tmux too old for #{client_session}: no session field at all, so nothing is preferred.
    func testOldTmuxWithoutClientSessionStillOrdersByAttachTime() {
        let output = [clientLine("/dev/pts/3", created: 100, session: nil),
                      clientLine("/dev/pts/4", created: 200, session: nil),
                      optionLine("/dev/pts/3", "{\"suite\":\"older\"}"),
                      optionLine("/dev/pts/4", "{\"suite\":\"newer\"}"),
                      "IT2PANESESSION\t$9"].joined(separator: "\n")
        XCTAssertEqual(TmuxOwnership.records(inServerOutput: output).map { $0["suite"] },
                       ["newer", "older"])
    }

    func testQueryAsksWhichSessionHoldsThePane() {
        let args = TmuxOwnership.queryArguments(socketPath: "/tmp/s", pane: "%7")
        let i = try? XCTUnwrap(args.firstIndex(of: "display-message"))
        XCTAssertNotNil(i)
        XCTAssertEqual(Array(args[i!..<(i! + 4)]), ["display-message", "-p", "-t", "%7"])
        XCTAssertEqual(args[i! + 4], "IT2PANESESSION\t#{session_id}")
        XCTAssertTrue(args.contains { $0.contains("#{client_session}") })
    }

    func testQuerySkipsThePaneCommandWhenThereIsNoPane() {
        XCTAssertFalse(TmuxOwnership.queryArguments(socketPath: "/tmp/s", pane: nil)
            .contains("display-message"))
        XCTAssertFalse(TmuxOwnership.queryArguments(socketPath: "/tmp/s", pane: "")
            .contains("display-message"))
    }

    // MARK: - An explicit --tmux feeds the record lookup

    // A caller that passes --tmux may not have TMUX in its own environment: a hook spawned with a
    // trimmed environment, a peer launched from elsewhere, or a test. Such a call addresses the
    // pane correctly but would pick its socket from the inherited IT2_SUITE, which is the wrong
    // instance whenever those disagree.
    func testExplicitTmuxWinsOverTheEnvironment() {
        XCTAssertEqual(TmuxOwnership.effectiveTMUX(explicit: "/tmp/sock,42,0",
                                                   environment: ["TMUX": "/other,1,0"]),
                       "/tmp/sock,42,0")
    }

    func testEnvironmentIsUsedWhenNoExplicitValueIsGiven() {
        XCTAssertEqual(TmuxOwnership.effectiveTMUX(explicit: nil,
                                                   environment: ["TMUX": "/env,1,0"]),
                       "/env,1,0")
    }

    func testNeitherYieldsNil() {
        XCTAssertNil(TmuxOwnership.effectiveTMUX(explicit: nil, environment: [:]))
        XCTAssertNil(TmuxOwnership.effectiveTMUX(explicit: "", environment: [:]))
    }

    // An empty value is not a path; it must not produce `application ""`.
    func testEmptyValuesAreIgnored() {
        XCTAssertEqual(CookieAuth.appTarget(recordAppPath: "", inheritedAppPath: ""),
                       "application \"iTerm2\"")
        XCTAssertEqual(CookieAuth.appTarget(recordAppPath: "", inheritedAppPath: "/Inherited.app"),
                       "application \"/Inherited.app\"")
    }
}
