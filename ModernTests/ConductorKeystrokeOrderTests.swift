//
//  ConductorKeystrokeOrderTests.swift
//  iTerm2 ModernTests
//
//  Guards the order of input sent through an SSH integration (conductor) session: a
//  keystroke typed while a paste is still being sent must reach the remote after the
//  whole paste, never inside it. QA finding F-061 saw a stray `~` command after pasting
//  into it2ssh and suspected reordering; the cause turned out to be zsh ending a
//  bracketed paste when the final byte arrives more than KEYTIMEOUT (0.4 s) after the
//  rest, not reordering in iTerm2. These tests pin the ordering iTerm2 is responsible
//  for, without any timing dependence: timers are fired by hand and the remote's
//  %end replies are delivered explicitly.
//

import XCTest
@testable import iTerm2SharedARC

/// Records what the conductor writes to the ssh process, and decodes it the way
/// framer.py's mainloop does, so a test can recover the bytes the remote writes to the
/// shell's pty, in wire order.
private final class RecordingConductorDelegate: NSObject, ConductorDelegate {
    private(set) var written = ""

    func conductorWrite(string: String) {
        written += string
    }
    func conductorAbort(reason: String) {}
    func conductorQuit() {}
    func conductorStateDidChange() {}
    func conductorStopQueueingInput() {}
    func conductorSendInitialText() {}
    func conductorRequestIT2Authorization(guid: String,
                                          displayName: String,
                                          callerTmuxPane: String?,
                                          completion: @escaping (Bool, Bool, Bool) -> Void) {
        completion(false, false, false)
    }
    func conductorDismissIT2AuthorizationPrompt(guid: String) {}
    let guid = "recording-delegate"

    /// Parses `written` as framer.py does: a line ending in a backslash continues on the
    /// next line, an empty line ends a command, and each argument is base64. Returns the
    /// decoded arguments of every complete command, in wire order.
    func commands() -> [[String]] {
        var result = [[String]]()
        var args = [String]()
        for line in written.components(separatedBy: "\n") {
            if !line.isEmpty {
                if let last = args.last, last.hasSuffix("\\") {
                    args[args.count - 1] = String(last.dropLast()) + line
                } else {
                    args.append(line)
                }
            } else if !args.isEmpty {
                result.append(args.map { arg in
                    guard let data = Data(base64Encoded: arg),
                          let string = String(data: data, encoding: .utf8) else {
                        return "<undecodable \(arg)>"
                    }
                    return string
                })
                args = []
            }
        }
        return result
    }

    /// The payloads of the `send` commands concatenated in wire order. framer.py runs one
    /// command at a time and writes each payload to the pty before reading the next, so
    /// this is exactly the byte stream the remote shell reads.
    func bytesSentToPTY() -> Data {
        var data = Data()
        for args in commands() where args.first == "send" {
            guard args.count == 3, let payload = Data(base64Encoded: args[2]) else {
                XCTFail("Malformed send command \(args)")
                continue
            }
            data.append(payload)
        }
        return data
    }
}

/// Captures the paste helper's timers instead of scheduling them so the test can fire them
/// by hand.
private final class ManualTimerPasteHelper: iTermPasteHelper {
    var timer: Timer?

    override func scheduledTimer(withTimeInterval ti: TimeInterval,
                                 target aTarget: Any!,
                                 selector aSelector: Selector!,
                                 userInfo: Any!,
                                 repeats yesOrNo: Bool) -> Timer! {
        let timer = Timer(timeInterval: ti,
                          target: aTarget as Any,
                          selector: aSelector,
                          userInfo: userInfo,
                          repeats: yesOrNo)
        self.timer = timer
        return timer
    }

    func fireTimer() {
        let pending = timer
        timer = nil
        pending?.fire()
    }
}

@MainActor
final class ConductorKeystrokeOrderTests: XCTestCase {
    private var conductor: Conductor!
    private var delegate: RecordingConductorDelegate!
    private var pasteHelper: ManualTimerPasteHelper!
    private var bridge: PasteToConductorBridge!
    private var pasteWrites: [String] { bridge?.pasteWrites ?? [] }

    // The pasted text from the QA repro: a 2012-byte line ending in a newline. Bracketed,
    // it is three chunks at the default 768 bytes per chunk.
    private let pastedText = "echo " + String(repeating: "x", count: 2000) + " END2K\n"

    override func setUp() {
        super.setUp()
        resetConductor()
    }

    /// Replaces the conductor with a fresh one in the framing state.
    private func resetConductor() {
        removeConductorFromRegistry()
        delegate = RecordingConductorDelegate()
        conductor = Conductor("f061.example.com", boolArgs: "", dcsID: "dcs", clientUniqueID: "cid",
                              varsToSend: [:], clientVars: [:], initialDirectory: nil,
                              shouldInjectShellIntegration: false, parent: nil)
        conductor.delegate = delegate
        // Framing with a login shell running, as after a successful it2ssh handshake. In
        // this state PTYSession routes all input through sendKeys(_:).
        conductor.framedPID = 4242
        XCTAssertTrue(conductor.handlesKeystrokes)
    }

