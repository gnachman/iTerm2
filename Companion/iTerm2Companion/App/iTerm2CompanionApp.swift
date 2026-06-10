//
//  iTerm2CompanionApp.swift
//  iTerm2 Companion
//

import SwiftUI
import CompanionProtocol

@main
struct iTerm2CompanionApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { url in
                    // Pairing links (iterm2://pair?...) work without the
                    // camera: tapped links, and simctl openurl in development.
                    if let code = try? PairingCode.parse(url.absoluteString) {
                        model.pair(with: code)
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.route {
        case .launch:
            LaunchView()
        case .scanning:
            ScanningView()
        case .pairing:
            PairingView()
        case .home:
            HomeView()
        case .create:
            CreateView()
        case .conversation(let chatID):
            ConversationView(chatID: chatID)
        }
    }
}
