// Test program for Fn key remapping behavior.
// Automatically verifies key output by reading raw bytes in CSI u mode.
//
// Build:
//   swiftc -framework Carbon tests/test_fn_remapping.swift -o tests/test_fn_remapping
//
// Run inside a DEBUG build of iTerm2:
//   tests/test_fn_remapping

import Foundation
import Carbon

// MARK: - Constants

let kPreferenceModifierTagFunction = 10
let kPreferencesModifierTagLeftControl = 11

// MARK: - Terminal Formatting

func bold(_ s: String) -> String { "\u{1b}[1m\(s)\u{1b}[0m" }
func red(_ s: String) -> String { "\u{1b}[31m\(s)\u{1b}[0m" }
func green(_ s: String) -> String { "\u{1b}[32m\(s)\u{1b}[0m" }
func yellow(_ s: String) -> String { "\u{1b}[33m\(s)\u{1b}[0m" }
func dim(_ s: String) -> String { "\u{1b}[2m\(s)\u{1b}[0m" }

// MARK: - Terminal Raw Mode

var originalTermios = termios()
var rawModeEnabled = false

func enableRawMode() {
    guard !rawModeEnabled else { return }
    tcgetattr(STDIN_FILENO, &originalTermios)
    var raw = originalTermios
    cfmakeraw(&raw)
    raw.c_oflag |= tcflag_t(OPOST)   // keep output processing (\n -> \r\n)
    raw.c_lflag |= tcflag_t(ISIG)    // keep signal handling (Ctrl+C)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    rawModeEnabled = true
}

func disableRawMode() {
    guard rawModeEnabled else { return }
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
    rawModeEnabled = false
}

// MARK: - iTerm2 Control

/// Read exactly `count` bytes from stdin, or give up after `timeoutUs` microseconds.
func readExact(count: Int, timeoutUs: UInt32 = 2_000_000) -> [UInt8] {
    var result: [UInt8] = []
    let flags = fcntl(STDIN_FILENO, F_GETFL)
    fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)

    var elapsed: UInt32 = 0
    let sleepInterval: UInt32 = 10_000  // 10ms
    while result.count < count && elapsed < timeoutUs {
        var buf: UInt8 = 0
        if read(STDIN_FILENO, &buf, 1) > 0 {
            result.append(buf)
        } else {
            usleep(sleepInterval)
            elapsed += sleepInterval
        }
    }

    fcntl(STDIN_FILENO, F_SETFL, flags)
    return result
}

@discardableResult
func setFnRemapping(_ tag: Int) -> Bool {
    // Flush any pending input before sending the OSC
    flushStdin()

    print("\u{1b}]1337;Debug=RemapFn=\(tag)\u{07}", terminator: "")
    fflush(stdout)

    // Read the ack: \e]1337;DebugAck=FnRemap=<tag>\a
    let expected = "\u{1b}]1337;DebugAck=FnRemap=\(tag)\u{07}"
    let expectedBytes = Array(expected.utf8)

    // Wait for the ack with a generous timeout (2 seconds)
    let ack = readExact(count: expectedBytes.count, timeoutUs: 2_000_000)
    if ack == expectedBytes {
        return true
    }
    // If we didn't get the ack, the OSC handler may not be compiled (release build)
    return false
}

/// Query iTerm2 for the current Fn remapping state.
/// Returns a string like "FnState=0;Remap=10;Any=0;ET=0" or nil on timeout.
func queryFnState() -> String? {
    flushStdin()

    print("\u{1b}]1337;Debug=QueryFnState\u{07}", terminator: "")
    fflush(stdout)

    // Read ack prefix: \e]1337;DebugAck=
    let prefix = "\u{1b}]1337;DebugAck="
    let prefixBytes = Array(prefix.utf8)
    let prefixData = readExact(count: prefixBytes.count, timeoutUs: 2_000_000)
    guard prefixData == prefixBytes else { return nil }

    // Read until BEL (0x07)
    var value: [UInt8] = []
    let flags = fcntl(STDIN_FILENO, F_GETFL)
    fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
    var elapsed: UInt32 = 0
    while elapsed < 2_000_000 {
        var buf: UInt8 = 0
        if read(STDIN_FILENO, &buf, 1) > 0 {
            if buf == 0x07 { break }
            value.append(buf)
        } else {
            usleep(10_000)
            elapsed += 10_000
        }
    }
    fcntl(STDIN_FILENO, F_SETFL, flags)

    return String(bytes: value, encoding: .utf8)
}

