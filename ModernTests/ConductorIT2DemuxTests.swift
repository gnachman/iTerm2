//
//  ConductorIT2DemuxTests.swift
//  iTerm2
//
//  Exercises ConductorIT2Demux, which reconstructs it2.py's length-prefixed wire
//  protocol from "%it2 <connid> open|data <base64>|close" conductor frames, runs
//  the embedded command, and streams O/E/X frames back. The runner is faked so
//  these are pure, synchronous protocol tests.
//

import XCTest
@testable import iTerm2SharedARC

private let kNonce = "s3cr3t-nonce"

final class ConductorIT2DemuxTests: XCTestCase {

    // MARK: - Fakes

    private final class FakeCancellable: IT2Cancellable {
        var cancelCount = 0
        func cancel() { cancelCount += 1 }
    }

    private struct RunInvocation {
        let argv: [String]
        let context: IT2ClientContext
        let stdout: (String) -> Void
        let stderr: (String) -> Void
        let completion: (Int32) -> Void
        let cancellable: FakeCancellable
    }

    private final class Harness {
        var demux: ConductorIT2Demux!
        var sent = [String: Data]()      // connid -> concatenated down bytes
        var closed = [String]()
        var runs = [RunInvocation]()
        var currentNonce: String?        // mutable so a test can set it after construction

        init(nonce: String? = kNonce) {
            currentNonce = nonce
            demux = ConductorIT2Demux(
                nonce: { [weak self] in self?.currentNonce },
                send: { [weak self] connid, data in
                    self?.sent[connid, default: Data()].append(data)
                },
                close: { [weak self] connid in
                    self?.closed.append(connid)
                },
                run: { [weak self] argv, context, stdout, stderr, completion in
                    let cancellable = FakeCancellable()
                    self?.runs.append(RunInvocation(argv: argv, context: context,
                                                    stdout: stdout, stderr: stderr,
                                                    completion: completion,
                                                    cancellable: cancellable))
                    return cancellable
                })
        }

        // Down frames the demux emitted for a connection, parsed back into (type, payload).
        func downFrames(_ connid: String) -> [(UInt8, Data)] {
            return parseFrames(sent[connid] ?? Data())
        }
    }

    // MARK: - Frame helpers

    private static func upFrame(_ type: UInt8, _ payload: Data) -> Data {
        var d = Data([type])
        let n = UInt32(payload.count)
        d.append(contentsOf: [UInt8((n >> 24) & 0xff), UInt8((n >> 16) & 0xff),
                              UInt8((n >> 8) & 0xff), UInt8(n & 0xff)])
        d.append(payload)
        return d
    }

    private static func helloBytes(nonce: String, argv: [String],
                                   cwd: String = "/home/u", isatty: Bool = true) -> Data {
        let json: [String: Any] = ["nonce": nonce, "argv": argv, "cwd": cwd,
                                   "term": "xterm", "isatty": isatty, "cols": 80, "rows": 24]
        let payload = try! JSONSerialization.data(withJSONObject: json)
        return upFrame(UInt8(ascii: "H"), payload)
    }

    private static func parseFrames(_ data: Data) -> [(UInt8, Data)] {
        var out = [(UInt8, Data)]()
        var i = data.startIndex
        while data.distance(from: i, to: data.endIndex) >= 5 {
            let header = [UInt8](data[i..<data.index(i, offsetBy: 5)])
            let len = (Int(header[1]) << 24) | (Int(header[2]) << 16) | (Int(header[3]) << 8) | Int(header[4])
            let start = data.index(i, offsetBy: 5)
            guard data.distance(from: start, to: data.endIndex) >= len else { break }
            let end = data.index(start, offsetBy: len)
            out.append((header[0], Data(data[start..<end])))
            i = end
        }
        return out
    }

    private func dataEvent(_ connid: String, _ bytes: Data) -> String {
        return "\(connid) data \(bytes.base64EncodedString())"
    }

    // MARK: - Tests

