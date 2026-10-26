//
//  BashWordSplitterTests.swift
//  iTerm2 ModernTests
//
//  BashWordSplitter is checked against bash itself: for each input, bash's own word splitting
//  (eval "set -- <input>") is the expected answer.
//

import XCTest
@testable import iTerm2SharedARC

final class BashWordSplitterTests: XCTestCase {
    private func bashWords(_ input: String) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", #"eval "set -- $1"; printf '%s\0' "$@""#, "bash", input]
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var words = data.split(separator: 0, omittingEmptySubsequences: false).map {
            String(decoding: $0, as: UTF8.self)
        }
        words.removeLast()  // after the final NUL
        return words
    }

    func testMatchesBash() throws {
        let inputs = [
            "host",
            "  leading and   trailing  ",
            #"a\ b c"#,
            #"'single quoted' "double quoted""#,
            #"'it'\''s'"#,
            #""a\"b\\c\$d" 'x\y'"#,
            #"$'tab\there' $'nl\nx' $'\e[0m' $'\101\102' $'\x41\x4a' $'é' $'\'q\''"#,
            #"$'\346\227\245\346\234\254'"#,
            #"a''b "" ''"#,
            #"mixed'quo'"tes"$'\t'end"#,
            "trailing\\",
        ]
        // Not compared: anything bash would expand ($HOME, globs). A quoted argument list has no
        // expansions, and the splitter leaves them as written.
        for input in inputs {
            XCTAssertEqual(BashWordSplitter.words(input), try bashWords(input), "for \(input.debugDescription)")
        }
    }

    // Exactly what %q produces for awkward arguments, round-tripped.
    func testRoundTripsPrintfQ() throws {
        let arguments = ["plain", "two words", "it's", "a\"b", "back\\slash", "tab\there", "nl\nhere",
                         "日本語", "😀", "\u{1b}[0m", "$HOME", "", "semi;colon", "*glob?"]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "printf '%q ' \"$@\"", "bash"] + arguments
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(BashWordSplitter.words(String(decoding: data, as: UTF8.self)), arguments)
    }
}
