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

        init(_ aiPermission: iTermAIPermission) {
            switch aiPermission {
            case .allow:
                self = .always
            case .ask:
                self = .ask
            case .never:
                self = .never
            @unknown default:
                self = .ask
            }
        }
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

    // Here, "allowed" means we will tell the LLM about it. It's complicated by the fact that
    // some categories are autopopulated in the message when in "always" mode so we don't expose
    // those tools to the LLM.
    private func categoryIsAllowed(category: RemoteCommand.Content.PermissionCategory,
                                   permission: Permission) -> Bool {
        switch permission {
        case .always:
            return !category.autopopulatedWhenAlways
        case .ask:
            return true
        case .never:
            return false
        }
    }

    // Permission categories with always or ask (default is ask)
    func allowedCategories(chatID: String, terminalGuid: String?, browserGuid: String?) -> Set<RemoteCommand.Content.PermissionCategory> {
        var result = Set<RemoteCommand.Content.PermissionCategory>()
        for category in RemoteCommand.Content.PermissionCategory.allCases {
            let permission: Permission = if category.isBrowserSpecific {
                if let browserGuid {
                    permission(chatID: chatID,
                               inSessionGuid: browserGuid,
                               category: category)
                } else {
                    .never
                }
            } else {
                if let terminalGuid {
                    permission(chatID: chatID,
                               inSessionGuid: terminalGuid,
                               category: category)
                } else {
                    .never
                }
            }
            if categoryIsAllowed(category: category, permission: permission) {
                result.insert(category)
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

    func defaultPermissions(chatID: String, terminalGuid: String?, browserGuid: String?) -> [Key: Permission] {
        var result = [Key: Permission]()
        for category in RemoteCommand.Content.PermissionCategory.allCases {
            let rawValue = iTermPreferences.unsignedInteger(forKey: category.userDefaultsKey)
            let key: Key? = if category.isBrowserSpecific {
                if let browserGuid {
                    Key(chatID: chatID, guid: browserGuid, category: category)
                } else {
                    nil
                }
            } else {
                if let terminalGuid {
                    Key(chatID: chatID, guid: terminalGuid, category: category)
                } else {
                    nil
                }
            }
            if let key {
                let setting = iTermAIPermission(rawValue: rawValue) ?? .never
                result[key] = .init(setting)
            }
        }
        return result
    }

    func permissionsDict(encoded encodedPermissions: String) -> [Key: Permission]? {
         try? JSONDecoder().decode([Key: Permission].self, from: encodedPermissions.data(using: .utf8)!)
    }

    func allowedCategories(dict: [Key: Permission]) -> Set<RemoteCommand.Content.PermissionCategory> {
        var result = Set<RemoteCommand.Content.PermissionCategory>()
        for (key, permission) in dict {
            if categoryIsAllowed(category: key.category, permission: permission) {
                result.insert(key.category)
            }
        }
        return result
    }

    func load(encodedPermissions: String) {
        let sub = permissionsDict(encoded: encodedPermissions)
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
