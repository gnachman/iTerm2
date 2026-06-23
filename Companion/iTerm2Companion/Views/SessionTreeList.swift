//
//  SessionTreeList.swift
//  iTerm2 Companion
//
//  Renders the Mac's sessions the way the user sees them, window > tab > pane,
//  with one more level under panes that host a peer group (each peer labeled
//  with its role, e.g. “Code Review”). The content and tap behavior of each
//  session row is supplied by the caller: the Sessions tab drills into the
//  read-only session view, while the mention picker selects a session and
//  offers a preview.
//

import SwiftUI
import CompanionProtocol

/// The full session browser: the loading / error / empty / populated state
/// ladder around a `SessionTreeList`, backed by the shared `model.sessionTree`.
/// The Sessions tab and the mention picker both embed it, supplying their own
/// session-row content (and tap behavior) through `sessionRow`.
struct SessionTreeBrowser<SessionRow: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var sessionRow: (CompanionSessionSummary, String, Int) -> SessionRow

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
                    SessionTreeList(tree: tree,
                                    onRefresh: { await model.refreshSessionBrowser() },
                                    sessionRow: sessionRow)
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
        .task {
            await model.refreshSessionBrowser()
        }
    }
}

struct SessionTreeList<SessionRow: View>: View {
    let tree: CompanionSessionTree
    let onRefresh: () async -> Void
    /// Builds the row for one session, given its display title and indentation
    /// level (1 for a pane's own session, 2 for a peer).
    @ViewBuilder var sessionRow: (CompanionSessionSummary, String, Int) -> SessionRow

    var body: some View {
        List {
            ForEach(Array(tree.windows.enumerated()), id: \.offset) { _, window in
                Section {
                    ForEach(Array(window.tabs.enumerated()), id: \.offset) { _, tab in
                        SessionTreeRow(icon: "square.on.square", title: tab.title, level: 0)
                        ForEach(Array(tab.panes.enumerated()), id: \.offset) { _, pane in
                            sessionRow(pane.session, pane.session.name, 1)
                            ForEach(Array(pane.peers.enumerated()), id: \.offset) { _, peer in
                                sessionRow(peer.session, Self.peerTitle(peer), 2)
                            }
                        }
                    }
                } header: {
                    Label(window.title, systemImage: "macwindow")
                        .lineLimit(1)
                }
            }
        }
        .refreshable {
            await onRefresh()
        }
    }

    /// “Code Review: zsh”, collapsing to just the role when the session has no
    /// distinct name.
    static func peerTitle(_ peer: CompanionSessionTree.Peer) -> String {
        if peer.session.name.isEmpty || peer.session.name == peer.roleName {
            return peer.roleName
        }
        return "\(peer.roleName): \(peer.session.name)"
    }
}

/// One indented row in the session hierarchy: a leading icon, a title, and an
/// optional subtitle.
struct SessionTreeRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let level: Int

    var body: some View {
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
