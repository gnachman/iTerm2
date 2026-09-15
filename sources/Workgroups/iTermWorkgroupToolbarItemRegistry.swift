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
              displayName: String(localized: "WorkgroupToolbarItemRegistry.GitStatus", defaultValue: "Git Status", comment: "Toolbar item name: git status indicator"),
              hasParameters: false,
              defaultValue: .gitStatus),
        .init(kind: .changedFileSelector,
              displayName: String(localized: "WorkgroupToolbarItemRegistry.ChangedFileSelector", defaultValue: "Changed File Selector", comment: "Toolbar item name: picker for changed files"),
              hasParameters: false,
              defaultValue: .changedFileSelector),
        .init(kind: .modeSwitcher,
              displayName: String(localized: "WorkgroupToolbarItemRegistry.PeerModeSwitcher", defaultValue: "Peer Mode Switcher", comment: "Toolbar item name: switcher between peer sessions"),
              hasParameters: false,
              defaultValue: .modeSwitcher),
        .init(kind: .navigation,
              displayName: String(localized: "WorkgroupToolbarItemRegistry.NavigationButtons", defaultValue: "Navigation Buttons", comment: "Toolbar item name: back/forward/reload navigation buttons"),
              hasParameters: false,
              defaultValue: .navigation(WorkgroupNavigationShortcuts.defaults)),
        .init(kind: .reload,
              displayName: String(localized: "WorkgroupToolbarItemRegistry.Reload", defaultValue: "Reload", comment: "Toolbar item name: reload button"),
              hasParameters: false,
              defaultValue: .reload(WorkgroupToolbarShortcut.reloadDefault)),
        .init(kind: .gitBaseSelector,
              displayName: String(localized: "WorkgroupToolbarItemRegistry.GitBaseSelector", defaultValue: "Git Base Selector", comment: "Toolbar item name: picker for the git base ref"),
              hasParameters: false,
              defaultValue: .gitBaseSelector),
        .init(kind: .autoSendClippingsWhenIdle,
              displayName: String(localized: "WorkgroupToolbarItemRegistry.AutoSendClippingsWhenIdle", defaultValue: "Auto-Send Clippings When Idle", comment: "Toolbar item name: toggle to auto-send clippings when idle"),
              hasParameters: false,
              defaultValue: .autoSendClippingsWhenIdle),
        .init(kind: .autoRequestReviewWhenIdle,
              displayName: String(localized: "WorkgroupToolbarItemRegistry.AutoRequestReviewWhenIdle", defaultValue: "Auto-Request Review When Idle", comment: "Toolbar item name: toggle to auto-request a code review when idle"),
              hasParameters: false,
              defaultValue: .autoRequestReviewWhenIdle),
        .init(kind: .spacer,
              displayName: String(localized: "WorkgroupToolbarItemRegistry.Spacer", defaultValue: "Spacer", comment: "Toolbar item name: a flexible spacer"),
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
