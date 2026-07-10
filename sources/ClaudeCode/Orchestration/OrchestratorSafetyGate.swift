//
//  OrchestratorSafetyGate.swift
//  iTerm2SharedARC
//
//  The orchestrator's pre-dispatch AI safety gate for session_* commands.
//
//  Session-bound execute_command is safety-checked (ChatAgent.runRemoteCommand
//  -> RemoteCommand.isSafe), and start_session's command is checked via
//  gateSpawn. But the orchestrator's session_execute_command path
//  (OrchestratorDispatcher.handleSessionToolCall) dispatched straight to
//  session.execute after a one-time workgroup claim, with no classification
//  at all. This gate restores parity for the code-execution paths: shell
//  command execution (execute_command, submitted send_text) and file writes
//  (create_file, which is deferred code execution) are all classified, with
//  the failure direction always toward asking a human rather than silently
//  executing. Read/navigate tools (clipboard, browser load/search, history
//  reads) are NOT classified here -- they aren't arbitrary code execution and
//  remain covered by the one-time per-session claim.
//
//  The policy lives here as a pure, injectable function so it can be unit
//  tested with a scripted classifier (see OrchestratorSafetyGateTests); the
//  side-effecting wiring that builds the real classifier, derives inTUI from
//  the live session, and surfaces the outcome stays in the dispatcher.
//

import Foundation

extension OrchestratorDispatcher {
    // A classifier for this chat's safety checks, seeded with the chat's
    // recent history so the classifier can tell a risky command the user
    // asked for from one it didn't. Reads the client-side ChatListModel by
    // chatID (the same store the dispatcher already consults elsewhere);
    // projection to the trusted transcript shape is SafetyTranscript's job,
    // and AutoModeClassifier caps count and size.
    // A classifier seeded with this chat's recent history. `applyTerminalHardRules`
    // is false for the create_file path: the file content is not a shell command
    // line, so TerminalHardRules would over-block any body containing an ESC byte,
    // an `rm -rf` string, or a `sudo` line -- there the LLM judges path + content.
    func safetyClassifier(applyTerminalHardRules: Bool = true) -> AutoModeClassifier {
        return CommandSafetyChecker.makeClassifier(
            transcript: SafetyTranscript.forChat(chatID),
            applyTerminalHardRules: applyTerminalHardRules)
    }
    func fileWriteSafetyClassifier() -> AutoModeClassifier {
        return safetyClassifier(applyTerminalHardRules: false)
    }

    // What the gate decided for a proposed session_* command.
    enum SafetyGateOutcome: Equatable {
        // Run the command normally.
        case allow
        // Do not auto-run; a human must approve first. Carries the
        // classifier's reason so the approval UI (and the LLM, until that
        // UI exists) can explain why.
        case requireApproval(reason: String)
        // Categorically refuse and tell the LLM. The classifier judged the
        // action out of bounds for anything short of a direct user request.
        case deny(reason: String)
    }

    // Run one command string through the classifier and map its verdict to
    // a gate outcome. Shared by the execute_command path above and the
    // send_text path (a submitted shell line is the same risk as an
    // execute_command). Fails closed: classifier error and unparseable both
    // map to requireApproval, never allow.
    static func classifyCommand(
        _ command: String,
        inTUI: Bool,
        classifier: AutoModeClassifier
    ) async -> SafetyGateOutcome {
        return await classifyAction(
            .toolCall(name: "RunShellCommand", input: command),
            inTUI: inTUI, classifier: classifier)
    }

    // Classify a create_file write. Framed as a WriteFile action (not
    // RunShellCommand) so the LLM judges it as a file write, not a shell line
    // whose "content" lines are commands to run, and paired with a classifier
    // that omits the shell hard rules (fileWriteSafetyClassifier).
    static func classifyFileWrite(
        filename: String,
        content: String,
        classifier: AutoModeClassifier
    ) async -> SafetyGateOutcome {
        let repr = createFileClassificationCommand(filename: filename, content: content)
        return await classifyAction(
            .toolCall(name: "WriteFile", input: repr),
            inTUI: false, classifier: classifier)
    }

