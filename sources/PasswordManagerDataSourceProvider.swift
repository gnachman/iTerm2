//
//  PasswordManagerDataSourceProvider.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import Foundation
import LocalAuthentication

@objc(iTermPasswordManagerDataSourceProvider)
class PasswordManagerDataSourceProvider: NSObject {
    @objc private(set) static var authenticated = false
    private static var _dataSource: PasswordManagerDataSource? = nil
    private static var dataSourceType: DataSource = preferredDataSource
    private static let _keychain = KeychainPasswordDataSource()
    private static var _onePassword = OnePasswordDataSource()
    private static var _lastPass = LastPassDataSource()
    private static let dataSourceNameUserDefaultsKey = "NoSyncPasswordManagerDataSourceName"

    enum DataSource: String {
        case keychain = "Keychain"
        case onePassword = "OnePassword"
        case lastPass = "LastPass"

        static let defaultValue = DataSource.keychain
    }

    static var preferredDataSource: DataSource {
        get {
            let rawValue = UserDefaults.standard.string(forKey: dataSourceNameUserDefaultsKey) ?? ""
            return DataSource(rawValue: rawValue) ?? DataSource.defaultValue
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: dataSourceNameUserDefaultsKey)
            _dataSource = nil
        }
    }

    @objc static var dataSource: PasswordManagerDataSource? {
        guard authenticated else {
            return nil
        }
        guard let existing = _dataSource else {
            let fresh = { () -> PasswordManagerDataSource in
                switch preferredDataSource {
                case .keychain:
                    return keychain!
                case .onePassword:
                    return onePassword!
                case .lastPass:
                    return lastPass!
                }
            }()
            _dataSource = fresh
            return fresh
        }
        return existing
    }

    @objc static func enableKeychain() {
        preferredDataSource = .keychain
    }

    @objc static var keychainEnabled: Bool {
        return preferredDataSource == .keychain
    }

    @objc static func enable1Password() {
        preferredDataSource = .onePassword
    }

    @objc static var onePasswordEnabled: Bool {
        return preferredDataSource == .onePassword
    }

    @objc static func enableLastPass() {
        preferredDataSource = .lastPass
    }

    @objc static var lastPassEnabled: Bool {
        return preferredDataSource == .lastPass
    }

    @objc static var keychain: PasswordManagerDataSource? {
        if !authenticated {
            return nil
        }
        return _keychain
    }

    private static var onePassword: OnePasswordDataSource? {
        if !authenticated {
            return nil
        }
        return _onePassword
    }

    private static var lastPass: LastPassDataSource? {
        if !authenticated {
            return nil
        }
        return _lastPass
    }

    @objc static func revokeAuthentication() {
        authenticated = false
    }

    @objc static func requestAuthenticationIfNeeded(_ completion: @escaping (Bool) -> ()) {
        if authenticated {
            completion(true)
            return
        }
        if !SecureUserDefaults.instance.requireAuthToOpenPasswordmanager.value {
            authenticated = true
            completion(true)
            return
        }
        let context = LAContext()
        let policy = LAPolicy.deviceOwnerAuthentication
        var error: NSError? = nil
        if !context.canEvaluatePolicy(policy, error: &error) {
            DLog("Can't evaluate \(policy): \(error?.localizedDescription ?? "(nil)")")
            return
        }
        iTermApplication.shared().localAuthenticationDialogOpen = true
        let reason = "open the password manager"
        context.evaluatePolicy(policy, localizedReason: reason) { success, error in
            DLog("Policy evaluation success=\(success) error=\(String(describing: error))")
            DispatchQueue.main.async {
                iTermApplication.shared().localAuthenticationDialogOpen = false
                if success {
                    Self.authenticated = true
                    completion(true)
                } else {
                    Self.authenticated = false
                    if let error = error as NSError?, (error.code != LAError.systemCancel.rawValue &&
                                                       error.code != LAError.appCancel.rawValue) {
                        showError(error)
                    }
                    completion(false)
                }
            }
        }
    }

    @objc static func consolidateAvailabilityChecks(_ block: () -> ()) {
        if let dataSource = dataSource {
            dataSource.consolidateAvailabilityChecks(block)
            return
        }
        block()
    }

    private static func showError(_ error: NSError) {
        let alert = NSAlert()
        let reason: String
        switch LAError.Code(rawValue: error.code) {
        case .authenticationFailed:
            reason = "valid credentials weren't supplied.";

        case .userCancel:
            reason = "password entry was cancelled.";

        case .userFallback:
            reason = "password authentication was requested.";

        case .systemCancel:
            reason = "the system cancelled the authentication request.";

        case .passcodeNotSet:
            reason = "no passcode is set.";

        case .touchIDNotAvailable:
            reason = "touch ID is not available.";

        case .biometryNotEnrolled:
            reason = "touch ID doesn't have any fingers enrolled.";

        case .biometryLockout:
            reason = "there were too many failed Touch ID attempts.";

        case .appCancel:
            reason = "authentication was cancelled by iTerm2.";

        case .invalidContext:
            reason = "the context is invalid. This is a bug in iTerm2. Please report it.";

        case .none:
            reason = error.localizedDescription

        case .touchIDNotEnrolled:
            reason = "touch ID is not enrolled."

        case .touchIDLockout:
            reason = "touch ID is locked out."

        case .notInteractive:
            reason = "the required user interface could not be displayed."

        case .watchNotAvailable:
            reason = "watch is not available."

        case .biometryNotPaired:
            reason = "biometry is not paired."

        case .biometryDisconnected:
            reason = "biometry is disconnected."

        case .invalidDimensions:
            reason = "invalid dimensions given."

        @unknown default:
            reason = error.localizedDescription
        }
        alert.messageText = "Authentication Failed"
        alert.informativeText = "Authentication failed because \(reason)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

