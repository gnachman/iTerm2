//
//  KeyReportingResetOfferTests.swift
//  ModernTests
//
//  Coverage for the offer to reset a key reporting mode an app left behind
//  (Issue 13032).
//
//  The offer exists for the case its own text names: an ssh session dies or an
//  app crashes with the kitty keyboard protocol still enabled, and nothing puts
//  it back. It misfired for anyone whose shell drives that mode itself. Fish 4.x
//  arms the protocol while drawing its prompt, and a prompt renderer like
//  oh-my-posh emits FTCS D from inside the prompt function, so the flags sampled
//  at D are the shell's own - already armed for the prompt being drawn - rather
//  than an app's leftovers.
//
//  The distinction is not in the flag value, which is identical either way. It is
//  in the behavior of the shell at the prompt: one that writes the mode while it
//  owns the terminal and drives it to zero before running a command will replace
//  those flags at its next prompt, because it sets them with CSI = flags ; 1 u,
//  which replaces rather than merges. Nothing is left behind for the offer to
//  restore. A shell that never touches the mode leaves an app's flags standing,
//  which is exactly when the offer is worth showing.
//
//  So the decision is made at FTCS D from the D-time snapshot, and the single
//  question is whether the shell at the prompt manages the mode. That is
//  recomputed at every FTCS C rather than latched, so it follows whichever shell
//  is currently at the prompt: a local Fish and a remote Bash reached over ssh
//  get different answers, one command apart.
//
//  These tests drive the REAL byte stream through the real VT100Parser ->
//  VT100Terminal -> VT100ScreenMutableState -> side effects -> PTYSession
//  pipeline. Nothing about the key reporting flags or the FTCS timing is
//  hand-fed. The byte orders used here were captured from fish 4.9.3 and bash
//  with iTerm2 shell integration; see the comments on the feed helpers. The only
//  test double is the session's naggingController, which stands in for the
//  terminal UI and records whether the offer was consulted.
//

import XCTest
@testable import iTerm2SharedARC

// Records whether the reset offer was consulted, without showing UI.
private final class RecordingNaggingController: iTermNaggingController {
    var shouldResetCallCount = 0
    /// When false (the default) PTYSession does not go on to actually reset key
    /// reporting, which keeps most tests to pure bookkeeping. Set it to true to
    /// stand in for the user answering "Yes" or having chosen "Always", which
    /// makes PTYSession take its real reset path.
    var shouldResetResponse = false
    override func shouldResetKeyReportingMode() -> Bool {
        shouldResetCallCount += 1
        return shouldResetResponse
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
    /// PTYSession delegate callbacks have run by the time this returns.
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
        // Drain any queued side effects.
        screen.performBlock(joinedThreads: { _, _, _ in })
    }

    private static let ESC = "\u{1b}"
    private static let BEL = "\u{07}"
    private func osc133(_ body: String) -> String { "\(Self.ESC)]133;\(body)\(Self.BEL)" }

    private static let armKittyKeyboard = "\(ESC)[=5u"      // the value fish uses at its prompt
    private static let disarmKittyKeyboard = "\(ESC)[=0u"   // what fish sends before a command
    private static let leakKittyKeyboard = "\(ESC)[=15u"    // an app's value, distinct from 5

    /// FTCS A then FTCS B, with prompt characters between them so the prompt
    /// range differs from the previous one.
    private func feedPrompt() {
        feed(osc133("A"))
        feed("$ ")
        feed(osc133("B"))
    }

    private func feedCommandStart() {
        feed("\r\n")
        feed(osc133("C"))
    }

    private func feedPromptAndStartCommand() {
        feedPrompt()
        feedCommandStart()
    }

    /// One cycle of a shell that does not touch the key reporting mode, in the
    /// order captured from bash with iTerm2 shell integration: A, B, C, D and no
    /// key reporting writes at all.
    private func feedUnmanagedCycle() {
        feedPromptAndStartCommand()
        feed(osc133("D;0"))
    }

    /// One cycle of a shell that manages the mode, in the order captured from
    /// bare fish 4.9.3: the mode is armed after the command ends, and driven to
    /// zero again just before the next command starts.
    private func feedManagedCycle() {
        feed(Self.armKittyKeyboard)
        feedPrompt()
        feed(Self.disarmKittyKeyboard)
        feedCommandStart()
        feed(osc133("D;0"))
    }

    /// One cycle in the order captured from fish 4.9.3 with oh-my-posh, whose
    /// FTCS D is emitted from inside the prompt function and so arrives after
    /// fish has already armed the mode for the prompt it is drawing. This is the
    /// configuration from the issue report.
    private func feedManagedCycleWithLateFinalTermD() {
        feedPrompt()
        feed(Self.disarmKittyKeyboard)
        feedCommandStart()
        feed(Self.armKittyKeyboard)   // the shell arms before the late D
        feed(osc133("D;0"))           // ...so D reports the shell's own value
    }

