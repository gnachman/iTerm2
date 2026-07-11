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

// Per-SESSION typed-input state shared across every per-chat OrchestratorDispatcher
// of one OrchestratorClient. The client holds one instance and hands the same
// reference to each dispatcher it creates, so the accumulator is genuinely
// per-session (keyed by session GUID) rather than per-(chat, session). Two chats
// driving the same PTY then share one accumulator, so a payload split across the
// two chats (fragment typed from chat A, submitted from chat B) is reconstructed
// whole instead of dodging chat B's otherwise-empty accumulator.
//
// @MainActor: every SYNCHRONOUS access is serialized on the main actor without
// additional locking. It does NOT make a read-classify-write sequence atomic:
// the actor is released at every `await`, so gateTypedText's classify await can
// interleave with a concurrent send on the same session (via another chat's
// dispatcher sharing this store). gateTypedText handles that itself -- it
// re-checks pending/contaminated after the await and refuses to clobber a value
// that changed under it (see its concurrency guard) -- rather than this store
// providing atomicity. Keyed by session, not chat, so a dispatcher tearing down
// never clears a session another chat drives; entries are removed on submit /
// interrupt / session termination.
@MainActor
final class OrchestratorTypedInputStore {
    // Everything the orchestrator has typed into a session's prompt since its
    // last submit, keyed by session GUID. See gateTypedText / planTypedGate.
    var pending: [String: String] = [:]

    // Session GUIDs whose linear accumulation is contaminated (a disturbing
    // keystroke was allowed, leaving un-accounted bytes on the prompt). While
    // present, gateTypedText forces screen-aware classification. See gateTypedText.
    var contaminated: Set<String> = []

    init() {}
}