    // Run one action through the classifier and map its verdict to a gate
    // outcome. Fails closed: classifier error and unparseable both map to
    // requireApproval, never allow.
    static func classifyAction(
        _ action: TranscriptEntry,
        inTUI: Bool,
        classifier: AutoModeClassifier
    ) async -> SafetyGateOutcome {
        return await mappedOutcome { try await classifier.classify(action: action, inTUI: inTUI) }
    }

    // Screen-aware safety gate for a keystroke sent into a full-screen TUI
    // (alternate screen). The classifier is given the current screen so it can
    // judge what the keystroke does. Fails closed: a classifier error maps to
    // requireApproval, never allow.
    static func tuiKeystrokeOutcome(
        keystroke: String,
        screen: String,
        classifier: AutoModeClassifier
    ) async -> SafetyGateOutcome {
        return await mappedOutcome {
            try await classifier.classifyTUIKeystroke(keystroke: keystroke, screen: screen)
        }
    }

    // Run a throwing classify call and map its verdict to a gate outcome,
    // failing closed on a thrown error (requireApproval, never allow).
    private static func mappedOutcome(
        _ classify: () async throws -> ClassifierDecision
    ) async -> SafetyGateOutcome {
        do {
            return mapDecision(try await classify())
        } catch {
            return .requireApproval(
                reason: "The safety check could not be completed, so this needs manual approval.")
        }
    }

    // Shared verdict -> outcome mapping for both the command and TUI paths.
    private static func mapDecision(_ decision: ClassifierDecision) -> SafetyGateOutcome {
        switch decision {
        case .allow:
            return .allow
        case .needsManualApproval(let reason):
            return .requireApproval(reason: reason)
        case .block(let reason):
            return .deny(reason: reason)
        case .unparseable:
            return .requireApproval(
                reason: "The safety check result could not be understood, so this needs manual approval.")
        }
    }

    // The whole command line that will run when `decoded` is inserted between
    // `prefix` (left of cursor) and `suffix` (right of cursor), trimmed; nil if
    // empty. Used only WITH shell integration, where prefix/suffix come from the
    // live command line. Classifying the whole line (not this call's text alone)
    // is what stops a command split across sends or spliced mid-line from
    // dodging the gate. Without shell integration the dispatcher routes to the
    // screen-aware classifier instead (the screen echoes the real line, and the
    // old cross-call accumulation was unreliable -- lag, cursor moves, and
    // cross-chat all defeated it).
    nonisolated static func reconstructedLine(prefix: String,
                                              decoded: String,
                                              suffix: String) -> String? {
        let line = trimmedLine(prefix + decoded + suffix)
        return line.isEmpty ? nil : line
    }

    // Render a createFile as a shell heredoc write so the classifier judges it
    // the way it judges any file write. session_create_file otherwise reaches
    // the PTY with no classification (needsSafetyCheck is false for it), and
    // writing ~/.zshrc, ~/.ssh/authorized_keys, or a .git/hooks script is
    // deferred code execution -- a real hole in "every arbitrary-code action is
    // vetted." The content carries risk too (a malicious rc file), so include a
    // truncated snippet; the path plus leading content are what matter.
    /// Largest file content we will pass to the classifier in full. Above this
    /// we cannot be sure a payload isn't buried in the unseen middle, so the
    /// caller requires manual approval instead of classifying a partial view.
    nonisolated static let createFileMaxClassifiableContent = 8000

    /// Representation of a create_file operation for the classifier. The full
    /// content is included (the caller guarantees it is within
    /// `createFileMaxClassifiableContent`), so no truncation hides a middle
    /// payload. A plain natural-language framing avoids a heredoc delimiter
    /// the content could collide with.
    nonisolated static func createFileClassificationCommand(filename: String,
                                                            content: String) -> String {
        return "Write a file at \(filename) with exactly this content:\n\(content)"
    }

