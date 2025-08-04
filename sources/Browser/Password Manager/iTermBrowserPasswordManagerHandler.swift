//
//  iTermBrowserPasswordManagerHandler.swift
//  iTerm2
//
//  Created by George Nachman on 6/22/25.
//

import Foundation
import Security
import WebKit

@MainActor
class iTermBrowserPasswordManagerHandler {
    static let instance = iTermBrowserPasswordManagerHandler()
    static let messageHandlerName = "iTermOpenPasswordManager"
    private let secret: String

    enum Action {
        case openPasswordManagerForPassword
        case openPasswordManagerForUser
        case openPasswordManagerForBoth(passwordID: String)
    }

    init?() {
        guard let secret = String.makeSecureHexString() else {
            return nil
        }
        self.secret = secret
    }

    var javascript: String {
        return iTermBrowserTemplateLoader.loadTemplate(named: "password-button",
                                                       type: "js",
                                                       substitutions: [ "SECRET": secret ])

    }

    func handleMessage(webView: WKWebView,
                       message: WKScriptMessage) -> Action? {
        guard let messageDict = message.body as? [String: Any],
              let type = messageDict["type"] as? String,
              let sessionSecret = messageDict["sessionSecret"] as? String,
              sessionSecret == secret else {
            DLog("Invalid notification message format")
            return nil
        }
        switch type {
        case "openPassword":
            return .openPasswordManagerForPassword
        case "openUser":
            if let passwordID = messageDict["nextPasswordFieldId"] as? String {
                return .openPasswordManagerForBoth(passwordID: passwordID)
            }
            return .openPasswordManagerForUser
        default:
            DLog("Unknown type \(type)")
            return nil
        }
    }
}