// MARK: - Secure Keyboard Entry

var secureInputEnabled = false

func enableSecureInput() {
    if !secureInputEnabled {
        EnableSecureEventInput()
        secureInputEnabled = true
    }
}

func disableSecureInput() {
    if secureInputEnabled {
        DisableSecureEventInput()
        secureInputEnabled = false
    }
}

// MARK: - CSI u Key Reporting

func enableKeyReporting() {
    print("\u{1b}[>1u", terminator: "")
    fflush(stdout)
}

func disableKeyReporting() {
    print("\u{1b}[<u", terminator: "")
    fflush(stdout)
}

// MARK: - Cleanup

func restoreDefaults() {
    disableKeyReporting()
    disableSecureInput()
    disableRawMode()
    _ = setFnRemapping(kPreferenceModifierTagFunction)
}

// MARK: - Raw I/O

func flushStdin() {
    tcflush(STDIN_FILENO, TCIFLUSH)
}

/// Read a complete key sequence from stdin in raw mode.
/// Blocks until the first byte arrives, then drains remaining bytes.
func readKeySequence() -> [UInt8] {
    flushStdin()

    var bytes: [UInt8] = []
    var buf: UInt8 = 0

    // Block for first byte
    let n = read(STDIN_FILENO, &buf, 1)
    if n > 0 {
        bytes.append(buf)
    }

    // Wait briefly for remaining bytes of escape sequence to arrive
    usleep(50_000)

    // Switch to non-blocking to drain
    let flags = fcntl(STDIN_FILENO, F_GETFL)
    fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
    while true {
        var b: UInt8 = 0
        if read(STDIN_FILENO, &b, 1) <= 0 { break }
        bytes.append(b)
    }
    fcntl(STDIN_FILENO, F_SETFL, flags)

    return bytes
}

/// Wait for Enter key in raw mode. Discards other input.
func waitForEnterRaw() {
    flushStdin()
    while true {
        var buf: UInt8 = 0
        let n = read(STDIN_FILENO, &buf, 1)
        if n > 0 && (buf == 0x0d || buf == 0x0a) {
            // Drain any trailing bytes
            usleep(10_000)
            let flags = fcntl(STDIN_FILENO, F_GETFL)
            fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
            while read(STDIN_FILENO, &buf, 1) > 0 {}
            fcntl(STDIN_FILENO, F_SETFL, flags)
            return
        }
    }
}

// MARK: - Byte Sequence Display

func describeBytes(_ bytes: [UInt8]) -> String {
    var parts: [String] = []
    for b in bytes {
        if b == 0x1b { parts.append("\\e") }
        else if b == 0x0d { parts.append("\\r") }
        else if b == 0x0a { parts.append("\\n") }
        else if b == 0x7f { parts.append("\\x7f") }
        else if b < 0x20 { parts.append(String(format: "\\x%02x", b)) }
        else if b < 0x7f { parts.append(String(UnicodeScalar(b))) }
        else { parts.append(String(format: "\\x%02x", b)) }
    }
    return parts.joined()
}

