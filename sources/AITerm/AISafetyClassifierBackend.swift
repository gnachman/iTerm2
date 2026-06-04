//
//  AISafetyClassifierBackend.swift
//  iTerm2
//
//  Bridges AutoModeClassifier to the AITerm provider infrastructure. The
//  classifier is backend-agnostic; this adapter runs its one-shot side-query
//  as a non-streaming AIConversation completion using the SAME model and API
//  key as the user's configured AI conversation. (A separate, dedicated
//  classifier model can be added later.)
//

import Foundation

struct AISafetyClassifierBackend: AutoModeClassifier.Backend {
    // The single-command safety checker has no conversation history to show
    // the classifier, so this is empty. Richer transcript wiring (feeding the
    // live ChatAgent conversation) is a future enhancement.
    var entries: [TranscriptEntry]

    // Conversations are value types that own a controller doing async work;
    // retain them here for the duration of the request so the controller is
    // not deallocated mid-flight. Keyed by a token and only touched on the
    // main queue. Mirrors AICompletion's retention approach.
    private static var inflight = [UUID: AIConversation]()

    func sideQuery(system: String, user: String, maxTokens: Int) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            // AITermController and its delegate callbacks expect the main
            // thread; the classifier may be awaited from a background executor.
            DispatchQueue.main.async {
                // The classifier uses the configured conversation model and key.
                // If AI is not set up there is nothing to classify with, so fail
                // closed (the caller maps a thrown error to "unsafe").
                guard AITermControllerRegistrationHelper.instance.registration != nil else {
                    continuation.resume(
                        throwing: AIError("No AI model is configured to classify command safety."))
                    return
                }
                let token = UUID()
                var conversation = AIConversation(
                    registrationProvider: nil,
                    messages: [
                        AITermController.Message(role: .system, content: system),
                        AITermController.Message(role: .user, content: user),
                    ])
                // Leave `conversation.model` unset so it uses the configured
                // chat model rather than a classifier-specific override.
                Self.inflight[token] = conversation
                conversation.complete(streaming: nil) { result in
                    Self.inflight.removeValue(forKey: token)
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
