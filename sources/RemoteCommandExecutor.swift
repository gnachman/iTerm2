//
//  RemoteCommandExecutor.swift
//  iTerm2
//
//  Created by George Nachman on 2/13/25.
//

class RemoteCommandExecutor {
    static let instance = RemoteCommandExecutor()
    private var storage = [String: Permission]()

    enum Permission {
        case always
        case never
        case ask
    }

    func permission(inSessionGuid guid: String) -> Permission {
        return storage[guid] ?? .ask
    }

    func setPermission(allowed: Bool, remember: Bool, guid: String) {
        if remember {
            storage[guid] = allowed ? .always : .never
        }
    }

    func erasePermissions(guid: String) {
        storage.removeValue(forKey: guid)
    }
}
