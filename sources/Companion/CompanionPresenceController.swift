//
//  CompanionPresenceController.swift
//  iTerm2
//
//  Surfaces companion-device presence: a menu bar status item that appears only
//  while a device is paired (and reflects whether it is connected right now),
//  plus a centered toast when the device connects or disconnects. Both are
//  driven by CompanionPairingController.presenceDidChange. macOS user
//  notifications are deliberately avoided (unreliable delivery).
//

import AppKit

@MainActor
@objc(iTermCompanionPresenceController)
final class CompanionPresenceController: NSObject {
    @objc static let shared = CompanionPresenceController()

    private var statusItem: NSStatusItem?
    private var observer: (any NSObjectProtocol)?
    private var settingsObserver: (any NSObjectProtocol)?
    private var wasConnected = false
    private var controller: CompanionPairingController { .shared }

    /// Begin observing presence changes and create the status item if a device
    /// is already paired. Call once, at app launch.
    @objc func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: CompanionPairingController.presenceDidChange,
            object: nil,
            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh(animated: true)
            }
        }
        // The admin/feature-flag gate can hide the whole feature; track it so the
        // status item appears and disappears with it (no toast for a flag flip).
        settingsObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(iTermAdvancedSettingsDidChange),
            object: nil,
            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh(animated: false)
            }
        }
        wasConnected = controller.isConnected
        // animated: false so launching with a device already connected does not
        // pop a toast for a connection that did not just happen.
        refresh(animated: false)
    }

    private func refresh(animated: Bool) {
        // When companion pairing is disabled there is no presence to show, even
        // if a stale pairing from before it was disabled still exists.
        let paired = controller.hasPairedDevice && iTermAdvancedSettingsModel.companionPairingAllowed()
        let connected = controller.isConnected && paired

        if paired {
            updateStatusItem(connected: connected)
        } else {
            removeStatusItem()
        }

        if animated, connected != wasConnected {
            if connected {
                CompanionToast.show(message: "iTerm2 Companion connected",
                                    symbolName: SFSymbol.laptopcomputerAndIphone.rawValue,
                                    tint: .systemGreen)
            } else if paired {
                CompanionToast.show(message: "iTerm2 Companion disconnected",
                                    symbolName: SFSymbol.laptopcomputerAndIphone.rawValue,
                                    tint: .secondaryLabelColor)
            }
        }
        wasConnected = connected
    }

    private func updateStatusItem(connected: Bool) {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            let image = NSImage(systemSymbolName: SFSymbol.laptopcomputerAndIphone.rawValue,
                                accessibilityDescription: "iTerm2 Companion")
            image?.isTemplate = true
            button.image = image
            // Dim the glyph when paired but not currently connected.
            button.alphaValue = connected ? 1.0 : 0.5
            button.toolTip = connected
                ? "Companion device connected"
                : "Companion device paired (not connected)"
        }
        item.menu = makeMenu(connected: connected)
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func makeMenu(connected: Bool) -> NSMenu {
        let menu = NSMenu()
        let header = NSMenuItem(title: connected
                                ? "Companion device connected"
                                : "Companion device paired (not connected)",
                                action: nil,
                                keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Companion Device Settings…",
                                  action: #selector(openSettings),
                                  keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        return menu
    }

    @objc private func openSettings() {
        CompanionPairingWindowController.shared.showAndBeginPairing()
    }
}
