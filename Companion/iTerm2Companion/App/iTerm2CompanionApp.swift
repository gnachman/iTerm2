//
//  iTerm2CompanionApp.swift
//  iTerm2 Companion
//

import SwiftUI

@main
struct iTerm2CompanionApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
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
