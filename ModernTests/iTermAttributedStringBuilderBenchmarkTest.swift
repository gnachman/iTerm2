import XCTest
@testable import iTerm2SharedARC

// Deterministic, app-free benchmark of the per-row attributed-string build (the
// path taken when ligatures or bidi are on). Used to measure optimizations like
// attribute-dictionary interning.
//
// This is a benchmark, not a pass/fail perf gate: wall-clock thresholds would be
// flaky, so it asserts only that work happened and logs timings. Run with the
// diagnostics-free plan and optimization on:
//   xcodebuild test -scheme ModernTests -configuration Development \
//     -testPlan Benchmark -enableAddressSanitizer NO \
//     GCC_OPTIMIZATION_LEVEL=s SWIFT_OPTIMIZATION_LEVEL=-O \
//     -only-testing:ModernTests/iTermAttributedStringBuilderBenchmarkTest
final class iTermAttributedStringBuilderBenchmarkTest: XCTestCase {
    // A maximized display: ~250 cols x 80 rows = 20k cells.
    private let width: Int32 = 250
    private let height: Int32 = 80

    // Override with ASBBENCH_ITERATIONS (via TEST_RUNNER_ASBBENCH_ITERATIONS) to
    // lengthen a run for profiling in Instruments.
    private var iterations: Int32 {
        if let s = ProcessInfo.processInfo.environment["ASBBENCH_ITERATIONS"],
           let v = Int32(s), v > 0 {
            return v
        }
        return 60
    }

    private func run(_ scheme: iTermASBBenchColorScheme,
                     nativeColorSpace: Bool = true,
                     ligatures: Bool = false,
                     threads: Int32 = 1,
                     label: String) {
        let bench = iTermAttributedStringBuilderBenchmark(width: width, height: height)
        bench.nativeColorSpace = nativeColorSpace
        bench.ligatures = ligatures
        let seconds = bench.run(with: scheme, iterations: iterations, threads: threads)
        let msPerFrame = seconds * 1000.0 / Double(iterations)
        let fps = msPerFrame > 0 ? 1000.0 / msPerFrame : 0
        print(String(format: "[ASBBench] %-34@  %7.2f ms/frame  (%5.1f fps)  [%dx%d, %d frames]",
                     label as NSString, msPerFrame, fps, width, height, iterations))
        XCTAssertGreaterThan(seconds, 0)
    }

    func testBenchmarkMono() {
        run(.mono, label: "mono (default fg)")
    }

    func testBenchmarkAnsi() {
        run(.ansi, label: "ansi per-cell")
    }

    func testBenchmarkTrueColorNativeSpace() {
        run(.trueColor, label: "truecolor, native space")
    }

    func testBenchmarkTrueColorNonNativeSpace() {
        run(.trueColor, nativeColorSpace: false, label: "truecolor, ColorSync convert")
    }

    func testBenchmarkTrueColorLigatures() {
        run(.trueColor, ligatures: true, label: "truecolor, ligatures on")
    }
}
