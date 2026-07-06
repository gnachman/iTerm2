//
//  CompanionHistoryWindow.swift
//  iTerm2
//
//  Absolute, overflow-adjusted line addressing for scrollback browsing. Lines are
//  identified by an absolute number that never changes as scrollback grows or is
//  trimmed, so cached history tiles stay valid: a tile keyed by an absolute line
//  range refers to the same content regardless of how many lines have since
//  scrolled off the top.
//
//  A window is the currently-available span: [firstAbsLine, firstAbsLine +
//  lineCount). firstAbsLine equals the session's total scrollback overflow (the
//  count of lines that have scrolled off), so it only ever increases. Requests are
//  clamped to the window, and the response reports the range actually covered plus
//  the current firstAbsLine, which lets the phone resolve eviction races (it asked
//  for lines that were trimmed before the host rendered them) deterministically.
//
//  Pure and dependency-free so it can be unit-tested directly.
//

import Foundation

struct CompanionHistoryWindow: Equatable {
    /// Oldest available absolute line (== total scrollback overflow). Monotonic.
    let firstAbsLine: Int64
    /// Number of lines currently available from firstAbsLine.
    let lineCount: Int

    init(firstAbsLine: Int64, lineCount: Int) {
        self.firstAbsLine = firstAbsLine
        self.lineCount = max(0, lineCount)
    }

    /// One past the newest available absolute line.
    var endAbsLine: Int64 { firstAbsLine + Int64(lineCount) }

    /// Whether an absolute line is currently available (not yet evicted, in range).
    func contains(absLine: Int64) -> Bool {
        absLine >= firstAbsLine && absLine < endAbsLine
    }

    /// The buffer-relative index of an absolute line, or nil if it is outside the
    /// window (evicted off the top, or beyond the end).
    func relativeLine(forAbs absLine: Int64) -> Int? {
        guard contains(absLine: absLine) else { return nil }
        return Int(absLine - firstAbsLine)
    }

    /// The absolute line for a buffer-relative index.
    func absLine(forRelative relative: Int) -> Int64 {
        firstAbsLine + Int64(relative)
    }

    /// Clamp an absolute request [absLine, absLine + count) to the window. Returns
    /// the covered absolute range, or nil if it does not overlap the window at all
    /// (e.g. an entirely-evicted request).
    func clamped(absLine: Int64, count: Int) -> (absLine: Int64, count: Int)? {
        guard count > 0 else { return nil }
        let start = max(absLine, firstAbsLine)
        let end = min(absLine + Int64(count), endAbsLine)
        guard end > start else { return nil }
        return (start, Int(end - start))
    }
}
