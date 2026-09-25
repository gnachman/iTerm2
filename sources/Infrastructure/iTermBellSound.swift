//
//  iTermBellSound.swift
//  iTerm2SharedARC
//

import AppKit
import UniformTypeIdentifiers

// The sound a profile’s audible bell makes.
//
// A profile stores a short string under KEY_BELL_SOUND rather than a resolved
// sound, so that the setting keeps its meaning when the profile moves to another
// Mac:
//
//   ""                     the system alert sound, which is what the bell has
//                          always played
//   "Glass"                a sound installed in one of the Sounds folders,
//                          looked up by name
//   "/path/to/chime.m4a"   any audio file
//
@objc(iTermBellSound)
class iTermBellSound: NSObject {
    // The stored value meaning “play the system alert sound”.
    @objc static let systemAlertValue = ""

    // Posted on the main thread when a scan of the Sounds folders finds a different set of
    // sounds than the one before it.
    @objc static let installedSoundsDidChangeNotification = NSNotification.Name("iTermBellSoundInstalledSoundsDidChange")

    enum Source: Equatable {
        case systemAlert
        case named(String)
        case file(URL)
    }

    // The directories NSSound looks in, in the order it looks.
    static var soundDirectories: [String] {
        return [(NSHomeDirectory() as NSString).appendingPathComponent("Library/Sounds"),
                "/Library/Sounds",
                "/Network/Library/Sounds",
                "/System/Library/Sounds"]
    }

    static func source(of profileValue: String?) -> Source {
        guard let profileValue, !profileValue.isEmpty else {
            return .systemAlert
        }
        if profileValue.hasPrefix("/") || profileValue.hasPrefix("~") {
            return .file(URL(fileURLWithPath: (profileValue as NSString).expandingTildeInPath))
        }
        return .named(profileValue)
    }

    // What to show for a stored value in a menu. Empty for the system alert sound, whose
    // menu item is titled by the caller because that title is localized.
    @objc(displayNameForProfileValue:)
    static func displayName(forProfileValue profileValue: String?) -> String {
        switch source(of: profileValue) {
        case .systemAlert:
            return ""
        case .named(let name):
            return name
        case .file(let url):
            return url.deletingPathExtension().lastPathComponent
        }
    }

    // Whether a stored value names a sound that can actually be played right now. A
    // profile can outlive the file it points at, or the file can stop being audio, and a
    // stale value should be visible in Settings rather than silently ringing the default
    // bell. This asks the player itself, so Settings and the bell can’t disagree.
    @objc(profileValueIsPlayable:)
    static func isPlayable(profileValue: String?) -> Bool {
        return iTermBellSoundPlayer.shared.canPlay(profileValue: profileValue)
    }

    // MARK: - The installed sounds

    // The audio files in the Sounds folders as of one scan.
    struct Catalog {
        struct Entry: Equatable {
            // Index into the directories scanned. Lower wins.
            var precedence: Int
            var url: URL
        }

        // Every audio file found, keyed by name, highest precedence first.
        private(set) var entriesByName = [String: [Entry]]()

        // One name per sound, in display order.
        var names: [String] {
            return entriesByName.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        init() {}

        // Lists the directories without loading any of the files: deciding from the
        // extension whether NSSound can play a file is enough for a menu, and loading them
        // would decode, and through NSSound’s name table permanently retain, every sound
        // installed.
        init(directories: [String], fileManager: FileManager = .default) {
            let playableTypes = NSSound.soundUnfilteredTypes.compactMap { UTType($0) }
            for (precedence, directory) in directories.enumerated() {
                let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
                guard let filenames = try? fileManager.contentsOfDirectory(atPath: directory) else {
                    continue
                }
                for filename in filenames.sorted() where !filename.hasPrefix(".") {
                    let url = directoryURL.appendingPathComponent(filename)
                    guard let type = UTType(filenameExtension: url.pathExtension),
                          playableTypes.contains(where: { type.conforms(to: $0) }) else {
                        continue
                    }
                    let name = url.deletingPathExtension().lastPathComponent
                    guard !name.isEmpty else {
                        continue
                    }
                    entriesByName[name, default: []].append(
                        Entry(precedence: precedence,
                              url: url.resolvingSymlinksInPath().standardizedFileURL))
                }
            }
        }

        // The value to store for a file the user chose. A file sitting in a Sounds folder
        // is stored by name because NSSound can find it again from the name alone, and a
        // name survives a move to a Mac whose home directory is somewhere else. But only
        // when the name leads back to this very file: NSSound takes the first folder that
        // has the name, so ~/Library/Sounds/Glass.aiff shadows the system’s Glass, and two
        // files differing only in extension leave it unclear which one plays. In those cases
        // store the path so the bell plays what was picked.
        func profileValue(for url: URL, bundle: Bundle = .main) -> String {
            let chosen = url.resolvingSymlinksInPath().standardizedFileURL
            let name = chosen.deletingPathExtension().lastPathComponent
            if bundle.path(forSoundResource: name) == nil,
               let winners = filesNSSoundWouldSearchFirst(forName: name),
               winners.count == 1,
               winners[0] == chosen {
                return name
            }
            return chosen.path
        }

        // The files named `name` in the first folder that has any.
        private func filesNSSoundWouldSearchFirst(forName name: String) -> [URL]? {
            guard let entries = entriesByName[name],
                  let first = entries.map(\.precedence).min() else {
                return nil
            }
            return entries.filter { $0.precedence == first }.map(\.url)
        }
    }

