import AppKit
import UniformTypeIdentifiers

@objc(iTermBackgroundImageRotationManager)
class iTermBackgroundImageRotationManager: NSObject {

    @objc(sharedInstance)
    static let instance = iTermBackgroundImageRotationManager()

    @objc
    static let didChangeNotification = NSNotification.Name("iTermBackgroundImageRotationDidChangeNotification")

    private static let minimumInterval: TimeInterval = 5

    private var states: [String: RotationState] = [:]

    private let scanQueue = DispatchQueue(label: "com.iterm2.background-rotation-scan", qos: .utility)

    // MARK: - Public API (main thread only)

    @objc
    func backgroundImagePath(forProfile profile: NSDictionary) -> String? {
        it_assert(Thread.isMainThread)
        guard let guid = effectiveGUID(for: profile), !guid.isEmpty else {
            return nil
        }
        let mode = iTermProfilePreferences.unsignedInteger(forKey: KEY_BACKGROUND_IMAGE_SOURCE_MODE,
                                                           inProfile: profile as! [AnyHashable: Any])
        if mode != iTermBackgroundImageSourceMode.folderRotation.rawValue {
            return profile[KEY_BACKGROUND_IMAGE_LOCATION] as? String
        }
        if let state = states[guid] {
            return state.currentImage
        }
        // First access — synchronous scan so the caller gets an image immediately.
        let state = getOrCreateState(for: profile)
        if let folder = state.folder, !folder.isEmpty {
            state.cachedPaths = Self.sortedImagePaths(inFolder: folder)
            selectNextImage(for: state)
        }
        reconfigureTimer(for: state)
        return state.currentImage
    }

    @objc
    func profileDidChange(_ profile: NSDictionary) {
        it_assert(Thread.isMainThread)
        guard let guid = effectiveGUID(for: profile), !guid.isEmpty else {
            return
        }
        let mode = iTermProfilePreferences.unsignedInteger(forKey: KEY_BACKGROUND_IMAGE_SOURCE_MODE,
                                                           inProfile: profile as! [AnyHashable: Any])
        if mode != iTermBackgroundImageSourceMode.folderRotation.rawValue {
            invalidateState(forGUID: guid)
            return
        }
        let folder = iTermProfilePreferences.string(forKey: KEY_BACKGROUND_IMAGE_FOLDER_LOCATION,
                                                    inProfile: profile as! [AnyHashable: Any])
        let rawInterval = iTermProfilePreferences.integer(forKey: KEY_BACKGROUND_IMAGE_FOLDER_INTERVAL,
                                                          inProfile: profile as! [AnyHashable: Any])
        let interval = max(TimeInterval(rawInterval), Self.minimumInterval)

        let state = getOrCreateState(for: profile)
        let folderChanged = state.folder != folder
        let intervalChanged = state.interval != interval

        if folderChanged {
            state.folder = folder
            state.cachedPaths = []
            state.deck = []
            state.currentImage = nil
            // Synchronous scan so we have an image immediately
            if let folder, !folder.isEmpty {
                state.cachedPaths = Self.sortedImagePaths(inFolder: folder)
                selectNextImage(for: state)
            }
            postDidChange(forGUID: guid)
        }
        if intervalChanged {
            state.interval = interval
        }
        if folderChanged || intervalChanged || state.timer == nil {
            reconfigureTimer(for: state)
        }
    }

    /// Shared helper for scanning a folder and returning the first valid image path.
    /// Used by both the rotation manager and the preferences UI for preview.
    @objc
    static func firstImagePath(inFolder folder: String?) -> String? {
        guard let folder, !folder.isEmpty else {
            return nil
        }
        let paths = sortedImagePaths(inFolder: folder)
        return paths.first
    }

    // MARK: - Per-profile state

    private class RotationState {
        let guid: String
        var folder: String?
        var interval: TimeInterval
        var currentImage: String?
        var deck: [String] = []
        var timer: Timer?
        var cachedPaths: [String] = []
        var generation: UInt = 0

        init(guid: String) {
            self.guid = guid
            self.interval = iTermBackgroundImageRotationManager.minimumInterval
        }
    }

    // MARK: - State management

    /// Use the original (shared) profile GUID so divorced sessions share the
    /// same rotation state as non-divorced ones on the same profile.
    private func effectiveGUID(for profile: NSDictionary) -> String? {
        return (profile[KEY_ORIGINAL_GUID] as? String) ?? (profile[KEY_GUID] as? String)
    }