    // MARK: - The reported bug

    // 13032: with a late FTCS D the flags sampled at D are the shell's own. A
    // shell that drives the mode will replace them at its next prompt, so there
    // is nothing left behind.
    func testManagingShellWithLateFinalTermDDoesNotOfferReset() {
        feedManagedCycle()   // teaches that this shell drives the mode

        for cycle in 0..<4 {
            feedManagedCycleWithLateFinalTermD()
            XCTAssertEqual(resetOfferCount, 0,
                           "Cycle \(cycle): flags at FTCS D that the shell armed for the prompt it "
                           + "is drawing are not an app's leftovers (13032).")
        }
    }

    // The original 13032 report: a duplicate FTCS D emitted while drawing the
    // next prompt, after the shell re-armed. Each D closes at most one command,
    // so a second one with no intervening C must be ignored.
    func testStrayDuplicateFinalTermDDoesNotOfferReset() {
        feedPromptAndStartCommand()
        feed(osc133("D;0"))            // the real exit, key reporting still off

        XCTAssertEqual(resetOfferCount, 0)

        feed(Self.armKittyKeyboard)    // the shell arms for the next prompt
        feed(osc133("A"))
        feed(osc133("D;0"))            // a stray duplicate D

        XCTAssertEqual(resetOfferCount, 0,
                       "A second FTCS D with no intervening FTCS C closes nothing (13032).")
    }

    // MARK: - The case the offer exists for

    // A shell that never touches the mode leaves an app's flags standing. This
    // is the byte order captured from bash with iTerm2 shell integration.
    func testUnmanagedShellStillOffersResetForLeakedFlags() {
        feedUnmanagedCycle()
        feedPromptAndStartCommand()
        feed(Self.leakKittyKeyboard)   // the command turns key reporting on and dies
        feed(osc133("D;0"))

        XCTAssertEqual(resetOfferCount, 1,
                       "A shell that does not drive the mode leaves the flags standing, which is "
                       + "what the offer is for.")
    }

    // Flags already on when the command started were not turned on by it.
    func testFlagsAlreadyOnAtCommandStartAreNotALeak() {
        feedUnmanagedCycle()
        feed(Self.leakKittyKeyboard)
        feedPromptAndStartCommand()    // this command starts with the mode already on
        feed(osc133("D;0"))

        XCTAssertEqual(resetOfferCount, 0,
                       "The command did not turn key reporting on, so it did not leave it behind.")
    }

    // MARK: - Following the shell at the prompt

    // The verdict describes whichever shell is at the prompt, not the session.
    // Local fish, then ssh to a host running bash: an app that dies there must
    // still be reported, one command after the remote shell first speaks.
    func testShellThatStopsManagingTheModeStartsOfferingAgain() {
        feedManagedCycle()             // local fish drives the mode
        feedManagedCycle()

        feedUnmanagedCycle()           // now a shell that does not

        feedPromptAndStartCommand()
        feed(Self.leakKittyKeyboard)
        feed(osc133("D;0"))

        XCTAssertEqual(resetOfferCount, 1,
                       "A verdict learned from a shell that has gone away must not speak for the "
                       + "one that replaced it (13032).")
    }

    // ...and the reverse: a shell that starts managing the mode stops the offers.
    func testShellThatStartsManagingTheModeStopsOffering() {
        feedUnmanagedCycle()
        feedManagedCycle()

        for cycle in 0..<3 {
            feedManagedCycleWithLateFinalTermD()
            XCTAssertEqual(resetOfferCount, 0, "Cycle \(cycle) must be quiet.")
        }
    }

    // MARK: - Marks that must not move the verdict

    // A stray FTCS D mid-prompt must not reset the prompt-period window, or the
    // following FTCS C would conclude the shell had written nothing.
    func testStrayFinalTermDDoesNotResetThePromptPeriodWindow() {
        feedManagedCycle()

        feed(Self.armKittyKeyboard)    // the shell writes while it owns the terminal
        feed(osc133("D;0"))            // a stray D arrives before the prompt is done
        feedPrompt()
        feed(Self.disarmKittyKeyboard)
        feedCommandStart()
        feed(Self.armKittyKeyboard)
        feed(osc133("D;0"))

        XCTAssertEqual(resetOfferCount, 0,
                       "A stray FTCS D closes no command, so it must not clear the evidence the "
                       + "shell wrote during the prompt (13032).")
    }

