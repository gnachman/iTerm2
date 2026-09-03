//
//  iTermMacOS13RequirementNotice.swift
//  iTerm2SharedARC
//
//  Phase 0 of the uv Python-runtime migration. While the deployment target is
//  still macOS 12, warn users running macOS 12 exactly once that a future beta
//  will require macOS 13, so the eventual target bump does not strand them
//  without notice. See docs/uv-python-runtime-migration.md.
//

import Foundation

@objc(iTermMacOS13RequirementNotice)
class iTermMacOS13RequirementNotice: NSObject {
    // Pure decision, split out so it can be unit-tested without the modal or the
    // real OS version: show only to pre-13 users who have not seen it before.
    static func shouldShow(majorVersion: Int, alreadyShown: Bool) -> Bool {
        return majorVersion < 13 && !alreadyShown
    }

    // Thin caller: consult the seam against the running OS and the persisted flag,
    // present the notice once, and record that it was shown.
    @objc static func maybeShow() {
        let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        guard shouldShow(majorVersion: majorVersion,
                         alreadyShown: iTermUserDefaults.haveShownMacOS13RequirementNotice) else {
            return
        }
        iTermWarning.show(
            withTitle: String(localized: "MacOs13RequirementNotice_FutureVersionsOfITerm2WillRequire", defaultValue: "Future versions of iTerm2 will require macOS 13 (Ventura) or later. This is the last version that supports macOS 12. Sorry for the inconvenience!", comment: "Alert title in maybeShow"),
            actions: [String(localized: "COMMON_OK", defaultValue: "OK", comment: "Action title in maybeShow")],
            accessory: nil,
            // No identifier: this is a persistent (non-silenceable) warning, so
            // iTermWarning writes no user-defaults key. Once-only is enforced by the
            // separate NoSyncHaveShownMacOS13RequirementNotice flag set below.
            identifier: nil,
            silenceable: .kiTermWarningTypePersistent,
            heading: String(localized: "MacOs13RequirementNotice_DeprecationNotice", defaultValue: "Deprecation Notice", comment: "Alert heading in maybeShow"),
            window: nil)
        iTermUserDefaults.haveShownMacOS13RequirementNotice = true
    }
}
