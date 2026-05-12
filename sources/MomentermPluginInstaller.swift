//
//  MomentermPluginInstaller.swift
//  iTerm2
//
//  Runs the install shell command for a plugin/MCP item via /bin/zsh -lc,
//  streams stdout/stderr to a progress callback, and posts completion on
//  the main queue. Installation is serialized so two clicks can't race.
//

import Foundation

@objc final class MomentermPluginInstaller: NSObject {

    @objc static let shared = MomentermPluginInstaller()

    enum Status: Equatable {
        case idle
        case installing
        case installed
        case failed(String)

        var isTerminal: Bool {
            switch self {
            case .installed, .failed: return true
            default: return false
            }
        }
    }

    private let serialQueue = DispatchQueue(label: "com.momenterm.plugin-installer")
    private var statusByKey: [String: Status] = [:]
    private let statusLock = NSLock()

    private override init() {
        super.init()
    }

    // MARK: - Public API

    func status(forKey key: String) -> Status {
        statusLock.lock()
        defer { statusLock.unlock() }
        return statusByKey[key] ?? .idle
    }

    /// Run `item.install` via zsh in a login shell so PATH includes
    /// homebrew / npm globals. Progress is delivered on the main queue.
    func install(item: MomentermPluginItem,
                 progress: @escaping (String) -> Void,
                 completion: @escaping (Bool, String) -> Void) {
        let key = Self.key(for: item)
        setStatus(.installing, forKey: key)

        serialQueue.async { [weak self] in
            guard let self = self else { return }
            let (success, log) = Self.runCommand(item.install) { line in
                DispatchQueue.main.async { progress(line) }
            }
            let finalStatus: Status = success ? .installed : .failed(log)
            self.setStatus(finalStatus, forKey: key)
            DispatchQueue.main.async { completion(success, log) }
        }
    }

    // MARK: - Helpers

    static func key(for item: MomentermPluginItem) -> String {
        return "\(item.kind == .mcp ? "mcp" : "plugin"):\(item.id)"
    }

    private func setStatus(_ status: Status, forKey key: String) {
        statusLock.lock()
        statusByKey[key] = status
        statusLock.unlock()
    }

    private static func runCommand(_ command: String,
                                   onLine: @escaping (String) -> Void) -> (Bool, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var collected = ""
        let collectLock = NSLock()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            collectLock.lock()
            collected += text
            collectLock.unlock()
            for line in text.split(whereSeparator: { $0.isNewline }) {
                onLine(String(line))
            }
        }

        do {
            try process.run()
        } catch {
            return (false, "Failed to launch: \(error.localizedDescription)")
        }

        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil

        // Drain any remaining buffered data after process exit.
        let remaining = pipe.fileHandleForReading.availableData
        if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
            collectLock.lock()
            collected += text
            collectLock.unlock()
        }

        let success = process.terminationStatus == 0
        return (success, collected)
    }
}
