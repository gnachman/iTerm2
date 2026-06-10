//
//  CompanionPairingController.swift
//  iTerm2
//
//  Drives the mac side of pairing: it advertises the companion service, shows a
//  pairing code (as a QR), waits for a phone to connect, runs the Noise XK
//  handshake as the responder, and hands the encrypted channel to a
//  CompanionHostBridge. The transport is reached through the pluggable
//  TransportListener abstraction, so adding a relay or iCloud transport later is
//  a matter of listening on more of them at once.
//

import Foundation
import AppKit
import CoreImage
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
    private var bridge: CompanionHostBridge?

    private(set) var pairingCode: PairingCode?

    // Set by the window controller; all invoked on the main actor.
    var onPaired: (@MainActor () -> Void)?
    var onFailed: (@MainActor (String) -> Void)?
    var onDisconnect: (@MainActor () -> Void)?

    private override init() {
        super.init()
    }

    /// Begin advertising and waiting for a phone. Returns the pairing code whose
    /// URL should be displayed as a QR.
    func startPairing() throws -> PairingCode {
        // Route the transport/crypto layers' diagnostics into the debug log.
        CompanionLog.handler = { message in
            DLog("\(message)")
        }
        cancel()
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

        // Today this is just the local-network listener; wrap additional
        // TransportListeners in a CombinedTransportListener to accept on more.
        let listener = try BonjourTransportListener(pairingID: pairingID,
                                                    version: PairingCode.supportedVersion)
        self.listener = listener

        acceptTask = Task { [weak self] in
            await self?.acceptLoop(listener: listener, keyPair: keyPair, code: code)
        }
        return code
    }

    func cancel() {
        acceptTask?.cancel()
        acceptTask = nil
        listener?.stop()
        listener = nil
        bridge?.stop()
        bridge = nil
        pairingCode = nil
    }

    private func acceptLoop(listener: TransportListener,
                            keyPair: NoiseKeyPair,
                            code: PairingCode) async {
        do {
            DLog("Companion pairing: waiting for a connection (pid \(code.pairingID))")
            let transport = try await listener.accept()
            DLog("Companion pairing: connection accepted; starting Noise handshake")
            let channel = try await NoiseHandshake.perform(
                role: .responder,
                transport: transport,
                localKeyPair: keyPair,
                remoteStaticPublicKey: nil,
                prologue: code.handshakePrologue())
            DLog("Companion pairing: handshake complete")

            let bridge = CompanionHostBridge(transport: channel)
            bridge.onClose = { [weak self] in
                self?.bridge = nil
                self?.onDisconnect?()
            }
            bridge.start()
            self.bridge = bridge

            // Stop advertising once a phone is connected.
            listener.stop()
            self.listener = nil
            onPaired?()
        } catch {
            DLog("Companion pairing failed: \(error)")
            // The listener is dead or the handshake failed; stop advertising a
            // pairing that can no longer complete.
            listener.stop()
            if self.listener === listener {
                self.listener = nil
            }
            if !Task.isCancelled {
                onFailed?(Self.userFacingDescription(of: error))
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
