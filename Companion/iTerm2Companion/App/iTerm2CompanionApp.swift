//
//  iTerm2CompanionApp.swift
//  iTerm2 Companion
//

import SwiftUI
import UserNotifications
import CompanionProtocol

/// Exists for the APNs registration callbacks, which only arrive via the app
/// delegate. The token is handed to AppModel, which forwards it to the Mac.
final class CompanionAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var onPushToken: (@MainActor (Data) -> Void)?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show notifications even while the app is frontmost; the alert is the
    /// product here, not a redundant copy of on-screen state.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        companionLog("APNs device token: \(deviceToken.map { String(format: "%02x", $0) }.joined())")
        Task { @MainActor in
            Self.onPushToken?(deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        companionLog("APNs registration failed: \(String(describing: error))")
    }
}

@main
struct iTerm2CompanionApp: App {
    @UIApplicationDelegateAdaptor(CompanionAppDelegate.self) private var appDelegate
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
                    CompanionAppDelegate.onPushToken = { [weak model] token in
                        model?.pushTokenDidChange(token)
                    }
                    model.handleLaunch()
                }
                .onOpenURL { url in
                    // Pairing links (iterm2://pair?...) work without the camera:
                    // tapped links, and simctl openurl in development. Unlike a
                    // scanned QR, a link could come from anywhere (e.g. a web
                    // page), so confirm with the user and show the relay host
                    // before connecting.
                    if let code = try? PairingCode.parse(url.absoluteString) {
                        model.requestExternalPairing(code)
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
            // Two top-level modes, one tab each, with independent
            // NavigationStacks so each tab keeps its own place. Pushes slide
            // and the interactive swipe-back gesture works per tab.
            TabView(selection: $model.selectedTab) {
                Tab("Chats", systemImage: "bubble.left.and.bubble.right", value: AppModel.AppTab.chats) {
                    NavigationStack(path: $model.navigationPath) {
                        HomeView()
                            .reconnectingBanner(model.isReconnecting)
                            .navigationDestination(for: AppModel.Destination.self) { destination in
                                destinationView(destination)
                            }
                    }
                }
                Tab("Sessions", systemImage: "terminal", value: AppModel.AppTab.sessions) {
                    NavigationStack(path: $model.sessionsPath) {
                        SessionBrowserView()
                            .reconnectingBanner(model.isReconnecting)
                            .navigationDestination(for: AppModel.Destination.self) { destination in
                                destinationView(destination)
                            }
                    }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .transition(.opacity)
        }
        }
        .animation(.smooth(duration: 0.35), value: model.phase)
        .alert("Pair with this Mac?",
               isPresented: Binding(get: { model.pendingExternalPairing != nil },
                                    set: { presented in if !presented { model.cancelExternalPairing() } })) {
            Button("Pair") { model.confirmExternalPairing() }
            Button("Cancel", role: .cancel) { model.cancelExternalPairing() }
        } message: {
            Text("This pairing link will connect through the relay:\n\n\(model.pendingPairingRelayDisplay)\n\nOnly continue if you opened it yourself.")
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: AppModel.Destination) -> some View {
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
        case .session(let guid, let title):
            SessionView(guid: guid, title: title)
                .reconnectingBanner(model.isReconnecting)
        case .workgroup(let id, let title):
            WorkgroupView(workgroupID: id, title: title)
                .reconnectingBanner(model.isReconnecting)
        }
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
