//
//  iTerm2CompanionApp.swift
//  iTerm2 Companion
//

import SwiftUI
import CompanionProtocol

@main
struct iTerm2CompanionApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        model.checkConnectionOnForeground()
                    }
                }
                .task {
                    model.handleLaunch()
                }
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
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // The ZStack + phase-keyed animation make the switch branches animate
        // as they come and go. Launch lives on the leading edge and the
        // scanner on the trailing edge, so Launch -> Scan plays as a push and
        // Scan -> Launch as a pop.
        ZStack {
        switch model.phase {
        case .launch:
            LaunchView()
                .transition(.move(edge: .leading))
        case .scanning:
            ScanningView()
                .transition(.move(edge: .trailing))
        case .pairing:
            PairingView()
                .transition(.opacity)
        case .home:
            // One NavigationStack owns the whole paired flow so pushes slide
            // and the interactive swipe-back gesture works.
            NavigationStack(path: $model.navigationPath) {
                HomeView()
                    .reconnectingBanner(model.isReconnecting)
                    .navigationDestination(for: AppModel.Destination.self) { destination in
                        switch destination {
                        case .create:
                            CreateView()
                                .reconnectingBanner(model.isReconnecting)
                        case .conversation(let chatID):
                            ConversationView(chatID: chatID)
                                .reconnectingBanner(model.isReconnecting)
                        case .settings:
                            SettingsView()
                                .reconnectingBanner(model.isReconnecting)
                        }
                    }
            }
            .transition(.opacity)
        }
        }
        .animation(.smooth(duration: 0.35), value: model.phase)
    }
}

// The reconnecting pill is inset into each screen's CONTENT (below its
// navigation bar) rather than onto the NavigationStack, where it would share
// the safe-area band with the bar title and render text on text.
private struct ReconnectingBanner: ViewModifier {
    let isReconnecting: Bool

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top) {
            if isReconnecting {
                Label("Reconnecting to your Mac…", systemImage: "wifi.exclamationmark")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.yellow, in: Capsule())
                    .padding(.top, 4)
            }
        }
    }
}

extension View {
    func reconnectingBanner(_ isReconnecting: Bool) -> some View {
        modifier(ReconnectingBanner(isReconnecting: isReconnecting))
    }
}
