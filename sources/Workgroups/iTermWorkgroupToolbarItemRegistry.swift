//
//  iTermWorkgroupToolbarItemRegistry.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import CoreGraphics
import Foundation

// Metadata catalog for the toolbar tools the user can attach to a
// workgroup session's toolbar. Phase 1 uses this to populate the settings
// UI's item-picker. Phase 2 will add the runtime factory that turns a
// concrete iTermWorkgroupToolbarItem value into a SessionToolbarGeneric-
// View, taking the runtime context (git poller, button delegates, etc.)
// that the settings UI doesn't have access to.
struct iTermWorkgroupToolbarItemMetadata {
    let kind: iTermWorkgroupToolbarItemKind
    let displayName: String
    let hasParameters: Bool          // true for .spacer
    let defaultValue: iTermWorkgroupToolbarItem
}

enum iTermWorkgroupToolbarItemRegistry {
    // Order here is the order the picker UI lists items.
    static let all: [iTermWorkgroupToolbarItemMetadata] = [
        .init(kind: .gitStatus,
              displayName: "Git Status",
              hasParameters: false,
              defaultValue: .gitStatus),
        .init(kind: .changedFileSelector,
              displayName: "Changed File Selector",
              hasParameters: false,
              defaultValue: .changedFileSelector),
        .init(kind: .modeSwitcher,
              displayName: "Peer Mode Switcher",
              hasParameters: false,
              defaultValue: .modeSwitcher),
        .init(kind: .navigation,
              displayName: "Navigation Buttons",
              hasParameters: false,
              defaultValue: .navigation),
        .init(kind: .reload,
              displayName: "Reload",
              hasParameters: false,
              defaultValue: .reload),
        .init(kind: .spacer,
              displayName: "Spacer",
              hasParameters: true,
              defaultValue: .spacer(minWidth: 4, maxWidth: 4)),
    ]

    static func metadata(forKind kind: iTermWorkgroupToolbarItemKind) -> iTermWorkgroupToolbarItemMetadata? {
        return all.first(where: { $0.kind == kind })
    }

    static func metadata(for item: iTermWorkgroupToolbarItem) -> iTermWorkgroupToolbarItemMetadata? {
        return metadata(forKind: item.kind)
    }
}