func friendlyName(_ bytes: [UInt8]) -> String {
    let seq = describeBytes(bytes)
    switch seq {
    case "\\e[A": return "Up Arrow (\\e[A)"
    case "\\e[B": return "Down Arrow (\\e[B)"
    case "\\e[C": return "Right Arrow (\\e[C)"
    case "\\e[D": return "Left Arrow (\\e[D)"
    case "\\e[5~": return "Page Up (\\e[5~)"
    case "\\e[6~": return "Page Down (\\e[6~)"
    case "\\e[H": return "Home (\\e[H)"
    case "\\e[F": return "End (\\e[F)"
    case "\\e[3~": return "Delete (\\e[3~)"
    case "\\e[1;5A": return "Ctrl+Up (\\e[1;5A)"
    case "\\e[1;5B": return "Ctrl+Down (\\e[1;5B)"
    case "\\e[1;5C": return "Ctrl+Right (\\e[1;5C)"
    case "\\e[1;5D": return "Ctrl+Left (\\e[1;5D)"
    case "\\e[97;5u": return "Ctrl+a CSI u (\\e[97;5u)"
    case "\\x01": return "Ctrl+a legacy (0x01)"
    default:
        if bytes.count == 1 && bytes[0] >= 0x20 && bytes[0] < 0x7f {
            return "'\(String(UnicodeScalar(bytes[0])))' (0x\(String(format: "%02x", bytes[0])))"
        }
        return seq
    }
}

// MARK: - Expected Byte Sequences

let seqUpArrow: [UInt8]    = [0x1b, 0x5b, 0x41]                               // \e[A
let seqPageUp: [UInt8]     = [0x1b, 0x5b, 0x35, 0x7e]                         // \e[5~
let seqCtrlUp: [UInt8]     = [0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x41]            // \e[1;5A
let seqLetterA: [UInt8]    = [0x61]                                            // a
let seqCtrlA_CSIu: [UInt8] = [0x1b, 0x5b, 0x39, 0x37, 0x3b, 0x35, 0x75]      // \e[97;5u
let seqCtrlA_leg: [UInt8]  = [0x01]                                            // ^A

// MARK: - Test Case Model

struct TestCase {
    let row: Int              // row from truth table (0 = extra test)
    let secureInputOn: Bool
    let internalKB: Bool
    let fnPressed: Bool
    let functionAreaKey: Bool
    let fnRemapped: Bool
    let expectedDesc: String  // human-readable expected result
    let accepted: [[UInt8]]   // acceptable byte sequences
    let instruction: String
}

// MARK: - Test Case Definitions

