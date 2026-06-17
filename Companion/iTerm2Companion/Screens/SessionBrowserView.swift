//
//  SessionBrowserView.swift
//  iTerm2 Companion
//
//  The Sessions tab's root: the Mac's sessions organized the way the user
//  sees them, window > tab > pane, with one more level under panes that host
//  a peer group (each peer labeled with its role, e.g. “Code Review”).
//  Session rows drill into the read-only session view.
//

import SwiftUI
import CompanionProtocol

struct SessionBrowserView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let tree = model.sessionTree {
                if tree.windows.isEmpty {
                    ContentUnavailableView {
                        Label("No Sessions", systemImage: "terminal")
                    } description: {
                        Text("Your Mac has no terminal windows right now.")
                    }
                } else {
                    treeList(tree)
                }
            } else if let error = model.sessionTreeError {
                ContentUnavailableView {
                    Label("Can’t Load Sessions", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") {
                        model.sessionTreeError = nil
                        Task { await model.refreshSessionBrowser() }
                    }
                }
            } else {
                ProgressView("Loading sessions…")
            }
        }
        .navigationTitle("Sessions")
        .task {
            await model.refreshSessionBrowser()
        }
    }

    private func treeList(_ tree: CompanionSessionTree) -> some View {
        List {
            ForEach(Array(tree.windows.enumerated()), id: \.offset) { _, window in
                Section {
                    ForEach(Array(window.tabs.enumerated()), id: \.offset) { _, tab in
                        row(icon: "square.on.square", title: tab.title, level: 0)
                        ForEach(Array(tab.panes.enumerated()), id: \.offset) { _, pane in
                            paneRows(pane)
                        }
                    }
                } header: {
                    Label(window.title, systemImage: "macwindow")
                        .lineLimit(1)
                }
            }
        }
        .refreshable {
            await model.refreshSessionBrowser()
        }
    }

    @ViewBuilder
    private func paneRows(_ pane: CompanionSessionTree.Pane) -> some View {
        sessionRow(session: pane.session,
                   title: pane.session.name,
                   level: 1)
        ForEach(Array(pane.peers.enumerated()), id: \.offset) { _, peer in
            sessionRow(session: peer.session,
                       title: peerTitle(peer),
                       level: 2)
        }
    }

    /// “Code Review: zsh”, collapsing to just the role when the session has
    /// no distinct name.
    private func peerTitle(_ peer: CompanionSessionTree.Peer) -> String {
        if peer.session.name.isEmpty || peer.session.name == peer.roleName {
            return peer.roleName
        }
        return "\(peer.roleName): \(peer.session.name)"
    }

    private func sessionRow(session: CompanionSessionSummary,
                            title: String,
                            level: Int) -> some View {
        NavigationLink(value: AppModel.Destination.session(guid: session.guid,
                                                          title: title)) {
            row(icon: "terminal",
                title: title,
                subtitle: session.subtitle.isEmpty ? nil : session.subtitle,
                level: level)
        }
    }

    private func row(icon: String,
                     title: String,
                     subtitle: String? = nil,
                     level: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, CGFloat(level) * 24)
    }
}