extension OrchestratorDispatcher {
    // A classifier for this chat's safety checks, seeded with the chat's recent
    // history so the classifier can tell a risky command the user asked for from
    // one it didn't. Reads the client-side ChatListModel by chatID (the same
    // store the dispatcher already consults elsewhere); projection to the trusted
    // transcript shape is SafetyTranscript's job, and AutoModeClassifier caps
    // count and size. `applyTerminalHardRules` is false for the create_file path:
    // the file content is not a shell command line, so TerminalHardRules would
    // over-block any body containing an ESC byte, an `rm -rf` string, or a `sudo`
    // line -- there the LLM judges path + content.
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
        // The classifier judged the action dangerous (out of bounds for
        // anything short of a direct user request). NOT a categorical refusal:
        // `enforce` surfaces it through the same one-tap approval bubble as
        // requireApproval, only flagged=true (a stronger warning), and runs the
        // command if the user approves. The distinction from requireApproval is
        // the severity of the warning shown, not whether an approval path
        // exists -- there is no verdict the gate refuses outright.
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
        // blockIsDeny: false -- see mapDecision. The TUI prompt asks the model to
        // HOLD a keystroke for approval whenever the screen is unclear or the
        // action unrecognized, not only when it is destructive; its only verdicts
        // are allow / hold. Mapping a hold to .deny would label every held
        // keystroke "potentially dangerous", overstating the usually-just-unclear
        // case. A hold is requireApproval ("a human should look"); the gate still
        // requires approval either way, so the fail-safe direction is unchanged.
        return await mappedOutcome(blockIsDeny: false) {
            try await classifier.classifyTUIKeystroke(keystroke: keystroke, screen: screen)
        }
    }

    // Run a throwing classify call and map its verdict to a gate outcome,
    // failing closed on a thrown error (requireApproval, never allow).
    private static func mappedOutcome(
        blockIsDeny: Bool = true,
        _ classify: () async throws -> ClassifierDecision
    ) async -> SafetyGateOutcome {
        do {
            return mapDecision(try await classify(), blockIsDeny: blockIsDeny)
        } catch {
            return .requireApproval(
                reason: "The safety check could not be completed, so this needs manual approval.")
        }
    }

    // Verdict -> outcome mapping. `blockIsDeny` distinguishes the two callers: the
    // command path treats an LLM block as "potentially dangerous" (.deny, flagged
    // approval); the TUI keystroke path maps it to .requireApproval instead
    // (neutral "needs review" copy), because a TUI hold reflects uncertainty as
    // often as danger. Both still require human approval; only the warning copy
    // differs.
    private static func mapDecision(_ decision: ClassifierDecision,
                                    blockIsDeny: Bool) -> SafetyGateOutcome {
        switch decision {
        case .allow:
            return .allow
        case .needsManualApproval(let reason):
            return .requireApproval(reason: reason)
        case .block(let reason):
            return blockIsDeny ? .deny(reason: reason) : .requireApproval(reason: reason)
        case .unparseable:
            return .requireApproval(
                reason: "The safety check result could not be understood, so this needs manual approval.")
        }
    }

    // The command line that will run when `decoded` is inserted at the cursor,
    // reconstructed as `prefix + decoded + suffix` and trailing-trimmed; nil if
    // empty. Used only WITH shell integration (prefix/suffix come from the live
    // command line via promptContext). Classifying the whole line, not this
    // call's text alone, is what stops a command split across sends from dodging
    // the gate.
    //
    // In practice `suffix` is ALWAYS empty: `session.currentCommand` (`full` in
    // promptContext) is the command range, which ends AT the cursor and never
    // contains right-of-cursor text, so promptContext returns non-nil only with
    // the cursor at end-of-line, where suffix == "". A mid-line cursor MOVE is
    // itself a disturbsLinearAccumulation keystroke that routes to the screen-
    // aware classifier (which reads the whole rendered line), so a genuine
    // mid-line splice is covered THERE, not by this reconstruction. The `suffix`
    // parameter is retained as a defensive generalization but is inert given
    // today's integration data.
    //
    // Without shell integration, planTypedGate does NOT use this: it falls back
    // to the per-session accumulator (`priorBuffer + decoded`), which is lag-free
    // and reconstructs the whole split line from the orchestrator's own typed
    // record. A disturbing keystroke (arrows/Tab/ESC/Ctrl-*) that resets that
    // accumulator marks the session contaminated, so the NEXT submit is judged
    // against the rendered screen instead (which still echoes the leftover
    // prefix) until a clean submit clears it.
    nonisolated static func reconstructedLine(prefix: String,
                                              decoded: String,
                                              suffix: String) -> String? {
        // Trim only a trailing submit run: a leading/interior `\r`/`\n` is a real
        // submit boundary and must stay visible to the classifier (the CR hard
        // rule for `\r`; multi-line visibility for `\n`).
        let line = trimTrailingSubmit(prefix + decoded + suffix)
        return line.isEmpty ? nil : line
    }

    // A createFile is classified the way any file write is: session_create_file
    // otherwise reaches the PTY with no classification (needsSafetyCheck is false
    // for it), and writing ~/.zshrc, ~/.ssh/authorized_keys, or a .git/hooks
    // script is deferred code execution -- a real hole in "every arbitrary-code
    // action is vetted." The content carries risk too (a malicious rc file), so
    // it is classified in full up to the cap below.

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

    // Split the live command line at the cursor for reconstruction. Both come
    // from shell integration: `full` is `session.currentCommand` -- the command
    // RANGE, which ends AT the cursor and does NOT include right-of-cursor text
    // -- and `upToCursor` is `currentCommandUpToCursor`. Returns (prefix, suffix)
    // so the caller can reconstruct prefix + decoded + suffix.
    //
    // Because `full` ends at the cursor, `suffix` is empty whenever this returns
    // non-nil. With the cursor MID-LINE the two views disagree (upToCursor
    // includes the char under the cursor, one longer than `full`, so
    // `full.hasPrefix(upToCursor)` fails) and this returns nil; only an
    // end-of-line cursor matches, and there suffix == "". A mid-line splice is
    // therefore handled by the disturbs -> screen-aware path, not here. nil is
    // also returned for the auto-composer (the two views come from different
    // sources and disagree). On nil, planTypedGate falls back to the accumulator
    // (`priorBuffer + decoded`); if that yields an empty line the empty-submit
    // backstop routes to the screen-aware classifier.
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
        // Next value of the caller's per-session "linear accumulation
        // contaminated" flag (see planTypedGate). The caller stores it after an
        // allowed send. Defaults false: only the screen-aware reset path can
        // set or preserve it; every normal accumulate/classify path clears it.
        var contaminated: Bool = false
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

    // Trim only a TRAILING run of submit newlines (CR/LF) -- never leading or
    // interior ones, and never spaces. Used to build the CLASSIFIED line: a
    // leading/interior `\r` is a real submit boundary that runs earlier content
    // (e.g. an accumulated `rm -rf /`) as its own line, so it must survive into
    // the classified string to trip the carriage-return hard rule. trimmedLine's
    // both-ends trim would drop a leading `\r` and silently fuse the
    // separately-submitted `rm -rf /` with a benign residual (`rm -rf /home/safe`),
    // rewriting a root wipe into a subpath the classifier waves through.
    nonisolated static func trimTrailingSubmit(_ s: String) -> String {
        var end = s.endIndex
        while end > s.startIndex {
            let prev = s.index(before: end)
            let c = s[prev]
            guard c == "\r" || c == "\n" else { break }
            end = prev
        }
        return String(s[s.startIndex..<end])
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

    // Text after the last submit-newline (`\r` or `\n`) in `s`: it stays at the
    // prompt un-submitted after the earlier line(s) run. Both count as submit
    // boundaries: a raw `\n` DOES submit on a canonical-mode shell (Ctrl-J is
    // accept-line), which is the threat model here -- assuming it doesn't would
    // let a leading `\n` submit an accumulated command that was never classified.
    nonisolated static func residualAfterLastSubmit(_ s: String) -> String {
        guard let idx = s.lastIndex(where: { $0 == "\r" || $0 == "\n" }) else { return s }
        return String(s[s.index(after: idx)...])
    }

    // The portion of the reconstructed stream the shell actually SUBMITS when
    // this send lands: everything up to and including the last submit-newline
    // (`\r`/`\n`) in `priorBuffer + decoded`, or the whole thing when a trailing
    // `\r` is appended -- with that trailing submit gesture then trimmed off.
    // Complementary to residualAfterLastSubmit (what stays at the prompt).
    //
    // Classifying THIS (not the whole fused stream) is the fix for the leading-
    // newline laundering: when `decoded` begins with a submit-newline, the shell
    // runs `priorBuffer` as its OWN command and leaves the residual at the
    // prompt. Splitting at the boundary makes the classifier see the real first
    // command (`rm -rf /`, catastrophic) instead of `priorBuffer` glued onto the
    // residual with the boundary erased (`rm -rf /home/safe`, a benign subpath).
    // Interior newlines are preserved, so a genuine multi-line submission still
    // reaches the LLM intact.
    nonisolated static func submittedLine(priorBuffer: String,
                                          decoded: String,
                                          appendNewline: Bool) -> String {
        let combined = priorBuffer + decoded
        if appendNewline {
            return trimTrailingSubmit(combined)
        }
        guard let idx = combined.lastIndex(where: { $0 == "\r" || $0 == "\n" }) else {
            return trimTrailingSubmit(combined)
        }
        return trimTrailingSubmit(String(combined[...idx]))
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
                                          upToCursor: String?,
                                          contaminated: Bool = false) -> TypedGatePlan {
        // A submit-newline (`\r` or `\n`) in the payload, or an appended trailing
        // `\r`, means content runs: classify it. A raw `\n` DOES submit on a
        // canonical-mode shell (Ctrl-J is accept-line), so it counts -- assuming
        // otherwise would let a leading `\n` submit an accumulated command that
        // was never classified.
        let submits = appendNewline || decoded.contains("\r") || decoded.contains("\n")
        // ownDecoded preserves leading/interior submit newlines (only a trailing
        // submit run is trimmed), used for the accumulate/integration paths; the
        // submitted line for classification is computed via `submittedLine`.
        let ownDecoded = trimTrailingSubmit(decoded)
        let disturbs = disturbsLinearAccumulation(ownDecoded)

        // Next value of the per-session "linear accumulation contaminated" flag.
        // A disturbing keystroke allowed on a primary-screen shell wipes the
        // accumulator (below) but leaves the already-typed prefix on the prompt
        // line, so the lag-free accumulator can no longer reconstruct the whole
        // command. Until the next submit resets the prompt, stay contaminated so
        // the caller forces screen-aware classification (the screen echoes the
        // real line). A submit clears it; a TUI (screenAware) never sets it,
        // since it is screen-aware regardless.
        // Bytes still on the prompt after this send's submit boundary: empty when
        // a trailing `\r` is appended (submits everything) or nothing submits;
        // otherwise the text after the last `\r`/`\n`, which the shell leaves at
        // the prompt un-submitted.
        let residual = (submits && !appendNewline)
            ? residualAfterLastSubmit(priorBuffer + decoded)
            : ""

        // Next accumulator value: after a submit only the residual stays (the
        // rest ran); otherwise the whole fragment accumulates. Consistent with
        // the submitted line classified below.
        let nextBuffer: String? = submits
            ? (residual.isEmpty ? nil : capPending(residual))
            : capPending(priorBuffer + ownDecoded)

        // Next value of the "linear accumulation contaminated" flag. ONLY a submit
        // that leaves NO residual fully resets the prompt and clears it. A submit
        // that leaves residual (a leading/interior newline runs earlier content
        // and leaves bytes after it) must NOT clear it -- otherwise the orphaned
        // residual, dropped from the accumulator on a screen-aware/empty-line
        // route, would run unclassified on the next send. A disturbing keystroke
        // on a shell sets it (the edit leaves un-accounted bytes on the prompt).
        let nextContaminated: Bool
        if submits && residual.isEmpty {
            nextContaminated = false
        } else if !screenAware && disturbs {
            nextContaminated = true
        } else {
            nextContaminated = contaminated
        }

        // A non-shell foreground (TUI / alternate screen): the linear accumulator
        // doesn't apply; always judge against the rendered screen.
        if screenAware {
            return TypedGatePlan(route: .screenAware, newBuffer: nil,
                                 contaminated: false)
        }

        // A full-line kill on a shell CLEARS the prompt -- it REMOVES bytes rather
        // than leaving un-accounted ones -- so (matching doInterrupt) it can reset
        // the accumulator to the fresh post-kill text and CLEAR contamination. But
        // that only holds when the WHOLE line was killed:
        //  - Ctrl-C (0x03) aborts the entire line via SIGINT: always a full reset.
        //  - Ctrl-U (0x15) is readline unix-line-discard: it kills only from the
        //    cursor to the line START, so a right-of-cursor tail survives IF the
        //    cursor was previously moved -- which is exactly what sets
        //    `contaminated`. So Ctrl-U is a full reset only when the session was
        //    NOT already contaminated (cursor at end => kill-to-start == whole
        //    line). An already-contaminated Ctrl-U must PRESERVE contamination and
        //    NOT trust `afterKill`, since the surviving tail (which we cannot see
        //    without integration) would otherwise be laundered past the gate.
        // Only applies when this send doesn't also submit (a kill+submit is left
        // to the normal classify path). Ctrl-W kills only a word, so it is NOT a
        // full reset and stays a contaminating disturbance below.
        if !submits,
           let lastKill = decoded.unicodeScalars.lastIndex(where: {
               $0.value == 0x03 || $0.value == 0x15
           }) {
            let isCtrlC = decoded.unicodeScalars[lastKill].value == 0x03
            if isCtrlC || !contaminated {
                let afterKill = String(
                    decoded.unicodeScalars[decoded.unicodeScalars.index(after: lastKill)...])
                return TypedGatePlan(route: .screenAware,
                                     newBuffer: afterKill.isEmpty ? nil : capPending(afterKill),
                                     contaminated: false)
            }
            // Contaminated Ctrl-U: a right-of-cursor tail may survive on the
            // prompt. Keep the only protective signal and don't reset to afterKill.
            return TypedGatePlan(route: .screenAware, newBuffer: nil,
                                 contaminated: true)
        }

        // A disturbing edit or an already-contaminated shell: judge THIS send
        // against the screen, and keep contamination while un-accounted bytes
        // remain on the prompt. PRESERVE the post-submit residual (nextBuffer)
        // when this send carried a submit boundary, so the next send can still
        // reconstruct the residual; a PURE disturbing edit (Ctrl-U/arrows, no
        // submit) invalidated the line non-linearly, so wipe the accumulator.
        if disturbs || contaminated {
            return TypedGatePlan(route: .screenAware,
                                 newBuffer: submits ? nextBuffer : nil,
                                 contaminated: nextContaminated)
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

        // Integration present and locatable, but the live line EXTENDS our
        // accumulator: `upToCursor` starts with `priorBuffer` and has more after
        // it (content we did not type -- a user edit or a non-accumulator write),
        // yet does not END with it (so integrationFresh is false). That extra
        // content is on the prompt and about to run; trusting the lag-free
        // accumulator would classify only our fragments and DROP it. Judge the
        // whole visible line against the rendered screen instead. This is
        // distinct from a LAGGING line (which does not start with priorBuffer):
        // there the screen is behind our writes and the accumulator is
        // authoritative, so that case still falls through to the accumulator.
        if let full, let upToCursor,
           promptContext(full: full, upToCursor: upToCursor) != nil,
           !integrationFresh(upToCursor),
           !priorBuffer.isEmpty,
           upToCursor.hasPrefix(priorBuffer) {
            // This branch is only reached with `submits` true. Preserve the
            // post-submit residual and contamination exactly as the disturbs /
            // contaminated branch does: a submit that leaves residual (a
            // leading/interior newline) must not have it orphaned to an
            // unclassified next send, nor clear a contamination flag that a prior
            // disturbing edit set.
            return TypedGatePlan(route: .screenAware,
                                 newBuffer: submits ? nextBuffer : nil,
                                 contaminated: nextContaminated)
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
            // yet reflect our prior fragments: classify the SUBMITTED portion of
            // our own lag-free record. A leading/interior submit-newline runs
            // `priorBuffer` (and earlier fragments) as their own line(s), so
            // splitting at the boundary is what makes the classifier see the real
            // first command (`rm -rf /`) instead of `priorBuffer` fused onto the
            // residual with the boundary erased (`rm -rf /home/safe`). The residual
            // stays buffered (nextBuffer above) for the next send.
            line = submittedLine(priorBuffer: priorBuffer, decoded: decoded,
                                 appendNewline: appendNewline)
            provenByIntegration = false
        }

        if line.isEmpty {
            // A bare/empty submitted line. Treat the Enter as inert (nothing
            // runs) ONLY with positive proof the prompt is empty: a NON-EMPTY
            // `full` that reconstructed to empty-after-cursor. An empty `full`
            // (currentCommand == "") is returned even when integration has not
            // caught up to residual echoed on the prompt (from a wiped/lagging
            // accumulator, or user typing), so it is NOT proof -- judge against
            // the real screen, which shows any residual, and keep the residual
            // buffered rather than discarding it.
            let promptProvenEmpty = provenByIntegration && !(full ?? "").isEmpty
            return promptProvenEmpty
                ? TypedGatePlan(route: .accumulateOnly, newBuffer: nextBuffer)
                : TypedGatePlan(route: .screenAware, newBuffer: nextBuffer,
                                contaminated: nextContaminated)
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

    // What gateTypedText does with the shared accumulator AFTER the classify
    // await returns. The store is shared across a client's per-chat dispatchers
    // and the classify is a suspension point, so a concurrent send on the same
    // session may have mutated the buffer or contamination flag while we awaited.
    enum ConcurrentSendResolution: Equatable {
        // No concurrent mutation: apply the plan's accumulator advance. `buffer`
        // nil means remove the pending entry; `contaminate` is the plan's flag.
        case commit(buffer: String?, contaminate: Bool)
        // A concurrent send changed the shared accumulator during the await AND
        // this send submits a line: the line we classified is stale (the shell
        // would run a fusion we never checked whole), so block THIS send. The
        // caller marks the session contaminated and leaves `pending` as the
        // concurrent writer set it.
        case failClosed
        // A concurrent send changed the accumulator but this send is inert (no
        // submit): leave the concurrent writer's `pending`, mark contaminated,
        // and return without clobbering. The next submit is judged against the
        // screen.
        case markContaminatedAndReturn
    }

    // Pure decision for the post-await concurrency guard, factored out of
    // gateTypedText so the race resolution is unit-testable without a live
    // session. `observed*` are re-read AFTER the await; `prior*` were captured
    // before it; `planned*` come from the plan computed against the stale prior
    // state.
    nonisolated static func resolveConcurrentSend(
        priorBuffer: String, observedBuffer: String,
        priorContaminated: Bool, observedContaminated: Bool,
        sendSubmits: Bool,
        plannedNewBuffer: String?, plannedContaminated: Bool
    ) -> ConcurrentSendResolution {
        let raced = observedBuffer != priorBuffer
            || observedContaminated != priorContaminated
        guard raced else {
            return .commit(buffer: plannedNewBuffer, contaminate: plannedContaminated)
        }
        return sendSubmits ? .failClosed : .markContaminatedAndReturn
    }
}
