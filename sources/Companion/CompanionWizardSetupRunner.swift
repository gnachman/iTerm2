//
//  CompanionWizardSetupRunner.swift
//  iTerm2
//
//  The step sequence behind the companion setup wizard's Install button:
//  download and install the plugins, grant consent (which raises the admin
//  password prompt), store the AI key, and verify. It is separate from the
//  window controller, with every side effect behind CompanionWizardSetupSteps, so
//  tests can drive it with fakes (no network, no admin prompt) and check that a
//  wizard closed mid-setup stops before any side effect and rolls back silently.
//

import Foundation

/// The side-effecting operations Install performs. `live` is the real thing.
@MainActor
struct CompanionWizardSetupSteps {
    var installAIPlugin: () async throws -> Void
    var installCompanionPlugin: () async throws -> Void
    /// Raises the admin password prompt when a consent is off.
    var grantConsent: (_ ai: Bool, _ companion: Bool) throws -> Void
    /// Turns a consent back off. Needs no authorization (it is fail-safe).
    var revokeAIConsent: () -> Void
    var revokeCompanionConsent: () -> Void
    var writeAIKey: (CompanionWizardAIKeyPlan.Write) -> Void

    static var live: CompanionWizardSetupSteps {
        return CompanionWizardSetupSteps(
            installAIPlugin: { try await CompanionPluginInstaller.installAIPlugin() },
            installCompanionPlugin: { try await CompanionPluginInstaller.installCompanionPlugin() },
            grantConsent: { ai, companion in
                try SecureUserDefaults.grantConsent(ai: ai, companion: companion)
            },
            revokeAIConsent: { try? SecureUserDefaults.instance.enableAI.reset() },
            revokeCompanionConsent: { try? SecureUserDefaults.instance.enableCompanionPairing.reset() },
            writeAIKey: { write in
                AITermControllerObjC.setAPIKey(write.key, for: write.vendor)
                iTermPreferences.setInt(Int32(write.vendorPreference), forKey: kPreferenceKeyAIVendor)
            })
    }
}

@MainActor
enum CompanionWizardSetupRunner {
    /// What Install is about to do, for the status line.
    enum Stage: Equatable {
        case downloadingAIPlugin
        case downloadingCompanionPlugin
        case grantingConsent
        case verifying
    }

    enum Outcome {
        case completed
        case failed(Error)
        /// The wizard was closed. Nothing more was done and anything this
        /// attempt wrote was rolled back; show nothing.
        case cancelled
    }

    struct Plan {
        /// Set up AI as well as the companion.
        var full: Bool
        /// Key and vendor to store after consent, or nil to leave them alone.
        var keyCommit: CompanionWizardAIKeyPlan.Write?
        /// Restores the key and vendor if `keyCommit` was written and setup
        /// does not finish.
        var keyRollback: CompanionWizardAIKeyPlan.Write?
        var priorEnableAI: Bool
        var priorEnableCompanion: Bool
    }

    /// Run Install. `isCancelled` is polled before every step with a side
    /// effect; once it returns true no further step runs, what was written is
    /// undone, and the outcome is `.cancelled` (even if a step then failed).
    static func run(plan: Plan,
                    steps: CompanionWizardSetupSteps,
                    isCancelled: () -> Bool,
                    progress: (Stage) -> Void,
                    verify: () -> CompanionWizardVerification) async -> Outcome {
        var grantedConsent = false
        var wroteAIKey = false
        func rollBack() {
            // Restore everything this attempt changed so an unfinished setup
            // does not leave consent on, a switched vendor, or a replaced key.
            if grantedConsent {
                if plan.full, !plan.priorEnableAI {
                    steps.revokeAIConsent()
                }
                if !plan.priorEnableCompanion {
                    steps.revokeCompanionConsent()
                }
            }
            if wroteAIKey, let keyRollback = plan.keyRollback {
                DLog("Companion wizard: rolling back API key for vendor \(keyRollback.vendor.rawValue)")
                steps.writeAIKey(keyRollback)
            }
        }
        func cancelled() -> Outcome {
            DLog("Companion wizard: setup cancelled (consent granted: \(grantedConsent), key written: \(wroteAIKey))")
            rollBack()
            return .cancelled
        }
        do {
            if plan.full {
                if isCancelled() { return cancelled() }
                progress(.downloadingAIPlugin)
                try await steps.installAIPlugin()
            }
            if isCancelled() { return cancelled() }
            progress(.downloadingCompanionPlugin)
            try await steps.installCompanionPlugin()
            // The next step raises an admin password prompt and writes defaults.
            if isCancelled() { return cancelled() }
            progress(.grantingConsent)
            try steps.grantConsent(plan.full, true)
            grantedConsent = true
            if isCancelled() { return cancelled() }
            if let keyCommit = plan.keyCommit {
                // Persist the key/vendor only now that the plugins installed and
                // consent was granted, so an earlier failure leaves the saved
                // defaults untouched.
                DLog("Companion wizard: storing API key for vendor \(keyCommit.vendor.rawValue)")
                steps.writeAIKey(keyCommit)
                wroteAIKey = true
            }
            progress(.verifying)
            switch verify() {
            case .ready:
                break
            case .pluginsNotLoaded:
                throw CompanionPluginInstallerError.verificationFailed(
                    plan.full
                    ? String(localized: "Companion.VerifyFailed.Both",
                             defaultValue: "AI and companion plugins",
                             comment: "Names the components that failed to verify, inserted into a verification-failed error")
                    : String(localized: "Companion.VerifyFailed.Companion",
                             defaultValue: "companion plugin",
                             comment: "Names the component that failed to verify, inserted into a verification-failed error"))
            case .aiModelCannotAuthenticate:
                throw CompanionWizardSetupError.aiModelCannotAuthenticate
            }
            if isCancelled() { return cancelled() }
            return .completed
        } catch {
            // A step interrupted by the cancellation (e.g. a download that threw
            // because its Task was cancelled) is not a failure to report.
            if isCancelled() { return cancelled() }
            DLog("Companion wizard: setup failed: \(error)")
            rollBack()
            return .failed(error)
        }
    }
}
