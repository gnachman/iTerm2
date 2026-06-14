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

    /// True while a fresh-pairing QR is being shown (from startPairing until the
    /// pairing completes or the window is torn down via stopAdvertising). It
    /// distinguishes "a QR is up, keep its park alive" from a stale pairingCode
    /// left over after the window closed, so retry re-parks only a live pairing.
    private var freshPairingActive = false

    // Set by the window controller; all invoked on the main actor.
    var onPaired: (@MainActor () -> Void)?
    var onFailed: (@MainActor (String) -> Void)?
    var onDisconnect: (@MainActor () -> Void)?
    var onStatus: (@MainActor (String) -> Void)?
    /// A fresh pairing finished its handshake and needs the user to type the
    /// code shown on the phone. The window switches to code-entry UI and calls
    /// submitSASEntry with what the user typed (nil = user declined).
    var onSASEntryNeeded: (@MainActor () -> Void)?
    /// The confirmation resolved (matched, declined, or too many mistypes);
    /// the window dismisses the entry UI, restoring the QR when not accepted.
    var onSASEntryDismissed: (@MainActor (_ accepted: Bool) -> Void)?

    // Internal (not private): CompanionPushRegistry.devicePaired reads the
    // same default from nonisolated contexts. nonisolated so that read does not
    // cross actor isolation (an immutable Sendable constant).
    nonisolated static let pairedPIDKey = "NoSyncCompanionPairedPID"

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

    /// The paired phone's Noise static public key, learned and SAS-confirmed at
    /// pairing. On reconnect the mac requires the initiator to present this same
    /// static (Noise proves possession of the matching private key), which
    /// authenticates the phone END-TO-END: a relay-admitted impostor, or a
    /// QR-photo attacker, completes no session because it cannot present this
    /// key. The relay is untrusted, so this check, not the relay, is the
    /// reconnect authentication. Stored in the keychain (not UserDefaults):
    /// it is public, but its integrity is security-critical, a tampered value
    /// would authenticate an impostor. Kept beside the mac's private key.
    private var pairedPhoneStatic: Data? {
        get { CompanionMacIdentity.pairedPhoneStaticPublicKey() }
        set {
            if let newValue {
                try? CompanionMacIdentity.storePairedPhoneStaticPublicKey(newValue)
            } else {
                CompanionMacIdentity.deletePairedPhoneStaticPublicKey()
            }
        }
    }

    /// A phone is connected right now.
    var isConnected: Bool { bridge != nil }
    /// A device has paired at some point (it may or may not be connected).
    var hasPairedDevice: Bool { pairedPID != nil }

    /// The pairing id the mac should currently be parked for: the established
    /// device, or, during a fresh pairing, the QR being shown. Retry uses this
    /// so a dropped park is re-established in BOTH states, waiting for a first
    /// scan and after pairing. nil means there is nothing to listen for.
    private var desiredListeningPID: String? {
        if let pairedPID { return pairedPID }
        if freshPairingActive { return pairingCode?.pairingID }
        return nil
    }

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
        relayLog("resumePairedListeningIfNeeded called")
        guard Self.aiGate() == .allowed else {
            DLog("Companion: not listening; AI features are unavailable")
            relayLog("resume: SKIP (AI gate not allowed)")
            return
        }
        // Park only when nothing is connected. The relay room has a single mac
        // slot, so parking while a bridge is live would displace it. The
        // bridge's onClose nils `bridge` before calling here, so a genuine
        // reconnect (after the connection is gone) still proceeds; only callers
        // firing while connected (launch races, gate changes) are held off.
        guard acceptTask == nil, bridge == nil, let pid = desiredListeningPID else {
            relayLog("resume: SKIP guard "
                     + "(acceptTaskNil=\(acceptTask == nil) bridgeNil=\(bridge == nil) "
                     + "hasPID=\(desiredListeningPID != nil))")
            return
        }
        do {
            relayLog("resume: starting listening for pid \(pid)")
            try startListening(pairingID: pid)
            DLog("Companion: resumed listening for paired device (pid \(pid))")
        } catch {
            DLog("Companion: could not resume listening: \(error); will retry")
            relayLog("resume: startListening THREW \(error); scheduling retry")
            scheduleListenerRetry()
        }
    }

    /// The background listener must outlive transient failures (sleep/wake
    /// and network changes can kill the NW listener): whenever it dies while
    /// a device is paired, retry until it sticks. Without this the mac
    /// silently stops advertising and the phone can never reconnect.
    private var listenerRetryTask: Task<Void, Never>?

    private func scheduleListenerRetry() {
        guard listenerRetryTask == nil, desiredListeningPID != nil else {
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
        relayLog("startPairing() called (fresh QR)")
        stopAdvertising()
        let keyPair = try CompanionMacIdentity.keyPair()
        let pairingID = Self.makePairingID()
        let code = PairingCode(responderStaticPublicKey: keyPair.publicKey,
                               pairingID: pairingID,
                               relayOrigin: Self.configuredRelayOrigin())
        pairingCode = code
        // A live QR is up: keep its park retried until the phone pairs or the
        // window is torn down (stopAdvertising clears this).
        freshPairingActive = true

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
        relayLog("unpair() called")
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
        pairedPhoneStatic = nil
        pairingCode = nil
        CompanionMacIdentity.deletePairedRoomSecret()
        CompanionMacIdentity.deleteKeyPair()
        CompanionPushRegistry.clear()
        DLog("Companion: unpaired; key material deleted")
    }

    /// The phone unpaired itself: mirror unpair() minus the farewell (the
    /// phone is the one leaving).
    private func peerDidUnpair() {
        relayLog("peerDidUnpair() called")
        DLog("Companion: peer unpaired; deleting key material")
        bridge?.stop()
        bridge = nil
        stopAdvertising()
        pairedPID = nil
        pairedPhoneStatic = nil
        pairingCode = nil
        CompanionMacIdentity.deletePairedRoomSecret()
        CompanionMacIdentity.deleteKeyPair()
        CompanionPushRegistry.clear()
        onDisconnect?()
    }

    /// Stop advertising and accepting. Does NOT touch a connected bridge; the
    /// pairing window calls this when it closes.
    func stopAdvertising() {
        relayLog("stopAdvertising() called (cancelling acceptTask, stopping listener)")
        // Teardown of the current advertising intent: a fresh-pairing QR is no
        // longer live, so retry must not re-park it. An established pairing
        // (pairedPID) is unaffected and still drives reconnect.
        freshPairingActive = false
        listenerRetryTask?.cancel()
        listenerRetryTask = nil
        // An accept loop parked in SAS entry must not leak its continuation.
        submitSASEntry(nil)
        acceptTask?.cancel()
        acceptTask = nil
        listener?.stop()
        listener = nil
    }

    // MARK: SAS confirmation

    /// Pending code-entry continuation while a fresh pairing waits for the
    /// user to type the SAS code shown on the phone.
    private var sasContinuation: CheckedContinuation<String?, Never>?

    /// The window delivers the user's typed code here (nil = declined). Safe to
    /// call when no entry is pending.
    func submitSASEntry(_ code: String?) {
        sasContinuation?.resume(returning: code)
        sasContinuation = nil
    }

    /// Run the mac side of SAS confirmation: prompt for entry and allow a few
    /// mistypes before giving up. Returns whether the typed code matched.
    /// The phone SHOWS the code and the mac is input-only: a photographed-QR
    /// attacker never sees the victim's mac, so the victim has no code to type.
    private func runSASConfirmation(expected: String) async -> Bool {
        relayLog("SAS: awaiting code entry")
        onStatus?("Enter the code shown on your iPhone.")
        onSASEntryNeeded?()
        for attempt in 1...3 {
            let typed = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                sasContinuation = continuation
            }
            guard let typed else {
                relayLog("SAS: entry declined")
                return false
            }
            if typed.trimmingCharacters(in: .whitespacesAndNewlines) == expected {
                relayLog("SAS: code matched")
                return true
            }
            relayLog("SAS: mismatch (attempt \(attempt))")
            onStatus?("That code doesn’t match. Check your iPhone and try again.")
        }
        return false
    }

    private func installLogHandler() {
        CompanionLog.handler = { message in
            DLog("\(message)")
            // TEMP DEBUG: mirror the transport/crypto layer's logs to NSLog too,
            // tagged so the relay lifecycle is greppable without the giant DLog.
            NSFuckingLog("%@", "COMPANIONRELAY transport: \(message)")
        }
    }

    /// TEMP DEBUG: one-line, greppable trace of the relay lifecycle, stamped
    /// with the state that actually drives the single-mac-slot logic. Filter the
    /// system log with: `log stream --predicate 'eventMessage CONTAINS "COMPANIONRELAY"'`
    /// (or grep stderr for COMPANIONRELAY).
    private func relayLog(_ message: String) {
        NSFuckingLog("%@", "COMPANIONRELAY \(message) "
                     + "[bridge=\(bridge != nil) acceptTask=\(acceptTask != nil) "
                     + "pairedPID=\(pairedPID ?? "nil") gate=\(Self.aiGate())]")
    }

    private func startListening(pairingID: String) throws {
        let keyPair = try CompanionMacIdentity.keyPair()
        // The relay origin comes from local config, not the stored pairing, so
        // it applies to background reconnect listening too (where there is no
        // fresh QR). nil => local-network only, the default.
        let relayOrigin = Self.configuredRelayOrigin()
        let code = PairingCode(responderStaticPublicKey: keyPair.publicKey,
                               pairingID: pairingID,
                               relayOrigin: relayOrigin)
        let roomName = relayOrigin == nil ? "n/a"
            : RelayRoom.name(responderStaticPublicKey: keyPair.publicKey, pairingID: pairingID)
        relayLog("startListening pid=\(pairingID) relayOrigin=\(relayOrigin ?? "nil") room=\(roomName)")
        let listener = try CompanionTransports.listener(
            pairingID: pairingID,
            responderStaticPublicKey: keyPair.publicKey,
            relayOrigin: relayOrigin,
            // Sign the mac's park once the phone has couriered the room secret
            // and the room is established; nil keeps an open-mode park.
            roomSecret: { CompanionMacIdentity.pairedRoomSecret() })
        self.listener = listener
        acceptTask = Task { [weak self] in
            await self?.acceptLoop(listener: listener, keyPair: keyPair, code: code)
        }
    }

    /// The relay origin the pairing uses for connectivity. The relay is the
    /// only transport (Bonjour is currently disabled), so this must be set for
    /// pairing to work; it defaults to the project relay and can be overridden
    /// per machine via the CompanionRelayOrigin default (e.g. a fork's own
    /// Worker, or an open-mode test relay). Setting it to the empty string
    /// disables the relay entirely (no transport, pairing cannot complete).
    /// Validated as a bare https origin with the same rule the phone applies to
    /// the QR, so an invalid value is ignored (logged) rather than producing a
    /// QR the phone rejects.
    static let relayOriginKey = "CompanionRelayOrigin"
    static let defaultRelayOrigin = "https://iterm2-companion-relay.gnachman.workers.dev"

    private static func configuredRelayOrigin() -> String? {
        let raw = iTermUserDefaults.userDefaults().string(forKey: relayOriginKey) ?? defaultRelayOrigin
        guard !raw.isEmpty else {
            // Explicitly disabled.
            return nil
        }
        guard let origin = try? PairingCode.canonicalRelayOrigin(raw) else {
            DLog("Companion: ignoring \(relayOriginKey)=\(raw); must be a bare https origin")
            return nil
        }
        return origin
    }

    private func acceptLoop(listener: TransportListener,
                            keyPair: NoiseKeyPair,
                            code: PairingCode) async {
        DLog("Companion pairing: accept loop started (pid \(code.pairingID))")
        relayLog("acceptLoop START pid=\(code.pairingID); awaiting a connection (park)")
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
                relayLog("acceptLoop EXIT via accept() error (intentional=\(intentional)): \(error)")
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
                relayLog("acceptLoop: connection ACCEPTED (peer joined); starting Noise handshake")
                onStatus?("Phone connected. Securing the connection…")
                let channel = try await NoiseHandshake.perform(
                    role: .responder,
                    transport: transport,
                    localKeyPair: keyPair,
                    remoteStaticPublicKey: nil,
                    prologue: code.handshakePrologue())
                DLog("Companion pairing: handshake complete")

                // The relay is untrusted: it cannot vouch for who connected.
                // Authenticate the phone end-to-end by its Noise static key,
                // learned (and decrypted) during the handshake. Fail closed if
                // we somehow did not learn it.
                guard let phoneStatic = channel.remoteStaticPublicKey else {
                    DLog("Companion pairing: no phone static key; rejecting")
                    relayLog("acceptLoop: REJECT, no phone static key from handshake")
                    await channel.close()
                    continue
                }

                if code.pairingID != pairedPID {
                    // Fresh pairing (pid not yet persisted): the user types the
                    // SAS code the phone shows; the verdict is the first frame on
                    // the encrypted channel. On acceptance the phone static is
                    // pinned below so future reconnects are authenticated.
                    let expected = PairingSAS.code(handshakeHash: channel.handshakeHash)
                    let accepted = await runSASConfirmation(expected: expected)
                    onSASEntryDismissed?(accepted)
                    let verdict: PairingConfirmation = accepted ? .accepted : .rejected
                    try await channel.send(verdict.encoded())
                    if !accepted {
                        DLog("Companion pairing: SAS not confirmed; rejecting")
                        relayLog("acceptLoop: SAS REJECTED; closing and re-accepting")
                        onStatus?("Pairing declined.")
                        await channel.close()
                        continue
                    }
                } else if let pinned = pairedPhoneStatic, pinned != phoneStatic {
                    // Reconnect whose phone presents a DIFFERENT static than the
                    // device confirmed at pairing: reject end-to-end, regardless
                    // of what the relay admitted. This is the reconnect auth that
                    // SAS bootstrapped; without it a QR-photo attacker reaching
                    // the relay could complete a session. (A paired device with
                    // no pinned static yet predates pinning: trusted on first use
                    // and pinned below.)
                    DLog("Companion pairing: reconnect static mismatch; rejecting")
                    relayLog("acceptLoop: REJECT, reconnecting phone static does not match the paired device")
                    await channel.close()
                    continue
                }
                relayLog("acceptLoop: handshake COMPLETE; creating bridge")

                let newBridge = CompanionHostBridge(transport: channel)
                newBridge.onClose = { [weak self, weak newBridge] in
                    guard let self, let newBridge, self.bridge === newBridge else {
                        // A stale bridge must not tear down its replacement.
                        DLog("Companion: stale bridge closed; ignoring")
                        self?.relayLog("bridge.onClose: STALE bridge closed; ignoring")
                        return
                    }
                    DLog("Companion: bridge closed; resuming listening for reconnect")
                    self.relayLog("bridge.onClose: LIVE bridge closed; nil-ing bridge + resuming")
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
                // Now established: reconnect is keyed on pairedPID, so the
                // fresh-pairing intent is done.
                freshPairingActive = false
                // Pin the phone static: fresh pairings record the SAS-confirmed
                // key; a matched reconnect re-affirms it; a pre-pinning pairing
                // is captured here on first reconnect (trust on first use).
                pairedPhoneStatic = phoneStatic
                onPaired?()
                // Connected: stop accepting now. The relay room has a single mac
                // slot, so parking again while connected would displace this very
                // connection (newest-wins). The next park happens only after this
                // connection is gone, driven by the bridge's onClose ->
                // resumePairedListeningIfNeeded above. (When Bonjour returns as a
                // parallel transport, this can keep accepting again.)
                acceptTask = nil
                relayLog("acceptLoop EXIT: connected, bridge up, stopped accepting "
                         + "(reconnect now driven by bridge.onClose)")
                return
            } catch {
                DLog("Companion pairing: handshake failed: \(error); still listening")
                relayLog("acceptLoop: handshake FAILED (\(error)); closing socket and re-accepting")
                onStatus?("Waiting for your iPhone…")
                // The parked socket was consumed by the failed handshake; close
                // it so the next accept() can park a fresh one (and the relay
                // listener's wait-for-close serialization is released).
                await transport.close()
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
            default:
                // A plain default (not @unknown): NWError has availability-gated
                // cases (e.g. .wifiAware on macOS 26+) that cannot be named on
                // the macOS 12 deployment target, so they fall through to the
                // localizedDescription below.
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
