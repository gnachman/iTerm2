//
//  AccountPicker.swift
//  iTerm2
//
//  Created by George Nachman on 11/25/25.
//

import AppKit

class AccountPicker {
    struct Account: Codable {
        var title: String?
        var accountID: String?
    }

    static func askUserToSelect(from accounts: [Account]) -> String {
        DLog("begin")
        let alert = NSAlert()
        alert.messageText = "Select an Account"
        alert.informativeText = "Please choose an account:"
        alert.alertStyle = .informational

        var ids = [String]()
        for account in accounts {
            if let email = account.title, let uuid = account.accountID {
                alert.addButton(withTitle: email)
                ids.append(uuid)
            }
        }
        if ids.count == 1 {
            return ids[0]
        }
        it_assert(ids.count > 1)

        // Can't present a sheet modal within a sheet modal so go app modal instead.
        let response = alert.runModal()

        let selectedIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue

        let uuid = ids[selectedIndex]
        return uuid
    }
}
