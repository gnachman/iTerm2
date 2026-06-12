//
//  Bundle+ShellIntegration.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/22.
//

import Foundation

extension Bundle {
    @objc static var shellIntegrationDirectory: String? {
        return Bundle(for: PTYSession.self).path(forResource: ".zshenv", ofType: nil)?.deletingLastPathComponent
    }
}
