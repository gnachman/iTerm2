//
//  PerformanceCounter.swift
//  iTerm2
//
//  Created by George Nachman on 6/10/25.
//

class PerformanceCounter<Op: Hashable & Comparable & CustomStringConvertible> {
    struct Operations {
        fileprivate var didComplete: (Op) -> ()
        func complete(_ op: Op) { didComplete(op) }
    }

    private var histograms = [Op: iTermHistogram]()

    init() {
    }

    func perform<Value>(_ operation: Op, closure: () async throws -> (Value)) async throws -> Value {
        let (result, duration) = await mesuareElapsedTime(closure)
        add(operation: operation, duration: duration)
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    func perform<Value>(_ operation: Op, closure: () async -> (Value)) async -> Value {
        let (value, duration) = await mesuareElapsedTime(closure)
        add(operation: operation, duration: duration)
        return value
    }

    func perform<Value>(_ operation: Op, closure: () throws -> (Value)) throws -> Value {
        let (result, duration) = mesuareElapsedTime(closure)
        add(operation: operation, duration: duration)
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    func perform<Value>(_ operation: Op, closure: () -> (Value)) -> Value {
        let (value, duration) = mesuareElapsedTime(closure)
        add(operation: operation, duration: duration)
        return value
    }

    private func add(operation: Op, duration: TimeInterval) {
        let histogram = histograms.getOrCreate(for: operation) {
            iTermHistogram()
        }
        histogram.addValue(duration)
    }

    func start(_ operations: [Op]) -> Operations {
        var startTime = NSDate.it_timeSinceBoot()
        var remaining = operations
        return Operations { [weak self] completedOp in
            let stopTime = NSDate.it_timeSinceBoot()
            guard let i = remaining.firstIndex(of: completedOp) else {
                return
            }
            remaining.remove(at: i)
            self?.add(operation: completedOp, duration: stopTime - startTime)
            startTime = NSDate.it_timeSinceBoot()
        }
    }

    func log() {
        let millisWidth = 7

        // Header
        let avgPadding = String(repeating: " ", count: millisWidth - 1)
        let pPadding = String(repeating: " ", count: millisWidth - 3)

        print(String(
            format: "%-20@    %@µ      N  %@p50  %@p75  %@p95 [min  distribution  max]",
            "Statistic",
            avgPadding,
            pPadding,
            pPadding,
            pPadding))

        let dash20 = String(repeating: "-", count: 20)
        let dashAvg = String(repeating: "-", count: millisWidth - 1)
        let dashP = String(repeating: "-", count: millisWidth - 3)

        print("\(dash20)    \(dashAvg)-  -----  \(dashP)---  \(dashP)---  \(dashP)--- ------------------------")

        // Body

        func formatMillis(_ ms: Double) -> String {
            let numeric = String(format: "%.1fms", ms)
            let padding = String(repeating: " ", count: millisWidth - numeric.count)
            return padding + numeric
        }

        objc_sync_enter(iTermPreciseTimersLock.self)
        defer {
            objc_sync_exit(iTermPreciseTimersLock.self)
        }

        for op in histograms.keys.sorted() {
            guard let hist = histograms[op] else {
                continue
            }
            if hist.count == 0 {
                continue
            }

            let mean = hist.mean * 1000
            let p50 = hist.value(atNTile: 0.50)
            let p75 = hist.value(atNTile: 0.75)
            let p95 = hist.value(atNTile: 0.95)

            let emoji = iTermEmojiForDuration(p75)!
            let name = op.description
            let sparkline = hist.sparklineGraph(withPrecision: 2, multiplier: 1, units: "ms")
            let namePadding = String(repeating: " ", count: 20 - name.count)
            print(String(format: "%@ %@%@ %@  %5d  %@  %@  %@ [%@]",
                         emoji,
                         namePadding,
                         name,
                         formatMillis(mean),
                         hist.count,
                         formatMillis(p50),
                         formatMillis(p75),
                         formatMillis(p95),
                         sparkline))
        }
        print()
    }
}

func mesuareElapsedTime<Value>(_ closure: () async throws -> (Value)) async -> (Result<Value, Error>, TimeInterval) {
    let start = NSDate.it_timeSinceBoot()
    do {
        let result = try await closure()
        return (.success(result), NSDate.it_timeSinceBoot() - start)
    } catch {
        return (.failure(error), NSDate.it_timeSinceBoot() - start)
    }
}

func mesuareElapsedTime<Value>(_ closure: () async -> (Value)) async -> (Value, TimeInterval) {
    let start = NSDate.it_timeSinceBoot()
    let result = await closure()
    return (result, NSDate.it_timeSinceBoot() - start)
}

func mesuareElapsedTime<Value>(_ closure: () throws -> (Value)) -> (Result<Value, Error>, TimeInterval) {
    let start = NSDate.it_timeSinceBoot()
    do {
        let result = try closure()
        return (.success(result), NSDate.it_timeSinceBoot() - start)
    } catch {
        return (.failure(error), NSDate.it_timeSinceBoot() - start)
    }
}

func mesuareElapsedTime<Value>(_ closure: () -> (Value)) -> (Value, TimeInterval) {
    let start = NSDate.it_timeSinceBoot()
    let result = closure()
    return (result, NSDate.it_timeSinceBoot() - start)
}
