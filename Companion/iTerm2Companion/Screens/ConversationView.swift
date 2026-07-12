//
//  ConversationView.swift
//  iTerm2 Companion
//
//  The chat transcript plus a message input row, styled after the iTerm2 AI
//  chat. New messages and typing-status changes scroll into view. The input row
//  (composer + dictation + send) is the shared AgentComposerBar.
//

import SwiftUI

struct ConversationView: View {
    @Environment(AppModel.self) private var model
    let chatID: String

    private var title: String {
        model.chat(for: chatID)?.chat.title ?? "Chat"
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            transcript
            if model.conversationRefreshFailed {
                refreshFailedBanner
            }
            Divider()
            AgentComposerBar(placeholder: "Message",
                             isDisabled: model.openChatWasDeleted) { text in
                model.send(text: text)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Mute needs a mac that persists the muted set; hide the toggle
            // rather than offer one that does nothing on an older mac.
            if model.macSupportsChatMuting {
                ToolbarItem(placement: .primaryAction) {
                    let muted = model.isChatMuted(chatID: chatID)
                    Button {
                        model.setChatMuted(chatID: chatID, muted: !muted)
                    } label: {
                        Label(muted ? "Unmute" : "Mute",
                              systemImage: muted ? "bell.slash.fill" : "bell")
                    }
                    .accessibilityLabel(muted ? "Unmute this chat" : "Mute this chat")
                }
            }
        }
        .onAppear {
            // A real navigation to this chat (vs the internal tab-sync/reconnect
            // callers), so its load failures can escalate the refresh banner.
            model.conversationDidAppear(chatID: chatID, userInitiated: true)
        }
        .sheet(item: $model.sessionPicker) { request in
            SessionPickerSheet(request: request)
        }
    }

    private var refreshFailedBanner: some View {
        // Escalates from a soft "showing cached" note to the real error once the
        // failure is no longer plausibly transient.
        let escalated = model.conversationRefreshError
        return HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(escalated ?? "Couldn’t refresh. Showing the last loaded messages.")
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(escalated == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background((escalated == nil ? Color.yellow : Color.red).opacity(0.12))
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

    private let typingIndicatorID = "typing-indicator"

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
