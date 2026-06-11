//
//  CompanionPairingController.swift
//  iTerm2
//
//  Drives the mac side of pairing: it advertises the companion service, waits
//  for a phone to connect, runs the Noise XK handshake as the responder, and
//  hands the encrypted channel to a CompanionHostBridge. A successful pairing
//  is persisted (the pairing id; the static identity is already in the
//  keychain) so the phone can reconnect after either side relaunches: at app
//  launch, and whenever the phone disconnects, the mac resumes advertising the
//  stored pairing id. The transport is reached through the pluggable
//  TransportListener abstraction.
//

import Foundation
import AppKit
import CoreImage
import Network
import Security
import CompanionProtocol
import CompanionNoise
import CompanionTransport

@MainActor
@objc(iTermCompanionPairingController)
final class CompanionPairingController: NSObject {
    @objc static let shared = CompanionPairingController()

    private var listener: TransportListener?
    private var acceptTask: Task<Void, Never>?
    private var bridge: CompanionHostBridge? {
        didSet {
            // Mirrored where the (nonisolated) tool-registration path can
            // read it.
            CompanionPushRegistry.setPhoneConnected(bridge != nil)
        }
    }

    private(set) var pairingCode: PairingCode?

    // Set by the window controller; all invoked on the main actor.
    var onPaired: (@MainActor () -> Void)?
    var onFailed: (@MainActor (String) -> Void)?
    var onDisconnect: (@MainActor () -> Void)?
    var onStatus: (@MainActor (String) -> Void)?

    // Internal (not private): CompanionPushRegistry.devicePaired reads the
    // same default from nonisolated contexts.
    static let pairedPIDKey = "NoSyncCompanionPairedPID"

    /// The pairing id of the (single, for now) paired device, persisted so
    /// reconnection survives relaunches. NoSync: device state, not a setting.
    private var pairedPID: String? {
        get { iTermUserDefaults.userDefaults().string(forKey: Self.pairedPIDKey) }
        set {
            if let newValue {
                iTermUserDefaults.userDefaults().set(newValue, forKey: Self.pairedPIDKey)
            } else {
                iTermUserDefaults.userDefaults().removeObject(forKey: Self.pairedPIDKey)
            }
        }
    }

    /// A phone is connected right now.
    var isConnected: Bool { bridge != nil }
    /// A device has paired at some point (it may or may not be connected).
    var hasPairedDevice: Bool { pairedPID != nil }

    /// The same three gates iTermAITermGatekeeper.check() applies, evaluated
    /// without its alerts. Pairing (and even listening for a paired device) is
    /// pointless without working AI features.
    enum AIGate: Equatable {
        case allowed
        case adminDisabled
        case pluginMissing
        case consentNeeded
    }

    static func aiGate() -> AIGate {
        if !iTermAdvancedSettingsModel.generativeAIAllowed() {
            return .adminDisabled
        }
        if !iTermAITermGatekeeper.pluginInstalled() {
            return .pluginMissing
        }
        if !SecureUserDefaults.instance.enableAI.value {
            return .consentNeeded
        }
        return .allowed
    }

    private var gateObservers: [any NSObjectProtocol] = []