    // Split the live command line at the cursor. Both come from shell
    // integration: `full` is the whole line, `upToCursor` its left-of-cursor
    // prefix. Returns (prefix, suffix) so the caller can reconstruct
    // prefix + decoded + suffix. Returns nil when the cursor is unlocatable
    // (the auto-composer, where the two views come from different sources and
    // disagree); the caller then fails closed to the screen-aware classifier
    // rather than assume append semantics, since a mid-line splice could
    // otherwise launder past the reconstruction.
    nonisolated static func promptContext(full: String,
                                          upToCursor: String) -> (prefix: String, suffix: String)? {
        guard full.hasPrefix(upToCursor) else { return nil }
        return (upToCursor, String(full.dropFirst(upToCursor.count)))
    }

    // The plan for gating one typed send, computed purely so the routing can be
    // unit-tested without a live PTY. `route` says what to do; `newBuffer` is
    // the per-session accumulator's next value (nil = clear it).
    struct TypedGatePlan: Equatable {
        enum Route: Equatable {
            // Not a reconstructible shell command line -- a TUI / non-shell
            // foreground, or a cursor/control byte a linear accumulator cannot
            // model. Judge the keystroke against the rendered screen instead.
            case screenAware
            // A shell command line about to run: classify it.
            case classifyLine(String)
            // A non-submitting shell fragment: typed but inert until Enter, so
            // only accumulate it. The eventual submit classifies the whole line,
            // so the fragment is never lost even though it isn't classified now.
            case accumulateOnly
            // The line to classify is too long to vet safely (a payload could
            // hide in the dropped region), so fail closed to manual approval.
            case failClosed(reason: String)
        }
        var route: Route
        var newBuffer: String?
    }

    // Largest pending shell line we will classify. A real command line is far
    // shorter; a line at or above this was truncated by the accumulator cap, so
    // a submit at that size fails closed rather than trust a partial view.
    nonisolated static let maxPendingInput = 16_384

    nonisolated static let submitNewlines = CharacterSet(charactersIn: "\r\n")

    // Trim only the submit newlines (CR/LF) from the ends -- never spaces, so a
    // trailing/leading space that is part of the command is preserved.
    nonisolated static func trimmedLine(_ s: String) -> String {
        return s.trimmingCharacters(in: submitNewlines)
    }

    // True for input that edits the line non-linearly (arrows, Ctrl-U/W/C, ESC,
    // DEL, Tab completion): a simple append-accumulator cannot model it, so the
    // caller resets the buffer and defers to the screen-aware classifier. Submit
    // newlines (LF/CR) are NOT disturbing -- they are handled as submits.
    nonisolated static func disturbsLinearAccumulation(_ s: String) -> Bool {
        return s.unicodeScalars.contains { sc in
            if sc.value == 0x1B || sc.value == 0x7F { return true }        // ESC, DEL
            return sc.value < 0x20 && sc.value != 0x0A && sc.value != 0x0D  // other C0 incl. Tab
        }
    }

    // Text after the last submit newline in `s`: it stays at the prompt
    // un-submitted after the earlier line(s) run.
    nonisolated static func residualAfterLastSubmit(_ s: String) -> String {
        guard let idx = s.lastIndex(where: { $0 == "\n" || $0 == "\r" }) else { return s }
        return String(s[s.index(after: idx)...])
    }

    // Bound the accumulator's memory, keeping the HEAD: for a shell command the
    // dangerous verb is at the head, so if a truncated line is ever classified
    // the primary command is still seen. (An at-cap line fails closed anyway.)
    private nonisolated static func capPending(_ s: String) -> String {
        return s.count <= maxPendingInput ? s : String(s.prefix(maxPendingInput))
    }

