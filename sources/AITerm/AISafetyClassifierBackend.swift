//
//  AISafetyClassifierBackend.swift
//  iTerm2
//
//  Bridges AutoModeClassifier to the AITerm provider infrastructure. The
//  classifier is backend-agnostic; this adapter runs its one-shot side-query
//  as a non-streaming AIConversation completion. By default it uses the SAME
//  model and API key as the user's configured AI conversation. Users who were
//  grandfathered in under the free on-device path and declined to switch keep
//  using Apple Intelligence (kPreferenceKeyAISafetyCheckUsesAppleIntelligence);
//  see iTermMigrationHelper and RemoteCommand.isSafe.
//

import Foundation

struct AISafetyClassifierBackend: AutoModeClassifier.Backend {
    // The single-command safety checker has no conversation history to show
    // the classifier, so this is empty. Richer transcript wiring (feeding the
    // live ChatAgent conversation) is a future enhancement.
    var entries: [TranscriptEntry]

    func sideQuery(system: String, user: String, maxTokens: Int) async throws -> String {
        // "Wants Apple" (the stored user choice) is deliberately kept separate
        // from "Apple is available right now" (the probe). A user who chose the
        // on-device path must never be silently downgraded to a cloud provider,
        // so when they want Apple but it is unavailable we fail closed rather
        // than fall back to the configured model.
        let wantsAppleIntelligence =
            iTermUserDefaults.userDefaults().bool(forKey: kPreferenceKeyAISafetyCheckUsesAppleIntelligence)
        return try await withCheckedThrowingContinuation { continuation in
            // AITermController and its delegate callbacks expect the main
            // thread; the classifier may be awaited from a background executor.
            DispatchQueue.main.async {
                if wantsAppleIntelligence {
                    // Never fall back to the cloud for an on-device user. If
                    // Apple Intelligence is unavailable (not ready, or this Mac
                    // is not eligible), fail closed; the caller maps a thrown
                    // error to "unsafe" -> manual approval.
                    guard AIAvailabilityProbe.check() else {
                        continuation.resume(throwing: AIError(
                            "Apple Intelligence is unavailable; the command safety check will not fall back to a cloud provider."))
                        return
                    }
                } else {
                    // The configured-model path needs AI set up; if it is not,
                    // there is nothing to classify with, so fail closed.
                    guard AITermControllerRegistrationHelper.instance.registration != nil else {
                        continuation.resume(
                            throwing: AIError("No AI model is configured to classify command safety."))
                        return
                    }
                }
                var conversation = AIConversation(
                    registrationProvider: nil,
                    messages: [
                        AITermController.Message(role: .system, content: system),
                        AITermController.Message(role: .user, content: user),
                    ])
                if wantsAppleIntelligence {
                    // Routes through the AITermController Apple Intelligence
                    // bypass (on-device, no API key).
                    conversation.model = AIMetadata.recommendedAppleModel.name
                }
                // Otherwise leave `conversation.model` unset so it uses the
                // configured chat model.
                AIConversation.completeOneShot(conversation) { result in
                    switch result {
                    case .success(let updated):
                        if let content = updated.messages.last?.body.content {
                            continuation.resume(returning: content)
                        } else {
                            continuation.resume(
                                throwing: AIError("Empty response from classifier model."))
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
