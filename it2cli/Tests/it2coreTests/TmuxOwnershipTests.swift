import XCTest
import ProtobufRuntime
@testable import it2core

// Reading the records that attached iTerm2 controllers published on a tmux server. The tmux round
// trip itself is not exercised beyond the timeout; these cover the parsing of its output, which is
// the same wire form TmuxController writes and it2.py reads.
final class TmuxOwnershipTests: XCTestCase {
    private func hex(_ string: String) -> String {
        return Data(string.utf8).map { String(format: "%02x", $0) }.joined()
    }

    private func clientLine(_ name: String, control: String = "1", created: Int) -> String {
        return "IT2CLIENT\t\(name)\t\(control)\t\(created)"
    }

    private func optionLine(_ name: String, _ record: String) -> String {
        return "@it2_client_\(hex(name)) c_\(hex(record))"
    }

    func testFindsRecordOfAttachedClient() {
        let output = [clientLine("/dev/pts/3", created: 100),
                      optionLine("/dev/pts/3", "{\"suite\":\"iTerm2\"}"),
                      "status on"].joined(separator: "\n") + "\n"
        XCTAssertEqual(TmuxOwnership.records(inServerOutput: output), [["suite": "iTerm2"]])
    }

    func testRemoteRecordKeepsSocketAndNonceTogether() {
        let output = [clientLine("/dev/pts/3", created: 100),
                      optionLine("/dev/pts/3", "{\"nonce\":\"deadbeef\",\"sock\":\"/home/u/.iterm2/it2/abc.sock\"}")]
            .joined(separator: "\n")
        XCTAssertEqual(TmuxOwnership.records(inServerOutput: output),
                       [["nonce": "deadbeef", "sock": "/home/u/.iterm2/it2/abc.sock"]])
    }

    // A record whose client is no longer attached is exactly the stale case: its iTerm2 crashed
    // or its ssh dropped and nothing pruned it. It must be ignored, not tried.
    func testRecordWithoutAttachedClientIsIgnored() {
        let output = [clientLine("/dev/pts/3", created: 100),
                      optionLine("/dev/pts/3", "{\"suite\":\"live\"}"),
                      optionLine("/dev/pts/9", "{\"suite\":\"stale\"}")].joined(separator: "\n")
        XCTAssertEqual(TmuxOwnership.records(inServerOutput: output), [["suite": "live"]])
    }

    // Two attached iTerm2s: the most recently attached owns the pane, so it comes first.
    func testNewestAttacherFirst() {
        let output = [clientLine("/dev/pts/3", created: 100),
                      clientLine("/dev/pts/4", created: 200),
                      optionLine("/dev/pts/3", "{\"suite\":\"older\"}"),
                      optionLine("/dev/pts/4", "{\"suite\":\"newer\"}")].joined(separator: "\n")
        XCTAssertEqual(TmuxOwnership.records(inServerOutput: output),
                       [["suite": "newer"], ["suite": "older"]])
    }

    // A plain (non-control-mode) client cannot place a pane and never has a record, but a
    // recycled tty name could make one look attached.
    func testNonControlModeClientDoesNotCount() {
        let output = [clientLine("/dev/pts/3", control: "0", created: 100),
                      optionLine("/dev/pts/3", "{\"suite\":\"iTerm2\"}")].joined(separator: "\n")
        XCTAssertEqual(TmuxOwnership.records(inServerOutput: output), [])
    }

    // Very old tmux prints nothing for an unknown format variable; that is not a rejection.
    func testEmptyControlModeFieldIsAccepted() {
        let output = [clientLine("/dev/pts/3", control: "", created: 100),
                      optionLine("/dev/pts/3", "{\"suite\":\"iTerm2\"}")].joined(separator: "\n")
        XCTAssertEqual(TmuxOwnership.records(inServerOutput: output), [["suite": "iTerm2"]])
    }

