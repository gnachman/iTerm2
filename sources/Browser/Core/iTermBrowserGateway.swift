//
//  iTermBrowserGateway.swift
//  iTerm2
//
//  Created by George Nachman on 9/5/25.
//

import Security

struct ExpiringValue<T> {
    private let duration: TimeInterval
    private var _value: T?
    private var _expiration: TimeInterval

    var value: T? {
        get {
            if NSDate.it_timeSinceBoot() > _expiration {
                return nil
            }
            return _value
        }
        set {
            _value = newValue
            _expiration = NSDate.it_timeSinceBoot() + duration
        }
    }

    mutating func expire() {
        _value = nil
        _expiration = 0
    }

    init(value: T?, duration: TimeInterval) {
        self.duration = duration
        _expiration = 0
        self.value = value
    }
}

@objc
class iTermBrowserGateway: NSObject {
    private static var cached = ExpiringValue<Bool>(value: nil, duration: 30)
    private static let bundleID = "com.googlecode.iterm2.iTermBrowserPlugin"
    private static let teamID = "H7V7XYVQ7D"
    @objc static let didChange = Notification.Name(rawValue: "iTermBrowserGatewayDidChange")

    @objc
    static func reload() {
        cached.expire()
    }

    @objc(didLocateBundleManually:)
    static func didLocateBundleManually(_ url: URL) -> String? {
        guard let bundle = Bundle(url: url) else {
            return "The file at \(url.path) is not a valid app bundle."
        }
        if bundle.bundleIdentifier != Self.bundleID {
            return "This is not the browser plugin. This file’s bundle ID is “\(bundle.bundleIdentifier ?? "not set")”.\n The expected ID is “\(Self.bundleID)”."
        }
        if !verifyCodeSignature(at: url, teamID: teamID) {
            return "The code signature of the plugin at \(url.path) is invalid. Download it again, and ensure your anti-virus does not quarantine it."
        }
        iTermAdvancedSettingsModel.setBrowserPluginPathHint(url.path)
        cached.expire()
        return nil
    }

    @objc(browserAllowedCheckingIfNot:)
    static func browserAllowed(checkIfNo: Bool) -> Bool {
        if let cached = cached.value {
            if !checkIfNo || cached {
                return cached
            }
        }
        if !iTermAdvancedSettingsModel.browserProfiles() {
            return false
        }
        let value = checkPluginInstalled()
        cached.value = value
        NotificationCenter.default.post(name: didChange, object: nil)
        return value
    }

    @objc
    static func revealInFinder() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
        }
    }

    @objc
    static func shouldOfferPlugin() -> Bool {
        return iTermAdvancedSettingsModel.browserProfiles() && !checkPluginInstalled()
    }

    @objc
    static func offerPlugin() {
        let selection = iTermWarning.show(withTitle: "You must install the Browser Plugin first. Download it now?",
                                          actions: ["OK", "Cancel"],
                                          accessory: nil,
                                          identifier: nil,
                                          silenceable: .kiTermWarningTypePersistent,
                                          heading: "Plugin Required",
                                          window: nil)
        if selection == .kiTermWarningSelection0 {
            NSWorkspace.shared.open(URL(string: "https://iterm2.com/browser-plugin.html")!)
        }
    }

    private static let upsellWarningIdentifier = "NoSyncBrowserUpsell"
    @objc
    static func wouldUpsell() -> Bool {
        if let n = iTermWarning.conditionalSavedSelection(forIdentifier: upsellWarningIdentifier) {
            return n.intValue == iTermWarningSelection.kiTermWarningSelection0.rawValue
        }
        return true
    }

    // Return values:
    //   .true -> User will download plugin
    //   .false -> Use system browser
    //   .other -> Abort open
    @objc
    static func upsell() -> iTermTriState {
        // Only "Use System Browser" should be remembered. Remembering "Download"
        // would cause an infinite loop since the plugin would still not be installed.
        // Remembering "Cancel" is also not useful.
        let warning = iTermWarning()
        warning.title = "iTerm2 can display web pages! But first you must download the Browser Plugin."
        warning.actionLabels = ["Download", "Use System Browser", "Cancel"]
        warning.identifier = upsellWarningIdentifier
        warning.warningType = .kiTermWarningTypePermanentlySilenceable
        warning.heading = "Plugin Required"
        warning.doNotRememberLabels = ["Download", "Cancel"]
        let selection = warning.runModal()
        switch selection {
        case .kiTermWarningSelection0:
            cached.expire()
            openDownloadPage()
            return .true
        case .kiTermWarningSelection1:
            return .false
        case .kiTermWarningSelection2:
            return .other
        default:
            it_fatalError()
        }
    }

    @objc
    static func openDownloadPage() {
        NSWorkspace.shared.open(URL(string: "https://iterm2.com/browser-plugin.html")!)
        cached.expire()
    }

    private static func checkPluginInstalled() -> Bool {
        if verifyApp(bundleID: bundleID, teamID: teamID) {
            return true
        }
        guard let hint = iTermAdvancedSettingsModel.browserPluginPathHint() else {
            DLog("No hint")
            return false
        }
        if hint.isEmpty {
            DLog("Empty hint")
            return false
        }
        DLog("Check hint \(hint)")
        return verifyCodeSignature(at: URL(fileURLWithPath: hint), teamID: teamID)
    }

    private static func verifyApp(bundleID: String, teamID: String) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            DLog("Error: No app found with bundle ID '\(bundleID)'")
            return false
        }

        DLog("Found app at: \(appURL.path)")
        return verifyCodeSignature(at: appURL, teamID: teamID)
    }

    private static func verifyCodeSignature(at url: URL, teamID: String) -> Bool {
        DLog("Verify that \(url) has signature with team \(teamID)")
        var staticCode: SecStaticCode?

        // Create a static code object from the app URL
        let result = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard result == errSecSuccess, let code = staticCode else {
            DLog("Error: Failed to create static code object (OSStatus: \(result))")
            return false
        }

        // Create requirement string for team ID verification
        let requirementString = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""

        var requirement: SecRequirement?
        let reqResult = SecRequirementCreateWithString(requirementString as CFString, [], &requirement)
        guard reqResult == errSecSuccess, let req = requirement else {
            DLog("Error: Failed to create requirement (OSStatus: \(reqResult))")
            return false
        }

        // Verify the code signature with the requirement
        let verifyResult = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: 0), req)

        if verifyResult == errSecSuccess {
            DLog("OK")
            return true
        } else {
            let reason = SecCopyErrorMessageString(verifyResult, nil) as String?
            DLog("Invalid: Error code \(verifyResult): \(reason.d)")
            return false
        }
    }
}