let internalTests: [TestCase] = [
    // Event tap ON (secure input OFF), internal keyboard
    TestCase(row: 1, secureInputOn: false, internalKB: true,
             fnPressed: false, functionAreaKey: true, fnRemapped: false,
             expectedDesc: "Up Arrow",
             accepted: [seqUpArrow],
             instruction: "Press Up Arrow (do NOT hold Fn)"),
    TestCase(row: 2, secureInputOn: false, internalKB: true,
             fnPressed: false, functionAreaKey: true, fnRemapped: true,
             expectedDesc: "Up Arrow",
             accepted: [seqUpArrow],
             instruction: "Press Up Arrow (do NOT hold Fn)"),
    TestCase(row: 3, secureInputOn: false, internalKB: true,
             fnPressed: false, functionAreaKey: false, fnRemapped: false,
             expectedDesc: "'a'",
             accepted: [seqLetterA],
             instruction: "Press 'a' (do NOT hold Fn)"),
    TestCase(row: 4, secureInputOn: false, internalKB: true,
             fnPressed: false, functionAreaKey: false, fnRemapped: true,
             expectedDesc: "'a'",
             accepted: [seqLetterA],
             instruction: "Press 'a' (do NOT hold Fn)"),
    TestCase(row: 5, secureInputOn: false, internalKB: true,
             fnPressed: true, functionAreaKey: true, fnRemapped: false,
             expectedDesc: "Page Up",
             accepted: [seqPageUp],
             instruction: "Hold Fn, then press Up Arrow"),
    TestCase(row: 6, secureInputOn: false, internalKB: true,
             fnPressed: true, functionAreaKey: true, fnRemapped: true,
             expectedDesc: "Ctrl+Up Arrow",
             accepted: [seqCtrlUp],
             instruction: "Hold Fn, then press Up Arrow"),
    TestCase(row: 7, secureInputOn: false, internalKB: true,
             fnPressed: true, functionAreaKey: false, fnRemapped: false,
             expectedDesc: "'a'",
             accepted: [seqLetterA],
             instruction: "Hold Fn, then press 'a'"),
    TestCase(row: 8, secureInputOn: false, internalKB: true,
             fnPressed: true, functionAreaKey: false, fnRemapped: true,
             expectedDesc: "Ctrl+a",
             accepted: [seqCtrlA_CSIu, seqCtrlA_leg],
             instruction: "Hold Fn, then press 'a'"),

    // Event tap OFF (secure input ON), internal keyboard
    TestCase(row: 17, secureInputOn: true, internalKB: true,
             fnPressed: false, functionAreaKey: true, fnRemapped: false,
             expectedDesc: "Up Arrow",
             accepted: [seqUpArrow],
             instruction: "Press Up Arrow (do NOT hold Fn)"),
    TestCase(row: 18, secureInputOn: true, internalKB: true,
             fnPressed: false, functionAreaKey: true, fnRemapped: true,
             expectedDesc: "Up Arrow",
             accepted: [seqUpArrow],
             instruction: "Press Up Arrow (do NOT hold Fn)"),
    TestCase(row: 19, secureInputOn: true, internalKB: true,
             fnPressed: false, functionAreaKey: false, fnRemapped: false,
             expectedDesc: "'a'",
             accepted: [seqLetterA],
             instruction: "Press 'a' (do NOT hold Fn)"),
    TestCase(row: 20, secureInputOn: true, internalKB: true,
             fnPressed: false, functionAreaKey: false, fnRemapped: true,
             expectedDesc: "'a'",
             accepted: [seqLetterA],
             instruction: "Press 'a' (do NOT hold Fn)"),
    TestCase(row: 21, secureInputOn: true, internalKB: true,
             fnPressed: true, functionAreaKey: true, fnRemapped: false,
             expectedDesc: "Page Up",
             accepted: [seqPageUp],
             instruction: "Hold Fn, then press Up Arrow"),
    TestCase(row: 22, secureInputOn: true, internalKB: true,
             fnPressed: true, functionAreaKey: true, fnRemapped: true,
             expectedDesc: "Ctrl+Up Arrow",
             accepted: [seqCtrlUp],
             instruction: "Hold Fn, then press Up Arrow"),
    TestCase(row: 23, secureInputOn: true, internalKB: true,
             fnPressed: true, functionAreaKey: false, fnRemapped: false,
             expectedDesc: "'a'",
             accepted: [seqLetterA],
             instruction: "Hold Fn, then press 'a'"),
    TestCase(row: 24, secureInputOn: true, internalKB: true,
             fnPressed: true, functionAreaKey: false, fnRemapped: true,
             expectedDesc: "Ctrl+a",
             accepted: [seqCtrlA_CSIu, seqCtrlA_leg],
             instruction: "Hold Fn, then press 'a'"),
]

