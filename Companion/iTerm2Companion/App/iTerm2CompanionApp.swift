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

    /// Routes a tap on a locally-posted session-view reply notification to the
    /// model. Buffered until the model wires the handler up (a cold launch from
    /// the notification runs the delegate before the SwiftUI scene's task).
    static var onSessionChatTap: (@MainActor (_ chatID: String, _ tab: AppModel.AppTab) -> Void)?
    private static var pendingSessionChatTap: (chatID: String, tab: AppModel.AppTab)?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
#if DEBUG
        // companionLog prints to stdout in debug builds. Under
        // `devicectl … --console` stdout is a pipe, not a TTY, so libc
        // full-buffers it (4 KB) and lines only surface when the buffer fills or
        // the process exits, i.e. "hardly anything" shows live. Make it
        // unbuffered so each logged line appears immediately.
        setvbuf(stdout, nil, _IONBF, 0)
#endif
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show notifications even while the app is frontmost; the alert is the
    /// product here, not a redundant copy of on-screen state.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    /// A notification was tapped. Only the live session view's own reply
    /// notifications carry a chat id to route to; push-driven NSE alerts don't,
    /// and just foreground the app (the default).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let chatID = userInfo[AppModel.sessionChatNavKey] as? String else { return }
        let tab = (userInfo[AppModel.sessionChatTabKey] as? String)
            .flatMap(AppModel.AppTab.init(rawValue:)) ?? .chats
        await MainActor.run {
            Self.routeSessionChatTap(chatID: chatID, tab: tab)
        }
    }

    @MainActor
    private static func routeSessionChatTap(chatID: String, tab: AppModel.AppTab) {
        if let handler = onSessionChatTap {
            handler(chatID, tab)
        } else {
            pendingSessionChatTap = (chatID, tab)
        }
    }

    /// Flush a tap that arrived before the model wired up its handler.
    @MainActor
    static func flushPendingSessionChatTap() {
        guard let pending = pendingSessionChatTap else { return }
        pendingSessionChatTap = nil
        onSessionChatTap?(pending.chatID, pending.tab)
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
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    // App lifecycle drives whether the relay socket is torn
                    // down (iOS closes background sockets), so log every transition
                    // to attribute disconnects to backgrounding.
                    companionLog("scenePhase \(oldPhase) -> \(newPhase)")
                    if newPhase == .active {
                        model.checkConnectionOnForeground()
                    }
                }
                .task {
                    CompanionAppDelegate.onPushToken = { [weak model] token in
                        model?.pushTokenDidChange(token)
                    }
                    CompanionAppDelegate.onSessionChatTap = { [weak model] chatID, tab in
                        model?.handleSessionChatNotificationTap(chatID: chatID, tab: tab)
                    }
                    CompanionAppDelegate.flushPendingSessionChatTap()
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
        case .needsUpgrade(let side):
            UpgradeRequiredView(side: side)
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
        case .session(let guid, let title, let originatingChatID):
            SessionView(guid: guid, title: title, originatingChatID: originatingChatID)
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
