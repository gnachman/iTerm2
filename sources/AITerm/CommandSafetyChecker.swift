//
//  CommandSafetyChecker.swift
//  iTerm2
//
//  Created by George Nachman on 11/5/25.
//

import Foundation
import FoundationModels

@objc(iTermAIAvailabilityProbe)
public final class AIAvailabilityProbe: NSObject {
    // An always-fresh read of Apple Intelligence availability. This is what the
    // security/migration callers use (the on-device command-safety classifier, the
    // "switch away from Apple Intelligence" prompt, and the migration helper): they
    // must see the true current availability, not a value up to 10s stale, so that
    // enabling/disabling Apple Intelligence takes effect immediately on those paths.
    @objc public static func check() -> Bool {
        return uncachedCheck()
    }

    // Availability changes only rarely (the user toggles Apple Intelligence in System
    // Settings, or a model download completes - none of which post an app notification
    // we could observe), yet the AI-tab-title feature queries it on hot paths: once
    // per OSC 0/1/2 title update for AI profiles (programs that animate their title
    // emit many per second) and once per generation attempt. checkCached() caches the
    // result for a few seconds so those hot paths do not run a model-availability
    // query per frame, while a system-level change is still picked up within the TTL.
    // Scoped to the title paths deliberately: the fresh check() above keeps the
    // security-sensitive callers exact. The lock guards concurrent callers.
    private static let cacheTTL: TimeInterval = 10
    private static let lock = NSLock()
    private static var cachedResult: Bool?
    private static var cachedAt: TimeInterval = 0

    @objc public static func checkCached() -> Bool {
        // Monotonic clock: a short TTL must not be pinned by a backward wall-clock
        // jump (NTP correction, manual change) that makes now - cachedAt negative and
        // therefore always < TTL. systemUptime never goes backward.
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if let cached = cachedResult, now - cachedAt < cacheTTL {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Compute outside the lock; the availability read has no need of mutual
        // exclusion and we don't want to hold the lock across it.
        let result = uncachedCheck()

        lock.lock()
        cachedResult = result
        // Stamp with a FRESH read taken AFTER the query, not the pre-query `now`: the
        // value was produced at ~now + query-duration, so stamping the older `now` ages
        // the cache by that duration and re-runs the availability query marginally more
        // often than the 10s TTL intends.
        cachedAt = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        return result
    }

    private static func uncachedCheck() -> Bool {
        if #available(macOS 26, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return true
            case .unavailable(.appleIntelligenceNotEnabled):
                return false
            case .unavailable(.deviceNotEligible):
                return false
            case .unavailable(.modelNotReady):
                return false
            case .unavailable:
                return false
            }
        }
        return false
    }
}

class CommandSafetyChecker {
    // Returns true if the command is safe to run automatically. Delegates to
    // AutoModeClassifier: deterministic TerminalHardRules run first, falling
    // through to a one-shot LLM side-query. The side-query runs against the
    // cheaper same-vendor economy model when one is available, else the
    // configured conversation model (a cloud provider for most users), or
    // against on-device Apple Intelligence for users grandfathered in under
    // the old free path who declined to switch (see AISafetyClassifierBackend).
    // Anything short of an unambiguous allow is treated as unsafe so the UI
    // prompts for manual approval; classification errors are fail-closed.
    // The single-command classifier: deterministic TerminalHardRules first,
    // falling through to the configured-model side-query. Shared with the
    // orchestrator's session_* safety gate (OrchestratorSafetyGate) so both
    // paths vet commands with identical rules and backend.
    //
    // `transcript` is recent chat history (projected by SafetyTranscript);
    // it lets the classifier see whether the user actually asked for a risky
    // command. `maxEntries` is deliberately lower than AutoModeClassifier's
    // 40 default: for a safety judgment a tight recent window is enough to
    // establish intent, and it cuts both token cost and the "implied
    // momentum" that a long transcript can use to push toward allow.
    // `applyTerminalHardRules` attaches the deterministic shell-line floor
    // (TerminalHardRules). Pass false for actions that are NOT shell command
    // lines -- e.g. a file write whose CONTENT would otherwise be scanned as a
    // shell line, hard-blocking any file that merely contains an ESC byte (a
    // .vimrc with colors), an `rm -rf` string, or a `sudo` line. Those rules
    // analyze command lines, not file bodies, so the file-write path judges the
    // action with the LLM alone (same reasoning as the TUI keystroke path).
    static func makeClassifier(transcript: [TranscriptEntry] = [],
                               maxEntries: Int = 15,
                               applyTerminalHardRules: Bool = true) -> AutoModeClassifier {
        var classifier = AutoModeClassifier(chat: AISafetyClassifierBackend(entries: transcript),
                                            rules: AutoModeRules())
        if applyTerminalHardRules {
            classifier.hardRules = TerminalHardRules().evaluate
        }
        classifier.maxTranscriptEntries = maxEntries
        return classifier
    }

    static func check(_ command: String, transcript: [TranscriptEntry] = []) async -> Bool {
        DLog("Check safety of command: \(command)")
        let classifier = makeClassifier(transcript: transcript)
        do {
            let decision = try await classifier.classify(
                action: .toolCall(name: "RunShellCommand", input: command),
                inTUI: false)
            switch decision {
            case .allow:
                RLog("For '\(redacted: command, or: "len=\(command.count)")' classifier says: allow -> SAFE")
                return true
            case .needsManualApproval(let reason):
                RLog("For '\(redacted: command, or: "len=\(command.count)")' classifier says: needsManualApproval (\(reason)) -> unsafe")
                return false
            case .block(let reason):
                RLog("For '\(redacted: command, or: "len=\(command.count)")' classifier says: block (\(reason)) -> unsafe")
                return false
            case .unparseable:
                RLog("For '\(redacted: command, or: "len=\(command.count)")' classifier returned unparseable -> unsafe")
                return false
            }
        } catch {
            RLog("Error checking command '\(redacted: command, or: "len=\(command.count)")': \(error) - treating as unsafe")
            return false
        }
    }
}
