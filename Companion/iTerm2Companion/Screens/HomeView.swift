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
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            model.deleteChat(chatID: entry.chat.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
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

    /// Height of the text column (plus the row's vertical padding), captured
    /// at layout time so the icon can be sized relative to the cell. The
    /// icon is excluded from the measurement to avoid a feedback loop.
    @State private var contentHeight: CGFloat = 56

    private var iconSize: CGFloat { contentHeight * 0.65 }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(chat.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.timestamp(for: chat.lastModifiedDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let snippet = entry.snippet, !snippet.isEmpty {
                    Text(model.renderedSnippet(snippet))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeight = height + 8
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// The last-activity stamp, iMessage style: time of day within the last
    /// 24 hours, weekday within the last week, M/d/yy beyond that.
    private static func timestamp(for date: Date) -> String {
        let age = Date().timeIntervalSince(date)
        if age < 24 * 60 * 60 {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if age < 7 * 24 * 60 * 60 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).year(.twoDigits))
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
                .frame(width: iconSize, height: iconSize)
                .clipShape(Circle())
        } else {
            Image(systemName: "bubble.left")
                .font(.system(size: iconSize * 0.45))
                .foregroundStyle(.secondary)
                .frame(width: iconSize, height: iconSize)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
    }
}
