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
    let message: Message

    var body: some View {
        switch message.content {
        case .clientLocal, .watcherEvent, .selectSessionRequest:
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
        case .explanationResponse(let response, _, let markdown):
            // The Mac client folds the response into `markdown` as it renders;
            // fall back to the parsed main response when that hasn't happened.
            Text(renderMarkdown(markdown.isEmpty ? (response.mainResponse ?? "") : markdown))
        case .remoteCommandRequest(let payload, _):
            Label {
                Text(renderMarkdown(payload.markdownDescription))
            } icon: {
                Image(systemName: "play.circle")
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
        case .selectSessionRequest:
            Text("Selecting session…")
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
        case .offerLink(_, _, let name):
            Text("Link available for \(name ?? "a session") (use your Mac to open it)")
        case .permissions:
            Text("Permissions updated")
        case .workgroupPermissionRequest(_, _, let workgroupName, let summary):
            VStack(spacing: 4) {
                Text("The agent wants to use the workgroup “\(workgroupName)”. Approve or deny on your Mac.")
                if !summary.isEmpty {
                    Text(summary).foregroundStyle(.tertiary)
                }
            }
        case .enableOrchestrationRequest:
            Text("The agent asked to enable orchestration. Respond on your Mac.")
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

    /// Best-effort inline markdown; falls back to the raw string if it does not
    /// parse (e.g. a partial streaming chunk).
    private func renderMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
