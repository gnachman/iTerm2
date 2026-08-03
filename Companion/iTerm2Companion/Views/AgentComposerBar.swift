//
//  AgentComposerBar.swift
//  iTerm2 Companion
//
//  The message input row shared by the chat screen and the live session view's
//  compose overlay: a mention-aware composer, an on-device voice-dictation
//  button, and a send button. It owns all of the dictation control flow so both
//  call sites behave identically; the host supplies only a placeholder and an
//  onSend closure that receives the serialized draft ("@<guid>" tokens intact).
//

import SwiftUI
import CompanionProtocol

struct AgentComposerBar: View {
    @Environment(AppModel.self) private var model

    let placeholder: String
    /// The @-mention button (and its picker sheet) is shown only where mentioning
    /// another session makes sense. The live session overlay hides it.
    var showsMentionButton: Bool = true
    /// Focus the field (and raise the keyboard) as soon as the bar appears. The
    /// overlay wants this; the chat screen lets the user tap in.
    var autoFocus: Bool = false
    /// Disables composing/sending, e.g. when the chat was deleted on the Mac.
    var isDisabled: Bool = false
    /// Notified whenever the draft's empty state changes, so a host (the session
    /// compose overlay) can avoid discarding a typed-but-unsent draft.
    var onEmptyChanged: ((Bool) -> Void)? = nil
    /// Seeds the field on appear, e.g. to restore a draft whose send failed.
    var initialText: String = ""
    /// Bumped by the caller to (re)seed initialText (e.g. restore a failed-send
    /// draft) without recreating the composer. See MentionComposerView.
    var seedGeneration: Int = 0
    /// Receives the serialized draft when the user sends. The bar clears itself.
    let onSend: (String) -> Void

    @State private var composer = MentionComposerController()
    @State private var draftIsEmpty = true
    @State private var draftRevision = 0
    @State private var showMentionPicker = false
    @State private var inputFocused = false
    @State private var dictationProblem: String?
    @State private var confirmingEnableDictation = false
    /// Latches an in-flight send so a rapid second Send tap is ignored while the
    /// first is finalizing dictation. Both taps otherwise see ownsDictation == true
    /// (ownership releases only when finish() completes) and both call finish(); the
    /// second loses the token guard and returns nil, showing a false "interrupted,
    /// text kept" alert even though the first send already delivered and cleared.
    @State private var isSending = false
    /// Stable identity for THIS bar's dictation ownership. Two bars can be mounted
    /// at once (a chat's bar behind a session view's compose overlay), so who owns
    /// dictation lives in the shared DictationController; this bar owns it iff the
    /// controller's owner equals this token. The controller makes claim/start/stop
    /// atomic, so this token is only ever passed in, never used to hand-roll
    /// ownership transitions here.
    @State private var dictationToken = UUID()
    private var ownsDictation: Bool { model.dictation.owns(dictationToken) }

