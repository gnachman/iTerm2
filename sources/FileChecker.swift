//
//  FileChecker.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/23.
//

import Foundation

protocol FileCheckerDataSource: AnyObject {
    func fileCheckerDataSourceDidReset()
    var fileCheckerDataSourceCanPerformFileChecking: Bool { get }
    func fileCheckerDataSourceCheck(path: String, completion: @escaping (Bool) -> ())
}

@objc(iTermFileChecker)
class FileChecker: NSObject {
    weak var dataSource: FileCheckerDataSource?
    var maxConcurrentChecks = 5

    private struct FileExistsCacheEntry: CustomDebugStringConvertible {
        var debugDescription: String {
            let e: String
            switch exists {
            case .none:
                e = "undecided"
            case .some(true):
                e = "true"
            case .some(false):
                e = "false"
            }
            return "<Conductor.FileExistsCacheEntry exists=\(e) observers=\(observers.count)>"
        }
        var exists: Bool?
        var observers = [(Bool) -> ()]()
    }

    private var cache = [String: FileExistsCacheEntry]()
    private var currentGeneration = 1

    private var outstandingCount = 0

    @objc
    func reset() {
        cache.removeAll()
        currentGeneration += 1
        dataSource?.fileCheckerDataSourceDidReset()
    }

    func cachedCheckIfFileExists(path: String) -> iTermTriState {
        if let entry = cache[path], let exists = entry.exists {
            return exists ? .true : .false
        }
        return .other
    }

    func checkIfFileExists(path: String, completion: @escaping (iTermTriState) -> ()) {
        guard dataSource?.fileCheckerDataSourceCanPerformFileChecking ?? false else {
            completion(.false)
            return
        }
        if let entry = cache[path], let exists = entry.exists {
            completion(exists ? .true : .false)
            return
        }
        if outstandingCount > maxConcurrentChecks {
            completion(.other)
            return
        }
        DLog("Will stat \(path) with entry \(cache[path]?.debugDescription ?? "(nil)")")

        var entry = cache[path] ?? FileExistsCacheEntry()
        entry.exists = nil
        entry.observers.append { exists in
            completion(exists ? .true : .false)
        }
        cache[path] = entry

        reallyCheckIfFileExists(path)
    }

    private func reallyCheckIfFileExists(_ path: String) {
        let generation = currentGeneration
        outstandingCount += 1
        DLog("Really stat \(path)")
        dataSource?.fileCheckerDataSourceCheck(path: path) { [weak self] exists in
            guard let self else {
                return
            }
            self.outstandingCount -= 1
            guard self.currentGeneration == generation else {
                return
            }
            guard var entry = self.cache[path] else {
                return
            }
            let observers = entry.observers
            entry.exists = exists
            entry.observers.removeAll()
            self.cache[path] = entry
            for observer in observers {
                observer(exists)
            }
        }
    }

}

@objc(iTermLocalFileChecker)
class LocalFileChecker: FileChecker, FileCheckerDataSource {
    @objc
    var workingDirectory = "/"

    @objc
    override init() {
        super.init()
        dataSource = self
    }

    func fileCheckerDataSourceDidReset() {
    }

    var fileCheckerDataSourceCanPerformFileChecking: Bool { true }

    func fileCheckerDataSourceCheck(path: String, completion: @escaping (Bool) -> ()) {
        iTermSlowOperationGateway.sharedInstance().statFile(makeAbsolute(path)) { _, error in
            completion(error == 0)
        }
    }

    private func makeAbsolute(_ path: String) -> String {
        if path.hasPrefix("/") {
            return path
        }
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return workingDirectory.appendingPathComponent(path)
    }
}
