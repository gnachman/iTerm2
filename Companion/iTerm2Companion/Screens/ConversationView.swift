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
    @EnvironmentObject private var model: AppModel
    let chatID: String

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var title: String {
        model.chats.first { $0.chat.id == chatID }?.chat.title ?? "Chat"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                Divider()
                inputRow
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        model.leaveConversation()
                    } label: {
                        Label("Chats", systemImage: "chevron.left")
                    }
                }
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
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
        draft = ""
        model.send(text: text)
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
