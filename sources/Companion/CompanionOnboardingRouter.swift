//
//  CompanionOnboardingRouter.swift
//  iTerm2
//
//  Single decision point for "Companion Device Settings". A user who has never
//  paired a device gets the guided first-run wizard (which downloads the
//  plugins, grants consent in one prompt, and walks them through phone setup and
//  pairing); everyone else gets today's plain settings window. Every entry point
//  (the main menu, the menu-bar status item, the What's New link) routes through
//  here so the choice is made the same way everywhere.
//

import AppKit

/// The single definition of "AI is set up" and "companion is set up", shared by
/// the router (which screen to start on) and the wizard (did setup succeed), so
/// the two cannot drift.
@MainActor
enum CompanionSetupState {
    /// AI is fully configured: the signed plugin is present, consent is granted,
    /// and an API key is saved.
    static var aiConfigured: Bool {
        return iTermAITermGatekeeper.pluginInstalled()
            && SecureUserDefaults.instance.enableAI.value
            && !(AITermControllerObjC.apiKey ?? "").isEmpty
    }

    /// Companion is fully configured: the signed plugin is present and consent
    /// is granted.
    static var companionConfigured: Bool {
        return CompanionPlugin.instance().isSuccess
            && SecureUserDefaults.instance.enableCompanionPairing.value
    }
}

@MainActor
@objc(iTermCompanionOnboardingRouter)
final class CompanionOnboardingRouter: NSObject {
    /// Open the right Companion Device Settings experience for the current state.
    @objc static func openSettingsOrWizard() {
        switch destination() {
        case .classicSettings:
            CompanionPairingWindowController.shared.showAndBeginPairing()
        case .wizard(let start):
            CompanionWizardWindowController.shared.show(startingAt: start)
        }
    }

    enum Destination: Equatable {
        case classicSettings
        case wizard(CompanionWizardWindowController.Screen)
    }

    private static func destination() -> Destination {
        return destination(
            companionPairingAllowed: iTermAdvancedSettingsModel.companionPairingAllowed(),
            experienced: CompanionPushRegistry.everPaired || CompanionPairingController.shared.hasPairedDevice,
            companionConfigured: CompanionSetupState.companionConfigured)
    }

    /// Pure routing decision, split out so it can be tested without touching admin
    /// settings, the keychain, or the installed plugins.
    static func destination(companionPairingAllowed: Bool,
                            experienced: Bool,
                            companionConfigured: Bool) -> Destination {
        // An administrator policy blocks companion pairing: the plain window
        // already explains the block, and the wizard cannot grant something an
        // admin has forbidden, so send the user there. AI being admin-disabled no
        // longer forces this: a companion-only setup does not need AI, so such a
        // user should still get the guided wizard.
        if !companionPairingAllowed {
            return .classicSettings
        }
        // The wizard is first-run only. A user is "experienced" if they have ever
        // paired (the sticky flag) OR a device is paired right now. The
        // hasPairedDevice check is essential for migration: the everPaired flag is
        // new and only set on a fresh pairing, so a user who paired in a prior
        // build has pairedPID set but everPaired == false, and without this they
        // would be dropped back into the first-run wizard.
        if experienced {
            return .classicSettings
        }
        // The companion isn't set up yet: let the user choose whether they want AI
        // features or terminal viewing/control only (screen 1.0), which routes to
        // the full (1.1, API key required) or companion-only (1.2) install. AI is
        // no longer a prerequisite, so we no longer force the full setup first.
        if !companionConfigured {
            return .wizard(.chooseMode)
        }
        // Everything is installed and consented but no device has ever paired:
        // skip the install steps and go straight to the phone-app instructions.
        return .wizard(.phoneApp)
    }
}
