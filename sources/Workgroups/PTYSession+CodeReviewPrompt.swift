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
        let defaultPrompt = CodeReviewPromptStore.shared.defaultPromptText
        // Route workgroup peer-switch / toolbar shortcuts to this host
        // session even while the overlay's NSTextView is first responder.
        // Without this hook the text view consumes ^1, etc. as text input
        // before PTYTextView's performKeyEquivalent: ever runs.
        let shortcutHandler: (NSEvent) -> Bool = { [weak self] event in
            guard let self else { return false }
            return self.textViewWorkgroupShortcutHandlesEvent(event)
        }
        sessionView.presentCodeReviewPromptOverlay(defaultPrompt: defaultPrompt,
                                                   workgroupShortcutHandler: shortcutHandler,
                                                   onStart: onStart)
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

        let resolvedCommand = evaluateSwiftyTemplate(rawCommand)
        if resolvedCommand.isEmpty {
            return nil
        }
        return ITAddressBookMgr.commandByWrapping(inLoginShell: resolvedCommand)
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
