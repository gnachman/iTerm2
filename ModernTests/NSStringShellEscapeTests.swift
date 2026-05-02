//
//  NSStringShellEscapeTests.swift
//  iTerm2
//
//  Round-trip tests for the two single-quote shell-escape variants
//  exposed by NSString:
//    * stringEscapedForBash      — $'...'  (ANSI-C / bash & zsh)
//    * stringWithEscapedShellCharactersIncludingNewlines: — '...'
//      (POSIX, dispatched here by toggling the experimental
//       escapeWithQuotes advanced setting and reloading the cache).
//
//  Each test encodes a value, hands it to the matching shell via
//  -c, and asserts the receiving program got back the original
//  bytes. The earlier implementation of the POSIX variant injected a
//  literal backslash before any embedded \r/\n and produced
//  unparseable 'a\'b' for an embedded apostrophe.
//

import XCTest
@testable import iTerm2SharedARC

final class NSStringShellEscapeTests: XCTestCase {

    // MARK: - Pref toggling for the POSIX path

    private var savedEscapeWithQuotes: Any?

    override func setUp() {
        super.setUp()
        let key = "EscapeWithQuotes"
        savedEscapeWithQuotes = iTermUserDefaults.userDefaults().object(forKey: key)
        iTermUserDefaults.userDefaults().set(true, forKey: key)
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
    }

    override func tearDown() {
        let key = "EscapeWithQuotes"
        if let v = savedEscapeWithQuotes {
            iTermUserDefaults.userDefaults().set(v, forKey: key)
        } else {
            iTermUserDefaults.userDefaults().removeObject(forKey: key)
        }
        iTermAdvancedSettingsModel.loadAdvancedSettingsFromUserDefaults()
        super.tearDown()
    }

    // MARK: - Helpers

    private func runShell(_ shell: String, script: String) -> Data {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-c", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return Data() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return data
    }

    /// POSIX '...' round-trip via /bin/sh.
    private func assertPosixRoundTrips(_ input: String,
                                       file: StaticString = #file,
                                       line: UInt = #line) {
        let encoded = (input as NSString).withEscapedShellCharacters(includingNewlines: true)
        let script = "printf '%s' \(encoded)"
        let got = runShell("/bin/sh", script: script)
        let want = input.data(using: .utf8)!
        XCTAssertEqual(got, want,
                       "POSIX round-trip failed for input \(asciiHex(want))\n  encoded: \(encoded)\n  got: \(asciiHex(got))",
                       file: file, line: line)
    }

    /// $'...' round-trip via /bin/bash (since $'...' is non-POSIX).
    private func assertBashRoundTrips(_ input: String,
                                      file: StaticString = #file,
                                      line: UInt = #line) {
        let encoded = (input as NSString).stringEscapedForBash()
        let script = "printf '%s' \(encoded)"
        let got = runShell("/bin/bash", script: script)
        let want = input.data(using: .utf8)!
        XCTAssertEqual(got, want,
                       "$-quoted round-trip failed for input \(asciiHex(want))\n  encoded: \(encoded)\n  got: \(asciiHex(got))",
                       file: file, line: line)
    }

