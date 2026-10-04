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
                                   cwd: String = "/home/u", isatty: Bool = true,
                                   stdin: Data? = nil,
                                   env: [String: String]? = nil,
                                   protocolVersion: Any? = nil) -> Data {
        var json: [String: Any] = ["nonce": nonce, "argv": argv, "cwd": cwd,
                                   "term": "xterm", "isatty": isatty, "cols": 80, "rows": 24]
        if let protocolVersion {
            json["protocol"] = protocolVersion
        }
        if let stdin {
            json["stdin"] = stdin.base64EncodedString()
        }
        if let env {
            json["env"] = env
        }
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

    // Let the demux's coalescing joiner (a DispatchQueue.main.async) flush pending output. The
    // flush block was enqueued on the first setNeedsUpdate, before this one, so FIFO ordering on
    // the main queue guarantees it runs before we return.
    private func pumpMainQueue() {
        let exp = expectation(description: "pump main queue")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 2)
    }

    // MARK: - Tests

    // MARK: - Protocol version

    private func exitCode(_ frames: [(UInt8, Data)]) -> Int? {
        guard let last = frames.last, last.0 == UInt8(ascii: "X") else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: last.1) as? [String: Any])?["code"] as? Int
    }

    func testCurrentProtocolRuns() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["session", "list"],
                                                      protocolVersion: ConductorIT2Demux.protocolVersion)))
        XCTAssertEqual(h.runs.count, 1)
    }

    // Every it2.py shipped before the field existed omits it, and must keep working.
    func testMissingProtocolIsAnOlderClientAndRuns() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["session", "list"])))
        XCTAssertEqual(h.runs.count, 1)
    }

    // A newer client may depend on fields this build would silently ignore, so refuse it and
    // say why rather than run it half-understood.
    func testNewerProtocolIsRefusedWithAnExplanation() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["session", "list"],
                                                      protocolVersion: ConductorIT2Demux.protocolVersion + 1)))
        pumpMainQueue()
        XCTAssertEqual(h.runs.count, 0)
        let frames = h.downFrames("c1")
        XCTAssertEqual(frames.first?.0, UInt8(ascii: "E"))
        let message = String(decoding: frames.first?.1 ?? Data(), as: UTF8.self)
        XCTAssertTrue(message.contains("iTerm2"), "got \(message)")
        XCTAssertEqual(exitCode(frames), 2)
    }

    // Hooks never complain (see IT2RunPolicy): same refusal, but silent and successful.
    func testNewerProtocolHookExitsSilently() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["handle-agent-hook"],
                                                      protocolVersion: ConductorIT2Demux.protocolVersion + 1)))
        pumpMainQueue()
        XCTAssertEqual(h.runs.count, 0)
        let frames = h.downFrames("c1")
        XCTAssertFalse(frames.contains { $0.0 == UInt8(ascii: "E") })
        XCTAssertEqual(exitCode(frames), 0)
    }

    // Not a number is not something this build understands either.
    func testNonIntegerProtocolIsRefused() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["session", "list"],
                                                      protocolVersion: "2")))
        pumpMainQueue()
        XCTAssertEqual(h.runs.count, 0)
        XCTAssertEqual(exitCode(h.downFrames("c1")), 2)
    }

    // The version is checked only after the nonce, so an unauthenticated caller learns nothing.
    func testNonceIsCheckedBeforeProtocol() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: "wrong", argv: ["session", "list"],
                                                      protocolVersion: ConductorIT2Demux.protocolVersion + 1)))
        pumpMainQueue()
        XCTAssertEqual(exitCode(h.downFrames("c1")), 1, "authorization failure, not a version error")
    }

    // MARK: - Stdin and environment (3b)

    // A hook's payload arrives on stdin, so a remote `it2 handle-agent-hook` is useless without
    // this. It rides in the HELLO rather than a later frame because startCommand launches the
    // command as soon as HELLO lands, so a second frame would race it.
    func testStdinFromHelloReachesTheCommand() {
        let h = Harness()
        let payload = Data(#"{"hook_event_name":"PreToolUse"}"#.utf8)
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce,
                                                       argv: ["handle-agent-hook"],
                                                       stdin: payload)))
        XCTAssertEqual(h.runs.first?.context.stdin, payload)
    }

    func testNoStdinKeyMeansNoPayload() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["session", "list"])))
        XCTAssertNil(h.runs.first?.context.stdin)
    }

    // Garbage in the stdin field must not take the command down; it simply has no payload.
    func testUndecodableStdinIsIgnored() {
        let h = Harness()
        h.demux.handle("c1 open")
        let json: [String: Any] = ["nonce": kNonce, "argv": ["handle-agent-hook"], "cwd": "/",
                                   "term": "xterm", "isatty": false, "cols": 80, "rows": 24,
                                   "stdin": "!!!not base64!!!"]
        let payload = try! JSONSerialization.data(withJSONObject: json)
        h.demux.handle(dataEvent("c1", Self.upFrame(UInt8(ascii: "H"), payload)))
        XCTAssertEqual(h.runs.count, 1, "the command still runs")
        XCTAssertNil(h.runs.first?.context.stdin)
    }

    func testAllowlistedEnvironmentReachesTheCommand() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["session", "list"],
                                                       env: ["TMUX": "/tmp/s,1,0",
                                                             "TMUX_PANE": "%3"])))
        XCTAssertEqual(h.runs.first?.context.environment["TMUX"], "/tmp/s,1,0")
        XCTAssertEqual(h.runs.first?.context.environment["TMUX_PANE"], "%3")
    }

    // The allowlist is enforced AGAIN here, not trusted. it2.py applies it, but a remote host is
    // not a trust boundary we control: anything else it sends must be dropped on arrival rather
    // than reaching a command's environment.
    func testUnlistedEnvironmentIsDroppedOnArrival() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["session", "list"],
                                                       env: ["TMUX": "/tmp/s,1,0",
                                                             "AWS_SECRET_ACCESS_KEY": "leak",
                                                             "PATH": "/evil/bin"])))
        let environment = h.runs.first?.context.environment ?? [:]
        XCTAssertEqual(environment["TMUX"], "/tmp/s,1,0")
        XCTAssertNil(environment["AWS_SECRET_ACCESS_KEY"], "got \(environment)")
        XCTAssertNil(environment["PATH"], "PATH especially must never arrive this way")
    }

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

    // Consecutive same-type output lines coalesce into ONE frame (the point of #8), while a
    // type change flushes the current batch. finish() drains synchronously, so no pump needed.
    func testConsecutiveSameTypeLinesCoalesceIntoOneFrame() {
        let h = Harness()
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["session", "list"])))
        h.runs[0].stdout("one")
        h.runs[0].stdout("two")
        h.runs[0].stdout("three")
        h.runs[0].stderr("err")   // type change -> flushes the O batch, starts an E batch
        h.runs[0].completion(0)

        let frames = h.downFrames("c1")
        XCTAssertEqual(frames.count, 3, "one coalesced O frame, one E frame, one X frame")
        XCTAssertEqual(frames[0].0, UInt8(ascii: "O"))
        XCTAssertEqual(frames[0].1, Data("one\ntwo\nthree\n".utf8),
                       "three stdout lines merged into a single frame payload")
        XCTAssertEqual(frames[1].0, UInt8(ascii: "E"))
        XCTAssertEqual(frames[1].1, Data("err\n".utf8))
        XCTAssertEqual(frames[2].0, UInt8(ascii: "X"))
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

    func testUndecodableDataFrameDropsConnection() {
        let h = Harness()
        h.demux.handle("c5 open")
        h.demux.handle(dataEvent("c5", Self.helloBytes(nonce: kNonce, argv: ["session", "list"])))
        XCTAssertEqual(h.runs.count, 1)
        XCTAssertEqual(h.closed, [], "still open after a valid HELLO")

        // A chunk that is not valid base64 desyncs the length-prefixed reassembly, so the
        // connection must be torn down rather than left to misparse a following chunk.
        h.demux.handle("c5 data @@@")
        XCTAssertEqual(h.closed, ["c5"], "connection dropped on undecodable chunk")
        XCTAssertEqual(h.runs[0].cancellable.cancelCount, 1, "in-flight command cancelled")

        // A subsequent well-formed chunk for the dropped connid must not resurrect it.
        h.demux.handle(dataEvent("c5", Data([0x00])))
        XCTAssertEqual(h.runs.count, 1, "no new run after the connection was dropped")
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

    func testNonceSurvivesRecoveryBlip() {
        // After an SSH recovery the conductor briefly loses it2Nonce, then re-reads
        // it from the surviving framer env. Because the demux reads the nonce lazily
        // per HELLO, authorization resumes once the value is restored (regression: a
        // snapshotted nonce would have pinned the connection to nil forever).
        let h = Harness(nonce: kNonce)
        h.demux.handle("c1 open")
        h.demux.handle(dataEvent("c1", Self.helloBytes(nonce: kNonce, argv: ["a"])))
        XCTAssertEqual(h.runs.count, 1)

        h.currentNonce = nil  // recovery: nonce transiently unavailable
        h.demux.handle("c2 open")
        h.demux.handle(dataEvent("c2", Self.helloBytes(nonce: kNonce, argv: ["b"])))
        XCTAssertEqual(h.runs.count, 1, "no nonce during recovery -> reject")

        h.currentNonce = kNonce  // framerGetenv restored it
        h.demux.handle("c3 open")
        h.demux.handle(dataEvent("c3", Self.helloBytes(nonce: kNonce, argv: ["c"])))
        XCTAssertEqual(h.runs.count, 2, "nonce restored -> authorize again")
        XCTAssertEqual(h.runs.last?.argv, ["c"])
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

        // Output routes to the connection that produced it. It is coalesced and flushed on the
        // next main-loop turn, so pump before asserting (there is no completion here to drain).
        h.runs[0].stdout("from-c1")
        h.runs[1].stdout("from-c2")
        pumpMainQueue()
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
