//
//  CreateView.swift
//  iTerm2 Companion
//
//  Choose whether a new chat talks to a single session or the orchestrator. For
//  a single-session chat the user picks the session from the same
//  window > tab > pane hierarchy the Sessions tab and the mention picker show
//  (SessionTreeBrowser), so the list reads identically everywhere instead of a
//  flat, unorganized roster.
//

import SwiftUI
import CompanionProtocol

struct CreateView: View {
    @Environment(AppModel.self) private var model
    @State private var kind: Kind = .orchestrator
    /// The session being previewed in a sheet, if any.
    @State private var preview: PreviewTarget?

    private enum Kind: Hashable {
        case session
        case orchestrator
    }

    /// A session to preview before committing; Identifiable so `.sheet(item:)`
    /// can drive the presentation.
    private struct PreviewTarget: Identifiable, Hashable {
        let guid: String
        let title: String
        var id: String { guid }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Chat with", selection: $kind) {
                Text("A session").tag(Kind.session)
                Text("Orchestration").tag(Kind.orchestrator)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top)

            Text(kind == .orchestrator
                 ? "The orchestrator can see and act across all of your sessions."
                 : "The chat is bound to one terminal session.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)

            switch kind {
            case .session:
                // The same window > tab > pane > peer hierarchy the Sessions tab
                // and the mention picker render. Tapping a session row's body
                // creates a chat bound to that session; the trailing eye button
                // previews it read-only first.
                SessionTreeBrowser { session, title, level in
                    pickerRow(session: session, title: title, level: level)
                }
            case .orchestrator:
                Form {
                    Section {
                        Button {
                            model.createChat(mode: .orchestrator)
                        } label: {
                            Label("Create Orchestrator Chat", systemImage: "rectangle.3.group")
                        }
                    }
                }
            }
        }
        .navigationTitle("New Chat")
        .navigationBarTitleDisplayMode(.inline)
        // Present the read-only preview in its OWN NavigationStack inside a sheet,
        // fully isolated from the app's shared, path-bound NavigationStack. This
        // screen is itself a pushed entry on that stack, so a second push (via
        // navigationDestination(item:)) onto it would compete with async
        // navigationPath mutations that can land while the preview is up (a
        // reply-notification tap appending .conversation, or
        // openConversation(replacingPath:) replacing the path), producing a
        // botched transition or a resurrected preview. A sheet sidesteps the
        // shared stack entirely; the mention picker isolates the same way.
        .sheet(item: $preview) { target in
            NavigationStack {
                SessionView(guid: target.guid, title: target.title, allowsChat: false)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { preview = nil }
                        }
                    }
            }
        }
    }

    /// A session row: tapping its body creates a chat bound to the session; the
    /// trailing eye button previews it read-only without committing.
    private func pickerRow(session: CompanionSessionSummary,
                           title: String,
                           level: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                model.createChat(mode: .session(guid: session.guid))
            } label: {
                SessionTreeRow(icon: "terminal",
                               title: title,
                               subtitle: session.subtitle.isEmpty ? nil : session.subtitle,
                               level: level)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            // Plain so the row highlights on tap without tinting its contents.
            .buttonStyle(.plain)

            Button {
                preview = PreviewTarget(guid: session.guid, title: title)
            } label: {
                Image(systemName: "eye")
                    .foregroundStyle(Color.accentColor)
                    .padding(.leading, 4)
                    .contentShape(Rectangle())
            }
            // Borderless so it stays a discrete tap target alongside the row
            // body rather than activating the whole row.
            .buttonStyle(.borderless)
            .accessibilityLabel("Preview \(title)")
        }
    }
}
