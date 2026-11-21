//
//  StressStreamReplayTests.swift
//  iTerm2
//
//  Replays the stress harness's inputs, and streams that push integers to
//  their extremes, through the real pty path of a VT100Screen (parser, token
//  executor, screen, line buffer), so that a sanitizer run of the suite sees
//  them. docs/swift-migration/translation-rules.md section 1 asks for the
//  integer discovery run to include the stress harness; the harness itself
//  (tools/perf/run_stress_test.sh) drives a running app with AppleScript and
//  cannot run beside the owner's iTerm2, so its inputs are replayed here
//  instead (docs/swift-migration/integer-findings.md).
//
//  Each test checks only what must hold whatever the stream: replay finishes
//  and the cursor is inside the grid. The value of these tests is what a
//  sanitizer reports while they run.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class StressStreamReplayTests: XCTestCase {
    private let width = 80
    private let height = 24

    // MARK: - Files under tests/

    /// tools/perf/stress_load.py's output, captured by tools/perf/capture_stress_load.py: every
    /// terminal output stress mode and every dashboard mode, a fixed number of iterations each.
    func testStressLoadCapture() throws {
        try replayFile("stress_load_capture.txt")
    }

    /// A recorded tmux and vim session: full-screen redraws, scroll regions, SGR. Its first
    /// 256 KB, to keep the test under a second (the whole file is 4 MB).
    func testPerf3() throws {
        try replayFile("perf3.txt", maxBytes: 256 * 1024)
    }

    /// CJK text: double-width characters wrapping at every line end. Its first 128 KB (the whole
    /// file is 2 MB).
    func testJourneyToTheWest() throws {
        try replayFile("journey_to_the_west.txt", maxBytes: 128 * 1024)
    }

    func testLongCJK() throws {
        try replayFile("long_cjk.txt")
    }

    func testEmojiTest() throws {
        // Its first 192 KB (the whole file is 386 KB).
        try replayFile("emoji-test.txt", maxBytes: 192 * 1024)
    }

    func testZalgo() throws {
        try replayFile("zalgo.txt")
    }

    func testUTF8Demo() throws {
        try replayFile("UTF-8-demo.txt")
    }

    func testTwentyFourBitColors() throws {
        try replayFile("slow_24bit_colors.txt")
    }

    func testSixel() throws {
        try replayFile("snake.six")
    }

    func testSixelWithEightBitDCS() throws {
        try replayFile("c1_dcs_sixel.txt")
    }

    /// Kitty graphics as tests/transmitAndDisplay-kitty.txt sends them (a PNG transmitted and
    /// displayed with a=T in 4096-byte chunks, m=1 on all but the last), with a small image so the
    /// test stays fast, then placements of the same image with extreme sizes and offsets.
    func testKittyGraphics() throws {
        let png = try XCTUnwrap(Self.pngData(width: 64, height: 48))
        let base64 = Array(png.base64EncodedString().utf8)
        let chunkSize = 4096
        var bytes = [UInt8]()
        var start = 0
        var first = true
        while start < base64.count {
            let end = min(base64.count, start + chunkSize)
            let more = end < base64.count ? 1 : 0
            let control = first ? "a=T,i=77,q=2,f=100,m=\(more)" : "m=\(more)"
            bytes += Array("\u{1B}_G\(control);".utf8) + base64[start..<end] + Array("\u{1B}\\".utf8)
            first = false
            start = end
        }
        for p in bigParameters {
            for keys in ["c=\(p),r=\(p)", "c=\(p)", "r=\(p)", "X=\(p),Y=\(p)", "x=\(p),y=\(p),w=\(p),h=\(p)",
                         "z=\(p)", "C=1,c=\(p),r=\(p)", "p=\(p)"] {
                bytes += Array("\u{1B}_Ga=p,i=77,q=2,\(keys)\u{1B}\\x".utf8)
            }
        }
        bytes += Array("\u{1B}_Ga=d,d=A,q=2\u{1B}\\".utf8)
        replay(bytes)
    }

    // MARK: - Extremes

    /// The largest parameter the CSI parser stores is 2147483639 (it refuses to go past
    /// (INT_MAX - 10) / 10 before the last digit); 2147483647 and longer numbers are kept as
    /// unrecognized. Each sequence is followed by a character so the result is written.
    private let bigParameters = ["2147483639", "2147483647", "4294967295", "99999999999999999999", "65535", "65536", "0"]

    /// CHT (CSI n I) and CBT (CSI n Z) loop n times with no cap, so a count near 2^31 keeps the
    /// token executor busy for minutes (bugs.md, "CHT and CBT loop once per count"). Until that
    /// is fixed they get only the counts that finish quickly.
    private func countIsSafeForTabLoops(_ p: String) -> Bool {
        guard let n = Int(p) else {
            return false
        }
        return n <= 65536
    }

    func testCursorMovementWithHugeCounts() {
        var bytes = ""
        for p in bigParameters {
            for final in ["A", "B", "C", "D", "E", "F", "G", "d", "`", "a", "e"] {
                bytes += "\u{1B}[\(p)\(final)x"
            }
            if countIsSafeForTabLoops(p) {
                bytes += "\u{1B}[\(p)Ix\u{1B}[\(p)Zx"
            }
            bytes += "\u{1B}[\(p);\(p)Hx\u{1B}[\(p);\(p)fx"
            bytes += "\u{1B}[H"
        }
        replay(Array(bytes.utf8))
    }

    /// The cursor is put at column 5 (x = 4) before each sequence. ICH (CSI n @), DCH (CSI n P),
    /// DECIC and DECDC overflow `int` from x = 9 with the largest counts and then pass a size near
    /// 2^64 to memmove (bugs.md, "ICH, DCH, DECIC and DECDC with a huge count"), so until that is
    /// fixed they get huge counts only at columns where the sum still fits. Do not move this
    /// cursor position right, and do not add DECIC or DECDC with these counts, until then.
    func testEditingWithHugeCounts() {
        var bytes = ""
        for p in bigParameters {
            // REP (CSI n b) is left to testRepeatPreviousCharacterAtItsCap.
            for final in ["@", "P", "X", "L", "M", "S", "T", "J", "K", " @", " A"] {
                bytes += "abc\u{1B}[5;5H\u{1B}[\(p)\(final)y"
            }
        }
        replay(Array(bytes.utf8))
    }

    func testScrollRegionsAndMarginsWithHugeValues() {
        var bytes = "\u{1B}[?69h"  // DECLRMM, so DECSLRM applies
        for p in bigParameters {
            bytes += "\u{1B}[1;\(p)r\u{1B}[\(p);\(p)r\u{1B}[\(p)rtext\r\n"
            bytes += "\u{1B}[1;\(p)s\u{1B}[\(p);\(p)s\u{1B}[\(p)stext\r\n"
            bytes += "\u{1B}[\(p)S\u{1B}[\(p)T\u{1B}[\(p)L\u{1B}[\(p)M"
            bytes += "\u{1B}[r\u{1B}[s"
        }
        bytes += "\u{1B}[?69l"
        replay(Array(bytes.utf8))
    }

    func testRectangleOperationsWithHugeValues() {
        var bytes = ""
        for p in bigParameters {
            bytes += "\u{1B}[65;\(p);\(p);\(p);\(p)$x"         // DECFRA
            bytes += "\u{1B}[1;1;\(p);\(p)$x"
            bytes += "\u{1B}[\(p);\(p);\(p);\(p)$z"            // DECERA
            bytes += "\u{1B}[\(p);\(p);\(p);\(p)${"            // DECSERA
            bytes += "\u{1B}[\(p);\(p);\(p);\(p);1;\(p);\(p);1$v"  // DECCRA
            bytes += "\u{1B}[1;1;\(p);\(p);7$r"                 // DECCARA
            bytes += "\u{1B}[1;1;\(p);\(p);7$t"                 // DECRARA
            bytes += "\u{1B}[\(p);1;1;\(p);\(p)*y"              // DECRQCRA
        }
        replay(Array(bytes.utf8))
    }

    func testTabStopsAndModesWithHugeValues() {
        var bytes = ""
        for p in bigParameters {
            bytes += "\u{1B}[\(p)g\tx"
            if countIsSafeForTabLoops(p) {
                bytes += "\u{1B}[\(p)I\u{1B}[\(p)Zx"
            }
            bytes += "\u{1B}[?\(p)h\u{1B}[?\(p)l\u{1B}[\(p)h\u{1B}[\(p)l"
            bytes += "\u{1B}[?\(p)$p\u{1B}[\(p)$p"                  // DECRQM
            bytes += "\u{1B}[\(p) q\u{1B}[\(p)\"p\u{1B}[\(p)\"q"     // DECSCUSR, DECSCL, DECSCA
            bytes += "\u{1B}[\(p);\(p)t\u{1B}[8;\(p);\(p)t\u{1B}[4;\(p);\(p)t"  // XTWINOPS
            bytes += "\u{1B}[3;\(p);\(p)t\u{1B}[22;\(p)t\u{1B}[23;\(p)t"
            bytes += "\u{1B}[\(p)n\u{1B}[?\(p)n\u{1B}[\(p)c\u{1B}[>\(p)c"
            bytes += "\u{1B}[\(p)x\u{1B}[\(p)u"                     // DECREQTPARM, kitty keyboard
            bytes += "\u{1B}[>\(p)u\u{1B}[<\(p)u\u{1B}[=\(p);\(p)u"
            bytes += "\u{1B}[>\(p);\(p)m\u{1B}[>\(p)n"               // XTMODKEYS
            bytes += "\u{1B}[\(p)*x\u{1B}[\(p),|"
        }
        bytes += "\u{1B}[?1049l\u{1B}[0 q\u{1B}[H"
        replay(Array(bytes.utf8))
    }

    func testSGRWithHugeValues() {
        var bytes = ""
        for p in bigParameters {
            bytes += "\u{1B}[\(p)mx"
            bytes += "\u{1B}[38;5;\(p)mx\u{1B}[48;5;\(p)mx\u{1B}[58;5;\(p)mx"
            bytes += "\u{1B}[38;2;\(p);\(p);\(p)mx\u{1B}[48;2;\(p);\(p);\(p)mx"
            bytes += "\u{1B}[38:2::\(p):\(p):\(p)mx\u{1B}[38:5:\(p)mx\u{1B}[4:\(p)mx"
            bytes += "\u{1B}[" + Array(repeating: p, count: 40).joined(separator: ";") + "mx"
            bytes += "\u{1B}[" + Array(repeating: p, count: 40).joined(separator: ":") + "mx"
        }
        bytes += "\u{1B}[0m"
        replay(Array(bytes.utf8))
    }

    func testOSCWithHugeValues() {
        var bytes = ""
        for p in bigParameters {
            bytes += "\u{1B}]4;\(p);rgb:ff/00/00\u{07}\u{1B}]4;\(p);?\u{07}"
            bytes += "\u{1B}]104;\(p)\u{07}\u{1B}]5;\(p);rgb:00/ff/00\u{07}"
            bytes += "\u{1B}]\(p);x\u{07}"
            bytes += "\u{1B}]1337;SetMark=\(p)\u{07}\u{1B}]1337;CursorShape=\(p)\u{07}"
            bytes += "\u{1B}]1337;SetColors=fg=\(p)\u{07}"
            bytes += "\u{1B}]133;D;\(p)\u{07}\u{1B}]133;A;aid=\(p)\u{07}\u{1B}]133;D;\(p);aid=\(p)\u{07}"
            bytes += "\u{1B}]8;id=\(p);https://example.com/\(p)\u{1B}\\link\u{1B}]8;;\u{1B}\\"
            bytes += "\u{1B}]9;4;1;\(p)\u{07}\u{1B}]9;4;\(p);\(p)\u{07}"
            bytes += "\u{1B}]22;\(p)\u{07}\u{1B}]12;rgb:\(p)/\(p)/\(p)\u{07}"
        }
        replay(Array(bytes.utf8))
    }

    /// 80,000 characters with no newline: 1,000 wrapped rows in one logical line.
    func testOneVeryLongLine() {
        replay(Array(repeating: UInt8(ascii: "x"), count: 80_000))
    }

    /// 15,000 double-width characters on one logical line, so every row ends with a
    /// double-width character pushed to the next row or a spacer.
    func testOneVeryLongLineOfDoubleWidthCharacters() {
        replay(Array(String(repeating: "漢", count: 15_000).utf8))
    }

    /// Hundreds of combining marks on a single base character.
    func testCombiningMarksOnOneCell() {
        replay(Array(("e" + String(repeating: "\u{0301}", count: 500) + "\r\n").utf8))
    }

    /// Many short lines, so the scrollback holds many lines and blocks.
    func testManyLines() {
        var bytes = [UInt8]()
        bytes.reserveCapacity(20_000 * 3)
        for i in 0..<20_000 {
            bytes.append(UInt8(ascii: "0") + UInt8(i % 10))
            bytes.append(13)
            bytes.append(10)
        }
        replay(bytes)
    }

    /// REP repeats the previous character up to 65535 times (VT100Terminal caps the count).
    func testRepeatPreviousCharacterAtItsCap() {
        var bytes = ""
        // Every count above the cap repeats 65535 times, so one of them is enough.
        for p in ["2147483639", "65536", "65535", "0"] {
            bytes += "a\u{1B}[\(p)b漢\u{1B}[\(p)b\r\n"
        }
        replay(Array(bytes.utf8))
    }

    // MARK: - Helpers

    private static func pngData(width: Int, height: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: width,
                                         pixelsHigh: height,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            return nil
        }
        for y in 0..<height {
            for x in 0..<width {
                rep.setColor(NSColor(deviceRed: CGFloat(x) / CGFloat(width),
                                     green: CGFloat(y) / CGFloat(height),
                                     blue: 0.5,
                                     alpha: 1),
                             atX: x,
                             y: y)
            }
        }
        return rep.representation(using: .png, properties: [:])
    }

    /// Replays the file, or its first maxBytes bytes. A prefix may end inside an escape or UTF-8
    /// sequence, as a pty read can.
    private func replayFile(_ name: String,
                            maxBytes: Int = .max,
                            file: StaticString = #filePath,
                            line: UInt = #line) throws {
        // tests/ is not bundled with the test host, so resolve it relative to this source file.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ModernTests/
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("tests")
            .appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0, file: file, line: line)
        replay([UInt8](data.prefix(maxBytes)), file: file, line: line)
    }

    /// Feeds bytes as the pty would, in reads of an odd size so that escape sequences and UTF-8
    /// sequences are split across reads, and waits for each read to execute before the next so
    /// the token executor's budget never fills.
    private func replay(_ bytes: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
        let harness = TerminalTestHarness(width: width, height: height)
        let readSize = 4093
        var start = 0
        while start < bytes.count {
            let end = min(bytes.count, start + readSize)
            harness.send(Array(bytes[start..<end]))
            harness.sync(file: file, line: line)
            start = end
        }
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            guard let grid = mutableState.currentGrid as VT100Grid? else {
                XCTFail("No grid", file: file, line: line)
                return
            }
            XCTAssertGreaterThanOrEqual(grid.cursorX, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(grid.cursorX, grid.size.width, file: file, line: line)
            XCTAssertGreaterThanOrEqual(grid.cursorY, 0, file: file, line: line)
            XCTAssertLessThan(grid.cursorY, grid.size.height, file: file, line: line)
        })
    }
}
