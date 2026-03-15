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
    private static let pamTidLine = "auth       sufficient     pam_tid.so"

    /// Returns true if biometric authentication (Touch ID) is available on this device.
    @objc static var isBiometricAuthenticationAvailable: Bool {
        let context = LAContext()
        var error: NSError? = nil
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if !canEvaluate {
            DLog("Biometric authentication not available: \(error?.localizedDescription ?? "unknown")")
        }
        return canEvaluate
    }

    /// Returns true if Touch ID for sudo is already enabled in sudo_local.
    @objc static var isTouchIDEnabledForSudo: Bool {
        guard let contents = try? String(contentsOfFile: sudoLocalPath, encoding: .utf8) else {
            return false
        }
        // Check for uncommented pam_tid.so line
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

    /// Enables Touch ID for sudo by appending to /etc/pam.d/sudo_local using AppleScript
    /// to gain administrator privileges.
    /// Returns true on success, false on failure.
    @objc static func enableTouchIDForSudo() -> Bool {
        // Check if already enabled
        if isTouchIDEnabledForSudo {
            DLog("Touch ID for sudo is already enabled")
            return true
        }

        // Create file from template if needed, make it writable, enable Touch ID, restore permissions.
        // We use sed to uncomment the existing line (from template), and fall back to appending if
        // the line doesn't exist. chmod is needed because sudo_local is read-only by default.
        let templatePath = "/etc/pam.d/sudo_local.template"
        let shellCommand = "test -f \(sudoLocalPath) || cp \(templatePath) \(sudoLocalPath); chmod u+w \(sudoLocalPath); sed -i '' 's/^#auth.*pam_tid.so/\(pamTidLine)/' \(sudoLocalPath); grep -q '^auth.*pam_tid.so' \(sudoLocalPath) || echo '\(pamTidLine)' >> \(sudoLocalPath); chmod u-w \(sudoLocalPath)"

        let code = """
        do shell script "\(shellCommand)" with prompt "iTerm2 wants to enable Touch ID for sudo authentication." with administrator privileges
        """

        DLog("Executing AppleScript to enable Touch ID for sudo")
        let script = NSAppleScript(source: code)
        var error: NSDictionary? = nil
        script?.executeAndReturnError(&error)

        if let error = error {
            DLog("AppleScript error: \(error)")
            // Error -128 is user cancellation - don't show an alert for that.
            if let errorNumber = error[NSAppleScript.errorNumber] as? Int, errorNumber == -128 {
                return false
            }
            let errorMessage = (error[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            iTermWarning.show(withTitle: errorMessage,
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Failed to Enable Touch ID for Sudo",
                              window: nil)
            return false
        }

        DLog("Touch ID for sudo enabled successfully")
        return true
    }
}
