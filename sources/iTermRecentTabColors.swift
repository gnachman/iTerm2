import Foundation
import AppKit

@objc(iTermRecentTabColors)
class iTermRecentTabColors: NSObject {
    @objc static let shared = iTermRecentTabColors()

    private let userDefaultsKey = "NoSyncRecentTabColors"
    @objc let maxRecents = 14

    private override init() {
        super.init()
    }

    private var hexStrings: [String] {
        get {
            return UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
        }
    }

    @objc var recentColors: [NSColor] {
        return hexStrings.compactMap { NSColor(fromHexString: $0) }
    }

    /// Adds a color to the front of the recents list, deduplicating and capping at maxRecents.
    @objc func addColor(_ color: NSColor) {
        let hex = color.hexString()
        var list = hexStrings
        list.removeAll { $0 == hex }
        list.insert(hex, at: 0)
        if list.count > maxRecents {
            list = Array(list.prefix(maxRecents))
        }
        hexStrings = list
    }
}
