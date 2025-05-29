//
//  SSHFilePromiseProvider.swift
//  iTerm2
//
//  Created by George Nachman on 6/4/25.
//

import UniformTypeIdentifiers

@available(macOS 11, *)
class SSHFilePromiseProvider: NSFilePromiseProvider {

    struct UserInfoKeys {
        static let node = "node"
        static let endpoint = "endpoint"
        static let fullPath = "fullPath"
        static let tempURL = "tempURL"
        static let sshIdentity = "sshIdentity"
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        types.append(contentsOf: [.fileURL, .string])
        return types
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard let userInfoDict = userInfo as? [String: Any] else { return nil }

        switch type {
        case .fileURL:
            if let tempURL = userInfoDict[UserInfoKeys.tempURL] as? NSURL {
                return tempURL.pasteboardPropertyList(forType: type)
            }
        case .string:
            if let tempURL = userInfoDict[UserInfoKeys.tempURL] as? NSURL {
                return tempURL.path
            }
        default:
            break
        }

        return super.pasteboardPropertyList(forType: type)
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        return super.writingOptions(forType: type, pasteboard: pasteboard)
    }
}