    // Main thread only.
    private static var catalog = Catalog()
    private static var scanInProgress = false
    private static var rescanNeeded = false
    private static var scanCompletions = [(Catalog) -> Void]()
    private static let scanQueue = DispatchQueue(label: "com.iterm2.bell-sound-scan", qos: .userInitiated)

    // Names of the sounds installed in the Sounds folders as of the last scan, in display
    // order. Empty until the first scan finishes; see refreshInstalledSounds().
    @objc
    static var installedSoundNames: [String] {
        dispatchPrecondition(condition: .onQueue(.main))
        return catalog.names
    }

    // Rescans the Sounds folders. The scan runs off the main thread because
    // /Network/Library/Sounds is an automount trigger that can block for a long time, and
    // posts installedSoundsDidChangeNotification if the sounds changed.
    @objc
    static func refreshInstalledSounds() {
        refreshInstalledSounds(completion: nil)
    }

    // Works out what to store for a file the user chose, against a fresh scan of the
    // Sounds folders so that a file added since the last scan can’t shadow it unnoticed.
    // Calls the completion block on the main thread.
    @objc(profileValueForURL:completion:)
    static func profileValue(for url: URL, completion: @escaping (String) -> Void) {
        refreshInstalledSounds { catalog in
            completion(catalog.profileValue(for: url))
        }
    }

    private static func refreshInstalledSounds(completion: ((Catalog) -> Void)?) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let completion {
            scanCompletions.append(completion)
        }
        if scanInProgress {
            // The scan under way may already have passed a folder that just changed.
            rescanNeeded = true
            return
        }
        scanInProgress = true
        let directories = soundDirectories
        scanQueue.async {
            let scanned = Catalog(directories: directories)
            DispatchQueue.main.async {
                iTermBellSound.scanDidFinish(scanned)
            }
        }
    }

    private static func scanDidFinish(_ scanned: Catalog) {
        dispatchPrecondition(condition: .onQueue(.main))
        scanInProgress = false
        let changed = scanned.names != catalog.names
        catalog = scanned
        if rescanNeeded {
            rescanNeeded = false
            refreshInstalledSounds(completion: nil)
        } else {
            let completions = scanCompletions
            scanCompletions = []
            for completion in completions {
                completion(scanned)
            }
        }
        if changed {
            NotificationCenter.default.post(name: installedSoundsDidChangeNotification, object: nil)
        }
    }
}

// Plays profiles’ bell sounds. Sessions share one player so that a sound is decoded
// once rather than once per session, and so that a burst of bells from one session
// does not pile up. Main thread only, like the rest of the bell path.
@objc(iTermBellSoundPlayer)
class iTermBellSoundPlayer: NSObject {
    @objc(sharedInstance) static let shared = iTermBellSoundPlayer()

    // What a file looked like when its sound was loaded, to tell whether it has since been
    // replaced, rewritten, or deleted.
    struct FileIdentity: Equatable {
        var device: dev_t
        var inode: ino_t
        var size: off_t
        var modificationTime: timespec
        var statusChangeTime: timespec

