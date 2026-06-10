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
        }
        .onDisappear {
            // Covered by a pushed screen (session view) or popped: drop focus
            // so the keyboard doesn't linger over content it can't edit.
            inputFocused = false
        }
        .sheet(item: $model.sessionPicker) { request in
            SessionPickerSheet(request: request)
        }
        .sheet(isPresented: $showMentionPicker) {
            MentionPickerSheet { session in
                insertMention(session)
            }
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
                                revision: draftRevision) {
                draftIsEmpty = composer.isEmpty
                draftRevision += 1
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 18))

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.accentColor : Color(.systemGray3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !draftIsEmpty
    }

    private let typingIndicatorID = "typing-indicator"

    private func send() {
        let text = composer.serializedText
        companionLog("send(): clearing draft (\(text.count) chars)")
        model.send(text: text)
        composer.clear()
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