    // The prompt-period window must exclude the command's own run. An app that
    // enables key reporting and tidily restores it leaves the flags at zero by
    // the next FTCS C; counting its writes would mark the shell as one that
    // drives the mode and silence the next real leak.
    func testWritesDuringTheCommandAreNotEvidenceAboutTheShell() {
        feedUnmanagedCycle()

        feedPromptAndStartCommand()
        feed(Self.leakKittyKeyboard)     // an app enables key reporting...
        feed(Self.disarmKittyKeyboard)   // ...and restores it before exiting
        feed(osc133("D;0"))

        XCTAssertEqual(resetOfferCount, 0, "Nothing was left behind by that command.")

        feedPromptAndStartCommand()      // the shell itself still wrote nothing
        feed(Self.leakKittyKeyboard)     // now an app leaks and dies
        feed(osc133("D;0"))

        XCTAssertEqual(resetOfferCount, 1,
                       "Writes made while a command was running say nothing about the shell "
                       + "(13032).")
    }

    // A shell that brackets its prompt with push/pop restores the mode it found
    // rather than replacing it, so an app's leftovers survive its next prompt.
    // Only a whole-value write supports the inference that the shell cleans up
    // after its own commands.
    func testShellThatPushesAndPopsIsNotTreatedAsManagingTheMode() {
        // A prompt bracketed by CSI > 5 u / CSI < u, with flags back to zero by
        // the time the command starts - the same shape a managing shell produces,
        // but by a mechanism that does not clobber anything.
        feedPrompt()
        feed("\(Self.ESC)[>5u")        // push
        feed("\(Self.ESC)[<u")         // pop
        feedCommandStart()
        feed(osc133("D;0"))

        // Now an app leaks and dies. This shell will not overwrite it.
        feedPrompt()
        feed("\(Self.ESC)[>5u")
        feed("\(Self.ESC)[<u")
        feedCommandStart()
        feed(Self.leakKittyKeyboard)
        feed(osc133("D;0"))

        XCTAssertEqual(resetOfferCount, 1,
                       "Push and pop restore the previous mode rather than replacing it, so the "
                       + "shell will not clear an app's leftovers (13032).")
    }

    // The merge forms set or clear individual bits, so they do not clear
    // leftovers either.
    func testShellThatMergesBitsIsNotTreatedAsManagingTheMode() {
        feedPrompt()
        feed("\(Self.ESC)[=5;2u")      // set the named bits
        feed("\(Self.ESC)[=5;3u")      // clear them again
        feedCommandStart()
        feed(osc133("D;0"))

        feedPrompt()
        feed("\(Self.ESC)[=5;2u")
        feed("\(Self.ESC)[=5;3u")
        feedCommandStart()
        feed(Self.leakKittyKeyboard)
        feed(osc133("D;0"))

        XCTAssertEqual(resetOfferCount, 1,
                       "Modes 2 and 3 only touch the named bits, so they will not clear an app's "
                       + "leftovers (13032).")
    }

    // MARK: - iTerm2's own reset

    // Accepting the offer drives the mode to zero at the prompt. That write is
    // iTerm2's, not the shell's, so it must not make an unmanaged shell look
    // like one that drives the mode - which would silence the next occurrence.
    func testOurOwnResetIsNotEvidenceAboutTheShell() {
        session.recordingNagging.shouldResetResponse = true

        feedUnmanagedCycle()
        feedPromptAndStartCommand()
        feed(Self.leakKittyKeyboard)
        feed(osc133("D;0"))            // offer fires; iTerm2 resets

        XCTAssertEqual(resetOfferCount, 1)
        drainMainQueue()

        feedPromptAndStartCommand()    // the shell still writes nothing
        feed(Self.leakKittyKeyboard)   // the same app leaks again
        feed(osc133("D;0"))

        XCTAssertEqual(resetOfferCount, 2,
                       "iTerm2's own reset write must not be counted as the shell managing the "
                       + "mode (13032).")
    }

    /// Let the main queue run to completion. -naggingControllerResetKeyReportingMode
    /// dispatches its reset asynchronously. Waits on a sentinel rather than a fixed
    /// duration: the queue is FIFO, so once the sentinel runs, everything enqueued
    /// before it has run too.
    private func drainMainQueue(file: StaticString = #filePath, line: UInt = #line) {
        var sentinelRan = false
        DispatchQueue.main.async { sentinelRan = true }
        let deadline = Date().addingTimeInterval(10)
        while !sentinelRan && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(sentinelRan, "main queue never drained", file: file, line: line)
        session.screen.performBlock(joinedThreads: { _, _, _ in })
    }
}