    // Decide how to gate one typed send. The per-session accumulator (`priorBuffer`,
    // everything the orchestrator typed since the last submit) is the only
    // LAG-FREE record of prior fragments: shell integration (`full` /
    // `upToCursor`) and the screen grid both trail our own PTY writes, so a
    // payload split across back-to-back sends within one LLM turn could have its
    // first fragment invisible when the second is classified. On submit we prefer
    // the reconstructed live line WHEN integration has caught up to our prior
    // fragments (it also captures user-typed context); otherwise we fall back to
    // the accumulator so the split payload is classified whole.
    nonisolated static func planTypedGate(priorBuffer: String,
                                          decoded: String,
                                          appendNewline: Bool,
                                          screenAware: Bool,
                                          full: String?,
                                          upToCursor: String?) -> TypedGatePlan {
        let submits = appendNewline || decoded.contains("\n") || decoded.contains("\r")
        let ownDecoded = trimmedLine(decoded)

        // A non-linear edit or a non-shell foreground: reset the accumulator and
        // defer to the screen-aware classifier (which reasons about the rendered
        // result, not a reconstructed line).
        if screenAware || disturbsLinearAccumulation(ownDecoded) {
            return TypedGatePlan(route: .screenAware, newBuffer: nil)
        }

        // Next accumulator value: a submit keeps only the post-newline residual
        // (the rest ran); otherwise append this fragment.
        let nextBuffer: String?
        if submits {
            let residual = appendNewline ? "" : residualAfterLastSubmit(priorBuffer + decoded)
            nextBuffer = residual.isEmpty ? nil : capPending(residual)
        } else {
            nextBuffer = capPending(priorBuffer + ownDecoded)
        }

        // A non-submitting fragment is inert until Enter: accumulate, don't
        // classify. The submit will classify the whole accumulated line.
        guard submits else {
            return TypedGatePlan(route: .accumulateOnly, newBuffer: nextBuffer)
        }

        // Reconstruct the line only when shell integration has demonstrably
        // caught up to our typed fragments: the accumulated fragments are typed
        // AT the cursor, so a fresh `upToCursor` ENDS with them. A substring-
        // anywhere test is too weak (a short fragment like "rm" is a coincidental
        // substring of an unrelated stale line), so require the anchored suffix.
        let integrationFresh = { (upToCursor: String) in
            priorBuffer.isEmpty || upToCursor.hasSuffix(priorBuffer)
        }
        let line: String
        let provenByIntegration: Bool
        if let full, let upToCursor,
           let (prefix, suffix) = promptContext(full: full, upToCursor: upToCursor),
           integrationFresh(upToCursor) {
            // Integration present AND caught up: reconstruct the true line, which
            // also includes any user-typed context on the line.
            line = reconstructedLine(prefix: prefix, decoded: ownDecoded, suffix: suffix) ?? ""
            provenByIntegration = true
        } else {
            // No integration, unlocatable cursor, or a stale line that doesn't
            // yet reflect our prior fragments: use our own lag-free record so a
            // split payload is classified whole.
            line = trimmedLine(priorBuffer + ownDecoded)
            provenByIntegration = false
        }

        if line.isEmpty {
            // A bare/empty submit. If integration PROVED the prompt empty,
            // nothing runs. Otherwise the prompt may hold content we can't see
            // (a buffer-wiping edit that we reset the accumulator on, or lag), so
            // an Enter is NOT inert: judge it against the real screen, which shows
            // the full assembled line.
            return provenByIntegration
                ? TypedGatePlan(route: .accumulateOnly, newBuffer: nextBuffer)
                : TypedGatePlan(route: .screenAware, newBuffer: nil)
        }
        // A line at/above the cap was truncated by capPending; a payload could
        // hide in the dropped region, so fail closed rather than classify it.
        if line.count >= maxPendingInput {
            return TypedGatePlan(
                route: .failClosed(reason: "the pending command line is too long to safety-check automatically"),
                newBuffer: nil)
        }
        return TypedGatePlan(route: .classifyLine(line), newBuffer: nextBuffer)
    }
}
