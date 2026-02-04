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
    @objc static let forTerminal = PasswordManagerDataSourceProvider(browser: false)
    @objc static let forBrowser = PasswordManagerDataSourceProvider(browser: true)
    @objc private(set) var authenticated = false
    private var _dataSource: PasswordManagerDataSource? = nil
    private var dataSourceType: DataSource!
    private let _keychain: KeychainPasswordDataSource
    private var _onePassword: OnePasswordDataSource
    private var _lastPass: LastPassDataSource
    private var _keePassXC: AdapterPasswordDataSource
    private var _bitwarden: AdapterPasswordDataSource
    private let browser: Bool
    private var dataSourceNameUserDefaultsKey: String {
        "NoSyncPasswordManagerDataSourceName" + (browser ? "Browser" : "")
    }

    enum DataSource: String {
        case keychain = "Keychain"
        case onePassword = "OnePassword"
        case lastPass = "LastPass"
        case keePassXC = "KeePassXC"
        case bitwarden = "Bitwarden"

        static let defaultValue = DataSource.keychain
    }

    init(browser: Bool) {
        _keychain = KeychainPasswordDataSource(browser: browser)
        _onePassword = OnePasswordDataSource(browser: browser)
        _lastPass = LastPassDataSource(browser: browser)

        let keepassPath = Bundle(for: Self.self).path(forAuxiliaryExecutable: "iterm2-keepassxc-adapter")!
        _keePassXC = AdapterPasswordDataSource(browser: browser,
                                               adapterPath: keepassPath,
                                               identifier: "KeePassXC")

        let bitwardenPath = Bundle(for: Self.self).path(forAuxiliaryExecutable: "iterm2-bitwarden-adapter")!
        _bitwarden = AdapterPasswordDataSource(browser: browser,
                                               adapterPath: bitwardenPath,
                                               identifier: "Bitwarden")

        self.browser = browser

        super.init()

        dataSourceType = preferredDataSource
    }

    var preferredDataSource: DataSource {
        get {
            let rawValue = iTermUserDefaults.userDefaults().string(forKey: dataSourceNameUserDefaultsKey) ?? ""
            return DataSource(rawValue: rawValue) ?? DataSource.defaultValue
        }
        set {
            iTermUserDefaults.userDefaults().set(newValue.rawValue, forKey: dataSourceNameUserDefaultsKey)
            _dataSource = nil
        }
    }

    @objc var dataSource: PasswordManagerDataSource? {
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
                case .keePassXC:
                    return keePassXC!
                case .bitwarden:
                    return bitwarden!
                }
            }()
            _dataSource = fresh
            return fresh
        }
        return existing
    }

    @objc func enableKeePassXC() {
        preferredDataSource = .keePassXC
    }

    @objc var keePassXCEnabled: Bool {
        return preferredDataSource == .keePassXC
    }

    @objc func enableBitwarden() {
        preferredDataSource = .bitwarden
    }

    @objc var bitwardenEnabled: Bool {
        return preferredDataSource == .bitwarden
    }

    @objc func enableKeychain() {
        preferredDataSource = .keychain
    }

    @objc var keychainEnabled: Bool {
        return preferredDataSource == .keychain
    }

    @objc func enable1Password() {
        preferredDataSource = .onePassword
    }

    @objc var onePasswordEnabled: Bool {
        return preferredDataSource == .onePassword
    }

    @objc func enableLastPass() {
        preferredDataSource = .lastPass
    }

    @objc var lastPassEnabled: Bool {
        return preferredDataSource == .lastPass
    }

    @objc var keychain: PasswordManagerDataSource? {
        if !authenticated {
            return nil
        }
        return _keychain
    }

    private var onePassword: OnePasswordDataSource? {
        if !authenticated {
            return nil
        }
        return _onePassword
    }

    private var lastPass: LastPassDataSource? {
        if !authenticated {
            return nil
        }
        return _lastPass
    }

    private var keePassXC: AdapterPasswordDataSource? {
        if !authenticated {
            return nil
        }
        return _keePassXC
    }

    private var bitwarden: AdapterPasswordDataSource? {
        if !authenticated {
            return nil
        }
        return _bitwarden
    }

    @objc func revokeAuthentication() {
        authenticated = false
    }

    @objc func requestAuthenticationIfNeeded(_ completion: @escaping (Bool) -> ()) {
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
                    self.authenticated = true
                    completion(true)
                } else {
                    self.authenticated = false
                    if let error = error as NSError?, (error.code != LAError.systemCancel.rawValue &&
                                                       error.code != LAError.appCancel.rawValue) {
                        self.showError(error)
                    }
                    completion(false)
                }
            }
        }
    }

    @objc func consolidateAvailabilityChecks(_ block: () -> ()) {
        if let dataSource = dataSource {
            dataSource.consolidateAvailabilityChecks(block)
            return
        }
        block()
    }

    private func showError(_ error: NSError) {
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

