//
//  FileExtensionDB.swift
//  iTerm2
//
//  Created by George Nachman on 4/24/22.
//

import Foundation

@objc
class iTermFileExtensionDB: NSObject {
    @objc static let instance = iTermFileExtensionDB()
    private let impl = FileExtensionDB()

    @objc
    func languagesForPath(_ path: String?) -> Set<String> {
        return impl?.languagesForPath(path) ?? Set()
    }
}

class FileExtensionDB {
    static let instance = FileExtensionDB()
    // Map a file extension to a set of languages.
    private let extensionToLanguages: [String: Set<String>]
    private let mimeTypeToLanguage: [String: String]
    private let shortNameToLanguage: [String: String]
    let languages: Set<String>

    init?() {
        guard let filename = Bundle(for: Self.self).path(forResource: "extensions", ofType: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filename)) else {
            return nil
        }
        struct Entry: Decodable {
            let name: String
            let extensions: [String]
            let mimeType: String?
            let shortname: String
        }
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return nil
        }
        var e2l = [String: Set<String>]()
        var m2l = [String: String]()
        var s2l = [String: String]()
        for entry in entries {
            for ext in entry.extensions {
                e2l[ext] = (e2l[ext] ?? Set()).union(Set([entry.name]))
            }
            if let mimeType = entry.mimeType {
                m2l[mimeType] = entry.name
            }
            s2l[entry.shortname] = entry.name
        }
        extensionToLanguages = e2l
        mimeTypeToLanguage = m2l
        shortNameToLanguage = s2l
        languages = Set(entries.map { $0.name })
    }

    private func languagesForExtension(_ ext: String) -> Set<String> {
        return extensionToLanguages[ext] ?? Set()
    }

    func languagesForPath(_ path: String?) -> Set<String> {
        guard let path = path else {
            return Set()
        }
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let parts = Array(filename.components(separatedBy: ".").dropFirst())
        if parts.isEmpty {
            return Set()
        }
        let candidates = (0 ..< parts.count).map { i in
            parts[i...].joined(separator: ".")
        }
        let sets = candidates.map {
            languagesForExtension($0)
        }
        return sets.reduce(into: Set()) { partialResult, set in
            partialResult.formUnion(set)
        }
    }

    func languageForMimeType(_ mimeType: String) -> String? {
        return mimeTypeToLanguage[mimeType]
    }

    func languageForShortName(_ shortName: String) -> String? {
        return shortNameToLanguage[shortName]
    }
}
