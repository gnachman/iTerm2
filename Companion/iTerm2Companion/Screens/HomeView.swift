//
//  HomeView.swift
//  iTerm2 Companion
//
//  The chat list, with a New Chat button. Tapping a chat opens the conversation.
//

import SwiftUI
import CompanionProtocol

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.chats.isEmpty {
                    emptyState
                } else {
                    List(model.chats) { chat in
                        Button {
                            model.openChat(chat.id)
                        } label: {
                            ChatRow(chat: chat)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .refreshable { model.refreshHome() }
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.beginCreateChat()
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("No chats yet")
                .font(.title3.bold())
            Text("Tap New Chat to start a conversation with a session or the orchestrator.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

private struct ChatRow: View {
    let chat: ChatDTO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: chat.orchestrationEnabled ? "rectangle.3.group" : "terminal")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title)
                    .font(.headline)
                    .lineLimit(1)
                if let snippet = chat.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
