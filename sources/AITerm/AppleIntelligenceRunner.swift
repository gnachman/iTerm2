//
//  AppleIntelligenceRunner.swift
//  iTerm2
//
//  Runs a one-shot, non-streaming completion against Apple's on-device
//  Foundation Models. This is the implementation behind the
//  `.appleIntelligence` AI backend, which AITermController dispatches to
//  directly rather than building an HTTP request (Apple Intelligence has no
//  wire format). Feature-limited on purpose: no streaming, tool calling, or
//  attachments. See AISafetyClassifierBackend for the main caller.
//

import Foundation
import FoundationModels

@available(macOS 26, *)
enum AppleIntelligenceRunner {
    /// Sends `system` as the session instructions and `user` as the prompt,
    /// returning the model's text. `maxTokens` is accepted for parity with the
    /// HTTP backends but is advisory here: the on-device session manages its
    /// own response length, and classification replies are short.
    static func complete(system: String?, user: String, maxTokens: Int) async throws -> String {
        let session = LanguageModelSession(model: .default,
                                           instructions: system ?? "")
        return try await session.respond(to: user).content
    }
}
