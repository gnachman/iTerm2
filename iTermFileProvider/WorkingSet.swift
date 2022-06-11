//
//  WorkingSet.swift
//  FileProvider
//
//  Created by George Nachman on 6/9/22.
//

import Foundation
import FileProvider

actor WorkingSet {
    static let instance = WorkingSet()

    enum Kind {
        case file  // includes symlinks
        case folder
    }

    struct Entry: Hashable {
        let path: String
        let kind: Kind
    }
    private(set) var entries = Set<Entry>()

    func addFile(_ path: String,
                 domain: NSFileProviderDomain) {
        log("Add \(path) as file to working set")
        entries.insert(Entry(path: path, kind: .file))
        didChange(domain)
        Task { await RemoteService.instance.subscribe([path]) }
    }

    func addFolder(_ path: String,
                   domain: NSFileProviderDomain) {
        log("Add \(path) as folder to working set")
        entries.insert(Entry(path: path, kind: .folder))
        didChange(domain)
        Task { await RemoteService.instance.subscribe([path]) }
    }

    private func didChange(_ domain: NSFileProviderDomain) {
        Task {
            await MainActor.run {
                log("Signal working set enumerator")
                NSFileProviderManager(for: domain)?.signalEnumerator(for: .workingSet) { error in
                    if let error = error {
                        log("Error when signaling enumerator for working set: \(error)")
                    }
                }
            }
        }
    }
}
