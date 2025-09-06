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

    // Return values:
    //   .true -> User will download plugin
    //   .false -> Use system browser
    //   .other -> Abort open
    @objc
    static func upsell() -> iTermTriState {
        let selection = iTermWarning.show(withTitle: "iTerm2 can display web pages! But first you must download the Browser Plugin.",
                                          actions: ["Download", "Use System Browser", "Cancel"],
                                          accessory: nil,
                                          identifier: "NoSyncBrowserUpsell",
                                          silenceable: .kiTermWarningTypePermanentlySilenceable,
                                          heading: "Plugin Required",
                                          window: nil)
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
        return verifyApp(bundleID: bundleID, teamID: teamID)
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
