//
//  WorkingSet.swift
//  FileProvider
//
//  Created by George Nachman on 6/9/22.
//

import Foundation
import FileProvider
import FileProviderService

actor WorkingSet {
    private let remoteService: RemoteService

    enum Kind {
        case file  // includes symlinks
        case folder
    }

    struct Entry: Hashable {
        let path: String
        let kind: Kind
    }
    private(set) var entries = Set<Entry>()

    init(remoteService: RemoteService) {
        self.remoteService = remoteService
    }

    func addFile(_ path: String,
                 domain: NSFileProviderDomain) {
        log("Add \(path) as file to working set")
        entries.insert(Entry(path: path, kind: .file))
        didChange(domain)
        Task { await remoteService.subscribe([path]) }
    }

    func addFolder(_ path: String,
                   domain: NSFileProviderDomain) {
        log("Add \(path) as folder to working set")
        entries.insert(Entry(path: path, kind: .folder))
        didChange(domain)
        Task { await remoteService.subscribe([path]) }
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