    func testQuotedValueIsAccepted() {
        let output = [clientLine("/dev/pts/3", created: 100),
                      "@it2_client_\(hex("/dev/pts/3")) \"c_\(hex("{\"suite\":\"iTerm2\"}"))\""].joined(separator: "\n")
        XCTAssertEqual(TmuxOwnership.records(inServerOutput: output), [["suite": "iTerm2"]])
    }

    // Garbage next to a good record must not take the good one down.
    func testMalformedRecordsAreSkipped() {
        let output = [clientLine("/dev/pts/3", created: 100),
                      clientLine("/dev/pts/4", created: 200),
                      clientLine("/dev/pts/5", created: 300),
                      "IT2CLIENT\tshort",                          // too few fields
                      "@it2_client_zz c_00",                        // bad hex name
                      "@it2_client_\(hex("/dev/pts/4")) x_\(hex("{}"))",  // wrong tag
                      "@it2_client_\(hex("/dev/pts/5")) c_\(hex("[1,2]"))", // not an object
                      "@it2_client_\(hex("/dev/pts/5")) c_abc",           // odd-length hex
                      "@it2_client_novalue",
                      optionLine("/dev/pts/3", "{\"suite\":\"ok\"}")].joined(separator: "\n")
        XCTAssertEqual(TmuxOwnership.records(inServerOutput: output), [["suite": "ok"]])
    }

    func testNotInsideTmuxAsksNothing() {
        XCTAssertEqual(TmuxOwnership.advertisedRecords(environment: [:]), [])
        XCTAssertEqual(TmuxOwnership.advertisedRecords(environment: ["TMUX": ""]), [])
        XCTAssertEqual(TmuxOwnership.advertisedRecords(environment: ["TMUX": "garbage"]), [])
    }

    func testHexDecode() {
        XCTAssertEqual(TmuxOwnership.hexDecode("2f6465762f7074732f33"), Data("/dev/pts/3".utf8))
        XCTAssertEqual(TmuxOwnership.hexDecode("2F64"), Data("/d".utf8))
        XCTAssertEqual(TmuxOwnership.hexDecode(""), Data())
        XCTAssertNil(TmuxOwnership.hexDecode("abc"))
        XCTAssertNil(TmuxOwnership.hexDecode("zz"))
    }

    func testQueryUsesOneTmuxInvocationWithRealTabs() {
        let args = TmuxOwnership.queryArguments(socketPath: "/tmp/od,d,socket")
        XCTAssertEqual(args.prefix(3), ["tmux", "-S", "/tmp/od,d,socket"])
        XCTAssertTrue(args.contains(";"), "both commands must run in one client")
        let format = args[args.firstIndex(of: "-F")! + 1]
        XCTAssertEqual(format, "IT2CLIENT\t#{client_name}\t#{client_control_mode}\t#{client_created}")
        XCTAssertFalse(format.contains("\\t"), "tmux does not interpret backslash escapes")
    }

    func testServerHalfOfTMUX() {
        let server = TmuxAddress.server(inTMUX: "/tmp/od,d,socket,52533,3")
        XCTAssertEqual(server?.socketPath, "/tmp/od,d,socket")
        XCTAssertEqual(server?.pid, 52533)
        XCTAssertNil(TmuxAddress.server(inTMUX: "/tmp/default,52533"))
    }

    // MARK: - The process runner

    // A tmux server that has stopped responding must not make every it2 call hang. The stand-in
    // never exits on its own and never closes stdout, which is exactly the shape of a wedged
    // client; the runner has to give up on its own clock.
    func testRunnerGivesUpOnAHungProcess() {
        let start = Date()
        let result = TmuxOwnership.runCapturingStdout(executable: "/bin/sleep",
                                                      arguments: ["30"],
                                                      timeout: 0.5)
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "must not wait for the process")
    }

    func testRunnerReturnsStdoutOfASuccessfulProcess() {
        let result = TmuxOwnership.runCapturingStdout(executable: "/bin/echo",
                                                      arguments: ["hello"],
                                                      timeout: 5)
        XCTAssertEqual(result, "hello\n")
    }

    func testRunnerReturnsNilOnNonzeroExit() {
        XCTAssertNil(TmuxOwnership.runCapturingStdout(executable: "/bin/sh",
                                                      arguments: ["-c", "echo out; exit 3"],
                                                      timeout: 5))
    }

    func testRunnerReturnsNilWhenExecutableIsMissing() {
        XCTAssertNil(TmuxOwnership.runCapturingStdout(executable: "/nonexistent/tmux",
                                                      arguments: [],
                                                      timeout: 5))
    }
}
