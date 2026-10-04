//
//  TmuxDroppedOutputScanner.swift
//  iTerm2
//
//  Created by George Nachman on 10/3/26.
//

import Foundation

// Output for a tmux pane that has no session yet (e.g., while its window is being opened) is
// discarded because its effect on the screen is recovered from tmux's capture-pane snapshot.
// Some control sequences change state that only iTerm2 keeps, so the snapshot can't recover
// them. This parses the discarded output and remembers the last instance of each such sequence so
// they can be executed once the session exists. See issue 13006.
@objc(iTermTmuxDroppedOutputScanner)
class TmuxDroppedOutputScanner: NSObject {
    // Keys of OSC 1337 sequences whose effect would otherwise be lost. Each must be safe to
    // execute late, at the prompt line of a freshly created session, with only its last value.
    private static let whitelist: Set<String> = [
        "SetUserVar",
        "RemoteHost",
        "CurrentDir",
        "ShellIntegrationVersion"
    ]

    private let parser: VT100Parser
    private var captured = [(key: String, token: VT100Token)]()

    override init() {
        parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        super.init()
    }

    // The coalesced tokens in the order their last instance arrived.
    @objc var tokens: [VT100Token] {
        return captured.map { $0.token }
    }

    @objc(consumeData:)
    func consume(_ data: Data) {
        if parser.streamLength == 0 && !Self.dataMayBeginSequence(data) {
            // Nothing in progress and no sequence can begin here.
            return
        }
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.baseAddress else {
                return
            }
            parser.putStreamData(base.assumingMemoryBound(to: CChar.self),
                                 length: Int32(buffer.count))
        }
        var vector = CVector()
        CVectorCreate(&vector, 100)
        _ = parser.addParsedTokens(to: &vector)
        for i in 0..<CVectorCount(&vector) {
            let token = CVectorGetObject(&vector, i) as! VT100Token
            if let key = Self.coalescingKey(token) {
                captured.removeAll { $0.key == key }
                captured.append((key: key, token: token))
                DLog("Captured \(key) from output for a pane without a session")
            }
        }
        CVectorReleaseObjectsAndDestroy(vector)
    }

    // Returns false if `data` can't contain the start of a control sequence.
    @objc(dataMayBeginSequence:)
    static func dataMayBeginSequence(_ data: Data) -> Bool {
        return data.contains(UInt8(VT100CC_ESC.rawValue))
    }

    private static func coalescingKey(_ token: VT100Token) -> String? {
        guard token.type == XTERMCC_SET_KVP,
              let key = token.kvpKey,
              whitelist.contains(key) else {
            return nil
        }
        if key == "SetUserVar" {
            // Each user variable is independent. The value is name=base64 or just name to unset.
            let value = token.kvpValue ?? ""
            let name = value.split(separator: "=",
                                   maxSplits: 1,
                                   omittingEmptySubsequences: false).first ?? ""
            return key + "=" + name
        }
        return key
    }
}

// Decides which panes' dropped output is worth scanning and owns their scanners. Only panes about
// to get a new session are scanned. Output for panes in hidden windows is ignored.
@objc(iTermTmuxDroppedOutputTracker)
class TmuxDroppedOutputTracker: NSObject {
    private var scanners = [Int32: TmuxDroppedOutputScanner]()
    // Panes whose window opener is fetching their state. A pane could be in more than one opener.
    private var panesBeingOpened = [Int32: Int]()
    // Windows announced by %window-add whose layouts haven't been fetched yet.
    private var windowsAwaitingLayout = [Int32: Int]()
    // The largest pane ID in any layout seen so far, excluding windows awaiting layout.
    private var maxKnownPane: Int32 = -1

    @objc(didDropOutput:pane:)
    func didDropOutput(_ data: Data, pane: Int32) {
        guard shouldScan(pane) else {
            return
        }
        if let scanner = scanners[pane] {
            scanner.consume(data)
            return
        }
        if !TmuxDroppedOutputScanner.dataMayBeginSequence(data) {
            return
        }
        let scanner = TmuxDroppedOutputScanner()
        scanners[pane] = scanner
        scanner.consume(data)
    }

    // Returns the captured tokens for the pane and forgets them.
    @objc(takeTokensForPane:)
    func takeTokens(pane: Int32) -> [VT100Token] {
        return scanners.removeValue(forKey: pane)?.tokens ?? []
    }

    // Discards anything captured for the pane, such as when it gets a session by another route.
    @objc(forgetPane:)
    func forget(pane: Int32) {
        scanners.removeValue(forKey: pane)
    }

    @objc(willOpenPane:)
    func willOpenPane(_ pane: Int32) {
        panesBeingOpened[pane, default: 0] += 1
    }

    @objc(didFinishOpeningPanes:)
    func didFinishOpeningPanes(_ panes: [NSNumber]) {
        for pane in panes.map({ $0.int32Value }) {
            guard let count = panesBeingOpened[pane] else {
                continue
            }
            if count > 1 {
                panesBeingOpened[pane] = count - 1
            } else {
                panesBeingOpened.removeValue(forKey: pane)
            }
        }
        discardUnneededScanners()
    }

    @objc(windowWillAwaitLayout:)
    func windowWillAwaitLayout(_ window: Int32) {
        windowsAwaitingLayout[window, default: 0] += 1
    }

    @objc(windowDidStopAwaitingLayout:)
    func windowDidStopAwaitingLayout(_ window: Int32) {
        guard let count = windowsAwaitingLayout[window] else {
            return
        }
        if count > 1 {
            windowsAwaitingLayout[window] = count - 1
        } else {
            windowsAwaitingLayout.removeValue(forKey: window)
        }
        discardUnneededScanners()
    }

    // Call with the panes of every layout received, including those of hidden windows.
    @objc(didLearnPanes:window:)
    func didLearnPanes(_ panes: [NSNumber], window: Int32) {
        if windowsAwaitingLayout[window] != nil {
            // Its panes are learned when it stops awaiting its layout and its opener has
            // registered the panes it will open.
            return
        }
        for pane in panes {
            maxKnownPane = max(maxKnownPane, pane.int32Value)
        }
        discardUnneededScanners()
    }

    @objc
    func reset() {
        scanners.removeAll()
        panesBeingOpened.removeAll()
        windowsAwaitingLayout.removeAll()
        maxKnownPane = -1
    }

    private func shouldScan(_ pane: Int32) -> Bool {
        if panesBeingOpened[pane] != nil {
            return true
        }
        // A window was just added and its panes aren't known yet. tmux never reuses pane IDs, so
        // a pane newer than every known layout is in the new window, not a hidden one.
        return !windowsAwaitingLayout.isEmpty && pane > maxKnownPane
    }

    private func discardUnneededScanners() {
        for pane in scanners.keys where !shouldScan(pane) {
            scanners.removeValue(forKey: pane)
        }
    }
}
