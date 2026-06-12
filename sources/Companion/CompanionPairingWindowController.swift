//
//  CompanionPairingWindowController.swift
//  iTerm2
//
//  The window shown by iTerm2 > Pair Companion Device. If a device is already
//  paired it says so and offers to unpair (kicking the device and deleting key
//  material) before showing a fresh QR code; otherwise it shows the QR and
//  live pairing status, and closes itself shortly after pairing succeeds.
//  Layout uses explicit frames (no auto layout).
//

import AppKit
import CompanionProtocol

@MainActor
@objc(iTermCompanionPairingWindowController)
final class CompanionPairingWindowController: NSWindowController, NSWindowDelegate {
    @objc static let shared = CompanionPairingWindowController()

    private let qrImageView = NSImageView()
    private let instructionsLabel = NSTextField(wrappingLabelWithString: "")
    // wrappingLabel, not label: a plain label cell is single-line and ignores
    // maximumNumberOfLines, silently truncating long error messages.
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let unpairButton = NSButton(title: "Unpair and Pair a New Device",
                                        target: nil,
                                        action: nil)
    // Shown instead of the QR when AI features are unavailable; reveals the
    // relevant setting. Hidden when there is no remedy (admin-disabled).
    private let gateButton = NSButton(title: "", target: nil, action: nil)
    private var gateAction: (() -> Void)?
    private var currentGate: CompanionPairingController.AIGate?
    private var gateObservers: [any NSObjectProtocol] = []
    // The plugin check is a filesystem probe with no change notification, so
    // while a blocked state is showing we poll for it.
    private var gatePollTimer: Timer?
    private let controller = CompanionPairingController.shared

    @objc init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Pair Companion Device"
        super.init(window: window)
        window.delegate = self
        buildContent()

