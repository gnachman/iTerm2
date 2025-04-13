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

    func commandIsValid(_ command: String) -> Bool? {
        return true
    }
}

@objc(iTermLocalFileChecker)
class LocalFileChecker: FileChecker, FileCheckerDataSource {
    @objc
    var workingDirectory = "/"

    private var path: iTermPromise<NSString>?
    private let shell: String?

    enum CommandValidity {
        case invalid(TimeInterval)
        case valid(TimeInterval)
        case pending(Int, TimeInterval)
    }
    private var knownCommands = [String: CommandValidity]()

    @objc(initWithShell:)
    init(shell: String?) {
        self.shell = shell
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

    // Max amount of time in seconds a file can be in the pending state without making progress.
    private let pendingTimeout = TimeInterval(10)

    // Max amount of time in seconds a file can be in the valid or invalid state before rechecking.
    private let steadyStateTimeout = TimeInterval(60)

    // true: definitely valid
    // false: definitely invalid
    // nil: don't know
    override func commandIsValid(_ command: String) -> Bool? {
        switch knownCommands[command] {
        case .none:
            break
        case .pending(_, let time):
            if NSDate.it_timeSinceBoot() - time < pendingTimeout {
                return nil
            }
            // Expired
            knownCommands.removeValue(forKey: command)
        case .valid(let time):
            if NSDate.it_timeSinceBoot() - time < steadyStateTimeout {
                return true
            }
            // Expired
            knownCommands.removeValue(forKey: command)
        case .invalid(let time):
            if NSDate.it_timeSinceBoot() - time < steadyStateTimeout {
                return false
            }
            // Expired
            knownCommands.removeValue(forKey: command)
        }
        guard dataSource?.fileCheckerDataSourceCanPerformFileChecking ?? false else {
            return nil
        }
        guard let shell else {
            return nil
        }
        if command.hasPrefix("/") || command.hasPrefix("~") {
            knownCommands[command] = .pending(1, NSDate.it_timeSinceBoot())
            let candidate = command
            iTermSlowOperationGateway.sharedInstance().statFile(candidate) { [weak self] sb, error in
                self?.handleStatResult(command: command,
                                       path: candidate,
                                       stat: sb,
                                       error: error)
            }
            return nil
        }
        if let path {
            // There is a promised path
            if let obj = path.maybeValue {
                let pathsString = obj as String
                let paths = pathsString.components(separatedBy: ":")
                // We know the path, so search it
                knownCommands[command] = .pending(paths.count, NSDate.it_timeSinceBoot())
                for path in paths {
                    let candidate = path.appending(pathComponent: command)
                    iTermSlowOperationGateway.sharedInstance().statFile(candidate) { [weak self] sb, error in
                        self?.handleStatResult(command: command,
                                               path: candidate,
                                               stat: sb,
                                               error: error)
                    }
                }
            }  // else still waiting on promise
        } else {
            // Create a path promise
            path = iTermPromise({ seal in
                iTermSlowOperationGateway.sharedInstance().exfiltrateEnvironmentVariableNamed("PATH", shell: shell) { result in
                    seal.fulfill(result)
                }
            })
        }
        return nil
    }

    private func handleStatResult(command: String, path: String, stat sb: stat, error: Int32) {
        let valid: Bool
        if error == 0 {
            let entry = iTermDirectoryEntry(name: command, statBuf: sb)
            valid = entry.isExecutable && !entry.isDirectory && entry.isReadable
        } else {
            valid = false
        }
        let disposition: CommandValidity
        let now = NSDate.it_timeSinceBoot()
        if valid {
            disposition = .valid(now)
        } else {
            switch knownCommands[command] {
            case .pending(let n, _):
                if n - 1 > 0 {
                    // Allow other pending stat()s to finish. Maybe one of them will find it.
                    disposition = .pending(n - 1, now)
                } else {
                    // All failed to find it.
                    disposition = .invalid(now)
                }
            default:
                // If the status is valid, then this invalid result is irrelevant.
                // If the status is invalid or nil, probably this one timed out and a search restarted.
                return
            }
        }
        knownCommands[command] = disposition
        NotificationCenter.default.post(name: Self.commandValidityDidChange, object: command)
    }

    @objc static let commandValidityDidChange = NSNotification.Name("iTermLocalFileCheckerCommandValidityDidChange")
}