let externalTests: [TestCase] = [
    // Event tap ON (secure input OFF), external keyboard
    TestCase(row: 9, secureInputOn: false, internalKB: false,
             fnPressed: false, functionAreaKey: true, fnRemapped: false,
             expectedDesc: "Up Arrow",
             accepted: [seqUpArrow],
             instruction: "Press Up Arrow"),
    TestCase(row: 10, secureInputOn: false, internalKB: false,
             fnPressed: false, functionAreaKey: true, fnRemapped: true,
             expectedDesc: "Up Arrow",
             accepted: [seqUpArrow],
             instruction: "Press Up Arrow"),
    TestCase(row: 11, secureInputOn: false, internalKB: false,
             fnPressed: false, functionAreaKey: false, fnRemapped: false,
             expectedDesc: "'a'",
             accepted: [seqLetterA],
             instruction: "Press 'a'"),
    TestCase(row: 12, secureInputOn: false, internalKB: false,
             fnPressed: false, functionAreaKey: false, fnRemapped: true,
             expectedDesc: "'a'",
             accepted: [seqLetterA],
             instruction: "Press 'a'"),

    // Event tap OFF (secure input ON), external keyboard
    TestCase(row: 25, secureInputOn: true, internalKB: false,
             fnPressed: false, functionAreaKey: true, fnRemapped: false,
             expectedDesc: "Up Arrow",
             accepted: [seqUpArrow],
             instruction: "Press Up Arrow"),
    TestCase(row: 26, secureInputOn: true, internalKB: false,
             fnPressed: false, functionAreaKey: true, fnRemapped: true,
             expectedDesc: "Up Arrow",
             accepted: [seqUpArrow],
             instruction: "Press Up Arrow"),
    TestCase(row: 27, secureInputOn: true, internalKB: false,
             fnPressed: false, functionAreaKey: false, fnRemapped: false,
             expectedDesc: "'a'",
             accepted: [seqLetterA],
             instruction: "Press 'a'"),
    TestCase(row: 28, secureInputOn: true, internalKB: false,
             fnPressed: false, functionAreaKey: false, fnRemapped: true,
             expectedDesc: "'a'",
             accepted: [seqLetterA],
             instruction: "Press 'a'"),

    // Physical Page Up on external keyboard.
    // Verifies reverseFnKeyTranslationIfNeeded: does NOT fire
    // (physicalFnKeyDown is NO on external keyboards).
    TestCase(row: 0, secureInputOn: false, internalKB: false,
             fnPressed: false, functionAreaKey: true, fnRemapped: false,
             expectedDesc: "Page Up",
             accepted: [seqPageUp],
             instruction: "Press Page Up"),
    TestCase(row: 0, secureInputOn: false, internalKB: false,
             fnPressed: false, functionAreaKey: true, fnRemapped: true,
             expectedDesc: "Page Up",
             accepted: [seqPageUp],
             instruction: "Press Page Up"),
    TestCase(row: 0, secureInputOn: true, internalKB: false,
             fnPressed: false, functionAreaKey: true, fnRemapped: false,
             expectedDesc: "Page Up",
             accepted: [seqPageUp],
             instruction: "Press Page Up"),
    TestCase(row: 0, secureInputOn: true, internalKB: false,
             fnPressed: false, functionAreaKey: true, fnRemapped: true,
             expectedDesc: "Page Up",
             accepted: [seqPageUp],
             instruction: "Press Page Up"),
]

let allTests = internalTests + externalTests
let totalTests = allTests.count

// MARK: - Results Tracking

struct TestResult {
    let testNumber: Int
    let row: Int
    let instruction: String
    let expectedDesc: String
    let receivedBytes: [UInt8]
    let passed: Bool
}

var results: [TestResult] = []

// MARK: - Test Runner

func runTest(_ tc: TestCase, number: Int) -> TestResult {
    // Configure secure input BEFORE setting the remap preference.
    // When secure input is ON, the event tap is disabled, so the app path
    // must be used. The OSC handler's call to setRemapModifiers: will
    // correctly set up the app path.
    if tc.secureInputOn {
        enableSecureInput()
    } else {
        disableSecureInput()
    }

    // Configure Fn remapping and verify the ack
    let remapTag = tc.fnRemapped ? kPreferencesModifierTagLeftControl : kPreferenceModifierTagFunction
    let ackReceived = setFnRemapping(remapTag)

    let secureLabel = tc.secureInputOn ? red("ON") : green("OFF")
    let remapLabel = tc.fnRemapped ? yellow("Fn -> Left Ctrl") : dim("none")
    let etLabel = tc.secureInputOn ? red("app path") : green("event tap")
    let rowLabel = tc.row > 0 ? "Row \(tc.row)" : "Extra"
    let ackLabel = ackReceived ? green("confirmed") : red("NO ACK")

    print("")
    print(bold("--- Test \(number)/\(totalTests)  [\(rowLabel)] ---"))
    print("  Path:           \(etLabel)")
    print("  Secure input:   \(secureLabel)")
    print("  Fn remap:       \(remapLabel) (\(ackLabel))")
    print("  " + bold("DO:     \(tc.instruction)"))
    print("  " + bold("EXPECT: \(tc.expectedDesc)"))
    if !ackReceived {
        print("  " + red("WARNING: OSC ack not received. Are you running a DEBUG build?"))
    }
    print("")

    // Read the key
    let received = readKeySequence()
    let passed = tc.accepted.contains(received)
    let receivedName = friendlyName(received)

    if passed {
        print("  " + green("PASS") + "  Got: \(receivedName)")
    } else {
        print("  " + red("FAIL") + "  Got: \(receivedName)  Expected: \(tc.expectedDesc)")
    }

    // For Fn-pressed tests, query iTerm2 for diagnostic state
    if tc.fnPressed {
        if let state = queryFnState() {
            print(dim("  Debug: \(state)"))
        }
    }

    // Brief pause so user can see the result before moving on
    print(dim("  Press Enter to continue..."))
    waitForEnterRaw()

    return TestResult(testNumber: number, row: tc.row, instruction: tc.instruction,
                      expectedDesc: tc.expectedDesc, receivedBytes: received, passed: passed)
}

