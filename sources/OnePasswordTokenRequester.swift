//
//  OnePasswordTokenRequester.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/20/22.
//

import Foundation

class OnePasswordTokenRequester {
    private var token = ""
    private static var biometricsAvailable: Bool? = nil

    enum Auth {
        case biometric
        case token(String)
    }

    // Returns nil if a token is unneeded because biometric authentication is available.
    func get() throws -> Auth {
        if Self.biometricsAvailable == nil {
            switch checkBiometricAvailability() {
            case .some(true):
                return .biometric
            case .some(false):
                break
            case .none:
                throw OnePasswordDataSource.OPError.canceledByUser
            }
        }
        guard let password = self.requestPassword(prompt: "Enter your 1Password master password:") else {
            throw OnePasswordDataSource.OPError.canceledByUser
        }
        let command = CommandLinePasswordDataSource.Command(command: "/usr/local/bin/op",
                                                            args: ["signin", "--raw"],
                                                            env: ["HOME": NSHomeDirectory()],
                                                            stdin: (password + "\n").data(using: .utf8))
        let output = try command.exec()
        if output.returnCode != 0 {
            let reason = String(data: output.stderr, encoding: .utf8) ?? "An unknown error occurred."
            showErrorMessage(reason)
            throw OnePasswordDataSource.OPError.needsAuthentication
        }
        guard let token = String(data: output.stdout, encoding: .utf8) else {
            showErrorMessage("The 1Password CLI app produced garbled output instead of an auth token.")
            throw OnePasswordDataSource.OPError.badOutput
        }
        return .token(token.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
    }

    private func showErrorMessage(_ reason: String) {
        let alert = NSAlert()
        alert.messageText = "Authentication Error"
        alert.informativeText = reason
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func requestPassword(prompt: String) -> String? {
        return ModalPasswordAlert(prompt).run(window: nil)
    }

    // Returns nil if it was canceled by the user.
    func checkBiometricAvailability() -> Bool? {
        // Issue a command that is doomed to fail so we can see what the error message looks like.
        let bogusID = UUID().uuidString
        let command = CommandLinePasswordDataSource.Command(command: "/usr/local/bin/op",
                                                            args: ["item", "get", bogusID],
                                                            env: ["HOME": NSHomeDirectory()],
                                                            stdin: nil)
        let output = try! command.exec()
        if output.returnCode == 0 {
            fatalError()
        }
        guard let string = String(data: output.stderr, encoding: .utf8) else {
            return false
        }
        if string.contains("error initializing client: authorization prompt dismissed, please try again") {
            return nil
        }
        // If it's unlocked by biometrics then you'll get an error like:
        //   "UUID" isn't an item. Specify the item with its UUID, name, or domain.
        return string.contains(bogusID)
    }
}