    var body: some View {
        inputRow
            .onAppear {
                warmDictationModel()
                // initialText is seeded inside MentionComposerView (keyed on
                // seedGeneration), not here, so it can't be lost to onAppear
                // ordering and doesn't need view-identity churn to re-apply.
                if autoFocus {
                    inputFocused = true
                }
            }
            .onDisappear {
                inputFocused = false
                // Leaving relinquishes any dictation THIS bar owns (the controller
                // cancels the recorder + releases the token, atomically, even mid-
                // startup); discard our partial live span.
                let owned = ownsDictation
                model.dictation.relinquish(dictationToken)
                if owned { composer.commitLiveTranscript("") }
            }
            .onChange(of: draftIsEmpty) { _, isEmpty in
                onEmptyChanged?(isEmpty)
            }
            .onChange(of: model.dictation.owner) { oldValue, newValue in
                // Lost ownership without our own teardown (a tab switch / another
                // bar) - onDisappear won't fire for a still-mounted hidden tab, so
                // strip the stranded live-transcript span here.
                if oldValue == dictationToken, newValue != dictationToken {
                    composer.commitLiveTranscript("")
                    syncDraft()
                }
            }
            .onChange(of: isDisabled) { _, disabled in
                if disabled { inputFocused = false }
            }
            .onChange(of: model.dictation.voice.liveText) { _, text in
                // Only the bar that owns dictation consumes the transcript.
                guard ownsDictation else { return }
                composer.updateLiveTranscript(text)
                syncDraft()
            }
            // Haptic when dictation actually starts and stops (keyed on the real
            // state transition, so it fires whether toggled by tap or
            // programmatically). Only for the bar that owns this dictation.
            .sensoryFeedback(trigger: model.dictation.voice.state) { old, new in
                guard ownsDictation else { return nil }
                switch (old, new) {
                case (.idle, .listening):
                    return .impact(weight: .medium, intensity: 0.9)
                case (.listening, .transcribing), (.listening, .idle):
                    return .impact(weight: .heavy, intensity: 1.0)
                default:
                    return nil
                }
            }
            .sheet(isPresented: $showMentionPicker) {
                MentionPickerSheet { session, title in
                    insertMention(session, title: title)
                }
            }
            .alert("Voice Input", isPresented: Binding(
                get: { dictationProblem != nil },
                set: { if !$0 { dictationProblem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dictationProblem ?? "")
            }
            .alert("Enable Voice Dictation?", isPresented: $confirmingEnableDictation) {
                Button("Download & Enable") { enableAndDownloadDictation() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Dictation needs a speech model (about 240 MB) downloaded to this device. It runs entirely on your phone, with no cloud and no cost. You can change or remove it later in Settings.")
            }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if showsMentionButton {
                Button {
                    showMentionPicker = true
                } label: {
                    Image(systemName: "at.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel("Mention a session")
            }

            MentionComposerView(controller: composer,
                                isFocused: $inputFocused,
                                placeholder: placeholder,
                                revision: draftRevision,
                                // Lock editing only when THIS bar owns an active
                                // dictation, not when another mounted bar does.
                                isDictating: model.dictation.isActive(dictationToken),
                                onChange: {
                                    syncDraft()
                                },
                                initialText: initialText,
                                seedGeneration: seedGeneration)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 18))

            micButton

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.accentColor : Color(.systemGray3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }

    private var canSend: Bool {
        !draftIsEmpty && !isDisabled
    }

    // MARK: - Send

    private func send() {
        // Ignore a re-entrant tap while a dictation finalize is in flight (see
        // isSending): a second finish() would lose the token guard and falsely
        // report the send as interrupted.
        guard !isSending else { return }
        // If this bar owns dictation (even mid-startup, before the recorder is
        // listening), finalize it first so the dictated tail is committed, THEN
        // deliver. finish() returns nil if ownership was lost during stop (a tab
        // switch): don't deliver a draft now missing that tail - the pre-dictation
        // text stays for the user to retry.
        guard ownsDictation else {
            deliverComposedDraft()
            return
        }
        isSending = true
        Task {
            defer { isSending = false }
            guard await finishDictationAndCommit() else {
                // Dictation ownership was lost mid-stop (e.g. a tab switch raced the
                // Send tap), so the dictated tail was discarded. Don't send a
                // truncated draft silently - tell the user, keeping what they typed.
                companionLog("Finalize lost ownership mid-stop; not delivering a truncated draft")
                dictationProblem = "Dictation was interrupted before this could send. Your text is kept - tap Send again."
                return
            }
            deliverComposedDraft()
        }
    }

    /// Re-sync the @State mirrors of the (non-observable) composer after ANY
    /// mutation of it. canSend reads draftIsEmpty and MentionComposerView keys its
    /// re-layout on draftRevision, so these two must always move together - one
    /// helper so a future mutation site can't bump only one and silently desync the
    /// send button or the field's redisplay.
    private func syncDraft() {
        draftIsEmpty = composer.isEmpty
        draftRevision += 1
    }

    private func deliverComposedDraft() {
        let text = composer.serializedText
        companionLog("AgentComposerBar send(): clearing draft (\(text.count) chars)")
        onSend(text)
        composer.clear()
        syncDraft()
    }

    /// Insert an @-mention of the chosen session at the cursor as an atomic
    /// styled token (like the Mac compose field); it serializes to "@<guid>"
    /// when the message is sent. The title is the picker's display label (e.g.
    /// a peer's "Code Review: zsh", or just its role when the session has no
    /// distinct name), so the token keeps that context; it falls back to the
    /// session name only when the title is empty.
    private func insertMention(_ session: CompanionSessionSummary, title: String) {
        showMentionPicker = false
        let displayName = title.isEmpty ? session.name : title
        composer.insertMention(guid: session.guid, displayName: displayName)
        inputFocused = true
    }

    // MARK: - Dictation

    @ViewBuilder
    private var micButton: some View {
        let manager = model.whisperManager
        // Present as listening only when THIS bar owns the dictation. Another
        // mounted bar (e.g. a chat's bar behind the session compose overlay) may
        // be the real owner, and the recorder is shared.
        let listening = ownsDictation && model.dictation.voice.state == .listening
        // While another bar owns an active dictation, disable this mic so a tap
        // can't hit toggleDictation's stop path and commit into the wrong composer.
        let ownedByOther = !ownsDictation && model.dictation.voice.state != .idle
        Button(action: toggleDictation) {
            switch manager.status {
            case .downloading, .preparing:
                ProgressView()
                    .frame(width: 30, height: 30)
            default:
                Image(systemName: listening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(listening ? Color.red : Color.accentColor)
                    .scaleEffect(listening ? 1 + CGFloat(model.dictation.voice.audioLevel) * 0.3 : 1)
                    .animation(.easeOut(duration: 0.1), value: model.dictation.voice.audioLevel)
            }
        }
        .disabled(ownedByOther)
        .accessibilityLabel(listening ? "Stop dictation" : "Dictate a message")
        // VU meter floats above the button while listening. The overlay does not
        // affect layout, and TimelineView polls the live level at display rate
        // (only while listening, since the overlay exists only then).
        .overlay(alignment: .top) {
            if listening {
                TimelineView(.animation) { _ in
                    VUMeterView(level: model.dictation.voice.currentInputLevel())
                }
                .offset(y: -72)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: listening)
    }

    /// Stop the recorder (via the controller) and commit its final transcript into
    /// THIS composer. Returns whether it committed: false when ownership was lost
    /// during stop() (so the caller must not deliver a now-truncated draft). The
    /// controller owns the token/recorder teardown; this just moves text into the
    /// composer.
    @discardableResult
    private func finishDictationAndCommit() async -> Bool {
        guard let finalText = await model.dictation.finish(token: dictationToken) else {
            return false
        }
        composer.commitLiveTranscript(finalText)
        syncDraft()
        return true
    }

    private func toggleDictation() {
        // Tapping while WE are actively listening stops and commits.
        if ownsDictation, model.dictation.voice.state == .listening {
            Task { await finishDictationAndCommit() }
            return
        }
        // Ignore taps while the recorder is busy (ours mid-finalize, or another
        // bar's active dictation).
        guard model.dictation.voice.state == .idle else { return }

        switch model.whisperManager.status {
        case .ready:
            beginDictation()
        case .downloading, .preparing:
            break // model is loading; the button shows a spinner
        case .idle, .failed:
            guard model.whisperManager.isDownloaded else {
                // Not set up yet: ask before enabling and downloading a model.
                confirmingEnableDictation = true
                return
            }
            beginDictation() // start() loads the cached model, then records
        }
    }

    /// The user agreed to set dictation up from the mic button: enable the default
    /// model and start. The controller's start() performs the download+load; the
    /// mic button shows a spinner (driven by whisperManager.status) until ready.
    private func enableAndDownloadDictation() {
        model.whisperManager.enableWithDefaultModel()
        beginDictation()
    }

    /// Begin dictation for this bar through the controller, which claims ownership,
    /// loads the model, and starts the recorder atomically - re-checking ownership
    /// across each await so a dismissal (onDisappear -> relinquish) or tab switch
    /// (tabChanged -> cancelActive) during startup aborts cleanly with no hot mic.
    private func beginDictation() {
        let tab = model.selectedTab
        Task {
            switch await model.dictation.start(token: dictationToken, tab: tab) {
            case .started:
                // Open the live span ONLY now the recorder is actually listening.
                // Opening it before start()'s model load (a ~240 MB download on
                // first run) would leave an editable "span open but not recording"
                // window: text typed then lands at/after the zero-length liveRange
                // without advancing it, and the first transcript inserts before it,
                // garbling order. From here the liveText observer feeds the span.
                composer.beginLiveTranscript()
            case .alreadyActive, .busy, .superseded:
                break // the other (winning) start owns the span; nothing to do here
            case .failed(let message):
                dictationProblem = message
            }
        }
    }

    /// Load the model into memory ahead of the first tap so dictation starts
    /// instantly. No-op if voice is off, not downloaded, or already loading/ready.
    private func warmDictationModel() {
        let manager = model.whisperManager
        guard manager.isEnabled, manager.isDownloaded else { return }
        if case .idle = manager.status {
            Task { await manager.prepare() }
        }
    }
}

/// A small vertical VU meter: a track that fills bottom-to-top with the live
/// input level, with green/amber/red zones like a hardware meter.
private struct VUMeterView: View {
    let level: Float // 0...1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color(.systemGray5))
                Capsule()
                    .fill(color)
                    .frame(height: max(2, geo.size.height * CGFloat(min(1, max(0, level)))))
            }
        }
        .frame(width: 12, height: 64)
        .accessibilityHidden(true)
    }

    private var color: Color {
        if level > 0.85 { return .red }
        if level > 0.6 { return .orange }
        return .green
    }
}

/// Lets the composer's @ button pick a session to mention. It shows the same
/// window > tab > pane > peer hierarchy as the Sessions tab so the choice is
/// unambiguous: tapping a row's body selects that session, while the trailing
/// preview button opens a read-only look at it without committing the choice.
private struct MentionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Selects a session to mention, with the picker's display title (so peer
    /// rows keep their "Code Review: zsh" / role context in the token).
    let onSelect: (CompanionSessionSummary, String) -> Void

    /// The session being previewed (pushed onto the sheet's own stack), if any.
    @State private var preview: PreviewTarget?

    /// A session to preview; Identifiable so navigationDestination(item:) can
    /// drive the push.
    private struct PreviewTarget: Identifiable, Hashable {
        let guid: String
        let title: String
        var id: String { guid }
    }

    var body: some View {
        NavigationStack {
            SessionTreeBrowser { session, title, level in
                pickerRow(session: session, title: title, level: level)
            }
            .navigationTitle("Mention a Session")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $preview) { target in
                SessionView(guid: target.guid, title: target.title, allowsChat: false)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    /// A session row: tapping its body selects the session for the mention;
    /// the trailing eye button previews it without selecting.
    private func pickerRow(session: CompanionSessionSummary,
                           title: String,
                           level: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                onSelect(session, title)
            } label: {
                SessionTreeRow(icon: "terminal",
                               title: title,
                               subtitle: session.subtitle.isEmpty ? nil : session.subtitle,
                               level: level)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            // Plain so the row highlights on tap without tinting its contents.
            .buttonStyle(.plain)

            Button {
                preview = PreviewTarget(guid: session.guid, title: title)
            } label: {
                Image(systemName: "eye")
                    .foregroundStyle(Color.accentColor)
                    .padding(.leading, 4)
                    .contentShape(Rectangle())
            }
            // Borderless so it stays a discrete tap target alongside the row
            // body rather than activating the whole row.
            .buttonStyle(.borderless)
            .accessibilityLabel("Preview \(title)")
        }
    }
}
