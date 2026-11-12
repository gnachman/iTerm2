import Foundation
import CoreFoundation

/// Real FSEvents smoke test; no app, UI, run-loop stream scheduling or user preferences.
private final class NativeWatcherProbe {
    let queue = DispatchQueue(label: "FileTreeWatcherNativeProbe")
    let roots: [URL]
    let changedFolder: URL
    var watcher: iTermFileTreeWatcher?
    weak var releasedWatcher: iTermFileTreeWatcher?
    var requestMicroseconds = [Double]()
    var registrationMilliseconds = [Double]()
    var finished = false

    init() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath, isDirectory: true).appendingPathComponent("file-tree-watch-" + UUID().uuidString)
        roots = [root.appendingPathComponent("a"), root.appendingPathComponent("b")]
        changedFolder = roots[1].appendingPathComponent("folder-🙂-测试")
        for path in roots { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true) }
        try FileManager.default.createDirectory(at: changedFolder, withIntermediateDirectories: true)
    }

    func run() {
        watcher = iTermFileTreeWatcher(queue: queue) { [weak self] root, paths in
            self?.events(root: root, paths: paths)
        }
        let began = DispatchTime.now().uptimeNanoseconds
        watcher?.watch(root: roots[0].path)
        requestMicroseconds.append(Double(DispatchTime.now().uptimeNanoseconds - began) / 1000)
        queue.async {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
            DispatchQueue.main.async { self.switchRoots(initialRegistration: elapsed) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if !self.finished { self.finish(success: false, reason: "Timed out waiting for native directory event") }
        }
    }

    private func switchRoots(initialRegistration: Double) {
        registrationMilliseconds.append(initialRegistration)
        let began = DispatchTime.now().uptimeNanoseconds
        // Superseded queued roots must not require registration before the current root.
        watcher?.watch(root: roots[1].path)
        watcher?.watch(root: roots[0].path)
        watcher?.watch(root: roots[1].path)
        watcher?.watch(root: roots[1].path)
        requestMicroseconds.append(Double(DispatchTime.now().uptimeNanoseconds - began) / 1000)
        queue.async {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
            do {
                try Data("native change".utf8).write(to: self.changedFolder.appendingPathComponent("new-file"))
                DispatchQueue.main.async { self.registrationMilliseconds.append(elapsed) }
            } catch {
                DispatchQueue.main.async { self.finish(success: false, reason: "Fixture write failed: \(error)") }
            }
        }
    }

    private func events(root: String, paths: [String]) {
        guard !finished else { return }
        guard Thread.isMainThread, root == roots[1].path else {
            finish(success: false, reason: "Obsolete root or off-main event delivered")
            return
        }
        guard paths.contains(changedFolder.path) else { return }
        finish(success: true, reason: "Native Unicode directory event reached current root on main")
    }

    private func finish(success: Bool, reason: String) {
        guard !finished else { return }
        finished = true
        let began = DispatchTime.now().uptimeNanoseconds
        watcher?.stop()
        requestMicroseconds.append(Double(DispatchTime.now().uptimeNanoseconds - began) / 1000)
        releasedWatcher = watcher
        watcher = nil
        let released = releasedWatcher == nil
        queue.async {
            // The worker cleanup is ahead of this marker; callbacks cannot retain the watcher.
            DispatchQueue.main.async {
                try? FileManager.default.removeItem(at: self.roots[0].deletingLastPathComponent())
                print(reason)
                print("Watch/switch/stop caller microseconds: \(self.requestMicroseconds)")
                print("Background registration queue elapsed milliseconds: \(self.registrationMilliseconds)")
                print("Watcher released immediately: \(released)")
                exit(success && released ? 0 : 1)
            }
        }
    }
}

@main
private struct NativeWatcherTest {
    static func main() throws {
        let probe = try NativeWatcherProbe()
        probe.run()
        withExtendedLifetime(probe) { CFRunLoopRun() }
    }
}
