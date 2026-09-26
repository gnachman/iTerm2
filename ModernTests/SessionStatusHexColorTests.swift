//
//  SessionStatusHexColorTests.swift
//  ModernTests
//
//  get_session_status reports colors as #rrggbb. iTermSRGBColor components are not clamped at the
//  source -- an out-of-gamut Display P3 selection converted to sRGB can overshoot either end, and
//  the OSC 21337 path goes through xtermParseColorArgument, which does not bound them -- so the
//  formatter has to.
//

import XCTest
@testable import iTerm2SharedARC

final class SessionStatusHexColorTests: XCTestCase {
    private func hex(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> String {
        return SetStatusBuiltInFunction.hexString(iTermSRGBColor(r: r, g: g, b: b))
    }

    func testExactEndpoints() {
        XCTAssertEqual(hex(0, 0, 0), "#000000")
        XCTAssertEqual(hex(1, 1, 1), "#ffffff")
    }

    // Truncation would give #7f7f7f, so a color set as #808080 would not read back as #808080.
    func testRoundsRatherThanTruncates() {
        XCTAssertEqual(hex(0.5, 0.5, 0.5), "#808080")
    }

    // Every 8-bit value must survive a set/get round trip.
    func testAllByteValuesRoundTrip() {
        for byte in 0...255 {
            let component = CGFloat(byte) / 255.0
            XCTAssertEqual(hex(component, component, component),
                           String(format: "#%02x%02x%02x", byte, byte, byte))
        }
    }

    // Truncating 1.05 * 255 = 267 would emit four hex digits for that channel; truncating
    // -0.05 * 255 = -12 would emit "fffffff4". Either way the result is not a color.
    func testClampsOutOfRangeComponents() {
        XCTAssertEqual(hex(1.05, 0.5, -0.05), "#ff8000")
        XCTAssertEqual(hex(-1, -1, -1), "#000000")
        XCTAssertEqual(hex(2, 2, 2), "#ffffff")
    }

    // NaN survives min/max (both comparisons are false), so an unguarded clamp reaches Int() and
    // traps, taking the app down. It is reachable from terminal output: OSC 21337 parses colors
    // with xtermParseColorArgument, whose limit calculation overflows to 0 for an 8-digit
    // component, so "rgb:00000000/00/00" divides 0 by 0.
    func testNaNDoesNotTrap() {
        // Derived at runtime so nothing is constant-folded.
        let zero = CGFloat(Double(SessionStatusHexColorTests.zeroSource))
        let nan = zero / zero
        XCTAssertTrue(nan.isNaN, "precondition")
        XCTAssertEqual(hex(nan, 0.5, nan), "#008000")
    }

    func testInfinitiesClamp() {
        let zero = CGFloat(Double(SessionStatusHexColorTests.zeroSource))
        XCTAssertEqual(hex(CGFloat(1.0) / zero, CGFloat(-1.0) / zero, 0), "#ff0000")
    }

    private static var zeroSource: Int { return Int(ProcessInfo.processInfo.processIdentifier) * 0 }

    func testResultIsAlwaysSixHexDigits() {
        let zero = CGFloat(Double(SessionStatusHexColorTests.zeroSource))
        for value in [-1.0, -0.05, 0.0, 0.25, 0.5, 1.0, 1.05, 2.0,
                      Double(zero / zero), Double(CGFloat(1.0) / zero)] as [CGFloat] {
            let result = hex(value, value, value)
            XCTAssertEqual(result.count, 7, "\(value) produced \(result)")
            XCTAssertTrue(result.hasPrefix("#"))
            XCTAssertTrue(result.dropFirst().allSatisfy { $0.isHexDigit })
        }
    }
}

// A pane address arrives from the public iterm2 namespace, so a script can pass anything. The
// bounds have to hold here as well as in the CLI's parser: inside the matcher, serverPid == 0 on a
// CONTROLLER means "identity has not arrived yet", so a zero passed IN would match every pending
// controller on any socket and hand back one of its panes.
final class TmuxPaneAddressRangeTests: XCTestCase {
    func testAcceptsAPlausibleAddress() {
        XCTAssertTrue(TmuxPaneLocator.addressIsInRange(socketPath: "/tmp/d", serverPID: 52533, pane: 0))
        XCTAssertTrue(TmuxPaneLocator.addressIsInRange(socketPath: "/tmp/d", serverPID: 1, pane: 423))
    }

