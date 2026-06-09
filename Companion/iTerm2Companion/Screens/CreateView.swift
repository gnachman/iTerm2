//
//  CreateView.swift
//  iTerm2 Companion
//
//  Choose whether a new chat talks to a single session or the orchestrator. For
//  a single-session chat the user then picks the session.
//

import SwiftUI
import CompanionProtocol

struct CreateView: View {
    @EnvironmentObject private var model: AppModel
    @State private var kind: Kind = .session

    private enum Kind: Hashable {
        case session
        case orchestrator
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Chat with", selection: $kind) {
                        Text("A session").tag(Kind.session)
                        Text("The orchestrator").tag(Kind.orchestrator)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(kind == .orchestrator
                         ? "The orchestrator can see and act across all of your sessions."
                         : "The chat is bound to one terminal session.")
                }

                if kind == .session {
                    Section("Session") {
                        if model.sessions.isEmpty {
                            Text("No sessions available.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.sessions) { session in
                                Button {
                                    model.createChat(mode: .session(guid: session.guid))
                                } label: {
                                    SessionRow(session: session)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    Section {
                        Button {
                            model.createChat(mode: .orchestrator)
                        } label: {
                            Label("Create Orchestrator Chat", systemImage: "rectangle.3.group")
                        }
                    }
                }
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.route = .home }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: SessionDTO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.body)
                    .lineLimit(1)
                if !session.subtitle.isEmpty {
                    Text(session.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
