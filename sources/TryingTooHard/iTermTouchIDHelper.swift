//
//  iTermTouchIDHelper.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/25/26.
//

import Foundation
import LocalAuthentication

@objc(iTermTouchIDHelper)
class iTermTouchIDHelper: NSObject {
    private static let sudoLocalPath = "/etc/pam.d/sudo_local"
    private static let scriptResourceName = "install-touchid-sudo"

    /// Returns true if biometric authentication (Touch ID) is available on this device.
    @objc static var isBiometricAuthenticationAvailable: Bool {
        let context = LAContext()
        var error: NSError? = nil
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if !canEvaluate {
            RLog("Biometric authentication not available: \(error?.localizedDescription ?? "unknown")")
        }
        return canEvaluate
    }

    /// Returns true if Touch ID for sudo is already enabled in sudo_local.
    @objc static var isTouchIDEnabledForSudo: Bool {
        guard let contents = try? String(contentsOfFile: sudoLocalPath, encoding: .utf8) else {
            return false
        }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                continue
            }
            if trimmed.contains("pam_tid.so") {
                return true
            }
        }
        return false
    }

    /// Path to the bundled install-touchid-sudo.sh script, or nil if missing.
    private static var scriptPath: String? {
        return Bundle.main.path(forResource: scriptResourceName, ofType: "sh")
    }

    /// The shell command a user can paste into a terminal to install Touch ID for
    /// sudo. Returns nil if the bundled script is missing.
    @objc static var installCommand: String? {
        guard let path = scriptPath else {
            RLog("install-touchid-sudo.sh not found in app bundle")
            return nil
        }
        let escaped = path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "sudo \"\(escaped)\""
    }

    /// Runs the install command in a new iTerm2 window. The user will be prompted
    /// for their sudo password in that window.
    @objc static func runInstallInNewWindow() {
        guard let path = scriptPath else {
            iTermWarning.show(withTitle: "The Touch ID install script is missing from the iTerm2 application bundle.",
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Cannot Enable Touch ID for Sudo",
                              window: nil)
            return
        }
        // Run the script without sudo. The script prints a banner explaining
        // what is about to happen, then re-execs itself under sudo so the user
        // sees context before the password prompt.
        iTermController.sharedInstance().openSingleUseWindow(withCommand: path,
                                                             arguments: [],
                                                             inject: nil,
                                                             environment: nil,
                                                             pwd: nil,
                                                             options: [],
                                                             didMakeSession: nil,
                                                             completion: nil)
    }
}