        init?(url: URL) {
            var info = stat()
            guard stat(url.path, &info) == 0 else {
                return nil
            }
            device = info.st_dev
            inode = info.st_ino
            size = info.st_size
            modificationTime = info.st_mtimespec
            statusChangeTime = info.st_ctimespec
        }

        static func == (lhs: FileIdentity, rhs: FileIdentity) -> Bool {
            return (lhs.device == rhs.device &&
                    lhs.inode == rhs.inode &&
                    lhs.size == rhs.size &&
                    lhs.modificationTime.tv_sec == rhs.modificationTime.tv_sec &&
                    lhs.modificationTime.tv_nsec == rhs.modificationTime.tv_nsec &&
                    lhs.statusChangeTime.tv_sec == rhs.statusChangeTime.tv_sec &&
                    lhs.statusChangeTime.tv_nsec == rhs.statusChangeTime.tv_nsec)
        }
    }

    private struct CachedSound {
        var sound: NSSound
        // Nil for a sound NSSound found by name.
        var fileIdentity: FileIdentity?
    }

    // The number of distinct sounds in play at once is bounded by the number of profiles,
    // but cap it anyway so that a profile edited over and over can’t retain every sound
    // it ever named.
    private static let maximumCachedSounds = 16
    private var cache = [String: CachedSound]()
    // The keys of `cache`, least recently used first.
    private var recency = [String]()

    @objc(playProfileValue:)
    func play(profileValue: String?) {
        let source = iTermBellSound.source(of: profileValue)
        guard let profileValue, source != .systemAlert else {
            NSSound.beep()
            return
        }
        guard let sound = sound(forProfileValue: profileValue, source: source) else {
            // The sound named by the profile is gone. Ring the ordinary bell rather than
            // nothing: a missing file shouldn’t mean a silent terminal.
            DLog("Beep: can’t load bell sound \(profileValue); using the system alert sound")
            NSSound.beep()
            return
        }
        // A bell that lands while the last one is still playing restarts it, so that a
        // burst of bells sounds like a burst instead of one long note.
        if sound.isPlaying {
            sound.stop()
        }
        sound.play()
    }

    // Whether play(profileValue:) would play the sound the value names rather than falling
    // back to the system alert sound.
    func canPlay(profileValue: String?) -> Bool {
        let source = iTermBellSound.source(of: profileValue)
        guard let profileValue, source != .systemAlert else {
            return true
        }
        return sound(forProfileValue: profileValue, source: source) != nil
    }

    private func sound(forProfileValue profileValue: String,
                       source: iTermBellSound.Source) -> NSSound? {
        let fileIdentity: FileIdentity?
        switch source {
        case .systemAlert:
            return nil
        case .named:
            fileIdentity = nil
        case .file(let url):
            guard let identity = FileIdentity(url: url) else {
                forget(profileValue)
                return nil
            }
            fileIdentity = identity
        }
        if let cached = cache[profileValue] {
            if cached.fileIdentity == fileIdentity {
                recency.removeAll { $0 == profileValue }
                recency.append(profileValue)
                return cached.sound
            }
            // The file changed since it was loaded.
            forget(profileValue)
        }
        let loaded: NSSound?
        switch source {
        case .systemAlert:
            loaded = nil
        case .named(let name):
            loaded = NSSound(named: name)
        case .file(let url):
            loaded = NSSound(contentsOf: url, byReference: false)
        }
        guard let loaded else {
            return nil
        }
        cache[profileValue] = CachedSound(sound: loaded, fileIdentity: fileIdentity)
        recency.append(profileValue)
        evictIfNeeded()
        return loaded
    }

    private func forget(_ profileValue: String) {
        cache.removeValue(forKey: profileValue)
        recency.removeAll { $0 == profileValue }
    }

    // Drops the least recently used sounds until the cache is back under its cap. A sound
    // that is playing is skipped because releasing the last reference to an NSSound stops
    // it mid-note; the cache can run over the cap until it finishes. The most recent entry
    // is the one just asked for, so it is never a candidate.
    private func evictIfNeeded() {
        var i = 0
        while cache.count > Self.maximumCachedSounds && i < recency.count - 1 {
            let key = recency[i]
            if cache[key]?.sound.isPlaying == true {
                i += 1
                continue
            }
            recency.remove(at: i)
            cache.removeValue(forKey: key)
        }
    }
}
