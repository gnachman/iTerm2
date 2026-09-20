//
//  iTermBellSound.swift
//  iTerm2SharedARC
//

import AppKit

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

    // The value to store for a file the user chose. A file sitting in a Sounds folder is
    // stored by name because NSSound can find it again from the name alone, and a name
    // survives a move to a Mac whose home directory is somewhere else.
    @objc(profileValueForURL:)
    static func profileValue(for url: URL) -> String {
        let standardized = url.resolvingSymlinksInPath().standardizedFileURL
        let name = standardized.deletingPathExtension().lastPathComponent
        let parent = standardized.deletingLastPathComponent().path
        if soundDirectories.contains(parent) && NSSound(named: name) != nil {
            return name
        }
        return standardized.path
    }

    // Names of the sounds installed in the Sounds folders, in display order. A name that
    // appears in more than one folder is listed once; NSSound decides which file wins.
    @objc
    static func installedSoundNames() -> [String] {
        var names = Set<String>()
        for directory in soundDirectories {
            let filenames = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            for filename in filenames where !filename.hasPrefix(".") {
                let name = (filename as NSString).deletingPathExtension
                if !name.isEmpty && NSSound(named: name) != nil {
                    names.insert(name)
                }
            }
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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
    // profile can outlive the file it points at, and a stale value should be visible in
    // Settings rather than silently ringing the default bell.
    @objc(profileValueIsPlayable:)
    static func isPlayable(profileValue: String?) -> Bool {
        switch source(of: profileValue) {
        case .systemAlert:
            return true
        case .named(let name):
            return NSSound(named: name) != nil
        case .file(let url):
            return FileManager.default.isReadableFile(atPath: url.path)
        }
    }
}

// Plays profiles’ bell sounds. Sessions share one player so that a sound is decoded
// once rather than once per session, and so that a burst of bells from one session
// does not pile up. Main thread only, like the rest of the bell path.
@objc(iTermBellSoundPlayer)
class iTermBellSoundPlayer: NSObject {
    @objc(sharedInstance) static let shared = iTermBellSoundPlayer()

    // The number of distinct sounds in play at once is bounded by the number of profiles,
    // but cap it anyway so that a profile edited over and over can’t retain every sound
    // it ever named.
    private static let maximumCachedSounds = 16
    private var cache = [String: NSSound]()
    private var leastRecentlyUsedFirst = [String]()

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

    private func sound(forProfileValue profileValue: String,
                       source: iTermBellSound.Source) -> NSSound? {
        if let cached = cache[profileValue] {
            return cached
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
        cache[profileValue] = loaded
        leastRecentlyUsedFirst.append(profileValue)
        while leastRecentlyUsedFirst.count > Self.maximumCachedSounds {
            cache.removeValue(forKey: leastRecentlyUsedFirst.removeFirst())
        }
        return loaded
    }
}