    func testRejectsNonPositiveServerPID() {
        XCTAssertFalse(TmuxPaneLocator.addressIsInRange(socketPath: "/tmp/d", serverPID: 0, pane: 0))
        XCTAssertFalse(TmuxPaneLocator.addressIsInRange(socketPath: "/tmp/d", serverPID: -1, pane: 0))
    }

    func testRejectsEmptySocketPath() {
        XCTAssertFalse(TmuxPaneLocator.addressIsInRange(socketPath: "", serverPID: 52533, pane: 0))
    }

    func testRejectsNegativePane() {
        XCTAssertFalse(TmuxPaneLocator.addressIsInRange(socketPath: "/tmp/d", serverPID: 52533, pane: -1))
    }
}

// RLogOncePerKey backs every always-on log on a per-hook-event path (the pane locator's misses and
// the gateway-status warning). It must stay bounded no matter how many distinct keys arrive: any
// script can call session_id_for_tmux_pane, and a user with many panes across servers iTerm2 is not
// attached to accumulates keys just by working.
//
// These drive the real iTermRLogKeyBudget rather than restating its logic, so changing the
// implementation can actually fail them.
final class RLogOncePerKeyBudgetTests: XCTestCase {
    private func loudCount(_ budget: iTermRLogKeyBudget, _ keys: [String]) -> Int {
        return keys.filter { budget.claim($0, budget: 4) }.count
    }

    func testEachKeyIsLoudOnlyOnce() {
        let budget = iTermRLogKeyBudget()
        XCTAssertEqual(loudCount(budget, ["veto:a", "veto:a", "veto:a"]), 1)
    }

    // Exhausting the allowance must stop the loud branch, not stop recording keys: a cap that did
    // the latter would take the loud branch forever for every key past it.
    func testRunningOutOfBudgetSilencesRatherThanLoops() {
        let budget = iTermRLogKeyBudget()
        let keys = (0..<50).map { "veto:pane-\($0)" }
        XCTAssertEqual(loudCount(budget, keys), 4)
        // Replaying them must add nothing.
        XCTAssertEqual(loudCount(budget, keys), 0)
        XCTAssertEqual(loudCount(budget, keys), 0)
    }

    // The budget is per group, so a call site minting many keys cannot silence an unrelated one.
    func testOneGroupCannotExhaustAnother() {
        let budget = iTermRLogKeyBudget()
        _ = loudCount(budget, (0..<50).map { "veto:pane-\($0)" })
        XCTAssertEqual(loudCount(budget, ["gateway-status:abc"]), 1,
                       "a noisy group must not consume another group's allowance")
    }

    // The group map has to be bounded too. A caller that built a key straight from untrusted input
    // with no colon would make every distinct value its own group, and an unbounded map would then
    // grow forever AND take the loud branch once per value -- the exact failure the budget exists
    // to prevent, just one level up.
    func testGroupCountIsBounded() {
        let budget = iTermRLogKeyBudget()
        var loud = 0
        for i in 0..<500 {
            if budget.claim("untrusted-value-\(i)", budget: 4) { loud += 1 }
        }
        XCTAssertLessThanOrEqual(loud, 32, "one group per value must not mean one loud line per value")
        // And replaying them adds nothing, rather than going loud again for the unrecorded ones.
        var second = 0
        for i in 0..<500 {
            if budget.claim("untrusted-value-\(i)", budget: 4) { second += 1 }
        }
        XCTAssertEqual(second, 0)
    }

    func testGroupIsTheTextBeforeTheFirstColon() {
        XCTAssertEqual(iTermRLogKeyBudget.group(for: "veto:socketPath=/tmp/d,99,0 pane=%1"), "veto")
        XCTAssertEqual(iTermRLogKeyBudget.group(for: "gateway-status:set_status:ABC"), "gateway-status")
        XCTAssertEqual(iTermRLogKeyBudget.group(for: "nocolon"), "nocolon")
    }
}

// The per-controller half of the pane lookup. This is where a mistake either misroutes a status
// update to an unrelated tab or drops it with no sign, so the cases are pinned here rather than
// left to the manual plan. Which tmux session a controller is showing never enters into it: a pane
// id is unique across the server, so socket path plus pid plus pane identifies the pane outright.
final class TmuxPaneLocatorDecisionTests: XCTestCase {
    private let socket = "/private/tmp/tmux-501/default"

