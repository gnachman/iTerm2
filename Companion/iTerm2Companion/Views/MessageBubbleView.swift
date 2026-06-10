//
//  MessageBubbleView.swift
//  iTerm2 Companion
//
//  Renders one chat Message in the iTerm2 AI chat style: user messages as blue
//  right-aligned bubbles, agent messages as gray left-aligned bubbles, and
//  system-ish content (client-local actions, watcher events) as a centered
//  notice. This consumes the same Message type the Mac renders, so the
//  conversation looks the same on both.
//

import SwiftUI
import CompanionProtocol

struct MessageBubbleView: View {
    @Environment(AppModel.self) private var model
    let message: Message

    var body: some View {
        switch message.content {
        case .clientLocal, .watcherEvent:
            systemNotice
        default:
            bubble
        }
    }

    // MARK: Bubble chrome

    private var isUser: Bool { message.author == .user }

    private var bubble: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            content
                .font(.body)
                .foregroundStyle(isUser ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isUser ? Color.accentColor : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 16))
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 48) }
        }
    }

    private var systemNotice: some View {
        HStack {
            Spacer(minLength: 24)
            content
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color(.separator), lineWidth: 0.5))
            Spacer(minLength: 24)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch message.content {
        case .plainText(let text, _):
            Text(text)
        case .markdown(let text):
            Text(renderMarkdown(text))
        case .multipart(let subparts, _):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(subparts.enumerated()), id: \.offset) { _, subpart in
                    self.subpart(subpart)
                }
            }
        case .explanationRequest(let request):
            Text(request.snippetText)
        case .selectSessionRequest(let original, let terminal):
            VStack(alignment: .leading, spacing: 10) {
                Text("The AI agent needs to run commands in a live \(terminal ? "terminal" : "web browser") session, but none is attached to this chat.")
                actionButtons(for: message, [
                    ActionButton(title: "Select a Session", destructive: false) {
                        model.beginSelectSession(requestMessage: message, original: original, terminal: terminal)
                    },
                    ActionButton(title: "Cancel", destructive: true) {
                        model.respondSelectSession(requestMessageID: message.uniqueID,
                                                   original: original,
                                                   terminal: terminal,
                                                   guid: nil)
                    },
                ])
            }
        case .explanationResponse(let response, _, let markdown):
            // The Mac client folds the response into `markdown` as it renders;
            // fall back to the parsed main response when that hasn't happened.
            Text(renderMarkdown(markdown.isEmpty ? (response.mainResponse ?? "") : markdown))
        case .remoteCommandRequest(let payload, let safe):
            if let remoteCommand = payload.classic {
                VStack(alignment: .leading, spacing: 10) {
                    if safe == false {
                        Label("The AI safety check flagged this command as potentially dangerous. Review it with care.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    Text(renderMarkdown(remoteCommand.markdownDescription))
                    Text(renderMarkdown("Would you like to grant AI **\(remoteCommand.content.permissionCategory.rawValue)** permission?"))
                        .font(.callout)
                    actionButtons(for: message, [
                        ActionButton(title: "Allow Once", destructive: false) {
                            model.respondRemoteCommand(requestMessage: message, decision: .allowOnce)
                        },
                        ActionButton(title: "Always Allow", destructive: false) {
                            model.respondRemoteCommand(requestMessage: message, decision: .allowAlways)
                        },
                        ActionButton(title: "Deny this Time", destructive: true) {
                            model.respondRemoteCommand(requestMessage: message, decision: .denyOnce)
                        },
                        ActionButton(title: "Always Deny", destructive: true) {
                            model.respondRemoteCommand(requestMessage: message, decision: .denyAlways)
                        },
                    ])
                }
            } else {
                // Orchestration-mode tool calls are informational; permission
                // flows through workgroupPermissionRequest instead.
                Label {
                    Text(renderMarkdown(payload.markdownDescription))
                } icon: {
                    Image(systemName: "play.circle")
                }
            }
        case .terminalCommand(let command):
            VStack(alignment: .leading, spacing: 4) {
                Text(command.command).font(.system(.body, design: .monospaced))
                if !command.output.isEmpty {
                    Text(command.output)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        case .watcherEvent(let update):
            Text(update.detail)
        case .clientLocal(let clientLocal):
            clientLocalView(clientLocal.action)
        case .append, .appendAttachment, .commit,
             .remoteCommandResponse, .renameChat, .setPermissions,
             .vectorStoreCreated, .userCommand:
            // Deltas are folded into their bubble by AppModel; the rest is
            // bookkeeping the Mac filters before sending. Defensive only.
            EmptyView()
        }
    }

    @ViewBuilder
    private func clientLocalView(_ action: ClientLocal.Action) -> some View {
        switch action {
        case .notice(let text):
            Text(text)
        case .pickingSession:
            Text("Selecting session…")
        case .executingCommand(let command):
            Label(command.markdownDescription, systemImage: "play.circle")
        case .streamingChanged(let state):
            switch state {
            case .active:
                Text("Sending commands to AI automatically")
            case .stopped, .stoppedAutomatically:
                Text("Stopped sending commands to AI")
            }
        case .offerLink(let terminal, let guid, let name):
            VStack(alignment: .leading, spacing: 8) {
                Text("Link this chat to \(terminal ? "terminal" : "browser") session “\(name ?? guid)”?")
                    .font(.callout.weight(.semibold))
                Text("Linking gives the AI access to this \(terminal ? "terminal" : "browser") session subject to your per-call permission.")
                actionButtons(for: message, [
                    ActionButton(title: "Link", destructive: false) {
                        model.linkSession(requestMessage: message, guid: guid, terminal: terminal)
                    },
                ])
            }
        case .permissions:
            Text("Permissions updated")
        case .workgroupPermissionRequest(let requestID, let workgroupID, let workgroupName, let summary):
            VStack(alignment: .leading, spacing: 8) {
                Text(workgroupID.hasPrefix("session:")
                     ? "**Allow agent to control session “\(workgroupName)”?**"
                     : "**Allow agent to control workgroup “\(workgroupName)”?**")
                    .font(.callout.weight(.semibold))
                if !summary.isEmpty {
                    Text(summary)
                }
                actionButtons(for: message, [
                    ActionButton(title: "Approve", destructive: false) {
                        model.respondUserCommand(requestMessage: message,
                                                 command: .workgroupPermissionResponse(requestID: requestID, approved: true))
                    },
                    ActionButton(title: "Deny", destructive: true) {
                        model.respondUserCommand(requestMessage: message,
                                                 command: .workgroupPermissionResponse(requestID: requestID, approved: false))
                    },
                ])
            }
        case .enableOrchestrationRequest(let requestID):
            VStack(alignment: .leading, spacing: 8) {
                Text("Enable orchestration?").font(.callout.weight(.semibold))
                Text("Orchestration mode lets the agent read screen contents from any session. To type into a session still requires your permission. Enabling will detach any linked terminal or browser session and switch the chat to Orchestration mode.")
                actionButtons(for: message, [
                    ActionButton(title: "Enable Orchestration", destructive: false) {
                        model.respondUserCommand(requestMessage: message,
                                                 command: .enableOrchestrationResponse(requestID: requestID, approved: true))
                    },
                    ActionButton(title: "Not Now", destructive: true) {
                        model.respondUserCommand(requestMessage: message,
                                                 command: .enableOrchestrationResponse(requestID: requestID, approved: false))
                    },
                ])
            }
        case .offerOrchestration:
            Text("Orchestration is available for this chat. Enable it on your Mac.")
        }
    }

    @ViewBuilder
    private func subpart(_ subpart: Message.Subpart) -> some View {
        switch subpart {
        case .plainText(let text):
            Text(text)
        case .markdown(let text):
            Text(renderMarkdown(text))
        case .attachment(let attachment):
            attachmentView(attachment)
        case .context:
            // Context rides along for the model, not for display.
            EmptyView()
        }
    }

    @ViewBuilder
    private func attachmentView(_ attachment: LLM.Message.Attachment) -> some View {
        switch attachment.type {
        case .code(let code):
            Text(code).font(.system(.footnote, design: .monospaced))
        case .statusUpdate(let update):
            Text(update.displayString)
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .file(let file):
            if file.mimeType.hasPrefix("image/"), let image = UIImage(data: file.content) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Label(file.name, systemImage: "paperclip")
            }
        case .fileID(_, let name):
            Label(name, systemImage: "paperclip")
        }
    }

    private struct ActionButton {
        var title: String
        var destructive: Bool
        var action: () -> Void
    }

    /// Bordered buttons under an interactive bubble, two per row. Disabled
    /// once the user has answered (one-shot, like the Mac's buttons).
    @ViewBuilder
    private func actionButtons(for message: Message, _ buttons: [ActionButton]) -> some View {
        let answered = model.respondedInteractiveMessageIDs.contains(message.uniqueID)
        let rows: [[ActionButton]] = stride(from: 0, to: buttons.count, by: 2).map {
            Array(buttons[$0..<min($0 + 2, buttons.count)])
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, button in
                        Button(button.title, action: button.action)
                            .buttonStyle(.bordered)
                            .tint(button.destructive ? .red : .accentColor)
                            .font(.callout)
                    }
                }
            }
        }
        .disabled(answered)
        .opacity(answered ? 0.5 : 1)
    }

    /// Best-effort inline markdown; falls back to the raw string if it does not
    /// parse (e.g. a partial streaming chunk).
    private func renderMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