    private func removeConductorFromRegistry() {
        if let conductor {
            ConductorRegistry.instance.remove(conductorGUID: conductor.guid,
                                              sshIdentity: conductor.sshIdentity)
        }
    }

    override func tearDown() {
        removeConductorFromRegistry()
        Self.resetWarningHandler()
        PasteboardHistory.sharedInstance().clear()
        pasteHelper?.delegate = nil
        pasteHelper = nil
        bridge = nil
        conductor = nil
        delegate = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private static func resetWarningHandler() {
        _ = (iTermWarning.self as AnyObject).perform(#selector(iTermWarning.setWarningHandler(_:)), with: nil)
    }

    /// Number of commands written to the remote whose %end has not come back yet.
    private var inFlight: Int {
        switch conductor.state {
        case .willExecutePipeline(let contexts):
            return contexts.count
        case .executingPipeline(_, let pending):
            return 1 + pending.count
        case .ground, .unhooked, .recovery, .recovered:
            return 0
        }
    }

    /// Delivers the remote's %end for the oldest in-flight command.
    private func deliverEnd(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(inFlight, 0, "No command is in flight", file: file, line: line)
        conductor.handleCommandEnd(identifier: "id", type: "f", status: 0, depth: conductor.depth)
    }

    /// Delivers %end replies until nothing is in flight or queued.
    private func drain(file: StaticString = #filePath, line: UInt = #line) {
        var remaining = 100
        while inFlight > 0 && remaining > 0 {
            deliverEnd(file: file, line: line)
            remaining -= 1
        }
        XCTAssertEqual(inFlight, 0, file: file, line: line)
        XCTAssertTrue(conductor.queue.isEmpty, "Commands left in the queue", file: file, line: line)
    }

    private func bracketed(_ string: String) -> String {
        return "\u{1b}[200~" + string + "\u{1b}[201~"
    }

    private func chunks(_ string: String, size: Int) -> [String] {
        var result = [String]()
        var rest = Substring(string)
        while !rest.isEmpty {
            result.append(String(rest.prefix(size)))
            rest = rest.dropFirst(size)
        }
        return result
    }

    private func makeReturnKeyDown() -> NSEvent? {
        return NSEvent.keyEvent(with: .keyDown,
                                location: .zero,
                                modifierFlags: [],
                                timestamp: 0,
                                windowNumber: 0,
                                context: nil,
                                characters: "\r",
                                charactersIgnoringModifiers: "\r",
                                isARepeat: false,
                                keyCode: 36)
    }

    // MARK: - Conductor

    // The paste's chunks are written to the conductor one at a time, as the paste helper
    // does, and Return follows the last chunk. For every point at which the remote's
    // replies could arrive relative to those writes, the remote must receive the whole
    // paste, then Return. A chunk this size is too big to pipeline, so it waits for the
    // previous chunk's %end; the last chunk is small enough that Return can be pipelined
    // behind it while it is in flight. Every path must keep the order.
    func testReturnAfterPasteReachesRemoteAfterWholePasteForEveryReplyTiming() {
        let paste = bracketed(pastedText.replacingOccurrences(of: "\n", with: "\r"))
        let pieces = chunks(paste, size: 768)
        XCTAssertEqual(pieces.count, 3)
        let writes = pieces + ["\r"]

        // repliesBefore[i] is how many %end replies arrive just before writes[i] is sent.
        // Enumerate every schedule where at most the in-flight replies are delivered.
        // With `outputLine`, the oldest in-flight command produces a line of output before
        // each write, which moves the conductor from willExecutePipeline to
        // executingPipeline, so the write takes that branch of Conductor.send instead.
        func run(_ repliesBefore: [Int], outputLine: Bool) {
            resetConductor()
            for (i, write) in writes.enumerated() {
                for _ in 0..<repliesBefore[i] where inFlight > 0 {
                    deliverEnd()
                }
                if outputLine && inFlight > 0 {
                    conductor.handle(line: "output", depth: conductor.depth)
                    guard case .executingPipeline = conductor.state else {
                        XCTFail("Expected executingPipeline, got \(conductor.state)")
                        return
                    }
                }
                conductor.sendKeys(write.data(using: .utf8)!)
            }
            drain()
            let received = String(data: delegate.bytesSentToPTY(), encoding: .utf8)
            XCTAssertEqual(received, paste + "\r",
                           "Replies before each write: \(repliesBefore), output line: \(outputLine)")
        }

        var schedules = 0
        for a in 0...3 {
            for b in 0...3 {
                for c in 0...3 {
                    for outputLine in [false, true] {
                        run([0, a, b, c], outputLine: outputLine)
                        schedules += 1
                    }
                }
            }
        }
        XCTAssertEqual(schedules, 128)
    }

    // Return typed while earlier keystrokes are still waiting behind an in-flight
    // command goes out after them.
    func testKeystrokesQueuedBehindInFlightCommandKeepTheirOrder() {
        let big = String(repeating: "a", count: 768)
        conductor.sendKeys(big.data(using: .utf8)!)
        for key in ["b", "c", "\r"] {
            conductor.sendKeys(key.data(using: .utf8)!)
        }
        XCTAssertEqual(inFlight, 1, "Nothing can join a pipeline behind a command that big")
        drain()
        XCTAssertEqual(String(data: delegate.bytesSentToPTY(), encoding: .utf8), big + "bc\r")
    }

    // MARK: - Paste helper through the conductor

    // End to end from the paste helper: Return pressed while the paste is still being
    // sent is held by the paste helper (PTYTextView queues key-downs while isPasting) and
    // replayed once the last chunk is written, so the remote shell reads it after the
    // closing bracket. This mirrors PTYSession, whose pasteHelperWriteString: and
    // keystroke paths both end in Conductor.sendKeys while the conductor is framing.
    func testReturnTypedDuringPasteReachesRemoteAfterPasteTerminator() throws {
        bridge = PasteToConductorBridge(conductor: conductor)
        iTermWarning.setWarningHandler(bridge)
        PasteboardHistory.sharedInstance().clear()
        pinAdvancedSetting("PromptForPasteWhenNotAtPrompt", to: false)
        pinAdvancedSetting("AlwaysWarnBeforePastingOverSize", to: -1)
        pinAdvancedSetting("StripZeroWidthFormatCharactersOnPaste", to: false)
        pinAdvancedSetting("QuickPasteBytesPerCall", to: nil)
        pinAdvancedSetting("QuickPasteDelayBetweenCalls", to: nil)
        pasteHelper = ManualTimerPasteHelper()
        pasteHelper.delegate = bridge

        pasteHelper.paste(pastedText,
                          slowly: false,
                          escapeShellChars: false,
                          isUpload: false,
                          allowBracketing: true,
                          tabTransform: .tabTransformNone,
                          spacesPerTab: 0)
        XCTAssertTrue(pasteHelper.isPasting, "A three-chunk paste is still being sent")
        XCTAssertEqual(pasteWrites.count, 1)

        // The user presses Return while the paste is in progress.
        let keyDown = try XCTUnwrap(makeReturnKeyDown())
        pasteHelper.enqueue(keyDown)

        // The remote acknowledges the first chunk, then the paste helper sends the rest.
        deliverEnd()
        while pasteHelper.timer != nil {
            pasteHelper.fireTimer()
        }
        XCTAssertFalse(pasteHelper.isPasting)
        drain()

        let paste = pasteWrites.joined()
        XCTAssertEqual(pasteWrites.count, 3)
        XCTAssertTrue(paste.hasPrefix("\u{1b}[200~"))
        XCTAssertTrue(paste.hasSuffix("\u{1b}[201~"), "Paste was not bracketed")
        XCTAssertEqual(String(data: delegate.bytesSentToPTY(), encoding: .utf8), paste + "\r")
    }
}

/// Stands in for PTYSession between the paste helper and the conductor: while the
/// conductor is framing, PTYSession's pasteHelperWriteString: and its keystroke path
/// (which the paste helper's queued key-downs replay through) both end in
/// Conductor.sendKeys.
private final class PasteToConductorBridge: NSObject, iTermPasteHelperDelegate, iTermWarningHandler {
    private let conductor: Conductor
    private(set) var pasteWrites = [String]()

    init(conductor: Conductor) {
        self.conductor = conductor
    }

    private func send(_ string: String) {
        MainActor.assumeIsolated {
            conductor.sendKeys(string.data(using: .utf8)!)
        }
    }

    // MARK: - iTermPasteHelperDelegate

    func pasteHelperWrite(_ string: String) {
        pasteWrites.append(string)
        send(string)
    }

    func pasteHelperKeyDown(_ event: NSEvent) {
        send(event.characters ?? "")
    }

    func pasteHelperShouldBracket() -> Bool {
        return true
    }

    func pasteHelperEncoding() -> UInt {
        return String.Encoding.utf8.rawValue
    }

    func pasteHelperViewForIndicator() -> NSView! {
        return nil
    }

    func pasteHelperStatusBarViewController() -> iTermStatusBarViewController! {
        return nil
    }

    func pasteHelperIsAtShellPrompt() -> Bool {
        return true
    }

    func pasteHelperShouldWaitForPrompt() -> Bool {
        return false
    }

    func pasteHelperCanWaitForPrompt() -> Bool {
        return false
    }

    func pasteHelperPasteViewVisibilityDidChange() {
    }

    func pasteHelperScope() -> iTermVariableScope! {
        return nil
    }

    // MARK: - iTermWarningHandler

    // Accept the multi-line paste warning, if one is shown.
    func warningWouldShow(_ alert: NSAlert, identifier: String?) -> NSApplication.ModalResponse {
        return .alertFirstButtonReturn
    }
}
