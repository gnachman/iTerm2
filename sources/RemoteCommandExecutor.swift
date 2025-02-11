//
//  RemoteCommandExecutor.swift
//  iTerm2
//
//  Created by George Nachman on 2/13/25.
//

class RemoteCommandExecutor {
    static let instance = RemoteCommandExecutor()
    struct Key: Hashable, Codable {
        var chatID: String
        var guid: String
        var category: RemoteCommand.Content.PermissionCategory
    }
    private var storage = [Key: Permission]()

    enum Permission: String, Codable {
        case always
        case never
        case ask
    }

    private func defaultPermission(for category: RemoteCommand.Content.PermissionCategory) -> Permission {
        switch iTermAIPermission(rawValue: iTermPreferences.unsignedInteger(forKey: category.userDefaultsKey)) {
        case .allow:
                .always
        case .ask:
                .ask
        case .never:
                .never
        case .none, .some:
                .ask
        }
    }
    func permission(chatID: String,
                    inSessionGuid guid: String,
                    category: RemoteCommand.Content.PermissionCategory) -> Permission {
        return storage[Key(chatID: chatID,
                           guid: guid,
                           category: category)] ?? defaultPermission(for: category)
    }

    func setPermission(chatID: String,
                       permission: Permission,
                       guid: String,
                       category: RemoteCommand.Content.PermissionCategory) {
        storage[Key(chatID: chatID, guid: guid, category: category)] = permission
    }

    func erasePermissions(guid: String) {
        let keys = storage.keys.filter { key in
            key.guid == guid
        }
        for key in keys {
            storage.removeValue(forKey: key)
        }
    }

    // Permission categories with always or ask (default is ask)
    func allowedCategories(chatID: String, for guid: String) -> Set<RemoteCommand.Content.PermissionCategory> {
        var result = Set<RemoteCommand.Content.PermissionCategory>()
        for category in RemoteCommand.Content.PermissionCategory.allCases {
            switch permission(chatID: chatID,
                              inSessionGuid: guid,
                              category: category) {
            case .always, .ask:
                result.insert(category)
            case .never:
                break
            }
        }
        return result
    }

    func encodedPermissions(chatID: String) -> String {
        let sub = storage.filter { element in
            element.key.chatID == chatID
        }
        return (try? JSONEncoder().encode(sub).lossyString) ?? ""
    }

    func load(encodedPermissions: String) {
        let sub = try? JSONDecoder().decode([Key: Permission].self, from: encodedPermissions.data(using: .utf8)!)
        guard let sub else {
            DLog("Failed to decode \(encodedPermissions)")
            return
        }
        storage.merge(sub) { lhs, rhs in
            rhs
        }
    }
}

extension RemoteCommandExecutor {
    func controlState(chatID: String,
                      guid: String,
                      category: RemoteCommand.Content.PermissionCategory) -> NSControl.StateValue {
        switch permission(chatID: chatID, inSessionGuid: guid, category: category) {
        case .always:
                .on
        case .never:
                .off
        case .ask:
                .mixed
        }
    }
}
