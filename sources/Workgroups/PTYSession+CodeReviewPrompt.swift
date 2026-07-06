//
//  PTYSession+CodeReviewPrompt.swift
//  iTerm2SharedARC
//
//  Helper that presents the in-session Code Review prompt overlay and
//  defers the program launch until the user clicks Start. Once Start
//  is pressed the entered text is exposed as the variable
//  `codeReviewPrompt`, the (swifty-templated) raw command is evaluated
//  and login-shell-wrapped, and the launch request is finally fired.
//

import AppKit

extension PTYSession {
    // Initial spawn (deferred launch). The session has been created but
    // no program has run yet; on Start, fire attachOrLaunch with the
    // resolved command.
    //
    // `workgroupInstanceID` is captured for ITERM_WORKGROUP_ID just
    // like the regular spawn paths in WorkgroupSessionSpawner.launch
    // and PTYSession.makeWorkgroupPeer — without this, the deferred
    // shell would launch with no workgroup-id env var.
    @objc
    func presentCodeReviewPromptOverlay(rawCommand: String,
                                         urlString: String?,
                                         objectType: iTermObjectType,
                                         factory: iTermSessionFactory,
                                         windowController: PseudoTerminal?,
                                         oldCWD: String?,
                                         workgroupInstanceID: String) {
        codeReviewRawCommand = rawCommand
        showCodeReviewPromptOverlay { [weak self] text in
            guard let self else { return }
            let wrapped = self.wrappedCommandForCodeReview(text: text,
                                                            rawCommand: rawCommand)
            let request = iTermSessionAttachOrLaunchRequest(
                session: self,
                canPrompt: false,
                objectType: objectType,
                hasServerConnection: false,
                serverConnection: iTermGeneralServerConnection(),
                urlString: urlString,
                allowURLSubs: false,
                environment: ["ITERM_WORKGROUP_ID": workgroupInstanceID],
                customShell: nil,
                oldCWD: oldCWD,
                forceUseOldCWD: true,
                command: wrapped,
                isUTF8: nil,
                substitutions: nil,
                windowController: windowController,
                ready: nil) { _, _ in }
            factory.attachOrLaunch(with: request)
        }
    }

    // Reload (toolbar reload button on a code-review-mode session, or
    // the broken-pipe restart announcement). The program is already
    // running; on Start, kill+restart the session with the new
    // resolved command. Reads the raw template from the cached
    // `codeReviewRawCommand` set during the initial spawn.
    //
    // restart(withCommand:) feeds through replaceTerminatedShellWith-
    // NewInstance, which preserves the existing _environment — so
    // ITERM_WORKGROUP_ID set during the initial deferred launch
    // carries forward across reloads.
    @objc
    func reloadCodeReviewPromptOverlay() {
        guard let rawCommand = codeReviewRawCommand else { return }
        showCodeReviewPromptOverlay { [weak self] text in
            guard let self else { return }
            let wrapped = self.wrappedCommandForCodeReview(text: text,
                                                            rawCommand: rawCommand)
            self.restart(withCommand: wrapped ?? "")
        }
    }

    private func showCodeReviewPromptOverlay(onStart: @escaping (String) -> Void) {
        guard let sessionView: SessionView = view else { return }
        // On the second and later presentations for this session, default to
        // the prompt the user last submitted (a preset or a hand-edited
        // value) rather than the store's last-selected preset. The first
        // presentation has no prior submission, so fall back to the store.
        let defaultPrompt = codeReviewLastUsedPrompt ?? CodeReviewPromptStore.shared.defaultPromptText
        sessionView.presentCodeReviewPromptOverlay(defaultPrompt: defaultPrompt) { [weak self] text in
            self?.codeReviewLastUsedPrompt = text
            onStart(text)
            // The overlay sits over scrolled-back content; once the user
            // submits, snap to the bottom so the launched program's output
            // is visible and the session follows new output.
            self?.scrollToBottomAfterCodeReviewPrompt()
        }
    }

    private func scrollToBottomAfterCodeReviewPrompt() {
        guard let textview else { return }
        textview.scrollEnd()
        (textview.enclosingScrollView as? PTYScrollView)?.detectUserScroll()
    }

    private func wrappedCommandForCodeReview(text: String,
                                               rawCommand: String) -> String? {
        // Single-quote wrap so the value is one positional arg in any
        // POSIX-style shell (bash, zsh, fish, …). Normalize line
        // endings first: a stray CR from NSTextView or pasted content
        // gets backslash-escaped to `\<CR>` by
        // commandByWrappingInLoginShell:, which the user's shell then
        // reads as line continuation — splitting the wrapping `'…'`
        // and producing "unmatched '". LF is safe inside `'…'`.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let shellEscaped =
            "'" + normalized.replacingOccurrences(of: "'", with: "'\\''") + "'"
        genericScope.setValue(shellEscaped, forVariableNamed: "codeReviewPrompt")

        // The system prompt is user-editable in Settings > General > AI >
        // Prompts. Materialize the current value to a per-session temp
        // file and expose its path as `codeReviewSystemPromptFile`, which
        // the command template feeds to `claude --append-system-prompt-file`.
        // The template wraps the value in single quotes, so a bare path is
        // expected here; temp paths under NSTemporaryDirectory don't
        // contain quotes. Falls back to the bundled file if the write
        // fails so the command still has a usable system prompt.
        let bundledFallback = NSString.path(withComponents:
            [Bundle.main.bundlePath, "Contents", "Resources", "code-review-system-prompt.txt"])
        let systemPromptPath = writeCodeReviewSystemPromptFile() ?? bundledFallback
        genericScope.setValue(systemPromptPath, forVariableNamed: "codeReviewSystemPromptFile")

        let resolvedCommand = evaluateSwiftyTemplate(rawCommand)
        if resolvedCommand.isEmpty {
            return nil
        }
        return ITAddressBookMgr.commandByWrapping(inLoginShell: resolvedCommand)
    }

    // Writes the configured code-review system prompt to a stable
    // per-session temp file and returns its path, or nil if the write
    // fails. Reusing one path per session GUID means reloads overwrite
    // rather than accumulate temp files. The configured value comes from
    // kPreferenceKeyAIPromptCodeReviewSystem, whose registered default is
    // the bundled code-review-system-prompt.txt.
    private func writeCodeReviewSystemPromptFile() -> String? {
        let text = iTermPreferences.string(forKey: kPreferenceKeyAIPromptCodeReviewSystem) ?? ""
        let filename = "iterm2-code-review-system-prompt-\(guid).txt"
        let path = NSString.path(withComponents: [NSTemporaryDirectory(), filename])
        do {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            return path
        } catch {
            RLog("Failed to write code review system prompt to \(path): \(error)")
            return nil
        }
    }

    private func evaluateSwiftyTemplate(_ template: String) -> String {
        let swifty = iTermSwiftyString(string: template,
                                        scope: genericScope,
                                        sideEffectsAllowed: false,
                                        observer: nil)
        var resolved = ""
        swifty.evaluateSynchronously(true,
                                       sideEffectsAllowed: false,
                                       with: genericScope) { value, _, _ in
            resolved = value ?? ""
        }
        return resolved
    }
}
