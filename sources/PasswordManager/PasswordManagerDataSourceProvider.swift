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
    private var _keeper: AdapterPasswordDataSource
    #if ITERM_DEBUG
    private var _testAdapter: AdapterPasswordDataSource
    #endif
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
        case keeper = "Keeper"
        #if ITERM_DEBUG
        case testAdapter = "TestAdapter"
        #endif

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

        let keeperPath = Bundle(for: Self.self).path(forAuxiliaryExecutable: "iterm2-keeper-adapter")!
        _keeper = AdapterPasswordDataSource(browser: browser,
                                            adapterPath: keeperPath,
                                            identifier: "Keeper Security")
        #if ITERM_DEBUG
        let testAdapterPath = Bundle(for: Self.self).path(forAuxiliaryExecutable: "iterm2-test-adapter")!
        _testAdapter = AdapterPasswordDataSource(browser: browser,
                                                 adapterPath: testAdapterPath,
                                                 identifier: "Test Adapter")
        #endif

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
                case .keeper:
                    return keeper!
                #if ITERM_DEBUG
                case .testAdapter:
                    return testAdapter!
                #endif
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

    @objc func enableKeeper() {
        preferredDataSource = .keeper
    }

    @objc var keeperEnabled: Bool {
        return preferredDataSource == .keeper
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

    private var keeper: AdapterPasswordDataSource? {
        if !authenticated {
            return nil
        }
        return _keeper
    }
    #if ITERM_DEBUG
    private var testAdapter: AdapterPasswordDataSource? {
        if !authenticated {
            return nil
        }
        return _testAdapter
    }

    @objc func enableTestAdapter() {
        preferredDataSource = .testAdapter
    }

    @objc var testAdapterEnabled: Bool {
        return preferredDataSource == .testAdapter
    }
    #endif
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
            RLog("Can't evaluate \(policy): \(error?.localizedDescription ?? "(nil)")")
            // Authentication is impossible here (no biometrics/passcode, MDM-restricted).
            // Report failure so callers don't hang or silently drop the requested action
            // waiting on a completion that would otherwise never fire.
            completion(false)
            return
        }
        iTermApplication.shared().localAuthenticationDialogOpen = true
        let reason = "open the password manager"
        context.evaluatePolicy(policy, localizedReason: reason) { success, error in
            RLog("Policy evaluation success=\(success) error=\(String(describing: error))")
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
            reason = String(localized: "PasswordManagerAuth.AuthenticationFailed", defaultValue: "valid credentials weren't supplied.", comment: "Authentication failure reason: wrong credentials");

        case .userCancel:
            reason = String(localized: "PasswordManagerAuth.UserCancel", defaultValue: "password entry was cancelled.", comment: "Authentication failure reason: user cancelled");

        case .userFallback:
            reason = String(localized: "PasswordManagerAuth.UserFallback", defaultValue: "password authentication was requested.", comment: "Authentication failure reason: user chose password fallback");

        case .systemCancel:
            reason = String(localized: "PasswordManagerAuth.SystemCancel", defaultValue: "the system cancelled the authentication request.", comment: "Authentication failure reason: system cancelled");

        case .passcodeNotSet:
            reason = String(localized: "PasswordManagerAuth.PasscodeNotSet", defaultValue: "no passcode is set.", comment: "Authentication failure reason: no passcode set");

        case .touchIDNotAvailable:
            reason = String(localized: "PasswordManagerAuth.TouchIDNotAvailable", defaultValue: "touch ID is not available.", comment: "Authentication failure reason: Touch ID not available");

        case .biometryNotEnrolled:
            reason = String(localized: "PasswordManagerAuth.BiometryNotEnrolled", defaultValue: "touch ID doesn't have any fingers enrolled.", comment: "Authentication failure reason: no fingerprints enrolled");

        case .biometryLockout:
            reason = String(localized: "PasswordManagerAuth.BiometryLockout", defaultValue: "there were too many failed Touch ID attempts.", comment: "Authentication failure reason: too many failed Touch ID attempts");

        case .appCancel:
            reason = String(localized: "PasswordManagerAuth.AppCancel", defaultValue: "authentication was cancelled by iTerm2.", comment: "Authentication failure reason: cancelled by the app");

        case .invalidContext:
            reason = String(localized: "PasswordManagerAuth.InvalidContext", defaultValue: "the context is invalid. This is a bug in iTerm2. Please report it.", comment: "Authentication failure reason: invalid context");

        case .none:
            reason = error.localizedDescription

        case .touchIDNotEnrolled:
            reason = String(localized: "PasswordManagerAuth.TouchIDNotEnrolled", defaultValue: "touch ID is not enrolled.", comment: "Authentication failure reason: Touch ID not enrolled")

        case .touchIDLockout:
            reason = String(localized: "PasswordManagerAuth.TouchIDLockout", defaultValue: "touch ID is locked out.", comment: "Authentication failure reason: Touch ID locked out")

        case .notInteractive:
            reason = String(localized: "PasswordManagerAuth.NotInteractive", defaultValue: "the required user interface could not be displayed.", comment: "Authentication failure reason: UI could not be displayed")

        case .watchNotAvailable:
            reason = String(localized: "PasswordManagerAuth.WatchNotAvailable", defaultValue: "watch is not available.", comment: "Authentication failure reason: Apple Watch not available")

        case .biometryNotPaired:
            reason = String(localized: "PasswordManagerAuth.BiometryNotPaired", defaultValue: "biometry is not paired.", comment: "Authentication failure reason: biometry not paired")

        case .biometryDisconnected:
            reason = String(localized: "PasswordManagerAuth.BiometryDisconnected", defaultValue: "biometry is disconnected.", comment: "Authentication failure reason: biometry disconnected")

        case .invalidDimensions:
            reason = String(localized: "PasswordManagerAuth.InvalidDimensions", defaultValue: "invalid dimensions given.", comment: "Authentication failure reason: invalid dimensions")

        @unknown default:
            reason = error.localizedDescription
        }
        alert.messageText = String(localized: "PasswordManagerAuth.FailedTitle", defaultValue: "Authentication Failed", comment: "Title of the alert shown when unlocking the password manager fails")
        alert.informativeText = String(localized: "PasswordManagerAuth.FailedFormat", defaultValue: "Authentication failed because \(reason)", comment: "Body of the authentication-failed alert; the placeholder is the reason for the failure")
        alert.addButton(withTitle: iTermLocalizedOK())
        alert.runModal()
    }
}

