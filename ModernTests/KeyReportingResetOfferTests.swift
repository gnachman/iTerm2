//
//  KeyReportingResetOfferTests.swift
//  ModernTests
//
//  End-to-end regression coverage for Issue 13032: with fish 4.x (native
//  OSC 133) plus oh-my-posh (its own OSC 133), the shell stack emits a
//  duplicate/stray FTCS D as part of drawing the next prompt, AFTER fish has
//  already re-enabled the kitty keyboard protocol (CSI =5u) for that prompt.
//  That stray D was sampled with key reporting ON and misread as an app
//  leaving key reporting stuck on, so iTerm2 falsely offered to reset the key
//  reporting mode after every command.
//
//  These tests drive the REAL byte stream (OSC 133 A/B/C/D plus CSI =5u)
//  through the real VT100Parser -> VT100Terminal -> VT100ScreenMutableState ->
//  side effects -> PTYSession pipeline. Nothing about the key reporting flags
//  or FTCS timing is hand-fed: the flags come from executing the actual
//  CSI =5u token, and the FTCS-C/FTCS-D flag snapshots come from the real
//  mutable-state code (the 13015 fix). The only test double is the session's
//  naggingController, which stands in for the terminal UI and records whether
//  the reset offer was consulted.
//
//  Root cause: -[PTYSession maybeOfferToResetKeyReportingModeWithFlags:] only
//  consumed its _haveCommandStart flag on the path that actually shows the
//  offer, so the real (first, flags-off) FTCS D returned early and left the
//  flag set for the stray (second, flags-on) D to trip over. The fix consumes
//  it on the first FTCS D after a command start.
//

import XCTest
@testable import iTerm2SharedARC

// Records whether the reset offer was consulted, without showing UI.
private final class RecordingNaggingController: iTermNaggingController {
    var shouldResetCallCount = 0
    override func shouldResetKeyReportingMode() -> Bool {
        shouldResetCallCount += 1
        // Return false so PTYSession does not go on to actually reset key reporting.
        return false
    }
}

// A PTYSession whose naggingController is the recording double.
private final class RecordingSession: PTYSession {
    let recordingNagging = RecordingNaggingController()
    override var naggingController: iTermNaggingController {
        return recordingNagging
    }
}

final class KeyReportingResetOfferTests: XCTestCase {
    private var session: RecordingSession!

    override func setUp() {
        super.setUp()
        session = RecordingSession(synthetic: false)
        let screen = session.screen
        screen.delegate = session
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal?.termType = "xterm"
            screen.destructivelySetScreenWidth(80, height: 24, mutableState: mutableState)
        })
    }

    override func tearDown() {
        session = nil
        super.tearDown()
    }

    private var resetOfferCount: Int {
        return session.recordingNagging.shouldResetCallCount
    }

    /// Feed a raw escape/control sequence through the real parser and execute
    /// the resulting tokens on the terminal, then drain side effects so the
    /// PTYSession delegate callbacks (and thus maybeOfferToResetKeyReportingMode)
    /// have run by the time this returns.
    private func feed(_ string: String) {
        let bytes = Array(string.utf8)
        let screen = session.screen
        screen.performBlock(joinedThreads: { terminal, _, _ in
            guard let terminal else { return }
            let parser = VT100Parser()
            parser.encoding = String.Encoding.utf8.rawValue
            bytes.withUnsafeBufferPointer { buf in
                parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
            }
            var vector = CVector()
            CVectorCreate(&vector, 100)
            _ = parser.addParsedTokens(to: &vector)
            for i in 0..<CVectorCount(&vector) {
                let token = CVectorGetObject(&vector, i) as! VT100Token
                terminal.execute(token)
            }
            CVectorDestroy(&vector)
        })
        // Drain any queued side effects (e.g. screenCommandDidExitWithCode).
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    private static let ESC = "\u{1b}"
    private static let BEL = "\u{07}"
    private func osc133(_ body: String) -> String { "\(Self.ESC)]133;\(body)\(Self.BEL)" }
    private static let enableKittyKeyboard = "\(ESC)[=5u"  // CSI =5u -> key reporting flags = 5

    /// Feed a prompt (FTCS A) followed by a command start (FTCS B) and output
    /// start (FTCS C), moving the cursor with a couple of prompt characters in
    /// between so FTCS B does not short-circuit as a duplicate. FTCS C is what
    /// causes screenDidExecuteCommand to fire, which sets _haveCommandStart and
    /// snapshots the key reporting flags at command start.
    private func feedPromptAndStartCommand() {
        feed(osc133("A"))   // FTCS A: prompt start
        feed("$ ")          // prompt characters advance the cursor
        feed(osc133("B"))   // FTCS B: command start (records commandStartCoord)
        feed("\r\n")        // the command executes; output begins on the next line
        feed(osc133("C"))   // FTCS C: output start -> screenDidExecuteCommand, flags snapshot
    }

    // The 13032 reproduction, driven by the real byte stream.
    func testStrayDuplicateFinalTermDDoesNotFalselyOfferReset() {
        // One full command cycle. Key reporting is OFF the whole time, matching a
        // shell that popped the kitty keyboard protocol before running the command.
        feedPromptAndStartCommand()  // A, B, C with key reporting OFF -> startFlags = 0
        feed(osc133("D;0"))          // FTCS D: real command exit, key reporting still OFF

        XCTAssertEqual(resetOfferCount, 0,
                       "A command that exits with key reporting off must not offer to reset it.")

        // The shell re-enables the kitty keyboard protocol for the next prompt...
        feed(Self.enableKittyKeyboard)

        // ...then oh-my-posh emits a stray/duplicate FTCS D as part of the prompt
        // sequence, with no intervening FTCS C. It is sampled with key reporting ON.
        feed(osc133("A"))            // FTCS A: new prompt
        feed(osc133("D;0"))          // stray FTCS D, key reporting now = 5

        XCTAssertEqual(resetOfferCount, 0,
                       "A stray FTCS D emitted during the next prompt (after the shell "
                       + "re-enabled key reporting) must not trigger the reset offer (13032).")
    }

    // Positive control: a single command that genuinely leaves key reporting on
    // (off at start, on at the single exit) must still offer to reset. Guards
    // against the fix over-suppressing legitimate warnings.
    func testGenuineStuckKeyReportingStillOffersReset() {
        feedPromptAndStartCommand()       // A, B, C with key reporting OFF -> startFlags = 0
        feed(Self.enableKittyKeyboard)    // the running command turns key reporting ON and never restores it
        feed(osc133("D;0"))               // single exit, key reporting ON at D

        XCTAssertEqual(resetOfferCount, 1,
                       "A single command that leaves key reporting on should offer to reset it.")
    }
}
