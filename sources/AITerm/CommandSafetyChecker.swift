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
    static func check(_ command: String) async -> Bool {
        DLog("Check safety of command: \(command)")
        let rules = TerminalHardRules()
        var classifier = AutoModeClassifier(chat: AISafetyClassifierBackend(entries: []),
                                            rules: AutoModeRules())
        classifier.hardRules = rules.evaluate
        do {
            let decision = try await classifier.classify(
                action: .toolCall(name: "RunShellCommand", input: command),
                inTUI: false)
            switch decision {
            case .allow:
                RLog("For '\(command)' classifier says: allow -> SAFE")
                return true
            case .needsManualApproval(let reason):
                RLog("For '\(command)' classifier says: needsManualApproval (\(reason)) -> unsafe")
                return false
            case .block(let reason):
                RLog("For '\(command)' classifier says: block (\(reason)) -> unsafe")
                return false
            case .unparseable:
                RLog("For '\(command)' classifier returned unparseable -> unsafe")
                return false
            }
        } catch {
            RLog("Error checking command '\(command)': \(error) - treating as unsafe")
            return false
        }
    }
}
