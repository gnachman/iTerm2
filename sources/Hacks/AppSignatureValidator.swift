//
//  AppSignatureValidator.swift
//  iTerm2
//
//  Created by George Nachman on 9/22/25.
//

import Foundation
import Security

@objc(iTermAppSignatureValidator)
class AppSignatureValidator: NSObject {
    /// Returns the Team Identifier of the current app if the code signature is valid.
    /// - Returns: The team ID string, or `nil` if the signature is invalid or missing.
    @objc
    static func currentAppTeamID() -> String? {
        let selfURL = Bundle.main.bundleURL as CFURL
        var staticCode: SecStaticCode?

        let status = SecStaticCodeCreateWithPath(selfURL, [], &staticCode)
        if status != errSecSuccess {
            return nil
        }

        guard let code = staticCode else {
            return nil
        }

        let flags: SecCSFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        let verifyStatus = SecStaticCodeCheckValidity(code, flags, nil)
        if verifyStatus != errSecSuccess {
            return nil
        }

        var info: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation|kSecCSRequirementInformation|kSecCSDynamicInformation), &info)
        if infoStatus != errSecSuccess {
            return nil
        }
        guard let dict = info as? [String: Any],
        let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String else {
            return nil
        }

        return teamID
    }

    @objc
    static func warn(reason: String) {
        let message = corruptionMessage(teamID: currentAppTeamID())
        let alert = NSAlert()
        alert.messageText = String(localized: "AppSignature.CorruptTitle", defaultValue: "Application Corrupt", comment: "Title of alert shown when the app's code signature is invalid")
        alert.informativeText = reason + ": " + message
        alert.addButton(withTitle: iTermLocalizedOK())
        alert.alertStyle = .critical
        alert.runModal()
    }

    // For a resource the app can't run without: tell the user the app is damaged and exit. This
    // exits rather than crashing because a damaged installation (e.g., a bundle moved or deleted
    // while the app launched) is not a bug, and crash reports for it are noise.
    //
    // Safe to call from any thread. The alert has to run on the main thread, so another thread
    // hands it off and parks, never continuing without the resource. (If the main thread is
    // waiting on that thread, the app hangs instead of showing the alert.)
    @objc
    static func warnAndExit(reason: String) -> Never {
        RLog("Exiting because the app is damaged: \(reason)")
        if Thread.isMainThread {
            warn(reason: reason)
            exit(1)
        }
        DispatchQueue.main.async {
            warn(reason: reason)
            exit(1)
        }
        let semaphore = DispatchSemaphore(value: 0)
        while true {
            semaphore.wait()
        }
    }

    // What to tell the user about a missing or damaged resource, given the app's verified team
    // ID (nil if the signature could not be verified).
    static func corruptionMessage(teamID team: String?) -> String {
        return if team == nil {
            String(localized: "AppSignature.CorruptUnverified", defaultValue: "A required file appears to be missing or corrupted and iTerm2’s code signature could not be verified.\n\nYou should download a fresh copy of the app and reinstall it.", comment: "Shown when the app's code signature could not be verified")
        } else if team != "H7V7XYVQ7D" {
            String(localized: "AppSignature.CorruptWrongTeam", defaultValue: "A required file appears to be missing or corrupted and iTerm2’s code signature did not match that of the official distribution.\n\nYou should download a fresh copy of the app and reinstall it.", comment: "Shown when the app's code signature does not match the official distribution")
        } else {
            String(localized: "AppSignature.CorruptButValidSignature", defaultValue: "A required file appears to be missing or corrupted, yet against all odds the code signature for iTerm2 is valid. Please file a bug at https://iterm2.com/bugs", comment: "Shown when a required file is corrupt but the signature is valid")
        }
    }
}

