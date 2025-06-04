//
//  SSHFilePanelSidebarItem.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

/// Sidebar item for the source list
@available(macOS 11, *)
enum SSHFilePanelSidebarItem: Equatable, Hashable {
    case host(RemoteHostStatus)
    case favorite(RemoteFavorite)
    case separator

    /// Represents connection status and metadata for an SSH host
    struct RemoteHostStatus: Equatable, Hashable {
        let identity: SSHIdentity
        let isConnected: Bool
        let lastConnected: Date?

        /// Display name with connection status
        var displayName: String {
            let status = isConnected ? "●" : "○"
            return "\(status) \(identity.compactDescription)"
        }
    }

    /// Favorited item in the panel
    struct RemoteFavorite: Equatable, Hashable, Identifiable {
        let id: UUID
        let path: String
        let identity: SSHIdentity
        let dateAdded: Date
        let sortOrder: Int

        var displayName: String {
            return (path as NSString).lastPathComponent.isEmpty ? "/" : (path as NSString).lastPathComponent
        }
    }

    var id: String {
        switch self {
        case .host(let hostStatus):
            return "host-\(hostStatus.identity.stringIdentifier)"
        case .favorite(let favorite):
            return "favorite-\(favorite.id)"
        case .separator:
            return "separator"
        }
    }

    var title: String {
        switch self {
        case .host(let hostStatus):
            return hostStatus.displayName
        case .favorite(let favorite):
            return favorite.displayName
        case .separator:
            return ""
        }
    }

    var icon: NSImage? {
        switch self {
        case .host(let hostStatus):
            return hostStatus.isConnected ?
                NSImage.it_image(forSymbolName: "desktopcomputer",
                                 accessibilityDescription: "Connected host",
                                 fallbackImageName: "desktopcomputer",
                                 for: SSHFilePanel.self) :
                NSImage.it_image(forSymbolName: "desktopcomputer.trianglebadge.exclamationmark",
                                 accessibilityDescription: "Disconnected host",
                                 fallbackImageName: "desktopcomputer.trianglebadge.exclamationmark",
                                 for: SSHFilePanel.self)
        case .favorite:
            return NSImage.it_image(forSymbolName: "star.fill",
                                    accessibilityDescription: "Star",
                                    fallbackImageName: "star.fill",
                                    for: SSHFilePanel.self)
        case .separator:
            return nil
        }
    }
}

