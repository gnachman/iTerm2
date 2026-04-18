//
//  MomentermProjectStorage.swift
//  iTerm2
//
//  Created by MomenTerm on 2026-04-19.
//

import Foundation

/// Persists project configuration to ~/.momenterm/projects.json
final class MomentermProjectStorage {

    static let shared = MomentermProjectStorage()

    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var _store: MomentermProjectStore?

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".momenterm")
        storageURL = dir.appendingPathComponent("projects.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Load / Save

    func load() -> MomentermProjectStore {
        if let cached = _store {
            return cached
        }
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            guard FileManager.default.fileExists(atPath: storageURL.path) else {
                let fresh = MomentermProjectStore()
                _store = fresh
                return fresh
            }

            let data = try Data(contentsOf: storageURL)
            let store = try decoder.decode(MomentermProjectStore.self, from: data)
            _store = store
            return store
        } catch {
            it_log("MomentermProjectStorage: load error: \(error)")
            let fresh = MomentermProjectStore()
            _store = fresh
            return fresh
        }
    }

    func save(_ store: MomentermProjectStore) {
        _store = store
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try encoder.encode(store)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            it_log("MomentermProjectStorage: save error: \(error)")
        }
    }

    // MARK: - Convenience mutations

    func addProject(_ project: MomentermProject, toSpace spaceId: String) {
        var store = load()
        guard let idx = store.spaces.firstIndex(where: { $0.id == spaceId }) else {
            return
        }
        store.spaces[idx].addProject(project)
        save(store)
    }

    func removeProject(withId projectId: String) {
        var store = load()
        for i in store.spaces.indices {
            store.spaces[i].removeProject(withId: projectId)
        }
        save(store)
    }

    func addSpace(named name: String) -> MomentermProjectSpace {
        var store = load()
        let space = store.addSpace(named: name)
        save(store)
        return space
    }

    func updateProject(_ project: MomentermProject) {
        var store = load()
        guard let indices = store.findProject(withId: project.id) else { return }
        store.spaces[indices.spaceIndex].projects[indices.projectIndex] = project
        save(store)
    }

    func markOpened(projectId: String) {
        var store = load()
        guard let indices = store.findProject(withId: projectId) else { return }
        store.spaces[indices.spaceIndex].projects[indices.projectIndex].lastOpenedAt = Date()
        save(store)
    }

    // MARK: - Invalidate cache

    func invalidateCache() {
        _store = nil
    }
}

// MARK: - Logging shim (uses iTerm2 logging)

private func it_log(_ message: String) {
    NSLog("[MomenTerm] %@", message)
}