    private func getOrCreateState(for profile: NSDictionary) -> RotationState {
        let guid = effectiveGUID(for: profile)!
        if let existing = states[guid] {
            return existing
        }
        let state = RotationState(guid: guid)
        let profileDict = profile as! [AnyHashable: Any]
        state.folder = iTermProfilePreferences.string(forKey: KEY_BACKGROUND_IMAGE_FOLDER_LOCATION,
                                                      inProfile: profileDict)
        let rawInterval = iTermProfilePreferences.integer(forKey: KEY_BACKGROUND_IMAGE_FOLDER_INTERVAL,
                                                          inProfile: profileDict)
        state.interval = max(TimeInterval(rawInterval), Self.minimumInterval)
        states[guid] = state
        return state
    }

    private func invalidateState(forGUID guid: String) {
        guard let state = states[guid] else {
            return
        }
        state.timer?.invalidate()
        state.timer = nil
        states.removeValue(forKey: guid)
    }

    // MARK: - Timer

    private func reconfigureTimer(for state: RotationState) {
        state.timer?.invalidate()
        state.timer = nil

        guard let folder = state.folder, !folder.isEmpty else {
            return
        }

        let guid = state.guid

        state.timer = Timer.scheduledTimer(withTimeInterval: state.interval, repeats: true) { [weak self] _ in
            self?.timerFired(forGUID: guid)
        }
    }

    private func timerFired(forGUID guid: String) {
        it_assert(Thread.isMainThread)
        guard let state = states[guid] else {
            return
        }
        triggerAsyncScan(for: state)
    }

    // MARK: - Async file scanning

    private func triggerAsyncScan(for state: RotationState) {
        guard let folder = state.folder, !folder.isEmpty else {
            return
        }
        state.generation &+= 1
        let generation = state.generation
        let guid = state.guid

        // Re-arm the timer so the next tick is a full interval from now
        if state.timer != nil {
            reconfigureTimer(for: state)
        }

        scanQueue.async { [weak self] in
            let paths = Self.sortedImagePaths(inFolder: folder)
            DispatchQueue.main.async {
                self?.scanCompleted(paths: paths, forGUID: guid, generation: generation)
            }
        }
    }

    private func scanCompleted(paths: [String], forGUID guid: String, generation: UInt) {
        it_assert(Thread.isMainThread)
        guard let state = states[guid], state.generation == generation else {
            return
        }
        state.cachedPaths = paths
        let previousImage = state.currentImage
        selectNextImage(for: state)
        if state.currentImage != previousImage {
            postDidChange(forGUID: guid)
        }
    }

    // MARK: - Image selection (deck shuffle)

    private func selectNextImage(for state: RotationState) {
        let images = state.cachedPaths
        if images.isEmpty {
            state.deck = []
            state.currentImage = nil
            return
        }
        if images.count == 1 {
            state.deck = []
            state.currentImage = images.first
            return
        }

        // Rebuild deck: keep existing deck entries that are still valid, add new ones
        var seen = Set<String>()
        var deck = [String]()
        for path in state.deck {
            if images.contains(path) && path != state.currentImage && !seen.contains(path) {
                deck.append(path)
                seen.insert(path)
            }
        }
        for path in images {
            if path != state.currentImage && !seen.contains(path) {
                deck.append(path)
                seen.insert(path)
            }
        }

        // If deck is empty, reshuffle all images except current
        if deck.isEmpty {
            deck = images.filter { $0 != state.currentImage }
            deck.shuffle()
        }

        let next = deck.first ?? state.currentImage ?? images.first
        if let next {
            deck.removeAll { $0 == next }
        }
        state.currentImage = next
        state.deck = deck
    }

    // MARK: - Directory scanning (runs on background queue)

    private static func sortedImagePaths(inFolder folder: String) -> [String] {
        let expandedPath = NSString(string: folder).expandingTildeInPath
        let folderURL = URL(fileURLWithPath: expandedPath, isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var result = [String]()
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            if isImageFile(url) {
                result.append(url.path)
            }
        }
        result.sort { lhs, rhs in
            (lhs as NSString).lastPathComponent.localizedStandardCompare((rhs as NSString).lastPathComponent) == .orderedAscending
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

    // MARK: - Notification

    private func postDidChange(forGUID guid: String) {
        it_assert(Thread.isMainThread)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: guid)
    }
}