    private func canMatch(pid: pid_t = 52533,
                          socketPath: String? = "/private/tmp/tmux-501/default",
                          origin: String? = nil,
                          isLocal: Bool = true,
                          requestedPID: pid_t = 52533,
                          requestedSocketPath: String? = nil,
                          requestedOrigin: String? = nil) -> Bool {
        return TmuxPaneLocator.canMatch(controllerPID: pid,
                                        controllerSocketPath: socketPath,
                                        controllerOrigin: origin,
                                        isLocal: isLocal,
                                        requestedPID: requestedPID,
                                        requestedSocketPath: requestedSocketPath ?? socket,
                                        requestedOrigin: requestedOrigin)
    }

    func testSameServerMatches() {
        XCTAssertTrue(canMatch())
    }

    // A controller that has not identified itself yet is simply not a candidate. No special
    // treatment: the event is dropped and the next one, a moment later, finds it ready.
    func testUnidentifiedControllerDoesNotMatch() {
        XCTAssertFalse(canMatch(pid: 0, socketPath: nil))
        XCTAssertFalse(canMatch(pid: 0, socketPath: nil, requestedPID: 999))
    }

    // Pids collide across machines and the default socket path is byte-identical between two Macs
    // with the same uid, so a remote controller must never be matchable against a local address.
    func testRemoteControllerCannotMatch() {
        XCTAssertFalse(canMatch(isLocal: false))
    }

    func testSocketPathMismatchRejectsAPidMatch() {
        XCTAssertFalse(canMatch(socketPath: "/private/tmp/tmux-501/other"))
    }

    // tmux before 2.2 has no #{socket_path}; a pid alone has to be enough there.
    func testNilSocketPathIsAccepted() {
        XCTAssertTrue(canMatch(socketPath: nil))
    }

    func testUnrelatedServerDoesNotMatch() {
        XCTAssertFalse(canMatch(pid: 111, requestedPID: 222))
    }

    // MARK: - Origin, which says which machine an address was collected on

    // The case this exists for: Claude Code in a tmux -CC pane on a host reached through ssh
    // integration. Both sides name the same conductor, so the pane resolves even though nothing
    // about the address itself is comparable across machines.
    func testRemoteControllerMatchesARequestFromItsOwnConnection() {
        XCTAssertTrue(canMatch(origin: "conductor-A", isLocal: false, requestedOrigin: "conductor-A"))
    }

    // serverIsLocal asks THIS Mac's kernel about a pid on another machine, so it is meaningless
    // for a remote request. A remote match must not depend on it either way.
    func testRemoteMatchIgnoresLocality() {
        XCTAssertTrue(canMatch(origin: "conductor-A", isLocal: true, requestedOrigin: "conductor-A"))
    }

    // Two ssh connections, two hosts (or the same host twice). The pid and socket path can be
    // identical by coincidence; the conductor is what keeps them apart.
    func testDifferentConnectionsDoNotMatch() {
        XCTAssertFalse(canMatch(origin: "conductor-A", isLocal: false, requestedOrigin: "conductor-B"))
    }

    // A remote request must never reach a local tmux server, however well the address matches.
    func testRemoteRequestCannotMatchALocalController() {
        XCTAssertFalse(canMatch(origin: nil, isLocal: true, requestedOrigin: "conductor-A"))
    }

    // And the reverse: a local request must never be answered by a server on the far side of an
    // ssh connection. This does not rely on serverIsLocal, which could be a false positive if the
    // remote pid happens to belong to a local process named tmux.
    func testLocalRequestCannotMatchARemoteController() {
        XCTAssertFalse(canMatch(origin: "conductor-A", isLocal: true, requestedOrigin: nil))
    }

    // A gateway reached by PLAIN ssh has no conductor, so it reports a nil origin exactly like a
    // local one. serverIsLocal is the only thing that can reject it, which is why the local branch
    // still consults it.
    func testPlainSshGatewayIsStillRejectedByLocality() {
        XCTAssertFalse(canMatch(origin: nil, isLocal: false, requestedOrigin: nil))
    }

    // The socket-path cross-check applies to remote matches too: one host can run two servers.
    func testSocketPathMismatchRejectsARemoteMatch() {
        XCTAssertFalse(canMatch(socketPath: "/private/tmp/tmux-501/other",
                                origin: "conductor-A",
                                isLocal: false,
                                requestedOrigin: "conductor-A"))
    }

    // An unidentified controller is not a candidate regardless of origin.
    func testUnidentifiedRemoteControllerDoesNotMatch() {
        XCTAssertFalse(canMatch(pid: 0, socketPath: nil, origin: "conductor-A", requestedOrigin: "conductor-A"))
    }
}