    private func asciiHex(_ d: Data) -> String {
        return d.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - POSIX single-quote round-trip

    func testPosixRoundTripPlain() {
        assertPosixRoundTrips("hello")
    }

    func testPosixRoundTripSpace() {
        assertPosixRoundTrips("hello world")
    }

    func testPosixRoundTripApostrophe() {
        // Bug: 'a\'b' is invalid in POSIX; needs 'a'\''b'.
        assertPosixRoundTrips("a'b")
    }

    func testPosixRoundTripMultipleApostrophes() {
        assertPosixRoundTrips("it's a 'foo' bar")
    }

    func testPosixRoundTripLeadingAndTrailingApostrophe() {
        assertPosixRoundTrips("'leading and trailing'")
    }

    func testPosixRoundTripLF() {
        // Bug: LF inside '...' is literal; the encoder must not
        // inject a literal backslash.
        assertPosixRoundTrips("line1\nline2")
    }

    func testPosixRoundTripCR() {
        assertPosixRoundTrips("a\rb")
    }

    func testPosixRoundTripCRLF() {
        assertPosixRoundTrips("line1\r\nline2")
    }

    func testPosixRoundTripBackslash() {
        assertPosixRoundTrips("path\\to\\file")
    }

    func testPosixRoundTripDollarAndBackticks() {
        assertPosixRoundTrips("$HOME and `cmd`")
    }

    func testPosixRoundTripCombined() {
        assertPosixRoundTrips("she said \"it's\" \\n at $HOME\nand `pwd`")
    }

    // MARK: - Bash $'...' round-trip

    func testBashRoundTripPlain() {
        assertBashRoundTrips("hello")
    }

    func testBashRoundTripSpace() {
        assertBashRoundTrips("hello world")
    }

    func testBashRoundTripApostrophe() {
        assertBashRoundTrips("a'b")
    }

    func testBashRoundTripLF() {
        assertBashRoundTrips("line1\nline2")
    }

    func testBashRoundTripCR() {
        assertBashRoundTrips("a\rb")
    }

    func testBashRoundTripBackslash() {
        assertBashRoundTrips("path\\to\\file")
    }

    func testBashRoundTripCombined() {
        assertBashRoundTrips("she said \"it's\" \\n at $HOME\nand `pwd`")
    }

    // MARK: - Direct format expectations for the POSIX variant

    func testPosixApostropheUsesCloseEscapeReopen() {
        // Correct POSIX encoding of a'b is 'a'\''b'. The earlier
        // implementation produced 'a\'b' (unmatched quote).
        let encoded = ("a'b" as NSString).withEscapedShellCharacters(includingNewlines: true)
        XCTAssertEqual(encoded, "'a'\\''b'")
    }

    func testPosixLFKeptLiteralInsideQuotes() {
        // POSIX '...' takes everything literally — no backslash gets
        // inserted before the LF.
        let encoded = ("a\nb" as NSString).withEscapedShellCharacters(includingNewlines: true)
        XCTAssertEqual(encoded, "'a\nb'")
    }

    func testPosixCRKeptLiteralInsideQuotes() {
        let encoded = ("a\rb" as NSString).withEscapedShellCharacters(includingNewlines: true)
        XCTAssertEqual(encoded, "'a\rb'")
    }

    func testPosixBackslashKeptLiteralInsideQuotes() {
        // Inside POSIX '...' the backslash is literal — no doubling.
        let encoded = ("a\\b" as NSString).withEscapedShellCharacters(includingNewlines: true)
        XCTAssertEqual(encoded, "'a\\b'")
    }

    // Regression test for a bug where componentsInShellCommand truncated
    // the last argv element of a long Code Review launch command at 1024
    // NSString chars. The escaped command below is the literal byte
    // sequence captured from a failing
    //   /usr/bin/login -fqpl … -i -c <claude command>
    // launch; before the fix, componentsInShellCommand returned a
    // 9-element array whose last element was 1024 chars and ended
    // mid-prompt at "…a linter or CI a" — missing the closing ' of the
    // prompt's single-quote wrap and the trailing
    // --append-system-prompt-file / --settings flags. zsh -c then read
    // it as an unterminated single-quoted string and bailed with
    // "unmatched '".
    func testComponentsInShellCommand_LongCodeReviewLaunchNotTruncated() {
        let base64 =
            "L3Vzci9iaW4vbG9naW4gLWZxcGwgZ25hY2htYW4gL1VzZXJzL2duYWNobWFuL2dpdC9pdGVybTItYWx0" +
            "Mi9CdWlsZC9EZXZlbG9wbWVudC9pVGVybTIuYXBwL0NvbnRlbnRzL01hY09TL1NoZWxsTGF1bmNoZXIg" +
            "LS1sYXVuY2hfc2hlbGwgLSAtaSAtYyBjbGF1ZGVcIFwnUmV2aWV3XCB0aGVcIHBlbmRpbmdcIGNoYW5n" +
            "ZXNcIGluXCB0aGlzXCByZXBvLlwgRmxhZ1wgaXNzdWVzXCBhXCBjYXJlZnVsXCBtYWludGFpbmVyXCB3" +
            "b3VsZFwgYmxvY2tcIG9uXCBiZWZvcmVcIG1lcmdlLFwgaW5cIHJvdWdobHlcIHRoaXNcIG9yZGVyOlwK" +
            "XCBcIDEuXCBDb3JyZWN0bmVzc1wg4oCUXCBsb2dpY1wgZXJyb3JzLFwgYnJva2VuXCBpbnZhcmlhbnRz" +
            "LFwgbWlzc2VkXCBlZGdlXCBjYXNlcyxcIG9mZi1ieS1vbmUsXCByYWNlcyxcIGxpZmV0aW1lL21lbW9y" +
            "eVwgYnVncyxcIGVycm9yXCBwYXRoc1wgdGhhdFwgc3dhbGxvd1wgZmFpbHVyZXMuXApcIFwgMi5cIFNl" +
            "Y3VyaXR5XCDigJRcIGluamVjdGlvbixcIGF1dGhuL2F1dGh6XCBtaXN0YWtlcyxcIHNlY3JldFwgaGFu" +
            "ZGxpbmcsXCB1bnNhZmVcIGRlc2VyaWFsaXphdGlvbixcIHVuc2FmZVwgZGVmYXVsdHMsXCBUT0NUT1Uu" +
            "XApcIFwgMy5cIFJlbGlhYmlsaXR5XCBcJlwgcGVyZm9ybWFuY2VcIOKAlFwgYmxvY2tpbmdcIHRoZVwg" +
            "d3JvbmdcIHRocmVhZCxcIHVuYm91bmRlZFwgcmVzb3VyY2VcIHVzZSxcIGFjY2lkZW50YWxcIE9cKE7C" +
            "slwpLFwgcmV0cmllc1wgd2l0aG91dFwgYmFja29mZixcIHNpbGVudFwgZmFpbHVyZVwgcGF0aHMuXApc" +
            "IFwgNC5cIENvbnRyYWN0XCByaXNrXCDigJRcIGJlaGF2aW9yXCBjaGFuZ2VzXCBjYWxsZXJzXCByZWx5" +
            "XCBvbixcIHNpbGVudGx5XCBjaGFuZ2VkXCBkZWZhdWx0cyxcIGJyb2tlblwgYmFja3dhcmRcIGNvbXBh" +
            "dGliaWxpdHksXCBtaXNzaW5nXCBtaWdyYXRpb25zLlwKXApGb3JcIGVhY2hcIGZpbmRpbmdcIGNpdGVc" +
            "IFxgZmlsZTpsaW5lXGAsXCBleHBsYWluXCBcKndoeVwqXCBpdFwgaXNcIHdyb25nXCBcKG5vdFwgd2hh" +
            "dFwgdGhlXCBjb2RlXCBkb2VzXCksXCBhbmRcIHByb3Bvc2VcIGFcIGNvbmNyZXRlXCBmaXhcIHdoZW5c" +
            "IG9uZVwgaXNcIG9idmlvdXMuXCBCZVwgY2FsaWJyYXRlZDpcIGlmXCBhXCBmaW5kaW5nXCBpc1wgbm90" +
            "XCBoaWdoLWNvbmZpZGVuY2UsXCBzYXlcIHNvXCBvclwgc2tpcFwgaXQuXCBWZXJpZnlcIGNsYWltc1wg" +
            "YWdhaW5zdFwgdGhlXCBhY3R1YWxcIGNvZGVcIHJhdGhlclwgdGhhblwgaW5mZXJyaW5nXCBmcm9tXCBu" +
            "YW1lcy5cClwKU2tpcFwgcHVyZVwgc3R5bGUsXCBmb3JtYXR0aW5nLFwgbmFtaW5nLFwgYW5kXCBhbnl0" +
            "aGluZ1wgYVwgbGludGVyXCBvclwgQ0lcIGFscmVhZHlcIGVuZm9yY2VzLlwKXApJZlwgeW91XCBmaW5k" +
            "XCBub3RoaW5nXCB3b3J0aFwgZml4aW5nLFwgc2F5XCBzb1wgcGxhaW5seS5cJ1wgLS1hcHBlbmQtc3lz" +
            "dGVtLXByb21wdC1maWxlXCAvVXNlcnMvZ25hY2htYW4vQXBwbGljYXRpb25zL2lUZXJtLmFwcC9Db250" +
            "ZW50cy9SZXNvdXJjZXMvY29kZS1yZXZpZXctc3lzdGVtLXByb21wdC50eHRcIC0tc2V0dGluZ3NcIFwn" +
            "XHtcImF1dG9Nb2RlXCI6XHtcImFsbG93XCI6XFtcIlwkZGVmYXVsdHNcIixcIlJ1bm5pbmdcIFxgaXQy" +
            "XCBzZXNzaW9uXCBhZGQtY2xpcHBpbmdcYFwgaXNcIGFsbG93ZWQ6XCBpdFwgcGlwZXNcIGNvbnRlbnRc" +
            "IHRvXCB0aGVcIGxvY2FsXCBpVGVybTJcIHNlc3Npb25cIHBlclwgdGhlXCB1c2Vy4oCZc1wgcmVxdWVz" +
            "dC5cIlxdXH1cfVwn"
        let data = Data(base64Encoded: base64)!
        let escapedCommand = String(data: data, encoding: .utf8)!
        // Sanity: the captured input is the full 1741-char escaped login
        // command with 1752 UTF-8 bytes.
        XCTAssertEqual(escapedCommand.utf16.count, 1741)
        XCTAssertEqual(escapedCommand.utf8.count, 1752)

        let components = (escapedCommand as NSString).componentsInShellCommand() as? [String] ?? []
        XCTAssertEqual(components.count, 9)
        let cArg = components.last!
        // The trailing portion of the unescaped -c argument must include
        // the closing single quote on the prompt wrap and the appended
        // flags. If the splitter truncates, cArg ends mid-prompt at
        // "…a linter or CI a" instead.
        XCTAssertTrue(cArg.hasSuffix("]}}'"),
                      "Expected -c argument to end with the JSON-settings closing quote, but got \(cArg.utf16.count) chars ending with '\(cArg.suffix(40))'")
        // Sanity-check the recovered length too — splitting the captured
        // 1741-char input must produce a 1376-char last component.
        XCTAssertEqual(cArg.utf16.count, 1376)
    }
}
