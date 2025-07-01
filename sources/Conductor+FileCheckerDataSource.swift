//
//  Conductor+FileCheckerDataSource.swift
//  iTerm2
//
//  Created by George Nachman on 7/1/25.
//

@available(macOS 11, *)
@MainActor
extension Conductor: FileCheckerDataSource {
    func fileCheckerDataSourceDidReset() {
        parent?.fileChecker?.reset()
    }

    @objc
    var canCheckFiles: Bool {
        guard framing && delegate != nil else {
            return false
        }
        if case .unhooked = state {
            return false
        }
        return true
    }

    var fileCheckerDataSourceCanPerformFileChecking: Bool {
        return canCheckFiles
    }

    func fileCheckerDataSourceCheck(path: String, completion: @escaping (Bool) -> ()) {
        Task {
            let exists: Bool
            do {
                DLog("Really stat \(path)")
                _ = try await self.stat(path, highPriority: true)
                exists = true
            } catch {
                exists = false
            }
            DispatchQueue.main.async {
                completion(exists)
            }
        }
    }
}

