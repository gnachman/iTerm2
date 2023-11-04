//
//  OnePasswordTokenRequester.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/20/22.
//

import Foundation

class OnePasswordUtils {
    static let basicEnvironment = ["HOME": NSHomeDirectory()]
    private static var _customPathToCLI: String? = nil
    private(set) static var usable: Bool? = nil

    static var pathToCLI: String {
        if let customPath = _customPathToCLI {
            return customPath
        }
        let normalPaths = ["/usr/local/bin/op", "/opt/homebrew/bin/op"]
        var defaultPath = normalPaths[0]
        lazy var anyNormalPathExists = {
            return normalPaths.anySatisfies {
                FileManager.default.fileExists(atPath: $0)
            }
        }()
        if anyNormalPathExists {
            DLog("normal path exists")
            let goodPath = normalPaths.first {
                FileManager.default.fileExists(atPath: $0) && checkUsability($0)
            }
            if let goodPath {
                defaultPath = goodPath
            }
            if usable == nil && goodPath == nil {
                DLog("usability fail")
                usable = false
                showUnavailableMessage(normalPaths.joined(separator: " or "))
            } else {
                DLog("normal path ok")
                usable = true
                return goodPath ?? normalPaths[0]
            }
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
    }
    static func checkUsability() -> Bool {
        return checkUsability(pathToCLI)
    }

    private static func checkUsability(_ path: String) -> Bool {
        return majorVersionNumber(path) == 2
    }

    static func showUnavailableMessage(_ path: String? = nil) {
        let alert = NSAlert()
        alert.messageText = "OnePassword Unavailable"
        if let path = path {
            alert.informativeText = "The existing installation of the OnePassword CLI at \(path) is an incompatible. The iTerm2 integration requires version 2."
        } else {
            alert.informativeText = "Version 2 of the OnePassword CLI could not be found. Check that \(OnePasswordUtils.pathToCLI) is installed and has version 2.x."
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
        panel.allowedFileTypes = [ "" ]
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
        return result
    }

    static func majorVersionNumber() -> Int? {
        return majorVersionNumber(pathToCLI)
    }

    private static func majorVersionNumber(_ pathToCLI: String) -> Int? {
        let maybeData = try? CommandLinePasswordDataSource.InteractiveCommandRequest(
            command: pathToCLI,
            args: ["-v"],
            env: [:]).exec().stdout
        if let data = maybeData, let string = String(data: data, encoding: .utf8) {
            var value = 0
            DLog("version string is \(string)")
            if Scanner(string: string).scanInt(&value) {
                DLog("scan returned \(value)")
                return value
            }
            DLog("scan failed")
            return nil
        }
        DLog("Didn't get a version number")
        return nil
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
                    DLog("biometrics are available")
                    Self.biometricsAvailable = true
                    completion(.success(.biometric))
                case .some(false):
                    DLog("biometrics unavailable, continue with regular auth")
                    Self.biometricsAvailable = false
                    self.asyncGetWithoutBiometrics(completion)
                case .none:
                    DLog("Failed to look up biometrics")
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
                DLog("Failure reason is: \(reason)")
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
        DLog("op signin returned \(string)")
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
                DLog("op signin returned \(string)")
                if string.contains("error initializing client: authorization prompt dismissed, please try again") {
                    completion(nil)
                    return
                }
                completion(false)
            }
        }
    }
}

