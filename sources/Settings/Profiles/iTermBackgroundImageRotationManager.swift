import AppKit
import UniformTypeIdentifiers

/// Rotates through images in a folder at a fixed cadence. Sessions retain an
/// instance; instances with the same (folder, interval) are shared via a
/// weakly-held registry so panes using the same configuration stay in sync.
/// When the last session releases it, the rotator deallocates and its timer
/// invalidates.
@objc(iTermBackgroundImageRotationManager)
class iTermBackgroundImageRotationManager: NSObject {

    @objc
    static let didChangeNotification = NSNotification.Name("iTermBackgroundImageRotationManagerDidChangeNotification")

    @objc static let minimumInterval: TimeInterval = 5

    @objc let folder: String
    @objc let interval: TimeInterval
    @objc var currentImage: String? { deck.current }

    private let deck = ShuffleDeck()
    private var timer: Timer?
    private var generation: UInt = 0

    private static let scanQueue = DispatchQueue(label: "com.iterm2.background-rotation-scan", qos: .utility)

    // MARK: - Registry

    private struct Key: Hashable {
        let folder: String
        let interval: TimeInterval
    }

    private static var registry: [Key: WeakBox<iTermBackgroundImageRotationManager>] = [:]

    /// Returns a rotator for the given folder and interval, reusing a live
    /// instance if any session is still holding one. The caller must retain
    /// the return value for as long as rotation should continue.
    @objc(sharedRotatorForFolder:interval:)
    static func sharedRotator(forFolder folder: String, interval: TimeInterval) -> iTermBackgroundImageRotationManager {
        dispatchPrecondition(condition: .onQueue(.main))
        let key = Key(folder: folder, interval: max(interval, minimumInterval))
        if let live = registry[key]?.value {
            return live
        }
        let rotator = iTermBackgroundImageRotationManager(folder: key.folder, interval: key.interval)
        registry[key] = WeakBox(rotator)
        return rotator
    }

    /// Returns the first image in the folder (locale-aware by filename) without
    /// creating or using a rotator. Used by the preferences UI for preview so
    /// the preview is stable across app launches.
    @objc
    static func firstImagePath(inFolder folder: String?) -> String? {
        guard let folder, !folder.isEmpty else {
            return nil
        }
        return imagePaths(inFolder: folder).min { lhs, rhs in
            (lhs as NSString).lastPathComponent.localizedStandardCompare((rhs as NSString).lastPathComponent) == .orderedAscending
        }
    }

    // MARK: - Init / deinit

    private init(folder: String, interval: TimeInterval) {
        self.folder = folder
        self.interval = interval
        super.init()
        dispatchPrecondition(condition: .onQueue(.main))
        deck.setPool(Self.imagePaths(inFolder: folder))
        deck.advance()
        scheduleTimer()
    }

    deinit {
        timer?.invalidate()
        // Drop our slot from the registry so it doesn't accumulate stale
        // WeakBox entries for every unique (folder, interval) ever used.
        // Dispatched to main so we don't mutate `registry` off the main queue
        // if the last release happens elsewhere.
        let key = Key(folder: folder, interval: interval)
        DispatchQueue.main.async {
            if let box = Self.registry[key], box.value == nil {
                Self.registry.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Timer

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // 10% tolerance lets the scheduler coalesce with other wake-ups. Precision
        // isn't important for a background image rotation.
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation &+= 1
        let gen = generation
        let folder = self.folder
        Self.scanQueue.async { [weak self] in
            let paths = Self.imagePaths(inFolder: folder)
            DispatchQueue.main.async {
                self?.scanCompleted(paths: paths, generation: gen)
            }
        }
    }

    private func scanCompleted(paths: [String], generation: UInt) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard generation == self.generation else {
            return
        }
        let previous = deck.current
        deck.setPool(paths)
        deck.advance()
        if deck.current != previous {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    // MARK: - Directory scanning (runs on background queue)

    private static func imagePaths(inFolder folder: String) -> [String] {
        let expandedPath = NSString(string: folder).expandingTildeInPath
        let folderURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var result: [String] = []
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            if isImageFile(url) {
                result.append(url.path)
            }
        }
        return result
    }

    private static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty {
            return false
        }
        guard let uttype = UTType(filenameExtension: ext) else {
            return false
        }
        return uttype.conforms(to: .image)
    }
}
