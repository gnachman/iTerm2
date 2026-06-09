//
//  MessageBubbleView.swift
//  iTerm2 Companion
//
//  Renders one chat message in the iTerm2 AI chat style: user messages as blue
//  right-aligned bubbles, agent messages as gray left-aligned bubbles, and
//  system messages as a centered notice.
//

import SwiftUI
import CompanionProtocol

struct MessageBubbleView: View {
    let message: MessageDTO

    var body: some View {
        switch message.author {
        case .user:
            bubble(alignment: .trailing,
                   background: Color.accentColor,
                   foreground: .white)
        case .agent:
            bubble(alignment: .leading,
                   background: Color(.secondarySystemBackground),
                   foreground: .primary)
        case .system:
            systemNotice
        }
    }

    private func bubble(alignment: HorizontalAlignment,
                        background: Color,
                        foreground: Color) -> some View {
        HStack {
            if alignment == .trailing { Spacer(minLength: 48) }
            content
                .font(.body)
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(background, in: RoundedRectangle(cornerRadius: 16))
                .textSelection(.enabled)
            if alignment == .leading { Spacer(minLength: 48) }
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

    @ViewBuilder
    private var content: some View {
        switch message.content {
        case .plainText(let text):
            Text(text)
        case .markdown(let text):
            Text(renderMarkdown(text))
        case .notice(let text):
            Text(text)
        case .multipart(let parts):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    subpart(part)
                }
            }
        case .terminalCommand(let command, let output):
            VStack(alignment: .leading, spacing: 4) {
                Text(command).font(.system(.body, design: .monospaced))
                if let output, !output.isEmpty {
                    Text(output)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        case .remoteCommandRequest(let description, _):
            Label(description, systemImage: "play.circle")
        case .streamingChanged(let active):
            Text(active ? "Sending commands to AI automatically"
                        : "Stopped sending commands to AI")
        case .unsupported(let summary):
            Text(summary).italic()
        case .append, .commit:
            // Deltas are folded into their target bubble by the model.
            EmptyView()
        }
    }

    @ViewBuilder
    private func subpart(_ part: MessageDTO.SubpartDTO) -> some View {
        switch part {
        case .plainText(let text):
            Text(text)
        case .markdown(let text):
            Text(renderMarkdown(text))
        case .code(let code):
            Text(code).font(.system(.footnote, design: .monospaced))
        case .attachment(let name, _):
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
