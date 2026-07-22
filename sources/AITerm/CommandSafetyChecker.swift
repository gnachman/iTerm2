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
    @objc public static func check() -> Bool {
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
