//
//  MomentermPluginRegistry.swift
//  iTerm2
//
//  Loads the bundled curated plugin list and the user-editable list at
//  ~/.momenterm/plugins.json, merges them (user entries override bundle by id),
//  and notifies observers when either source changes on disk.
//

import Foundation

@objc enum MomentermPluginKind: Int {
    case claudePlugin
    case mcp

    static func fromRawString(_ raw: String) -> MomentermPluginKind {
        switch raw {
        case "claude-plugin": return .claudePlugin
        case "mcp":           return .mcp
        default:              return .claudePlugin
        }
    }

    var displayName: String {
        switch self {
        case .claudePlugin: return "Plugin"
        case .mcp:          return "MCP"
        }
    }
}

struct MomentermPluginItem: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let kind: MomentermPluginKind
    let install: String
    let source: String?
    let tags: [String]
    let auth: String?

    static func == (lhs: MomentermPluginItem, rhs: MomentermPluginItem) -> Bool {
        lhs.id == rhs.id && lhs.kind == rhs.kind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(kind)
    }
}

private struct RawRegistryFile: Decodable {
    let plugins: [RawItem]?
    let mcpServers: [RawItem]?
}

private struct RawItem: Decodable {
    let id: String
    let name: String
    let kind: String?
    let detail: String?
    let description: String?
    let install: String
    let source: String?
    let tags: [String]?
    let auth: String?
}

@objc final class MomentermPluginRegistry: NSObject {

    @objc static let shared = MomentermPluginRegistry()

    /// Posted when items change (bundled load, user file mutation, manual reload).
    @objc static let didChangeNotification = Notification.Name("MomentermPluginRegistryDidChange")

    private(set) var items: [MomentermPluginItem] = []
    private let userURL: URL
    private var fileMonitor: DispatchSourceFileSystemObject?
    private let monitorQueue = DispatchQueue(label: "com.momenterm.plugin-registry.watch")

    private override init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        userURL = home.appendingPathComponent(".momenterm/plugins.json")
        super.init()
        ensureUserFileExists()
        reload()
        startMonitoring()
    }

    // MARK: - Public API

    /// Path the user can edit. UI exposes this via "Edit plugins.json".
    @objc var userPluginsPath: String { userURL.path }

    /// Force a reload from disk. Returns the merged item count.
    @discardableResult
    @objc func reload() -> Int {
        let bundled = Self.loadBundled()
        let userOverrides = Self.loadFromURL(userURL)
        items = Self.merge(bundled: bundled, overrides: userOverrides)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        return items.count
    }

    func filter(query: String, kind: MomentermPluginKind?) -> [MomentermPluginItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if let k = kind, item.kind != k { return false }
            guard !q.isEmpty else { return true }
            if item.name.lowercased().contains(q) { return true }
            if item.detail.lowercased().contains(q) { return true }
            if item.id.lowercased().contains(q) { return true }
            return item.tags.contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: - Loading

    private static func loadBundled() -> [MomentermPluginItem] {
        guard let url = Bundle.main.url(forResource: "plugins.default", withExtension: "json") else {
            NSLog("[MomenTerm] plugins.default.json not bundled")
            return []
        }
        return loadFromURL(url)
    }

    private static func loadFromURL(_ url: URL) -> [MomentermPluginItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let raw = try? JSONDecoder().decode(RawRegistryFile.self, from: data) else {
            NSLog("[MomenTerm] failed to decode %@", url.path)
            return []
        }
        let plugins = (raw.plugins ?? []).map { item(from: $0, fallbackKind: .claudePlugin) }
        let mcp = (raw.mcpServers ?? []).map { item(from: $0, fallbackKind: .mcp) }
        return plugins + mcp
    }

    private static func item(from raw: RawItem, fallbackKind: MomentermPluginKind) -> MomentermPluginItem {
        let kind: MomentermPluginKind
        if let k = raw.kind {
            kind = MomentermPluginKind.fromRawString(k)
        } else {
            kind = fallbackKind
        }
        return MomentermPluginItem(
            id: raw.id,
            name: raw.name,
            detail: raw.detail ?? raw.description ?? "",
            kind: kind,
            install: raw.install,
            source: raw.source,
            tags: raw.tags ?? [],
            auth: raw.auth
        )
    }

    private static func merge(bundled: [MomentermPluginItem],
                              overrides: [MomentermPluginItem]) -> [MomentermPluginItem] {
        var byKey: [String: MomentermPluginItem] = [:]
        for item in bundled {
            byKey[Self.key(for: item)] = item
        }
        for item in overrides {
            byKey[Self.key(for: item)] = item
        }
        return byKey.values.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .claudePlugin
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func key(for item: MomentermPluginItem) -> String {
        return "\(item.kind.rawValue):\(item.id)"
    }

    // MARK: - User file bootstrap & watch

    private func ensureUserFileExists() {
        let dir = userURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: userURL.path) {
            let template = """
            {
              "schemaVersion": 1,
              "plugins": [],
              "mcpServers": []
            }
            """
            try? template.write(to: userURL, atomically: true, encoding: .utf8)
        }
    }

    private func startMonitoring() {
        // O_NOFOLLOW: refuse to watch a symlink an attacker may have planted
        // in ~/.momenterm/. We re-read the file by URL below, so any symlink
        // swap between the open and the read still has to pass O_NOFOLLOW too
        // on the next monitor tick.
        let fd = open(userURL.path, O_EVTONLY | O_NOFOLLOW)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: monitorQueue)
        src.setEventHandler { [weak self] in
            DispatchQueue.main.async { _ = self?.reload() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileMonitor = src
    }

    deinit {
        fileMonitor?.cancel()
    }
}
