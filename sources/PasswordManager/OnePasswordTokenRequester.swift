//
//  OnePasswordTokenRequester.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/20/22.
//

import Foundation
import UniformTypeIdentifiers

class OnePasswordUtils {
    static let basicEnvironment = ["HOME": NSHomeDirectory()]
    private static var _customPathToCLI: String? = nil
    private(set) static var usable: Bool? = nil
    // Standard install locations, newest-preferred (see pathToCLI).
    static let normalPaths = ["/usr/local/bin/op", "/opt/homebrew/bin/op"]

    // Resolves each candidate CLI's version off the main thread and caches it, then calls
    // completion on the main thread. `pathToCLI` (which spawns `op -v` on a cache miss and can
    // show a modal alert, so it must stay on the main thread) then reads the warm cache instead
    // of blocking the run loop. Idempotent: a second call just re-reads the cache.
    static func resolveVersionsInBackground(_ completion: @escaping () -> ()) {
        DispatchQueue.global(qos: .userInitiated).async {
            for path in normalPaths where FileManager.default.fileExists(atPath: path) {
                _ = fullVersion(path)
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    static var pathToCLI: String {
        if let customPath = _customPathToCLI {
            return customPath
        }
        let normalPaths = Self.normalPaths
        let defaultPath = normalPaths[0]
        lazy var anyNormalPathExists = {
            return normalPaths.anySatisfies {
                FileManager.default.fileExists(atPath: $0)
            }
        }()
        if anyNormalPathExists {
            DLog("normal path exists")
            // Prefer the newest installed CLI. An old op earlier on the path (e.g. 2.5.x at
            // /usr/local/bin) silently ignores `op item edit` piped templates, which breaks
            // secure in-place editing; a newer one (e.g. 2.39 from Homebrew) works.
            let usablePaths = normalPaths.filter {
                FileManager.default.fileExists(atPath: $0) && checkUsability($0)
            }
            let goodPath = usablePaths.max {
                (fullVersion($0) ?? []).lexicographicallyPrecedes(fullVersion($1) ?? [])
            }
            if let goodPath {
                // A new-enough CLI exists: use it. This is the only branch that marks op
                // usable, so the decision is based purely on whether such a path was found
                // and stays consistent across repeated calls.
                DLog("normal path ok")
                usable = true
                return goodPath
            }
            // A normal op exists but none meets the minimum version. Mark it unusable (so
            // throwIfUnusable keeps throwing on every later call, not just the first) and warn
            // once, then fall through to offer locating a newer CLI elsewhere.
            RLog("usability fail")
            if usable != false {
                showUnavailableMessage(normalPaths.joined(separator: " or "))
            }
            usable = false
        }
        if showCannotFindCLIMessage() {
            _customPathToCLI = askUserToFindCLI()
            if let path = _customPathToCLI {
                usable = checkUsability(path)
                if usable == false {
                    showUnavailableMessage()
                }
            }
        }
        return _customPathToCLI ?? defaultPath
    }

    static func throwIfUnusable() throws {
        _ = pathToCLI
        if usable == false {
            throw OnePasswordDataSource.OPError.unusableCLI
        }
    }

    static func resetErrors() {
        if usable == false {
            usable = nil
            _customPathToCLI = nil
        }
        clearFullVersionCache()
    }
    static func checkUsability() -> Bool {
        return checkUsability(pathToCLI)
    }

    // op item edit only applies piped item templates reliably from this version on. Older
    // CLIs (e.g. 2.5.x) accept the input, report success, and silently change nothing, which
    // breaks secure in-place editing. Enforce it as the minimum.
    static let minimumSupportedVersion = [2, 23, 0]
    // Derived so the user-facing "requires version X" alert can never drift from the array
    // that actually gates usability.
    static var minimumSupportedVersionString: String {
        minimumSupportedVersion.prefix(2).map(String.init).joined(separator: ".")
    }

    private static func checkUsability(_ path: String) -> Bool {
        guard let version = fullVersion(path) else {
            return false
        }
        // Pad missing trailing components with 0 so a two-component "2.23" ([2,23]) is not
        // ranked below the minimum [2,23,0]: lexicographicallyPrecedes treats a proper prefix
        // as earlier, which would wrongly reject an op that exactly meets the minimum.
        var padded = version
        while padded.count < minimumSupportedVersion.count {
            padded.append(0)
        }
        return !padded.lexicographicallyPrecedes(minimumSupportedVersion)
    }

    static func showUnavailableMessage(_ path: String? = nil) {
        let alert = NSAlert()
        alert.messageText = "OnePassword Unavailable"
        if let path = path {
            alert.informativeText = "The 1Password CLI at \(path) is too old. The iTerm2 integration requires version \(minimumSupportedVersionString) or later."
        } else {
            alert.informativeText = "The 1Password CLI could not be found, or is older than the required version \(minimumSupportedVersionString). Check that a current op is installed."
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // Returns true to show an open panel to locate it.
    private static func showCannotFindCLIMessage() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Can’t Find 1Password CLI"
        alert.informativeText = "In order to use the 1Password integration, iTerm2 needs to know where to find the CLI app named “op”. It’s normally in /usr/local/bin. If you have installed it elsewhere, please select Locate to provide its location."
        alert.addButton(withTitle: "Locate")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func askUserToFindCLI() -> String? {
        class OnePasswordCLIFinderOpenPanelDelegate: NSObject, NSOpenSavePanelDelegate {
            func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
                if FileManager.default.itemIsDirectory(url.path) {
                    return true
                }
                return url.lastPathComponent == "op"
            }
        }
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [ UTType.unixExecutable ]
        let delegate = OnePasswordCLIFinderOpenPanelDelegate()
        return withExtendedLifetime(delegate) {
            panel.delegate = delegate
            if panel.runModal() == .OK,
                let url = panel.url,
                url.lastPathComponent == "op" {
                return url.path
            }
            return nil
        }
    }

    static func standardEnvironment(token: OnePasswordTokenRequester.Auth) -> [String: String] {
        var result = OnePasswordUtils.basicEnvironment
        switch token {
        case .biometric:
            break
        case .token(let token):
            result["OP_SESSION_my"] = token
        }
        if !iTermAdvancedSettingsModel.onePasswordAccount().isEmpty {
            result["OP_ACCOUNT"] = iTermAdvancedSettingsModel.onePasswordAccount()
        }
        return result
    }

    // Guards _fullVersionCache, which is read/written from both the main thread (pathToCLI) and
    // the background resolver (resolveVersionsInBackground).
    private static let _fullVersionCacheLock = NSLock()
    static var _fullVersionCache = [String: [Int]]()

    private static func cachedFullVersion(_ path: String) -> [Int]? {
        _fullVersionCacheLock.lock()
        defer { _fullVersionCacheLock.unlock() }
        return _fullVersionCache[path]
    }

    private static func cacheFullVersion(_ version: [Int], for path: String) {
        _fullVersionCacheLock.lock()
        _fullVersionCache[path] = version
        _fullVersionCacheLock.unlock()
    }

    static func clearFullVersionCache() {
        _fullVersionCacheLock.lock()
        _fullVersionCache = [:]
        _fullVersionCacheLock.unlock()
    }

    // Full version (e.g. [2, 39, 0]) for a specific CLI, used to pick the newest one and to
    // enforce the minimum. Runs the process directly with a blocking read rather than the
    // exec() helper: exec() posts its completion to the main queue, so calling it from the
    // main thread would deadlock. Prefer warming the cache via resolveVersionsInBackground so
    // the main-thread readers never spawn `op -v`; the process runs outside the cache lock.
    private static func fullVersion(_ path: String) -> [Int]? {
        if let cached = cachedFullVersion(path) {
            return cached
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-v"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        let components = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
            .compactMap { Int($0) }
        guard !components.isEmpty else {
            return nil
        }
        cacheFullVersion(components, for: path)
        return components
    }

}

class OnePasswordAccountPicker {
    static func askUserToSelect(from accounts: [Account]) {
        let pickerAccounts = accounts.map {
            AccountPicker.Account(title: $0.email, accountID: $0.account_uuid)
        }
        let identifier = AccountPicker.askUserToSelect(from: pickerAccounts)
        iTermAdvancedSettingsModel.setOnePasswordAccount(identifier)
    }

    struct Account: Codable {
        var url: String?
        var email: String?
        var user_uuid: String?
        var account_uuid: String?
    }
    static func asyncGetAccountList(_ completion: @escaping (Result<[Account], Error>) -> ()) {
        DLog("Read account list")
        let command = CommandLinePasswordDataSource.CommandRequestWithInput(
            command: OnePasswordUtils.pathToCLI,
            args: ["account", "list", "--format=json"],
            env: OnePasswordUtils.basicEnvironment,
            input: Data())
        DLog("Will execute account list")
        command.execAsync { (output: Output?, error: (any Error)?) in
            handle(output: output, error: error, completion: completion)
        }
    }

    private static func handle(output: Output?,
                               error: (any Error)?,
                               completion: (Result<[Account], Error>) -> ()) {
        DLog("account list finished")
        guard let output = output else {
            DLog("But there is no output")
            completion(.failure(error!))
            return
        }
        guard output.returnCode == 0 else {
            DLog("But the return code is nonzero")
            completion(.failure(OnePasswordDataSource.OPError.unexpectedError))
            return
        }
        let decoder = JSONDecoder()
        guard let accounts = try? decoder.decode([Account].self, from: output.stdout) else {
            // output's debug description dumps stdout/stderr, which here is the 1Password
            // account list (emails, sign-in URLs). Keep it out of the ring (byte count only).
            RLog("Failed to parse account list: \(redacted: output, or: "byteCount=\(output.stdout.count)")")
            completion(.failure(OnePasswordDataSource.OPError.unexpectedError))
            return
        }
        completion(.success(accounts))
    }
}

class OnePasswordTokenRequester {
    private var token = ""
    private static var biometricsAvailable: Bool? = nil

    enum Auth {
        case biometric
        case token(String)
    }

    private func argsByAddingAccountArg(_ argsIn: [String]) -> [String] {
        var args = argsIn
        let account = iTermAdvancedSettingsModel.onePasswordAccount()!
        if !account.isEmpty {
            args += ["--account", account]
        }
        return args
    }

    private var passwordPrompt: String {
        let account = iTermAdvancedSettingsModel.onePasswordAccount()!
        if account.isEmpty {
            return "Enter your 1Password master password:"
        }
        return "Enter the 1Password master password for account “\(account)”:"
    }

    func asyncGet(_ completion: @escaping (Result<Auth, Error>) -> ()) {
        DLog("Begin asyncGet")
        switch Self.biometricsAvailable {
        case .none:
            asyncCheckBiometricAvailability() { [weak self] availability in
                guard let self = self else {
                    DLog("Biometrics check finished but self is dealloced")
                    return
                }
                switch availability {
                case .some(true):
                    RLog("biometrics are available")
                    Self.biometricsAvailable = true
                    completion(.success(.biometric))
                case .some(false):
                    RLog("biometrics unavailable, continue with regular auth")
                    Self.biometricsAvailable = false
                    self.asyncGetWithoutBiometrics(completion)
                case .none:
                    RLog("Failed to look up biometrics")
                    completion(.failure(OnePasswordDataSource.OPError.canceledByUser))
                }
            }
        case .some(true):
            completion(.success(.biometric))
        case .some(false):
            asyncGetWithoutBiometrics(completion)
        }
    }

    private func asyncGetWithoutBiometrics(_ completion: @escaping (Result<Auth, Error>) -> ()) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let password = self.requestPassword(prompt: self.passwordPrompt) else {
            completion(.failure(OnePasswordDataSource.OPError.canceledByUser))
            return
        }
        self.asyncGet(password: password, completion)
    }

    private func asyncGet(password: String, _ completion: @escaping (Result<Auth, Error>) -> ()) {
        DLog("Read password from user entry")
        let command = CommandLinePasswordDataSource.CommandRequestWithInput(
            command: OnePasswordUtils.pathToCLI,
            args: argsByAddingAccountArg(["signin", "--raw"]),
            env: OnePasswordUtils.basicEnvironment,
            input: (password + "\n").data(using: .utf8)!)
        DLog("Will execute signin --raw")
        command.execAsync { [weak self] output, error in
            DLog("signin --raw finished")
            guard let self = self else {
                DLog("But I have been dealloced")
                return
            }
            guard let output = output else {
                DLog("But there is no output")
                completion(.failure(error!))
                return
            }
            guard output.returnCode == 0 else {
                DLog("But the return code is nonzero")
                DLog("signin failed")
                let reason = String(data: output.stderr, encoding: .utf8) ?? "An unknown error occurred."
                RLog("Failure reason is: \(reason)")
                if reason.contains("connecting to desktop app timed out") {
                    completion(.failure(OnePasswordDataSource.OPError.unusableCLI))
                    return
                }
                self.showErrorMessage(reason)
                completion(.failure(OnePasswordDataSource.OPError.needsAuthentication))
                return
            }
            guard let token = String(data: output.stdout, encoding: .utf8) else {
                DLog("got garbage output")
                self.showErrorMessage("The 1Password CLI app produced garbled output instead of an auth token.")
                completion(.failure(OnePasswordDataSource.OPError.badOutput))
                return
            }
            DLog("Got a token, yay")
            completion(.success(.token(token.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))))
        }
    }

    private func showErrorMessage(_ reason: String) {
        let alert = NSAlert()
        alert.messageText = "Authentication Error"
        alert.informativeText = reason
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func requestPassword(prompt: String) -> String? {
        DLog("requesting master password")
        return ModalPasswordAlert(prompt).run(window: nil)
    }

    // Returns nil if it was canceled by the user.
    func checkBiometricAvailability() -> Bool? {
        // Issue a command that is doomed to fail so we can see what the error message looks like.
        let cli = OnePasswordUtils.pathToCLI
        if OnePasswordUtils.usable != true {
           DLog("No usable version of 1password's op utility was found")
            // Don't ask for the master password if we don't have a good CLI to use.
            return nil
        }
        var command = CommandLinePasswordDataSource.InteractiveCommandRequest(
            command: cli,
            args: argsByAddingAccountArg(["user", "get", "--me"]),
            env: OnePasswordUtils.basicEnvironment)
        command.useTTY = true
        let output = try! command.exec()
        if output.returnCode == 0 {
            DLog("op user get --me succeeded so biometrics must be available")
            return true
        }
        guard let string = String(data: output.stderr, encoding: .utf8) else {
            DLog("garbage output")
            return false
        }
        RLog("op signin returned \(string)")
        if string.contains("error initializing client: authorization prompt dismissed, please try again") {
            return nil
        }
        return false
    }

    func asyncCheckBiometricAvailability(_ completion: @escaping (Bool?) -> ()) {
        // Issue a command that is doomed to fail so we can see what the error message looks like.
        let cli = OnePasswordUtils.pathToCLI
        if OnePasswordUtils.usable != true {
           DLog("No usable version of 1password's op utility was found")
            // Don't ask for the master password if we don't have a good CLI to use.
            completion(nil)
            return
        }
        var command = CommandLinePasswordDataSource.InteractiveCommandRequest(
            command: cli,
            args: argsByAddingAccountArg(["user", "get", "--me"]),
            env: OnePasswordUtils.basicEnvironment)
        command.useTTY = true
        command.execAsync { output, error in
            DispatchQueue.main.async {
                guard let output = output else {
                    completion(false)
                    return
                }
                if output.returnCode == 0 {
                    DLog("op user get --me succeeded so biometrics must be available")
                    completion(true)
                    return
                }
                guard let string = String(data: output.stderr, encoding: .utf8) else {
                    DLog("garbage output")
                    completion(false)
                    return
                }
                RLog("op signin returned \(string)")
                if string.contains("error initializing client: authorization prompt dismissed, please try again") {
                    completion(nil)
                    return
                }
                completion(false)
            }
        }
    }
}