// MARK: - Main

signal(SIGINT) { _ in
    restoreDefaults()
    exit(1)
}

atexit {
    restoreDefaults()
}

print(bold("=== Fn Key Remapping Test Suite ==="))
print("")
print("This program tests all valid combinations from the Fn remapping")
print("truth table in iTermModifierRemapper.m, plus external PageUp tests.")
print("")
print(yellow("IMPORTANT: You must run this inside a DEBUG build of iTerm2."))
print(yellow("The OSC 1337;Debug=RemapFn handler only exists in debug builds."))
print("")
print("The program reads raw key bytes via CSI u mode and automatically")
print("compares them to expected values. No manual judgment needed.")
print("")

// Switch to raw mode for the entire test session
enableKeyReporting()
enableRawMode()

// Pre-flight check: verify the OSC handler is working
print("Verifying OSC handler...")
if !setFnRemapping(kPreferenceModifierTagFunction) {
    print(red("FATAL: OSC 1337;Debug=RemapFn handler not responding."))
    print(red("You must run this inside a DEBUG build of iTerm2."))
    restoreDefaults()
    exit(1)
}
print(green("OSC handler verified."))
print("")

// --- Internal keyboard tests ---
print(bold("========== INTERNAL KEYBOARD TESTS (\(internalTests.count) tests) =========="))
print(yellow("Please ensure you are using the built-in laptop keyboard."))
print("Press Enter to begin...")
waitForEnterRaw()

for (i, tc) in internalTests.enumerated() {
    results.append(runTest(tc, number: i + 1))
}

// --- External keyboard tests ---
print("")
print(bold("========== EXTERNAL KEYBOARD TESTS (\(externalTests.count) tests) =========="))
print(yellow("Please switch to an external keyboard (one without a Fn key)."))
print("Press Enter when ready...")
waitForEnterRaw()

for (i, tc) in externalTests.enumerated() {
    results.append(runTest(tc, number: internalTests.count + i + 1))
}

// --- Summary ---
print("")
print(bold("=== All \(totalTests) tests complete! ==="))
print("")

let passedResults = results.filter { $0.passed }
let failedResults = results.filter { !$0.passed }

if failedResults.isEmpty {
    print(green("All \(totalTests) tests passed!"))
} else {
    print(red("\(failedResults.count) FAILED") + ", " + green("\(passedResults.count) passed") + " out of \(totalTests)")
    print("")
    print(bold("Failed tests:"))
    for r in failedResults {
        let rowLabel = r.row > 0 ? "Row \(r.row)" : "Extra"
        let got = friendlyName(r.receivedBytes)
        print(red("  #\(r.testNumber) [\(rowLabel)]: \(r.instruction)"))
        print(red("    Expected: \(r.expectedDesc)  Got: \(got)"))
    }
}

print("")
print("Fn remapping restored to default. Secure input disabled. CSI u disabled.")
