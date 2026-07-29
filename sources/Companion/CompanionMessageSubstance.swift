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
        // A .classic remote command BLOCKS on the user (Allow/Deny) and a session pick
        // likewise blocks; both are shown, rendered from their request text. A
        // .external orchestration command auto-executes with no per-call user decision,
        // so it is informational only and never notified.
        case .remoteCommandRequest(let payload, safe: _):
            switch payload {
            case .classic: return true
            case .external: return false
            }
        case .selectSessionRequest:
            return true
        // Control / bookkeeping content is never a "real reply". `.unsupported` is a
        // forward-compat placeholder for content this build can't render.
        case .remoteCommandResponse, .explanationRequest, .clientLocal, .renameChat,
                .append, .appendAttachment, .commit, .userCommand, .setPermissions,
                .vectorStoreCreated, .unsupported:
            return false
        }
    }
}

extension Message {
    /// The ONE predicate for "the NSE would render this as a notification item",
    /// shared by the syncSince responder (what to show) and the wakeup coordinator's
    /// stateless outstanding check (whether to push). Keeping a single definition is
    /// what stops the coordinator from pushing for content the responder then drops
    /// (the empty-placeholder class of bug). Mute is applied separately by the caller
    /// (it is per-chat, not a property of the message).
    var isCompanionRenderable: Bool {
        !hiddenFromClient && author == .agent && content.hasDisplayableSubstance
    }

    /// A .classic permission request is a LIVE prompt only while unanswered. Once it
    /// has a response - it auto-ran (permission .always), auto-denied (.never), or the
    /// user acted - it is resolved bookkeeping the phone must not surface. The
    /// ChatClient broker processor squelches auto/denied requests from LIVE delivery
    /// but still PERSISTS them for history, so the DB-reading companion paths (which
    /// bypass that processor) need this check. `answeredRequestIDs` is the set of
    /// request IDs that already have a remoteCommandResponse in the same window.
    func isResolvedClassicRequest(answeredRequestIDs: Set<UUID>) -> Bool {
        if case .remoteCommandRequest(.classic, safe: _) = content {
            return answeredRequestIDs.contains(uniqueID)
        }
        return false
    }

    /// The request IDs answered by a remoteCommandResponse in `messages` (the response
    /// carries its request's uniqueID). See isResolvedClassicRequest.
    static func answeredRequestIDs(in messages: some Sequence<Message>) -> Set<UUID> {
        var ids = Set<UUID>()
        for message in messages {
            if case .remoteCommandResponse(_, let answeredID, _, _) = message.content {
                ids.insert(answeredID)
            }
        }
        return ids
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
