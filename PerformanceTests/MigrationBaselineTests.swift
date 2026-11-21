//
//  MigrationBaselineTests.swift
//  PerformanceTests
//
//  Scenarios for the Objective-C to Swift migration's performance and memory
//  baselines (docs/swift-migration/phase0.md section 8). Each test prints one
//  line per metric, starting with "[MigrationPerf] " and followed by a JSON
//  object, which tools/swift_migration/perf_baseline.py collects. These are
//  measurements, not pass/fail gates: a wall-clock threshold here would be
//  flaky, so the tests assert only that work happened. Comparison against a
//  baseline is done by tools/swift_migration/perf_compare.py.
//
//  The number of samples per metric comes from MIGRATION_PERF_ITERATIONS
//  (default 10), which the runner sets in the test host's environment, along
//  with MIGRATION_PERF_OUTPUT, a file the lines are also appended to.
//

import XCTest
import iTerm2SharedARC

final class MigrationBaselineTests: XCTestCase {
    private var session = FakeSession()

    private var iterations: Int {
        if let s = ProcessInfo.processInfo.environment["MIGRATION_PERF_ITERATIONS"],
           let v = Int(s), v > 0 {
            return v
        }
        return 10
    }

    // MARK: - Reporting

    private func report(scenario: String,
                        metric: String,
                        unit: String,
                        better: String,
                        values: [Double]) {
        let object: [String: Any] = ["scenario": scenario,
                                     "metric": metric,
                                     "unit": unit,
                                     "better": better,
                                     "values": values]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            XCTFail("Could not encode a result for \(scenario)")
            return
        }
        let line = "[MigrationPerf] \(json)\n"
        print(line, terminator: "")
        // Newer Xcode does not show test output on xcodebuild's console, so the
        // runner also names a file to append to.
        if let path = ProcessInfo.processInfo.environment["MIGRATION_PERF_OUTPUT"], !path.isEmpty {
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            guard let handle = FileHandle(forWritingAtPath: path) else {
                XCTFail("Could not open \(path)")
                return
            }
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        }
    }

    private func seconds(_ block: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1e9
    }

    // MARK: - Workload

    // A fixed, deterministic byte stream of about 1 MB that resembles ordinary
    // terminal output: plain ASCII lines, lines with 256-color and 24-bit color
    // SGR changes, lines of CJK and emoji, and in-place edits with cursor
    // positioning and erase-in-line. No full-screen clears, so lines reach the
    // scrollback.
    private static let corpus: Data = {
        var s = ""
        s.reserveCapacity(1_100_000)
        let words = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta"]
        var line = 0
        while s.utf8.count < 1_000_000 {
            switch line % 8 {
            case 0, 1, 2:
                let ch = Character(UnicodeScalar(UInt8(33 + (line % 90))))
                s += String(repeating: ch, count: 78) + "\r\n"
            case 3:
                for (i, w) in words.enumerated() {
                    s += "\u{1b}[38;5;\((line + i) % 256)m\(w) "
                }
                s += "\u{1b}[0m\r\n"
            case 4:
                for (i, w) in words.enumerated() {
                    let r = (line * 7 + i * 31) % 256
                    let g = (line * 13 + i * 17) % 256
                    let b = (line * 3 + i * 29) % 256
                    s += "\u{1b}[38;2;\(r);\(g);\(b)m\(w)\u{1b}[48;2;\(b);\(r);\(g)m "
                }
                s += "\u{1b}[0m\r\n"
            case 5:
                s += "漢字かな混じり文 한국어 텍스트 😀👍🏽🇯🇵 e\u{301}x\u{308} done\r\n"
            case 6:
                s += "\u{1b}[\(1 + line % 40);\(1 + line % 60)Hupdated \(line)\u{1b}[K\r\n"
            default:
                s += "\u{1b}[1mbold\u{1b}[22m \u{1b}[4munderline\u{1b}[24m \u{1b}[7minverse\u{1b}[27m plain \(line)\r\n"
            }
            line += 1
        }
        return s.data(using: .utf8)!
    }()

    private static let chunkSize = 64 * 1024

    private func makeScreen(width: Int32, height: Int32, scrollback: UInt32) -> VT100Screen {
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session.asScreenDelegate
        XCTAssertEqual(FakeSession.missingScreenDelegateSelectors, [])
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.terminalEnabled = true
            mutableState.terminal!.termType = "xterm"
            screen.destructivelySetScreenWidth(width, height: height, mutableState: mutableState)
            mutableState.maxScrollbackLines = scrollback
        })
        return screen
    }

    // Parses `data` with the terminal's own parser and executes every token on
    // the screen, a chunk at a time, as the PTY reader and the mutation queue do.
    // Each chunk runs in its own autorelease pool, as each pass of the app's
    // read and execute loops does, so temporaries do not pile up across chunks.
    // Returns the number of tokens executed.
    @discardableResult
    private func parseAndExecute(_ data: Data, screen: VT100Screen) -> Int {
        var count = 0
        var offset = 0
        while offset < data.count {
            let end = min(offset + Self.chunkSize, data.count)
            autoreleasepool {
                screen.performBlock(joinedThreads: { _, mutableState, _ in
                    let terminal = mutableState.terminal!
                    data[offset..<end].withUnsafeBytes { raw in
                        let p = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
                        terminal.parser.putStreamData(p, length: Int32(raw.count))
                    }
                    var vector = CVector()
                    CVectorCreate(&vector, 1024)
                    _ = terminal.parser.addParsedTokens(to: &vector)
                    let n = Int(CVectorCount(&vector))
                    for i in 0..<n {
                        let token = CVectorGetObject(&vector, Int32(i)) as! VT100Token
                        terminal.execute(token)
                    }
                    count += n
                    CVectorReleaseObjects(&vector)
                    CVectorDestroy(&vector)
                })
            }
            offset = end
        }
        return count
    }

    // MARK: - Throughput

    // Parsing alone: bytes to tokens, with no screen.
    func testParseThroughput() {
        let data = Self.corpus
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        var samples = [Double]()
        var tokens = 0
        for _ in 0..<iterations {
            tokens = 0
            samples.append(seconds {
                var offset = 0
                while offset < data.count {
                    let end = min(offset + Self.chunkSize, data.count)
                    data[offset..<end].withUnsafeBytes { raw in
                        let p = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
                        parser.putStreamData(p, length: Int32(raw.count))
                    }
                    var vector = CVector()
                    CVectorCreate(&vector, 1024)
                    _ = parser.addParsedTokens(to: &vector)
                    tokens += Int(CVectorCount(&vector))
                    CVectorReleaseObjects(&vector)
                    CVectorDestroy(&vector)
                    offset = end
                }
            })
        }
        XCTAssertGreaterThan(tokens, 0)
        report(scenario: "parse.mixed_1mb", metric: "time", unit: "s", better: "lower", values: samples)
    }

    // Parsing and executing on a screen with a scrollback that is already full,
    // so every sample does the same work.
    func testParseAndExecuteThroughput() {
        let data = Self.corpus
        let screen = makeScreen(width: 120, height: 50, scrollback: 10_000)
        parseAndExecute(data, screen: screen)
        var samples = [Double]()
        var tokens = 0
        for _ in 0..<iterations {
            samples.append(seconds {
                tokens = parseAndExecute(data, screen: screen)
            })
        }
        XCTAssertGreaterThan(tokens, 0)
        report(scenario: "screen.parse_execute_mixed_1mb", metric: "time", unit: "s", better: "lower", values: samples)
    }

    // MARK: - Text drawing (CPU side)

    // The per-row attributed string build that text drawing does when ligatures
    // or bidi are on, over a 250x80 grid. Time per frame.
    private func attributedStringBuilder(_ scheme: iTermASBBenchColorScheme,
                                         ligatures: Bool,
                                         scenario: String) {
        let bench = iTermAttributedStringBuilderBenchmark(width: 250, height: 80)
        bench.ligatures = ligatures
        let framesPerSample: Int32 = 10
        var samples = [Double]()
        for _ in 0..<iterations {
            let total = bench.run(with: scheme, iterations: framesPerSample, threads: 1)
            XCTAssertGreaterThan(total, 0)
            samples.append(total * 1000.0 / Double(framesPerSample))
        }
        report(scenario: scenario, metric: "time_per_frame", unit: "ms", better: "lower", values: samples)
    }

    func testDrawAttributedStringsMono() {
        attributedStringBuilder(.mono, ligatures: false, scenario: "draw.attributed_strings_mono")
    }

    func testDrawAttributedStringsTrueColor() {
        attributedStringBuilder(.trueColor, ligatures: false, scenario: "draw.attributed_strings_truecolor")
    }

    func testDrawAttributedStringsTrueColorLigatures() {
        attributedStringBuilder(.trueColor, ligatures: true, scenario: "draw.attributed_strings_truecolor_ligatures")
    }

    // MARK: - Memory

    private struct MallocTotals {
        var blocks: Double
        var bytes: Double
    }

    private func mallocTotals() -> MallocTotals {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return MallocTotals(blocks: Double(stats.blocks_in_use), bytes: Double(stats.size_in_use))
    }

    private func footprint() -> (current: Double, peak: Double) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return (0, 0)
        }
        return (Double(info.phys_footprint), Double(info.ledger_phys_footprint_peak))
    }

    // The scripted memory workload: a fresh 120x50 screen with a 20,000-line
    // scrollback is filled with three passes of the corpus (about 36,000 lines,
    // so the scrollback fills and starts dropping lines, which is the steady
    // state of a long-running session), then released.
    //
    // Per sample it records the net change in the process's physical footprint
    // and in live malloc blocks and bytes from just before the screen is made
    // until its scrollback is full. These are net changes, not the screen's
    // cost: memory freed meanwhile (perhaps the previous sample's screen, which
    // seems to be freed lazily on its own queues; a hypothesis, not verified) is
    // subtracted, and in the first runs they were too noisy or too insensitive
    // to gate on, so perf_lib.py marks them informational. XCTest's memory
    // metric adds the peak physical memory during the fill, which is the usable
    // memory gate. What is left after the screen is released is not recorded,
    // for the same reason.
    func testMemoryScrollbackFill() {
        let data = Self.corpus
        var footprintGrowth = [Double]()
        var liveBlocks = [Double]()
        var liveBytes = [Double]()

        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()], options: options) {
            let mallocBefore = mallocTotals()
            let footprintBefore = footprint().current
            var screen: VT100Screen? = makeScreen(width: 120, height: 50, scrollback: 20_000)
            for _ in 0..<3 {
                parseAndExecute(data, screen: screen!)
            }
            stopMeasuring()
            let mallocFull = mallocTotals()
            footprintGrowth.append((footprint().current - footprintBefore) / 1024.0)
            liveBlocks.append(mallocFull.blocks - mallocBefore.blocks)
            liveBytes.append((mallocFull.bytes - mallocBefore.bytes) / 1024.0)
            autoreleasepool {
                session.screen = nil
                screen = nil
            }
        }
        XCTAssertFalse(liveBlocks.isEmpty)
        // XCTest runs one more iteration than it reports and discards the first;
        // discard it here too so these samples line up with XCTest's.
        if liveBlocks.count == iterations + 1 {
            footprintGrowth.removeFirst()
            liveBlocks.removeFirst()
            liveBytes.removeFirst()
        }
        let scenario = "memory.scrollback_fill_20k"
        report(scenario: scenario, metric: "footprint_growth", unit: "kB", better: "lower", values: footprintGrowth)
        report(scenario: scenario, metric: "live_malloc_blocks", unit: "count", better: "lower", values: liveBlocks)
        report(scenario: scenario, metric: "live_malloc_bytes", unit: "kB", better: "lower", values: liveBytes)
        report(scenario: scenario, metric: "process_peak_footprint", unit: "kB", better: "lower", values: [footprint().peak / 1024.0])
    }
}
