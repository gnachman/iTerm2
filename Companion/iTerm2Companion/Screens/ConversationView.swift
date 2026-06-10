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

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

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
        .sheet(item: $model.sessionPicker) { request in
            SessionPickerSheet(request: request)
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
            .onChange(of: model.messages.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.isAgentTyping) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground),
                           in: RoundedRectangle(cornerRadius: 18))
                .focused($inputFocused)

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
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let typingIndicatorID = "typing-indicator"

    private func send() {
        let text = draft
        companionLog("send(): clearing draft (\(text.count) chars)")
        model.send(text: text)
        draft = ""
        // Clearing in the same transaction as the tap can leave the visible
        // text behind (vertical-axis TextField quirk, especially with marked
        // autocomplete text); clear again a beat later.
        Task { @MainActor in
            draft = ""
        }
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
                                if !session.subtitle.isEmpty {
                                    Text(session.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
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
