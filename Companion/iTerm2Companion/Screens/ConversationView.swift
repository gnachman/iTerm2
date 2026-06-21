//
//  ConversationView.swift
//  iTerm2 Companion
//
//  The chat transcript plus a message input row, styled after the iTerm2 AI
//  chat. New messages and typing-status changes scroll into view.
//

import SwiftUI
import CompanionProtocol

struct ConversationView: View {
    @Environment(AppModel.self) private var model
    let chatID: String

    @State private var composer = MentionComposerController()
    @State private var draftIsEmpty = true
    @State private var draftRevision = 0
    @State private var showMentionPicker = false
    @State private var inputFocused = false
    @State private var dictationProblem: String?
    @State private var confirmingEnableDictation = false

    private var title: String {
        model.chats.first { $0.chat.id == chatID }?.chat.title ?? "Chat"
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            transcript
            Divider()
            inputRow
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.conversationDidAppear(chatID: chatID)
            warmDictationModel()
        }
        .onDisappear {
            // Covered by a pushed screen (session view) or popped: drop focus
            // so the keyboard doesn't linger over content it can't edit.
            inputFocused = false
            // Leaving the chat cancels any in-progress dictation (releases the
            // mic and audio session) and discards the partial transcript. Use
            // commitLiveTranscript("") so the inserted live segment is actually
            // removed (endLiveTranscript only clears tracking, leaving the text).
            if model.voiceCapture.state != .idle {
                model.voiceCapture.cancel()
                composer.commitLiveTranscript("")
            }
        }
        .sheet(item: $model.sessionPicker) { request in
            SessionPickerSheet(request: request)
        }
        .sheet(isPresented: $showMentionPicker) {
            MentionPickerSheet { session in
                insertMention(session)
            }
        }
        .onChange(of: model.voiceCapture.liveText) { _, text in
            composer.updateLiveTranscript(text)
            draftIsEmpty = composer.isEmpty
            draftRevision += 1
        }
        // Haptic when dictation actually starts and stops (keyed on the real
        // state transition, so it fires whether toggled by tap or programmatically).
        .sensoryFeedback(trigger: model.voiceCapture.state) { old, new in
            switch (old, new) {
            case (.idle, .listening):
                return .impact(weight: .medium, intensity: 0.9)
            case (.listening, .transcribing), (.listening, .idle):
                return .impact(weight: .heavy, intensity: 1.0)
            default:
                return nil
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

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.isLoadingConversation && model.messages.isEmpty {
                    ProgressView("Loading…")
                        .padding(.top, 48)
                }
                LazyVStack(spacing: 10) {
                    ForEach(model.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.uniqueID)
                    }
                    if model.isAgentTyping {
                        TypingIndicatorView()
                            .id(typingIndicatorID)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.isAgentTyping) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                model.refreshSessionsForMentionPicker()
                showMentionPicker = true
            } label: {
                Image(systemName: "at.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Mention a session")

            MentionComposerView(controller: composer,
                                isFocused: $inputFocused,
                                placeholder: "Message",
                                revision: draftRevision,
                                isDictating: model.voiceCapture.state != .idle) {
                draftIsEmpty = composer.isEmpty
                draftRevision += 1
            }
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
        // The chat was deleted on the Mac: the transcript stays readable,
        // but nothing can be composed or sent.
        .disabled(model.openChatWasDeleted)
        .opacity(model.openChatWasDeleted ? 0.4 : 1)
        .onChange(of: model.openChatWasDeleted) { _, deleted in
            if deleted {
                inputFocused = false
            }
        }
    }

    private var canSend: Bool {
        !draftIsEmpty
    }

    private let typingIndicatorID = "typing-indicator"

    // MARK: - Dictation

    @ViewBuilder
    private var micButton: some View {
        let manager = model.whisperManager
        let listening = model.voiceCapture.state == .listening
        Button(action: toggleDictation) {
            switch manager.status {
            case .downloading, .preparing:
                ProgressView()
                    .frame(width: 30, height: 30)
            default:
                Image(systemName: listening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(listening ? Color.red : Color.accentColor)
                    .scaleEffect(listening ? 1 + CGFloat(model.voiceCapture.audioLevel) * 0.3 : 1)
                    .animation(.easeOut(duration: 0.1), value: model.voiceCapture.audioLevel)
            }
        }
        .accessibilityLabel(listening ? "Stop dictation" : "Dictate a message")
        // VU meter floats above the button while listening. The overlay does not
        // affect layout, and TimelineView polls the live level at display rate
        // (only while listening, since the overlay exists only then).
        .overlay(alignment: .top) {
            if listening {
                TimelineView(.animation) { _ in
                    VUMeterView(level: model.voiceCapture.currentInputLevel())
                }
                .offset(y: -72)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: listening)
    }

    private func toggleDictation() {
        let manager = model.whisperManager
        let voice = model.voiceCapture

        // Tapping while listening always stops.
        if voice.state == .listening {
            Task {
                let finalText = await voice.stop()
                composer.commitLiveTranscript(finalText)
                draftIsEmpty = composer.isEmpty
                draftRevision += 1
            }
            return
        }
        guard voice.state == .idle else { return } // mid-finalize: ignore

        switch manager.status {
        case .ready:
            beginDictation()
        case .downloading, .preparing:
            break // model is loading; the button shows a spinner
        case .idle, .failed:
            guard manager.isDownloaded else {
                // Not set up yet: ask before enabling and downloading a model.
                confirmingEnableDictation = true
                return
            }
            // Cached weights but not loaded this session: load+prewarm (the
            // spinner), then start recording so it is a single tap.
            Task {
                await manager.prepare()
                if case .ready = manager.status {
                    beginDictation()
                }
            }
        }
    }

    /// The user agreed to set dictation up from the mic button: enable it, select
    /// the default model, and start downloading. The mic button shows a spinner
    /// (driven by the manager's .downloading/.preparing status) until it is ready.
    private func enableAndDownloadDictation() {
        model.whisperManager.enableWithDefaultModel()
        Task {
            await model.whisperManager.prepare()
            // Start dictating as soon as the first-run download + load finishes,
            // so it is one continuous action. Silence is harmless (VAD skips it)
            // if the user is not ready to speak yet.
            if case .ready = model.whisperManager.status {
                beginDictation()
            }
        }
    }

    private func beginDictation() {
        composer.beginLiveTranscript()
        Task {
            do {
                try await model.voiceCapture.start()
            } catch {
                composer.endLiveTranscript()
                dictationProblem = dictationMessage(for: error)
                companionLog("Dictation start failed: \(String(describing: error))")
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

    private func dictationMessage(for error: Error) -> String {
        switch error {
        case VoiceCaptureError.microphonePermissionDenied:
            return "Allow microphone access for iTerm2 Buddy in the Settings app to dictate."
        case VoiceCaptureError.modelNotReady:
            return "The voice model is not ready yet. Try again in a moment."
        default:
            return "Could not start dictation."
        }
    }

    private func send() {
        let voice = model.voiceCapture
        // Sending while dictating finalizes the transcript first so nothing is
        // dropped, then sends.
        guard voice.state == .idle else {
            Task {
                let finalText = await voice.stop()
                composer.commitLiveTranscript(finalText)
                sendComposedDraft()
            }
            return
        }
        sendComposedDraft()
    }

    private func sendComposedDraft() {
        let text = composer.serializedText
        companionLog("send(): clearing draft (\(text.count) chars)")
        model.send(text: text)
        composer.clear()
        draftIsEmpty = composer.isEmpty
    }

    /// Insert an @-mention of the chosen session at the cursor as an atomic
    /// styled token (like the Mac compose field); it serializes to "@<guid>"
    /// when the message is sent.
    private func insertMention(_ session: CompanionSessionSummary) {
        showMentionPicker = false
        composer.insertMention(guid: session.guid, displayName: session.name)
        inputFocused = true
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if model.isAgentTyping {
                proxy.scrollTo(typingIndicatorID, anchor: .bottom)
            } else if let last = model.messages.last {
                proxy.scrollTo(last.uniqueID, anchor: .bottom)
            }
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

private struct TypingIndicatorView: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 7, height: 7)
                    .foregroundStyle(.secondary)
                    .opacity(phase == Double(index) ? 1 : 0.3)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                phase = 2
            }
        }
    }
}

/// Lists the mac's terminal sessions so the composer's @ button can insert a
/// mention of one.
private struct MentionPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onSelect: (CompanionSessionSummary) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if model.sessions.isEmpty {
                    Text("No sessions available.")
                        .foregroundStyle(.secondary)
                } else {
                    List(model.sessions, id: \.guid) { session in
                        Button {
                            onSelect(session)
                        } label: {
                            // Default (borderless) button style so the row
                            // highlights on tap; color the text explicitly so
                            // it doesn't take the accent tint.
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name)
                                    .foregroundStyle(.primary)
                                if !session.subtitle.isEmpty {
                                    Text(session.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .navigationTitle("Mention a Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Lists the mac's terminal sessions so a selectSessionRequest can be
/// resolved from the phone.
private struct SessionPickerSheet: View {
    @Environment(AppModel.self) private var model
    let request: AppModel.SessionPickerRequest

    var body: some View {
        NavigationStack {
            Group {
                if model.sessions.isEmpty {
                    Text("No sessions available.")
                        .foregroundStyle(.secondary)
                } else {
                    List(model.sessions, id: \.guid) { session in
                        Button {
                            model.respondSelectSession(requestMessageID: request.requestMessageID,
                                                       original: request.originalMessage,
                                                       terminal: request.terminal,
                                                       guid: session.guid)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name)
                                    .foregroundStyle(.primary)
                                if !session.subtitle.isEmpty {
                                    Text(session.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .navigationTitle("Select a Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.sessionPicker = nil
                    }
                }
            }
        }
    }
}
