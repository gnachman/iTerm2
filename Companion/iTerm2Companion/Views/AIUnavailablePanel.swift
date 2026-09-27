//
//  AIUnavailablePanel.swift
//  iTerm2 Companion
//
//  Shown in place of the AI-dependent surfaces (the chat list, the new-chat
//  screen) when the paired Mac has AI turned off. It explains why chats are
//  unavailable and what to do, and reassures the user that session browsing, live
//  video, and keyboard control still work. The remedy lives on the Mac (turn on
//  AI in iTerm2's settings), so there is no in-app action button.
//

import SwiftUI

struct AIUnavailablePanel: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("AI Chat Is Off")
                .font(.title3.bold())
            Text("AI features are turned off on your paired Mac, so chats aren’t available here. To use chats, open iTerm2 on your Mac and turn on AI in Settings (an administrator may also have disabled it).")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("You can still browse sessions, watch live output, and control your terminal from the Sessions tab.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
