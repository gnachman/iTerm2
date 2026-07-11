//
//  CompanionMessageSubstance.swift
//  iTerm2
//
//  One definition of "has real, displayable substance" for companion
//  notifications, shared by the push TRIGGER (CompanionAgentActivityNotifier,
//  which decides whether a turn is worth a push) and the preview BUILDER
//  (MessagesSinceResponder, which decides what the NSE renders). They used to
//  judge this differently, so a status-only/reasoning agent message that did NOT
//  warrant a push could still be fetched-and-previewed onto the lock screen (and
//  a push could resolve to zero previews). Using the same predicate keeps the
//  fetched preview set aligned with what was deemed worth notifying.
//

import Foundation

extension Message.Content {
    /// Real content worth surfacing in a notification, as opposed to control /
    /// bookkeeping content or ephemeral status/reasoning. Inspects the actual
    /// content/subparts rather than snippetText, which returns display
    /// placeholders ("Empty message", a statusUpdate's text) for substance-free
    /// content.
    var hasDisplayableSubstance: Bool {
        switch self {
        case .plainText(let text, _), .markdown(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .explanationResponse(_, _, let markdown):
            return !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .multipart(let subparts, _):
            return subparts.contains { $0.hasDisplayableSubstance }
        case .terminalCommand, .watcherEvent:
            return true
        // Control / bookkeeping / request content is never a "real reply"
        // (permission and session requests are handled separately, as
        // userActionRequired, before this is consulted). `.unsupported` is a
        // forward-compat placeholder for content this build can't render, so it
        // has nothing displayable either.
        case .remoteCommandRequest, .selectSessionRequest, .remoteCommandResponse,
                .explanationRequest, .clientLocal, .renameChat, .append, .appendAttachment,
                .commit, .userCommand, .setPermissions, .vectorStoreCreated, .unsupported:
            return false
        }
    }
}

extension Message.Subpart {
    var hasDisplayableSubstance: Bool {
        switch self {
        case .plainText(let text), .markdown(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .attachment(let attachment):
            switch attachment.type {
            case .file, .fileID:
                return true
            case .code(let text):
                // Whitespace-only code is NOT substance. previewAndLabel returns the
                // RAW code text (not nil) for it; THIS substance gate is what filters
                // it out, so without this a whitespace-only .code would pass and fall
                // back to the literal "Empty message" in snippetText.
                return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .statusUpdate:
                return false   // ephemeral reasoning/status, not a real reply
            }
        case .context:
            return false       // user-context only, not displayable
        }
    }
}
