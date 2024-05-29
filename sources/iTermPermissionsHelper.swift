//
//  iTermPermissionsHelper.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/28/24.
//

import Foundation

@objc(iTermPermissionsHelperProtocol)
protocol PermissionsHelperProtocol {
    @objc @discardableResult func request() -> Bool
    @objc var status: Bool { get }
}

@objc(iTermPermissionsHelper)
class PermissionsHelper: NSObject {
    @objc static let accessibility: PermissionsHelperProtocol = AccessibilityPermissionsHelper("Accessibility")
}

class AccessibilityPermissionsHelper: PermissionsHelperProtocol {
    private let name: String
    private let userDefaultsKeyPrefix = "NoSyncPermissionsHelper_"

    fileprivate init(_ name: String) {
        self.name = name
    }

    @objc
    @discardableResult
    func request() -> Bool {
        let key = userDefaultsKeyPrefix + name

        let thisVersion = Bundle.main.infoDictionary?[kCFBundleVersionKey as String] as? String
        let lastVersion = UserDefaults.standard.string(forKey: key)

        guard let thisVersion else {
            return status
        }
        if thisVersion == lastVersion {
            return status
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let value = AXIsProcessTrustedWithOptions(options)
        UserDefaults.standard.set(thisVersion, forKey: key)
        return value
    }

    @objc
    var status: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        let value = AXIsProcessTrustedWithOptions(options)
        return value
    }
}