    func testHappyPathStreamsAndExits() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["session", "list"])))

        XCTAssertEqual(h.runs.count, 1)
        XCTAssertEqual(h.runs.first?.argv, ["session", "list"])
        XCTAssertEqual(h.runs.first?.context.cols, 80)
        XCTAssertEqual(h.runs.first?.context.isatty, true)

        // Stdout/stderr lines arrive newline-stripped; the demux re-adds "\n".
        h.runs[0].stdout("hello")
        h.runs[0].stderr("oops")
        h.runs[0].completion(0)

        let frames = h.downFrames("c1")
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].0, UInt8(ascii: "O"))
        XCTAssertEqual(frames[0].1, Data("hello\n".utf8))
        XCTAssertEqual(frames[1].0, UInt8(ascii: "E"))
        XCTAssertEqual(frames[1].1, Data("oops\n".utf8))
        XCTAssertEqual(frames[2].0, UInt8(ascii: "X"))
        let exit = try? JSONSerialization.jsonObject(with: frames[2].1) as? [String: Any]
        XCTAssertEqual(exit?["code"] as? Int, 0)
        XCTAssertEqual(h.closed, ["c1"])
    }

    func testHelloSplitAcrossDataFramesReassembles() {
        let h = Harness()
        h.demux.handle("c2 open")
        let hello = Self.helloBytes(nonce: kNonce, argv: ["window", "list"])
        let cut = hello.count / 2
        h.demux.handle(dataEvent("c2", hello.prefix(cut)))
        XCTAssertEqual(h.runs.count, 0, "must wait for the whole frame")
        h.demux.handle(dataEvent("c2", hello.suffix(from: cut)))
        XCTAssertEqual(h.runs.count, 1)
        XCTAssertEqual(h.runs.first?.argv, ["window", "list"])
    }

    func testNonceMismatchIsRejectedWithoutRunning() {
        let h = Harness()
        h.demux.handle("c3 open")
        h.demux.handle(dataEvent("c3", Self.helloBytes(nonce: "wrong", argv: ["session", "list"])))

        XCTAssertEqual(h.runs.count, 0, "must not run an unauthorized command")
        let frames = h.downFrames("c3")
        XCTAssertEqual(frames.first?.0, UInt8(ascii: "E"))
        XCTAssertEqual(frames.last?.0, UInt8(ascii: "X"))
        let exit = try? JSONSerialization.jsonObject(with: frames.last!.1) as? [String: Any]
        XCTAssertEqual(exit?["code"] as? Int, 1)
        XCTAssertEqual(h.closed, ["c3"])
    }

    func testCancelFrameCancelsRunningCommand() {
        let h = Harness()
        h.demux.handle("c4 open")
        h.demux.handle(dataEvent("c4", Self.helloBytes(nonce: kNonce, argv: ["monitor", "output"])))
        XCTAssertEqual(h.runs.count, 1)

        h.demux.handle(dataEvent("c4", Self.upFrame(UInt8(ascii: "C"), Data())))
        XCTAssertEqual(h.runs[0].cancellable.cancelCount, 1)
    }

    func testCloseEventCancelsRunningCommand() {
        let h = Harness()
        h.demux.handle("c5 open")
        h.demux.handle(dataEvent("c5", Self.helloBytes(nonce: kNonce, argv: ["monitor", "output"])))
        h.demux.handle("c5 close")
        XCTAssertEqual(h.runs[0].cancellable.cancelCount, 1)
        // A late completion after close must not emit an EXIT or re-close.
        h.runs[0].completion(0)
        XCTAssertTrue(h.downFrames("c5").isEmpty)
        XCTAssertEqual(h.closed, [], "close came from the client; do not echo a close back")
    }

    func testDataForUnknownConnidIsIgnored() {
        let h = Harness()
        // No "open" first.
        h.demux.handle(dataEvent("ghost", Self.helloBytes(nonce: kNonce, argv: ["session", "list"])))
        XCTAssertEqual(h.runs.count, 0)
        XCTAssertTrue(h.sent.isEmpty)
    }

    func testEmptyNonceRejectsEverything() {
        // Before startup injects IT2_NONCE the demux nonce is empty and must never
        // authorize a command.
        let h = Harness(nonce: "")
        h.demux.handle("c6 open")
        h.demux.handle(dataEvent("c6", Self.helloBytes(nonce: "", argv: ["session", "list"])))
        XCTAssertEqual(h.runs.count, 0)
    }

    func testNonceAssignedAfterDemuxCreationIsHonored() {
        // The demux is built on the first %it2 frame, which can precede startup
        // assigning the session nonce. A frame that arrives while the nonce is
        // still unavailable must be rejected, but the SAME demux must authorize
        // once the nonce is set (regression: nonce was snapshotted at creation and
        // pinned to "" for the session).
        let h = Harness(nonce: nil)
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["session", "list"])))
        XCTAssertEqual(h.runs.count, 0, "no nonce yet -> reject")

        h.currentNonce = kNonce  // startup injects the nonce
        h.demux.handle("c2 open")
        h.demux.handle(dataEvent("c2", Self.helloBytes(nonce: kNonce, argv: ["session", "list"])))
        XCTAssertEqual(h.runs.count, 1, "nonce now available -> command runs")
        XCTAssertEqual(h.runs.first?.argv, ["session", "list"])
    }

    func testCancelAllCancelsInFlightCommands() {
        // Conductor unhook/deinit must stop a streaming command so its it2core
        // thread and in-process API connection do not leak.
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["monitor", "output"])))
        XCTAssertEqual(h.runs.count, 1)

        h.demux.cancelAll()
        XCTAssertEqual(h.runs[0].cancellable.cancelCount, 1)
        // A late completion after teardown is a no-op (the connection is gone).
        h.runs[0].completion(0)
        XCTAssertTrue(h.downFrames("c1").isEmpty)
    }

    func testOversizeFrameDropsConnection() {
        // A malformed/adversarial header declaring a huge length must not make the
        // demux buffer unboundedly; the connection is dropped and closed.
        let h = Harness()
        h.demux.handle("c1 open")
        var frame = Data([UInt8(ascii: "H")])
        frame.append(contentsOf: [0x7f, 0xff, 0xff, 0xff])  // ~2 GiB declared length
        h.demux.handle(dataEvent("c1", frame))
        XCTAssertEqual(h.runs.count, 0)
        XCTAssertEqual(h.closed, ["c1"], "oversize frame closes the connection")
        // Further data for the dropped connection is ignored, not resurrected.
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["x"])))
        XCTAssertEqual(h.runs.count, 0)
    }

    func testTwoConnectionsRunIndependently() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle("c2 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["a"])))
        h.demux.handle(dataEvent("c2", Self.helloBytes(nonce: kNonce, argv: ["b"])))
        XCTAssertEqual(h.runs.count, 2)
        XCTAssertEqual(h.runs[0].argv, ["a"])
        XCTAssertEqual(h.runs[1].argv, ["b"])

        // Output routes to the connection that produced it.
        h.runs[0].stdout("from-c1")
        h.runs[1].stdout("from-c2")
        XCTAssertEqual(h.downFrames("c1").first?.1, Data("from-c1\n".utf8))
        XCTAssertEqual(h.downFrames("c2").first?.1, Data("from-c2\n".utf8))

        // Closing one connection cancels only its command; the other is unaffected.
        h.demux.handle("c1 close")
        XCTAssertEqual(h.runs[0].cancellable.cancelCount, 1)
        XCTAssertEqual(h.runs[1].cancellable.cancelCount, 0)
        h.runs[1].completion(0)
        XCTAssertEqual(h.downFrames("c2").last?.0, UInt8(ascii: "X"))
    }

    func testCancelBeforeHelloIsTolerated() {
        // A CANCEL with no command running must be a no-op, not a crash.
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.upFrame(UInt8(ascii: "C"), Data())))
        XCTAssertEqual(h.runs.count, 0)
        XCTAssertTrue(h.sent.isEmpty)
    }

    func testMalformedHelloRejectedWithExit2() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.upFrame(UInt8(ascii: "H"), Data("not json".utf8))))
        XCTAssertEqual(h.runs.count, 0)
        let frames = h.downFrames("c1")
        XCTAssertEqual(frames.first?.0, UInt8(ascii: "E"))
        XCTAssertEqual(frames.last?.0, UInt8(ascii: "X"))
        let exit = try? JSONSerialization.jsonObject(with: frames.last!.1) as? [String: Any]
        XCTAssertEqual(exit?["code"] as? Int, 2)
    }

    func testMultipleWireFramesInOneDataEvent() {
        // A HELLO immediately followed by a CANCEL in a single data chunk: both must
        // be parsed out of the buffer, not just the first.
        let h = Harness()
        h.demux.handle("c1 open")
        var payload = Self.helloBytes(nonce: kNonce, argv: ["monitor", "output"])
        payload.append(Self.upFrame(UInt8(ascii: "C"), Data()))
        h.demux.handle(dataEvent("c1", payload))
        XCTAssertEqual(h.runs.count, 1, "HELLO parsed")
        XCTAssertEqual(h.runs[0].cancellable.cancelCount, 1, "CANCEL in the same chunk also applied")
    }

    // MARK: - IT2RunCancel (the async cancel-block bridge)

    func testRunCancelFiresWhenCancelledAfterReady() {
        var fired = 0
        let rc = IT2RunCancel()
        rc.setCancelBlock { fired += 1 }
        rc.cancel()
        XCTAssertEqual(fired, 1)
    }

    func testRunCancelFiresWhenCancelledBeforeReady() {
        // A fast remote Ctrl-C can cancel before the runner hands back its block;
        // the request must be remembered and fired when the block arrives.
        var fired = 0
        let rc = IT2RunCancel()
        rc.cancel()
        rc.setCancelBlock { fired += 1 }
        XCTAssertEqual(fired, 1)
    }

    func testRunCancelIsIdempotent() {
        var fired = 0
        let rc = IT2RunCancel()
        rc.setCancelBlock { fired += 1 }
        rc.cancel()
        rc.cancel()
        XCTAssertEqual(fired, 1, "second cancel is a no-op")
    }
}
