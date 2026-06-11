//
//  HomeView.swift
//  iTerm2 Companion
//
//  The chat list, with a New Chat button. Tapping a chat opens the conversation.
//

import SwiftUI
import CompanionProtocol

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.chats.isEmpty {
                emptyState
            } else {
                List(model.chats, id: \.chat.id) { entry in
                    NavigationLink(value: AppModel.Destination.conversation(chatID: entry.chat.id)) {
                        ChatRow(entry: entry)
                    }
                }
                .listStyle(.plain)
                .refreshable { model.refreshHome() }
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.beginSettings()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.beginCreateChat()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
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
    @Environment(AppModel.self) private var model
    let entry: CompanionChatListEntry

    private var chat: Chat { entry.chat }

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title)
                    .font(.headline)
                    .lineLimit(1)
                if let snippet = entry.snippet, !snippet.isEmpty {
                    Text(model.renderedSnippet(snippet))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// The chat's AI-generated icon (a small PNG the Mac stores on the Chat),
    /// circle-clipped like the Mac's chat list; a default chat-bubble icon
    /// when none has been generated yet.
    @ViewBuilder
    private var icon: some View {
        if let data = chat.icon, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            Image(systemName: "bubble.left")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
    }
}