    private override init() {
        super.init()
        // Track consent and the advanced setting so the background listener
        // follows the gate: stop when AI becomes unavailable, resume when it
        // comes back. (Plugin presence has no notification; it is re-checked
        // on the next launch or pairing-window visit.)
        let center = NotificationCenter.default
        for name in [iTermSecureUserDefaults.didChange,
                     Notification.Name(iTermAdvancedSettingsDidChange)] {
            gateObservers.append(center.addObserver(forName: name,
                                                    object: nil,
                                                    queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.gateMayHaveChanged()
                }
            })
        }
    }

    private func gateMayHaveChanged() {
        if Self.aiGate() == .allowed {
            resumePairedListeningIfNeeded()
        } else if acceptTask != nil {
            DLog("Companion: AI features became unavailable; stopping listener")
            stopAdvertising()
        }
    }

    /// Called at app launch (and after disconnects): if a device is paired,
    /// quietly advertise its pairing id so it can reconnect.
    @objc func resumePairedListeningIfNeeded() {
        installLogHandler()
        guard Self.aiGate() == .allowed else {
            DLog("Companion: not listening; AI features are unavailable")
            return
        }
        // Note: no bridge==nil guard. The listener stays up even while a phone
        // is connected, because a phone returning from a network outage
        // reconnects while the old TCP session can still look alive here.
        guard acceptTask == nil, let pid = pairedPID else {
            return
        }
        do {
            try startListening(pairingID: pid)
            DLog("Companion: resumed listening for paired device (pid \(pid))")
        } catch {
            DLog("Companion: could not resume listening: \(error); will retry")
            scheduleListenerRetry()
        }
    }

    /// The background listener must outlive transient failures (sleep/wake
    /// and network changes can kill the NW listener): whenever it dies while
    /// a device is paired, retry until it sticks. Without this the mac
    /// silently stops advertising and the phone can never reconnect.
    private var listenerRetryTask: Task<Void, Never>?

    private func scheduleListenerRetry() {
        guard listenerRetryTask == nil, pairedPID != nil else {
            return
        }
        listenerRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.listenerRetryTask = nil
            self.resumePairedListeningIfNeeded()
        }
    }

    /// Begin a fresh pairing. Returns the pairing code whose URL should be
    /// displayed as a QR.
    func startPairing() throws -> PairingCode {
        installLogHandler()
        stopAdvertising()
        let keyPair = try CompanionMacIdentity.keyPair()
        let pairingID = Self.makePairingID()
        let code = PairingCode(responderStaticPublicKey: keyPair.publicKey, pairingID: pairingID)
        pairingCode = code

#if DEBUG
        // Development automation hook: the iOS simulator has no camera, so
        // end-to-end tests read the pairing URL from here and hand it to the
        // phone via simctl openurl.
        try? code.urlString().write(toFile: "/tmp/iterm2-companion-pairing-url.txt",
                                    atomically: true,
                                    encoding: .utf8)
#endif

        try startListening(pairingID: pairingID)
        return code
    }

    /// Whether a companion phone is connected right now (a live bridge). Used
    /// to decide which push tools the orchestrator gets.
    var isPhoneConnected: Bool {
        bridge != nil
    }

    /// Ask the connected phone to prompt for notification permission. nil
    /// when no phone is connected or it didn't answer.
    func requestNotificationPermission() async -> CompanionPushAuthorization? {
        await bridge?.requestNotificationPermission()
    }

    /// Kick the paired device and delete the pairing: closes any live bridge,
    /// forgets the pairing id, and destroys the mac's static identity so a new
    /// one is generated for the next pairing.
    func unpair() {
        DLog("Companion: unpair (bridge connected: \(bridge != nil))")
        if let bridge {
            // Fire-and-forget: the farewell flush is async, but the bridge is
            // already detached from the controller so nothing else uses it.
            Task {
                await bridge.announceUnpairedAndStop()
            }
        }
        bridge = nil
        stopAdvertising()
        pairedPID = nil
        pairingCode = nil
        CompanionMacIdentity.deleteKeyPair()
        CompanionPushRegistry.clear()
        DLog("Companion: unpaired; key material deleted")
    }

    /// The phone unpaired itself: mirror unpair() minus the farewell (the
    /// phone is the one leaving).
    private func peerDidUnpair() {
        DLog("Companion: peer unpaired; deleting key material")
        bridge?.stop()
        bridge = nil
        stopAdvertising()
        pairedPID = nil
        pairingCode = nil
        CompanionMacIdentity.deleteKeyPair()
        CompanionPushRegistry.clear()
        onDisconnect?()
    }

    /// Stop advertising and accepting. Does NOT touch a connected bridge; the
    /// pairing window calls this when it closes.
    func stopAdvertising() {
        listenerRetryTask?.cancel()
        listenerRetryTask = nil
        acceptTask?.cancel()
        acceptTask = nil
        listener?.stop()
        listener = nil
    }

    private func installLogHandler() {
        CompanionLog.handler = { message in
            DLog("\(message)")
        }
    }

    private func startListening(pairingID: String) throws {
        let keyPair = try CompanionMacIdentity.keyPair()
        let code = PairingCode(responderStaticPublicKey: keyPair.publicKey, pairingID: pairingID)
        let listener = try BonjourTransportListener(pairingID: pairingID,
                                                    version: PairingCode.supportedVersion)
        self.listener = listener
        acceptTask = Task { [weak self] in
            await self?.acceptLoop(listener: listener, keyPair: keyPair, code: code)
        }
    }

    private func acceptLoop(listener: TransportListener,
                            keyPair: NoiseKeyPair,
                            code: PairingCode) async {
        DLog("Companion pairing: accept loop started (pid \(code.pairingID))")
        onStatus?("Waiting for your iPhone…")
        while !Task.isCancelled {
            let transport: MessageTransport
            do {
                transport = try await listener.accept()
            } catch {
                listener.stop()
                if self.listener === listener {
                    self.listener = nil
                }
                acceptTask = nil
                // A closed listener is always a deliberate teardown (stop or
                // unpair), regardless of which error shape the cancellation
                // surfaced as; only genuine failures reach the user.
                let intentional = Task.isCancelled
                    || error is CancellationError
                    || (error as? TransportError) == .closed
                DLog("Companion pairing: accept ended: \(error), cancelled=\(Task.isCancelled), intentional=\(intentional)")
                if !intentional {
                    onFailed?(Self.userFacingDescription(of: error))
                    // The background listener for a paired device must come
                    // back on its own (e.g. after sleep/wake kills it).
                    scheduleListenerRetry()
                }
                return
            }
            do {
                DLog("Companion pairing: connection accepted; starting Noise handshake")
                onStatus?("Phone connected. Securing the connection…")
                let channel = try await NoiseHandshake.perform(
                    role: .responder,
                    transport: transport,
                    localKeyPair: keyPair,
                    remoteStaticPublicKey: nil,
                    prologue: code.handshakePrologue())
                DLog("Companion pairing: handshake complete")

                let newBridge = CompanionHostBridge(transport: channel)
                newBridge.onClose = { [weak self, weak newBridge] in
                    guard let self, let newBridge, self.bridge === newBridge else {
                        // A stale bridge must not tear down its replacement.
                        DLog("Companion: stale bridge closed; ignoring")
                        return
                    }
                    DLog("Companion: bridge closed; resuming listening for reconnect")
                    self.bridge = nil
                    self.onDisconnect?()
                    self.resumePairedListeningIfNeeded()
                }
                newBridge.onPeerUnpaired = { [weak self] in
                    self?.peerDidUnpair()
                }
                newBridge.start()
                let staleBridge = bridge
                bridge = newBridge
                if let staleBridge {
                    // The phone reconnected while the previous TCP session
                    // still looked alive here (e.g. its wifi was off). The new
                    // handshake supersedes it.
                    DLog("Companion: replacing stale bridge with the new connection")
                    staleBridge.stop()
                }
                pairedPID = code.pairingID
                onPaired?()
                // Keep accepting: this is what lets a phone reconnect after a
                // network outage the mac never noticed.
            } catch {
                DLog("Companion pairing: handshake failed: \(error); still listening")
                onStatus?("Waiting for your iPhone…")
            }
        }
    }

    /// Convert transport errors into actionable text. The transport layer
    /// translates the OS's Bonjour denial into a typed case; attach the
    /// macOS-specific remediation here.
    private static func userFacingDescription(of error: Error) -> String {
        if case TransportError.localNetworkAccessDenied = error {
            return "macOS denied local network access. Open System Settings > Privacy & Security > Local Network and enable iTerm2, then try again."
        }
        if let transport = error as? TransportError {
            return transport.errorDescription ?? "\(error)"
        }
        // Surface the real failure, not bridged-NSError boilerplate.
        if let nwError = error as? NWError {
            switch nwError {
            case .posix(let code):
                if let cString = strerror(code.rawValue) {
                    return String(cString: cString)
                }
            case .dns(let code):
                return "Bonjour/DNS error \(code)"
            case .tls(let status):
                return "TLS error \(status)"
            @unknown default:
                break
            }
        }
        return error.localizedDescription
    }

    private static func makePairingID() -> String {
        var bytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: QR rendering

    /// Render a QR code image for a string using CoreImage. `pointSize` is the
    /// logical size of the returned image; it is rasterized at 2x for crispness.
    static func qrImage(for string: String, pointSize: CGFloat) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage, output.extent.width > 0 else {
            return nil
        }
        let scale = (pointSize * 2) / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(representation)
        return image
    }
}
