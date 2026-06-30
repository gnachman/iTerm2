//
//  CompanionPairingWindowController.swift
//  iTerm2
//
//  The window shown by iTerm2 > Companion Device Settings. The top area is dynamic
//  (a QR code, the SAS code entry, paired-device info, or a "what's missing"
//  message). The bottom is a fixed settings section that is ALWAYS present and
//  shows the two companion settings and their status: the consent checkbox and
//  the plugin (installed/not installed, with Reveal/Download and Check Again).
//  Keeping that section constant makes the UI predictable: the controls never
//  appear or vanish, they just reflect the current state.
//  Layout uses explicit frames (no auto layout).
//

import AppKit
import CompanionProtocol
import CoreImage
import LocalAuthentication

@MainActor
@objc(iTermCompanionPairingWindowController)
final class CompanionPairingWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    @objc static let shared = CompanionPairingWindowController()

    // A persistent link to phone-install instructions, shown near the top in
    // every state. The companion app lives outside the Mac, so this is the only
    // affordance that gets the user to their phone.
    private let installAppButton = NSButton(title: "Install Companion App on your iPhone", target: nil, action: nil)

    // MARK: Dynamic top
    private let qrImageView = NSImageView()
    // Shown in place of the QR in the paired state: a big checkmark, green when
    // the device is connected, muted when paired but not currently connected.
    private let checkmarkImageView = NSImageView()
    private let instructionsLabel = NSTextField(wrappingLabelWithString: "")
    // wrappingLabel, not label: a plain label cell is single-line and ignores
    // maximumNumberOfLines, silently truncating long error messages.
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    // The mac's live relay status with a ticking timer (connected for…/last try…),
    // updated once a second by relayStatusTimer while the window is open.
    private let relayStatusLabel = NSTextField(labelWithString: "")
    private var relayStatusTimer: Timer?
    private let unpairButton = NSButton(title: "Unpair", target: nil, action: nil)
    // A remedy for the AI/admin prerequisites (e.g. "Reveal in Settings"). The
    // companion plugin and consent have their own controls in the bottom
    // section, so this is only used for the AI-side gates.
    private let gateButton = NSButton(title: "", target: nil, action: nil)
    // SAS confirmation: shown in place of the QR once the handshake completes,
    // asking the user to type the code the phone is displaying.
    private let sasField = NSTextField(string: "")
    private let sasVerifyButton = NSButton(title: "Verify", target: nil, action: nil)
    private let sasCancelButton = NSButton(title: "Cancel Pairing", target: nil, action: nil)

    // MARK: Fixed bottom settings section (always visible)
    private let sectionSeparator = NSBox()
    // The consent setting. Always shown, never conditional on the plugin:
    // checking it grants consent (set(...), which prompts for authorization);
    // unchecking revokes it. Mirrors the AI plugin's enable checkbox.
    private let consentCheckbox = NSButton(checkboxWithTitle: "Allow companion device pairing",
                                           target: nil,
                                           action: nil)
    // The plugin setting: a status line (with a reload icon to its left that
    // re-checks the plugin) above a Reveal in Finder / Download Plugin… button.
    // Always shown.
    private let pluginDetailLabel = NSTextField(labelWithString: "")
    private let recheckButton = NSButton()
    private let pluginActionButton = NSButton(title: "", target: nil, action: nil)
    private var pluginAction: (() -> Void)?

    // A blurred, dimmed fake QR shown in blocked states so the QR area is filled
    // with an obviously-inactive placeholder rather than a big empty hole.
    private lazy var placeholderQRImage: NSImage = Self.makePlaceholderQRImage()
    private var gateAction: (() -> Void)?
    private var currentGate: CompanionPairingController.Gate?
    // True while the biometric/password sheet for a fresh pairing is up, so a
    // poll or re-key does not stack a second prompt.
    private var pairingAuthInFlight = false
    private var gateObservers: [any NSObjectProtocol] = []
    // The plugin check is a filesystem probe with no change notification, so we
    // poll for it while the window is open (and refresh the settings section).
    private var gatePollTimer: Timer?
    private let controller = CompanionPairingController.shared

    @objc init() {
        // A floating panel so it isn't covered by the What's New onboarding
        // panel (a floating utility NSPanel) when opened from there, matching
        // the Claude Code installer's behavior.
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 600),
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.title = "Companion Device Settings"
        super.init(window: panel)
        panel.delegate = self
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

    /// Show the window. The top reflects the current gate (QR when everything is
    /// satisfied, otherwise what's still needed); the bottom settings section is
    /// always present.
    @objc func showAndBeginPairing() {
        // Reset state BEFORE showing the window: showWindow makes it key, and
        // the didBecomeKey observer runs refreshGateState synchronously (same
        // queue). Resetting currentGate after that would defeat the change
        // guard and present twice, generating two pairings back to back.
        installCallbacks()
        currentGate = nil
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        startGatePolling()
        refreshGateState()
    }

    /// Refresh the always-visible settings section, then re-present the dynamic
    /// top only when the gate changed (re-presenting .allowed would needlessly
    /// regenerate the QR and pairing id).
    private func refreshGateState() {
        guard window?.isVisible == true else { return }
        updateSettingsSection()
        let gate = CompanionPairingController.gate()
        if gate == currentGate {
            // Gate unchanged, so the top is already the right kind of view. But
            // the paired state's connected/not-connected text tracks the live
            // connection, which can change WITHOUT the gate changing (the phone
            // quitting or reconnecting), so keep it current on each poll.
            if gate == .allowed, controller.hasPairedDevice {
                // Paired and allowed but neither connected nor listening means
                // the background park has stopped (e.g. it never restarted after
                // a launch-time gate miss); kick it back to life so the phone can
                // reconnect. resumePairedListeningIfNeeded is guarded, so this is
                // a no-op while connected or already listening.
                if !controller.isConnected, !controller.isListening {
                    controller.resumePairedListeningIfNeeded()
                }
                updatePairedConnectionText()
            }
            return
        }
        currentGate = gate
        RLog("Companion pairing window: gate is now \(gate)")
        switch gate {
        case .aiAdminDisabled:
            // No remedy to offer: this is an administrator decision.
            showBlockedTop("Generative AI features have been disabled. Check with your system administrator.")
        case .aiPluginMissing:
            showBlockedTop("You must install the AI plugin before you can pair a companion device.",
                           remedyTitle: "Reveal in Settings") {
                PreferencePanel.sharedInstance().openToPreference(withKey: kPhonyPreferenceKeyInstallAIPlugin)
            }
        case .aiConsentNeeded:
            showBlockedTop("You must enable AI features in settings before you can pair a companion device.",
                           remedyTitle: "Reveal") {
                PreferencePanel.sharedInstance().openToPreference(withKey: kPreferenceKeyEnableAI)
            }
        case .companionAdminDisabled:
            // No remedy to offer: this is an administrator decision.
            showBlockedTop("Companion device pairing has been disabled. Check with your system administrator.")
        case .companionPluginMissing:
            showBlockedTop("Install the iTerm2 Companion plugin below, then allow companion device pairing.")
        case .companionConsentNeeded:
            showBlockedTop("Turn on “Allow companion device pairing” below to begin.")
        case .allowed:
            if controller.isConnected || controller.hasPairedDevice {
                showPairedState()
            } else {
                startFreshPairingFlow()
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
        // A separate 1s tick so the relay status's elapsed time counts smoothly
        // (the 2s gate poll would skip seconds).
        relayStatusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateRelayStatusLabel()
            }
        }
        updateRelayStatusLabel()
    }

    private func stopGatePolling() {
        gatePollTimer?.invalidate()
        gatePollTimer = nil
        relayStatusTimer?.invalidate()
        relayStatusTimer = nil
    }

    /// Refresh the live relay-status line (connected-for / last-try timers). Shown
    /// only when paired and the feature is allowed; hidden otherwise.
    private func updateRelayStatusLabel() {
        guard window?.isVisible == true,
              CompanionPairingController.gate() == .allowed else {
            relayStatusLabel.isHidden = true
            return
        }
        switch controller.relayStatus {
        case .idle:
            relayStatusLabel.isHidden = true
        case .connected(let since):
            relayStatusLabel.isHidden = false
            relayStatusLabel.textColor = .secondaryLabelColor
            relayStatusLabel.stringValue = "Connected to relay for \(Self.elapsed(since))"
        case .reconnecting(let lastAttempt):
            relayStatusLabel.isHidden = false
            relayStatusLabel.textColor = .systemYellow
            if let lastAttempt {
                relayStatusLabel.stringValue = "Not connected to relay (last try \(Self.elapsed(lastAttempt)) ago)"
            } else {
                relayStatusLabel.stringValue = "Not connected to relay"
            }
        }
    }

    /// Compact elapsed-time string for the relay timers: "5s", "3m 12s",
    /// "1h 04m". Whole seconds, since the label ticks once a second.
    private static func elapsed(_ since: Date) -> String {
        let total = max(0, Int(Date().timeIntervalSince(since)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        if m > 0 { return "\(m)m \(String(format: "%02d", s))s" }
        return "\(s)s"
    }

    // MARK: Bottom settings section

    /// Refresh the always-visible settings section from the current state: the
    /// consent checkbox and the plugin status with its reload icon and button.
    private func updateSettingsSection() {
        consentCheckbox.state = SecureUserDefaults.instance.enableCompanionPairing.value ? .on : .off

        if CompanionPlugin.instance().isSuccess {
            pluginDetailLabel.stringValue = "iTerm2 Companion plugin installed and working ✅"
            pluginDetailLabel.textColor = .systemGreen
            setPluginAction(title: "Reveal in Finder") { [weak self] in self?.revealPluginInFinder() }
        } else {
            pluginDetailLabel.stringValue = "iTerm2 Companion plugin not installed"
            pluginDetailLabel.textColor = .secondaryLabelColor
            setPluginAction(title: "Download Plugin…") {
                if let url = URL(string: "https://iterm2.com/companion-plugin.html") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        layoutPluginStatusRow()
    }

    /// Configure the primary plugin button (Reveal in Finder / Download Plugin…),
    /// centered on its own row below the status line.
    private func setPluginAction(title: String, action: @escaping () -> Void) {
        pluginAction = action
        pluginActionButton.title = title
        pluginActionButton.sizeToFit()
        let width = pluginActionButton.frame.width + 24
        pluginActionButton.frame = NSRect(x: (360 - width) / 2, y: 18, width: width, height: 32)
    }

    /// Lay out the reload icon and the status label as one centered group, the
    /// icon to the left of the message.
    private func layoutPluginStatusRow() {
        let iconSize: CGFloat = 16
        let gap: CGFloat = 6
        pluginDetailLabel.sizeToFit()
        let labelWidth = min(pluginDetailLabel.frame.width, 320 - iconSize - gap)
        // Use the label's NATURAL height so its text is centered within its own
        // frame, then align the icon and the label on one centerline. (A fixed,
        // taller label frame left the text top-aligned and above the icon.)
        let labelHeight = pluginDetailLabel.frame.height
        let centerY: CGFloat = 69
        let x = (360 - (iconSize + gap + labelWidth)) / 2
        recheckButton.frame = NSRect(x: x, y: centerY - iconSize / 2, width: iconSize, height: iconSize)
        pluginDetailLabel.frame = NSRect(x: x + iconSize + gap, y: centerY - labelHeight / 2,
                                         width: labelWidth, height: labelHeight)
    }

    @objc private func pluginActionPressed(_ sender: Any) {
        pluginAction?()
    }

    @objc private func installAppPressed(_ sender: Any) {
        if let url = URL(string: "https://iterm2.com/companion-app.html") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func recheckPressed(_ sender: Any) {
        recheckPlugin()
    }

    /// Force an immediate plugin re-check instead of waiting for the poll. A
    /// success is cached, so this is the only way to notice an uninstall.
    /// refreshGateState refreshes the settings section unconditionally and only
    /// re-presents the top if the gate actually changed, so a no-op recheck in
    /// the allowed state leaves the QR (and its pairing id) untouched.
    private func recheckPlugin() {
        CompanionPlugin.reload()
        // If the re-probe shows the plugin is gone, a paired device must be
        // unpaired and its key material deleted before we re-present the gate.
        controller.unpairIfPluginMissing()
        refreshGateState()
    }

    private func revealPluginInFinder() {
        guard case .success(let plugin) = CompanionPlugin.instance() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([plugin.bundleURL])
    }

    @objc private func consentToggled(_ sender: NSButton) {
        if sender.state == .on {
            // Granting consent writes a root-owned secure default, which prompts
            // for administrator authorization. On success set(...) posts
            // secureUserDefaultDidChange and the observer re-evaluates the gate
            // (advancing to .allowed) — do not refresh here too, or the .allowed
            // presentation would run twice and start two pairings. If auth is
            // cancelled it throws; revert the checkbox to the actual value.
            do {
                try SecureUserDefaults.instance.enableCompanionPairing.set(true)
            } catch {
                updateSettingsSection()
            }
        } else {
            // Turning off consent fully unpairs: kick the device, delete all key
            // material, and stop listening, then clear the secure opt-in. unpair()
            // announces the farewell over the live bridge, so call it before
            // resetting the default (which would otherwise drop the bridge
            // silently via the gate observer). Neither step needs authorization:
            // revoking and resetting to the default are both fail-safe.
            controller.unpair()
            try? SecureUserDefaults.instance.enableCompanionPairing.reset()
        }
    }

    // MARK: Dynamic top

    /// Hide every mutually-exclusive top widget so a caller can show just the
    /// one it wants. Leaves the title, instructions, status, and the fixed
    /// bottom settings section alone.
    private func hideTopContent() {
        gateButton.isHidden = true
        gateButton.keyEquivalent = ""
        qrImageView.isHidden = true
        checkmarkImageView.isHidden = true
        unpairButton.isHidden = true
        sasField.isHidden = true
        sasVerifyButton.isHidden = true
        sasCancelButton.isHidden = true
    }

    /// A blocked gate: no live QR. When there is a remedy (e.g. Authenticate),
    /// show a prominent default button on a clean background so it is obviously
    /// the thing to click. Otherwise fill the QR area with a dimmed, blurred
    /// placeholder so the layout has no empty hole. The bottom settings section
    /// is untouched; updateSettingsSection keeps it current.
    private func showBlockedTop(_ message: String,
                                remedyTitle: String? = nil,
                                remedyAction: (() -> Void)? = nil) {
        // If a QR was up when the gate slammed shut (e.g. consent revoked), stop
        // advertising it.
        controller.stopAdvertising()
        hideTopContent()
        instructionsLabel.stringValue = message
        setStatus("", color: .secondaryLabelColor)
        gateAction = remedyAction
        if let remedyTitle {
            // A clean background and a larger default (accent-highlighted) button:
            // the dimmed placeholder QR would camouflage a plain push button.
            gateButton.title = remedyTitle
            gateButton.controlSize = .large
            gateButton.keyEquivalent = "\r"
            gateButton.sizeToFit()
            let width = gateButton.frame.width + 48
            gateButton.frame = NSRect(x: (360 - width) / 2,
                                      y: 280,
                                      width: width,
                                      height: gateButton.frame.height)
            gateButton.isHidden = false
        } else {
            // Nothing to click: fill the QR area with the dimmed placeholder.
            qrImageView.image = placeholderQRImage
            qrImageView.alphaValue = 0.18
            qrImageView.isHidden = false
        }
    }

    /// Build the placeholder once: a real QR of a throwaway string, Gaussian
    /// blurred so it reads as an inactive QR. It is also shown at low opacity.
    private static func makePlaceholderQRImage() -> NSImage {
        guard let qr = CompanionPairingController.qrImage(for: "iterm2-companion", pointSize: 200) else {
            return NSImage(size: NSSize(width: 200, height: 200))
        }
        guard let tiff = qr.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let input = CIImage(bitmapImageRep: bitmap),
              let filter = CIFilter(name: "CIGaussianBlur") else {
            return qr
        }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(5.0, forKey: kCIInputRadiusKey)
        // Gaussian blur grows the extent; render cropped to the original bounds.
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: input.extent) else {
            return qr
        }
        return NSImage(cgImage: cg, size: qr.size)
    }

    @objc private func gatePressed(_ sender: Any) {
        gateAction?()
    }

    private func setSASEntryVisible(_ visible: Bool) {
        if visible {
            hideTopContent()
            sasField.isHidden = false
            sasVerifyButton.isHidden = false
            sasCancelButton.isHidden = false
            instructionsLabel.stringValue = "Type the 6-digit code shown on your iPhone. This confirms you’re pairing with your own phone."
            sasField.stringValue = ""
            updateSASVerifyEnabled()  // empty -> Verify disabled until 6 digits
            window?.makeFirstResponder(sasField)
        } else {
            sasField.isHidden = true
            sasVerifyButton.isHidden = true
            sasCancelButton.isHidden = true
        }
    }

    @objc private func sasVerifyPressed(_ sender: Any) {
        // Ignore an incomplete code, in case Return reaches here while the Verify
        // button is disabled.
        guard isCompleteSAS(sasField.stringValue) else { return }
        controller.submitSASEntry(sasField.stringValue)
        sasField.stringValue = ""
    }

    /// The SAS is exactly six decimal digits.
    private func isCompleteSAS(_ s: String) -> Bool {
        s.count == 6 && s.allSatisfy { ("0"..."9").contains($0) }
    }

    private func updateSASVerifyEnabled() {
        sasVerifyButton.isEnabled = isCompleteSAS(sasField.stringValue)
    }

    func controlTextDidChange(_ obj: Notification) {
        updateSASVerifyEnabled()
    }

    @objc private func sasCancelPressed(_ sender: Any) {
        // Cancel Pairing aborts the whole flow, so just close the window. That
        // guarantees the abort regardless of the in-flight SAS state (the
        // previous "decline this attempt" path could leave a stale message with
        // no QR). windowWillClose -> stopAdvertising unblocks the SAS wait and
        // stops the listener; the phone is disconnected when the mac leaves.
        close()
    }

    private func installCallbacks() {
        controller.onStatus = { [weak self] status in
            self?.setStatus(status, color: .secondaryLabelColor)
        }
        controller.onPaired = { [weak self] in
            // A device connected (a fresh pairing or a later reconnect, since the
            // accept loop fires this on every connection). Show the connected
            // paired state and leave the window open; the user closes it.
            self?.showPairedState()
        }
        controller.onFailed = { [weak self] message in
            self?.setStatus("Pairing failed: \(message)", color: .systemRed)
        }
        controller.onDisconnect = { [weak self] in
            guard let self else { return }
            self.setStatus("Device disconnected.", color: .secondaryLabelColor)
            // Reflect the drop in the paired-state instructions right away
            // rather than waiting for the next poll.
            if self.currentGate == .allowed, self.controller.hasPairedDevice {
                self.updatePairedConnectionText()
            }
        }
        controller.onSASEntryNeeded = { [weak self] in
            self?.setSASEntryVisible(true)
        }
        controller.onSASEntryDismissed = { [weak self] accepted in
            self?.setSASEntryVisible(false)
            if !accepted {
                // Declined or too many mistypes: back to the QR view. The
                // controller regenerates the pid (onPairingCodeChanged redraws
                // the code below), so the retry uses a fresh QR.
                self?.qrImageView.alphaValue = 1.0
                self?.qrImageView.isHidden = false
                self?.instructionsLabel.stringValue = "In the iTerm2 Buddy app on your iPhone, tap Scan and point the camera at this code."
            }
        }
        controller.onPairingCodeChanged = { [weak self] code in
            // The pid was regenerated (timeout, rejected SAS, or relay teardown):
            // redraw the QR for the new code so the displayed one stays valid.
            self?.qrImageView.image = CompanionPairingController.qrImage(for: code.urlString(), pointSize: 240)
        }
    }

    private func setStatus(_ text: String, color: NSColor) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
    }

    private func showPairedState() {
        hideTopContent()
        checkmarkImageView.isHidden = false
        unpairButton.isHidden = false
        updatePairedConnectionText()
        setStatus("To pair a different device, unpair first. Unpairing kicks the device off and deletes the pairing keys.",
                  color: .secondaryLabelColor)
    }

    /// Set the paired-state instructions and checkmark color from the live
    /// connection. Safe to call repeatedly; used to reflect the phone connecting
    /// or dropping while the gate (still .allowed) does not change.
    private func updatePairedConnectionText() {
        if controller.isConnected {
            instructionsLabel.stringValue = "A companion device is paired and connected."
            checkmarkImageView.contentTintColor = .systemGreen
        } else if controller.isListening {
            // Parked at the relay, just waiting for the phone to come back.
            instructionsLabel.stringValue = "A companion device is paired. Waiting for it to connect."
            checkmarkImageView.contentTintColor = .tertiaryLabelColor
        } else {
            // Not listening at all: the phone cannot reach this Mac. The poll in
            // refreshGateState nudges a resume, so word it as transient.
            instructionsLabel.stringValue = "A companion device is paired but iTerm2 isn’t listening for it yet. Reconnecting…"
            checkmarkImageView.contentTintColor = .systemYellow
        }
        updateRelayStatusLabel()
    }

    /// Require the device owner to authenticate before showing a fresh pairing
    /// QR, so brief physical access to an unlocked Mac is not enough to pair a
    /// new device. Authentication uses biometrics when available and falls back
    /// to the device passcode/login password.
    private func startFreshPairingFlow() {
        guard !pairingAuthInFlight else { return }
        pairingAuthInFlight = true
        // The system sheet appears over the window; show a neutral prompt behind.
        showBlockedTop("Authenticate to pair a companion device with this Mac.")
        Task { [weak self] in
            guard let self else { return }
            let authenticated = await self.authenticateToPair()
            self.pairingAuthInFlight = false
            // The gate may have changed while the sheet was up (consent revoked,
            // a device reconnected, the window closed): only show the QR if a
            // fresh pairing is still what's wanted.
            guard self.window?.isVisible == true,
                  self.currentGate == .allowed,
                  !self.controller.hasPairedDevice else {
                return
            }
            if authenticated {
                self.beginFreshPairing()
            } else {
                self.showBlockedTop("Authentication is required to pair a companion device.",
                                    remedyTitle: "Authenticate") { [weak self] in
                    self?.startFreshPairingFlow()
                }
            }
        }
    }

    private func authenticateToPair() async -> Bool {
        let context = LAContext()
        var error: NSError?
        // .deviceOwnerAuthentication uses biometrics when available and falls
        // back to the device passcode/login password otherwise.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics and no passcode configured: there is nothing to
            // authenticate against, so let pairing proceed (the Mac is unsecured
            // regardless).
            RLog("Companion: no device authentication available (\(error?.localizedDescription ?? "none")); proceeding")
            return true
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication,
                                   localizedReason: "pair a companion device with this Mac") { success, authError in
                if let authError {
                    RLog("Companion: pairing authentication failed: \(authError.localizedDescription)")
                }
                continuation.resume(returning: success)
            }
        }
    }

    private func beginFreshPairing() {
        hideTopContent()
        qrImageView.alphaValue = 1.0
        qrImageView.isHidden = false
        instructionsLabel.stringValue = "In the iTerm2 Buddy app on your iPhone, tap Scan and point the camera at this code."
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
        startFreshPairingFlow()
    }

    func windowWillClose(_ notification: Notification) {
        stopGatePolling()
        currentGate = nil
        RLog("Companion windowWillClose (hasPairedDevice=\(controller.hasPairedDevice)): "
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

    // MARK: Layout

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Companion Device Settings")
        title.font = .boldSystemFont(ofSize: 18)
        title.alignment = .center
        title.frame = NSRect(x: 20, y: 556, width: 320, height: 28)
        content.addSubview(title)

        // Live relay status with a ticking timer, just under the title. Hidden
        // until paired (updateRelayStatusLabel manages visibility + text).
        relayStatusLabel.alignment = .center
        relayStatusLabel.font = .systemFont(ofSize: 12)
        relayStatusLabel.textColor = .secondaryLabelColor
        relayStatusLabel.lineBreakMode = .byTruncatingTail
        relayStatusLabel.frame = NSRect(x: 20, y: 530, width: 320, height: 18)
        relayStatusLabel.isHidden = true
        content.addSubview(relayStatusLabel)

        installAppButton.target = self
        installAppButton.action = #selector(installAppPressed(_:))
        installAppButton.bezelStyle = .rounded
        installAppButton.sizeToFit()
        let installWidth = installAppButton.frame.width + 24
        installAppButton.frame = NSRect(x: (360 - installWidth) / 2, y: 484, width: installWidth, height: 32)
        content.addSubview(installAppButton)

        instructionsLabel.alignment = .center
        instructionsLabel.font = .systemFont(ofSize: 12)
        instructionsLabel.textColor = .secondaryLabelColor
        instructionsLabel.frame = NSRect(x: 30, y: 410, width: 300, height: 52)
        instructionsLabel.maximumNumberOfLines = 3
        content.addSubview(instructionsLabel)

        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.frame = NSRect(x: 80, y: 196, width: 200, height: 200)
        qrImageView.wantsLayer = true
        qrImageView.layer?.backgroundColor = NSColor.white.cgColor
        qrImageView.isHidden = true
        content.addSubview(qrImageView)

        checkmarkImageView.imageScaling = .scaleProportionallyUpOrDown
        checkmarkImageView.frame = NSRect(x: 115, y: 274, width: 130, height: 130)
        let checkConfig = NSImage.SymbolConfiguration(pointSize: 96, weight: .regular)
        let checkImage = NSImage(systemSymbolName: SFSymbol.checkmarkCircleFill.rawValue,
                                 accessibilityDescription: "Companion device connection status")?
            .withSymbolConfiguration(checkConfig)
        // Must be a template for contentTintColor to apply; .withSymbolConfiguration
        // can clear the flag. Template rendering also keeps the checkmark as a
        // visible cutout (a palette fill color would make a solid disc).
        checkImage?.isTemplate = true
        checkmarkImageView.image = checkImage
        checkmarkImageView.isHidden = true
        content.addSubview(checkmarkImageView)

        // Sits low, just above the "To pair a different device…" status text.
        unpairButton.target = self
        unpairButton.action = #selector(unpairPressed(_:))
        unpairButton.bezelStyle = .rounded
        unpairButton.sizeToFit()
        unpairButton.frame = NSRect(x: (360 - unpairButton.frame.width - 24) / 2,
                                    y: 198,
                                    width: unpairButton.frame.width + 24,
                                    height: 32)
        unpairButton.isHidden = true
        content.addSubview(unpairButton)

        gateButton.target = self
        gateButton.action = #selector(gatePressed(_:))
        gateButton.bezelStyle = .rounded
        gateButton.isHidden = true
        content.addSubview(gateButton)

        sasField.alignment = .center
        sasField.font = .monospacedDigitSystemFont(ofSize: 28, weight: .medium)
        sasField.placeholderString = "000000"
        sasField.frame = NSRect(x: 105, y: 300, width: 150, height: 44)
        sasField.target = self
        sasField.action = #selector(sasVerifyPressed(_:))  // Return key verifies.
        sasField.delegate = self  // Enable Verify only on a complete 6-digit code.
        sasField.isHidden = true
        content.addSubview(sasField)

        sasVerifyButton.target = self
        sasVerifyButton.action = #selector(sasVerifyPressed(_:))
        sasVerifyButton.bezelStyle = .rounded
        sasVerifyButton.keyEquivalent = "\r"
        sasVerifyButton.frame = NSRect(x: 130, y: 250, width: 100, height: 32)
        sasVerifyButton.isHidden = true
        content.addSubview(sasVerifyButton)

        sasCancelButton.target = self
        sasCancelButton.action = #selector(sasCancelPressed(_:))
        sasCancelButton.bezelStyle = .rounded
        sasCancelButton.frame = NSRect(x: 115, y: 206, width: 130, height: 32)
        sasCancelButton.isHidden = true
        content.addSubview(sasCancelButton)

        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isSelectable = false
        statusLabel.frame = NSRect(x: 20, y: 132, width: 320, height: 58)
        statusLabel.maximumNumberOfLines = 3
        statusLabel.cell?.truncatesLastVisibleLine = true
        content.addSubview(statusLabel)

        // Fixed settings section, delineated by a separator and always visible.
        sectionSeparator.boxType = .separator
        sectionSeparator.frame = NSRect(x: 20, y: 120, width: 320, height: 1)
        content.addSubview(sectionSeparator)

        consentCheckbox.target = self
        consentCheckbox.action = #selector(consentToggled(_:))
        consentCheckbox.sizeToFit()
        consentCheckbox.frame = NSRect(x: (360 - consentCheckbox.frame.width) / 2,
                                       y: 90,
                                       width: consentCheckbox.frame.width,
                                       height: 20)
        content.addSubview(consentCheckbox)

        pluginDetailLabel.alignment = .left
        pluginDetailLabel.font = .systemFont(ofSize: 12)
        pluginDetailLabel.lineBreakMode = .byTruncatingTail
        pluginDetailLabel.frame = NSRect(x: 20, y: 60, width: 320, height: 18)
        content.addSubview(pluginDetailLabel)

        recheckButton.target = self
        recheckButton.action = #selector(recheckPressed(_:))
        recheckButton.isBordered = false
        recheckButton.imageScaling = .scaleProportionallyDown
        recheckButton.image = NSImage(systemSymbolName: SFSymbol.arrowClockwise.rawValue,
                                      accessibilityDescription: "Check again")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        recheckButton.toolTip = "Check again for the plugin"
        content.addSubview(recheckButton)

        pluginActionButton.target = self
        pluginActionButton.action = #selector(pluginActionPressed(_:))
        pluginActionButton.bezelStyle = .rounded
        content.addSubview(pluginActionButton)

        // Pre-populate the settings section so it is correct before the first
        // gate evaluation (and even if the window is shown without pairing).
        updateSettingsSection()
    }
}
