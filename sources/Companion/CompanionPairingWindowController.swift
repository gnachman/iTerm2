//
//  CompanionPairingWindowController.swift
//  iTerm2
//
//  The window shown by iTerm2 > Pair Companion Device: it displays the QR code
//  the phone scans and reports pairing progress. Layout is done with explicit
//  frames (no auto layout) since the content is fixed-size.
//

import AppKit
import CompanionProtocol

@MainActor
@objc(iTermCompanionPairingWindowController)
final class CompanionPairingWindowController: NSWindowController, NSWindowDelegate {
    @objc static let shared = CompanionPairingWindowController()

    private let qrImageView = NSImageView()
    // wrappingLabel, not label: a plain label cell is single-line and ignores
    // maximumNumberOfLines, silently truncating long error messages.
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        it_fatalError("CompanionPairingWindowController does not support coder initialization")
    }

    /// Show the window and start advertising for a phone.
    @objc func showAndBeginPairing() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        beginPairing()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Pair Companion Device")
        title.font = .boldSystemFont(ofSize: 18)
        title.alignment = .center
        title.frame = NSRect(x: 20, y: 432, width: 320, height: 28)
        content.addSubview(title)

        let instructions = NSTextField(wrappingLabelWithString:
            "In the iTerm2 Companion app on your iPhone, tap Scan and point the camera at this code.")
        instructions.alignment = .center
        instructions.font = .systemFont(ofSize: 12)
        instructions.textColor = .secondaryLabelColor
        instructions.frame = NSRect(x: 30, y: 380, width: 300, height: 44)
        content.addSubview(instructions)

        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.frame = NSRect(x: 60, y: 110, width: 240, height: 240)
        qrImageView.wantsLayer = true
        qrImageView.layer?.backgroundColor = NSColor.white.cgColor
        content.addSubview(qrImageView)

        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isSelectable = false
        statusLabel.frame = NSRect(x: 20, y: 16, width: 320, height: 84)
        statusLabel.maximumNumberOfLines = 5
        statusLabel.cell?.truncatesLastVisibleLine = true
        content.addSubview(statusLabel)
    }

    private func beginPairing() {
        controller.onPaired = { [weak self] in
            self?.statusLabel.stringValue = "Paired. You can close this window."
            self?.statusLabel.textColor = .systemGreen
        }
        controller.onFailed = { [weak self] message in
            self?.statusLabel.stringValue = "Pairing failed: \(message)"
            self?.statusLabel.textColor = .systemRed
        }
        controller.onDisconnect = { [weak self] in
            self?.statusLabel.stringValue = "Device disconnected."
            self?.statusLabel.textColor = .secondaryLabelColor
        }

        do {
            let code = try controller.startPairing()
            qrImageView.image = CompanionPairingController.qrImage(for: code.urlString(), pointSize: 240)
            statusLabel.stringValue = "Waiting for your iPhone…"
            statusLabel.textColor = .secondaryLabelColor
        } catch {
            statusLabel.stringValue = "Could not start pairing: \(error)"
            statusLabel.textColor = .systemRed
        }
    }

    func windowWillClose(_ notification: Notification) {
        controller.cancel()
    }
}
