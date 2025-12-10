//
//  ArchivesMenuBuilder.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/7/25.
//

import Foundation
import UniformTypeIdentifiers

@objc
protocol ArchiveRestoring: AnyObject {
    func restoreArchive(_ menuItem: NSMenuItem?)
}

@objc
class ArchivesMenuBuilder: NSObject {
    @objc static var shared: ArchivesMenuBuilder?
    private let menuItem: NSMenuItem
    private let userDefaultsKey = "NoSyncRecentArchives"
    private var items = [(NSMenuItem, String)]()
    private let maxRecents = 10

    @objc(initWithMenuItem:)
    init(_ menuItem: NSMenuItem) {
        self.menuItem = menuItem
        super.init()
        loadFromUserDefaults()
    }

    private func loadFromUserDefaults() {
        let objects = UserDefaults.standard.object(forKey: userDefaultsKey)
        let paths = objects as? [String] ?? []
        items = paths.map {
            (menuItem(for: $0), $0)
        }
        if items.count > maxRecents {
            items.removeFirst(items.count - maxRecents)
        }
        updateSubmenu()
    }

    func didAdd(path: String) {
        items.append((menuItem(for: path), path))
        if items.count > maxRecents {
            items.removeFirst(items.count - maxRecents)
        }
        updateSubmenu()
        let paths = items.map(\.1)
        save(paths)
    }

    private func updateSubmenu() {
        if let submenu = menuItem.submenu,
           let i = submenu.items.firstIndex(where: { $0.isSeparatorItem }) {
            while submenu.items.count > i + 1 {
                submenu.removeItem(at: i + 1)
            }
        }
        for tuple in items {
            self.menuItem.submenu?.addItem(tuple.0)
        }
    }

    private func save(_ paths: [String]) {
        if paths.count > maxRecents {
            save(Array(paths.dropFirst(paths.count - maxRecents)))
        } else {
            UserDefaults.standard.set(paths, forKey: userDefaultsKey)
        }
    }

    private func menuItem(for path: String) -> NSMenuItem {
        let item = NSMenuItem(title: path.lastPathComponent.deletingPathExtension,
                              action: #selector(restoreArchive(_:)),
                              keyEquivalent: "")
        item.representedObject = path
        item.target = self
        return item
    }

    @objc func restoreArchive(_ sender: Any?) {
        if let menuPath = (sender as? NSMenuItem)?.representedObject as? String {
            reallyRestoreArchive(menuPath)
            return
        }
        Task { @MainActor in
            if let path = await userSelectedArchivePath() {
                reallyRestoreArchive(path)
            }
        }
    }

    private func reallyRestoreArchive(_ path: String) {
        if let arrangement = NSDictionary.init(contentsOfFile: path) {
            iTermController.sharedInstance().tryOpenArrangement(
                arrangement as? [AnyHashable: Any],
                named: (path as NSString).lastPathComponent.deletingPathExtension,
                asTabsInWindow: nil)
        }
    }

    @MainActor
    private func userSelectedArchivePath() async -> String? {
        let panel = iTermOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [ UTType(filenameExtension: "itermarchive")! ]
        panel.includeLocalhost = true
        let urls = try? await panel.show(window: nil)
        return urls?.first?.path
    }
}

