//
//  RemoteCommandExecutor.swift
//  iTerm2
//
//  Created by George Nachman on 2/13/25.
//

class RemoteCommandExecutor {
    static let instance = RemoteCommandExecutor()
    struct Key: Hashable {
        var guid: String
        var category: RemoteCommand.Content.PermissionCategory
    }
    private var storage = [Key: Permission]()

    enum Permission {
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
    func permission(inSessionGuid guid: String,
                    category: RemoteCommand.Content.PermissionCategory) -> Permission {
        return storage[Key(guid: guid, category: category)] ?? defaultPermission(for: category)
    }

    func setPermission(permission: Permission,
                       guid: String,
                       category: RemoteCommand.Content.PermissionCategory) {
        storage[Key(guid: guid, category: category)] = permission
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
    func allowedCategories(for guid: String) -> Set<RemoteCommand.Content.PermissionCategory> {
        var result = Set<RemoteCommand.Content.PermissionCategory>()
        for category in RemoteCommand.Content.PermissionCategory.allCases {
            switch permission(inSessionGuid: guid, category: category) {
            case .always, .ask:
                result.insert(category)
            case .never:
                break
            }
        }
        return result
    }
}

extension RemoteCommandExecutor {
    func controlState(guid: String, category: RemoteCommand.Content.PermissionCategory) -> NSControl.StateValue {
        switch permission(inSessionGuid: guid, category: category) {
        case .always:
                .on
        case .never:
                .off
        case .ask:
                .mixed
        }
    }
}