        // Re-evaluate the gates live: consent and the advanced setting post
        // notifications; window-key catches returns from Settings.
        let center = NotificationCenter.default
        for name in [iTermSecureUserDefaults.didChange,
                     Notification.Name(iTermAdvancedSettingsDidChange),
                     NSWindow.didBecomeKeyNotification] {
            gateObservers.append(center.addObserver(forName: name,
                                                    object: nil,
                                                    queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshGateState()
                }
            })
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("CompanionPairingWindowController does not support coder initialization")
    }

    /// Show the window. Pairing is pointless without working AI features, so
    /// the gate states replace the QR; otherwise begins a fresh pairing unless
    /// a device is already paired, in which case the unpair flow is offered.
    @objc func showAndBeginPairing() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        installCallbacks()
        currentGate = nil
        refreshGateState()
    }

    /// Recompute the gate and re-present only when it changed (re-presenting
    /// .allowed would needlessly regenerate the QR and pairing id).
    private func refreshGateState() {
        guard window?.isVisible == true else { return }
        let gate = CompanionPairingController.aiGate()
        guard gate != currentGate else { return }
        let wasBlocked = currentGate != nil && currentGate != .allowed
        currentGate = gate
        DLog("Companion pairing window: gate is now \(gate)")
        switch gate {
        case .adminDisabled:
            // No remedy to offer: this is an administrator decision.
            showGate(message: "Generative AI features have been disabled. Check with your system administrator.",
                     buttonTitle: nil,
                     action: nil)
        case .pluginMissing:
            showGate(message: "You must install the AI plugin before you can pair a companion device.",
                     buttonTitle: "Reveal in Settings") {
                PreferencePanel.sharedInstance().openToPreference(withKey: kPhonyPreferenceKeyInstallAIPlugin)
            }
        case .consentNeeded:
            showGate(message: "You must enable AI features in settings before you can pair a companion device.",
                     buttonTitle: "Reveal") {
                PreferencePanel.sharedInstance().openToPreference(withKey: kPreferenceKeyEnableAI)
            }
        case .allowed:
            stopGatePolling()
            _ = wasBlocked  // The presentation below is correct either way.
            if controller.isConnected || controller.hasPairedDevice {
                showPairedState()
            } else {
                beginFreshPairing()
            }
        }
    }

    private func startGatePolling() {
        guard gatePollTimer == nil else { return }
        gatePollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshGateState()
            }
        }
    }

    private func stopGatePolling() {
        gatePollTimer?.invalidate()
        gatePollTimer = nil
    }

    private func showGate(message: String, buttonTitle: String?, action: (() -> Void)?) {
        // If a QR was up when the gate slammed shut (e.g. consent revoked),
        // stop advertising it.
        controller.stopAdvertising()
        startGatePolling()
        qrImageView.isHidden = true
        unpairButton.isHidden = true
        instructionsLabel.stringValue = message
        setStatus("", color: .secondaryLabelColor)
        gateAction = action
        if let buttonTitle {
            gateButton.title = buttonTitle
            gateButton.sizeToFit()
            gateButton.frame = NSRect(x: (360 - gateButton.frame.width - 24) / 2,
                                      y: 210,
                                      width: gateButton.frame.width + 24,
                                      height: 32)
            gateButton.isHidden = false
        } else {
            gateButton.isHidden = true
        }
    }

    @objc private func gatePressed(_ sender: Any) {
        gateAction?()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Pair Companion Device")
        title.font = .boldSystemFont(ofSize: 18)
        title.alignment = .center
        title.frame = NSRect(x: 20, y: 432, width: 320, height: 28)
        content.addSubview(title)

        instructionsLabel.alignment = .center
        instructionsLabel.font = .systemFont(ofSize: 12)
        instructionsLabel.textColor = .secondaryLabelColor
        instructionsLabel.frame = NSRect(x: 30, y: 372, width: 300, height: 52)
        instructionsLabel.maximumNumberOfLines = 3
        content.addSubview(instructionsLabel)

        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.frame = NSRect(x: 60, y: 110, width: 240, height: 240)
        qrImageView.wantsLayer = true
        qrImageView.layer?.backgroundColor = NSColor.white.cgColor
        content.addSubview(qrImageView)

        unpairButton.target = self
        unpairButton.action = #selector(unpairPressed(_:))
        unpairButton.bezelStyle = .rounded
        unpairButton.sizeToFit()
        unpairButton.frame = NSRect(x: (360 - unpairButton.frame.width - 24) / 2,
                                    y: 210,
                                    width: unpairButton.frame.width + 24,
                                    height: 32)
        unpairButton.isHidden = true
        content.addSubview(unpairButton)

        gateButton.target = self
        gateButton.action = #selector(gatePressed(_:))
        gateButton.bezelStyle = .rounded
        gateButton.isHidden = true
        content.addSubview(gateButton)

        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isSelectable = false
        statusLabel.frame = NSRect(x: 20, y: 16, width: 320, height: 84)
        statusLabel.maximumNumberOfLines = 5
        statusLabel.cell?.truncatesLastVisibleLine = true
        content.addSubview(statusLabel)
    }

    private func installCallbacks() {
        controller.onStatus = { [weak self] status in
            self?.setStatus(status, color: .secondaryLabelColor)
        }
        controller.onPaired = { [weak self] in
            self?.setStatus("Paired.", color: .systemGreen)
            // Give the user a beat to see the confirmation, then get out of
            // the way.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self?.close()
            }
        }
        controller.onFailed = { [weak self] message in
            self?.setStatus("Pairing failed: \(message)", color: .systemRed)
        }
        controller.onDisconnect = { [weak self] in
            self?.setStatus("Device disconnected.", color: .secondaryLabelColor)
        }
    }

    private func setStatus(_ text: String, color: NSColor) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
    }

    private func showPairedState() {
        qrImageView.isHidden = true
        gateButton.isHidden = true
        unpairButton.isHidden = false
        instructionsLabel.stringValue = controller.isConnected
            ? "A companion device is paired and connected."
            : "A companion device is paired but not currently connected."
        setStatus("To pair a different device, unpair first. Unpairing kicks the device off and deletes the pairing keys.",
                  color: .secondaryLabelColor)
    }

    private func beginFreshPairing() {
        qrImageView.isHidden = false
        gateButton.isHidden = true
        unpairButton.isHidden = true
        instructionsLabel.stringValue = "In the iTerm2 Companion app on your iPhone, tap Scan and point the camera at this code."
        do {
            let code = try controller.startPairing()
            qrImageView.image = CompanionPairingController.qrImage(for: code.urlString(), pointSize: 240)
            setStatus("Waiting for your iPhone…", color: .secondaryLabelColor)
        } catch {
            setStatus("Could not start pairing: \(error.localizedDescription)", color: .systemRed)
        }
    }

    @objc private func unpairPressed(_ sender: Any) {
        controller.unpair()
        beginFreshPairing()
    }

    func windowWillClose(_ notification: Notification) {
        stopGatePolling()
        currentGate = nil
        NSFuckingLog("%@", "COMPANIONRELAY windowWillClose (hasPairedDevice=\(controller.hasPairedDevice)): "
                     + (controller.hasPairedDevice ? "keeping listener" : "stopAdvertising"))
        if controller.hasPairedDevice {
            // A pairing happened: the listener that handled it keeps running in
            // the background to serve the connection and accept reconnects.
            // Do NOT stop and restart it: over the single-slot relay a restart
            // parks a fresh mac socket that displaces the live connection, which
            // would tear down the bridge moments after pairing. Leave it be.
            return
        }
        // Window dismissed without pairing: stop advertising the QR.
        controller.stopAdvertising()
    }
}
