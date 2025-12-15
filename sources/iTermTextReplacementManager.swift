import Foundation

/// Minimal text replacement manager that applies macOS system text replacements.
/// This reads the user's text replacements from System Preferences > Keyboard > Text.
@objc(iTermTextReplacementManager)
public class iTermTextReplacementManager: NSObject {

    @objc public static let shared = iTermTextReplacementManager()

    /// Cached replacements: shortcut -> replacement
    private var replacements: [String: String] = [:]
    private var maxShortcutLength = 0
    private let observer = iTermUserDefaultsObserver()
    private var inserted = ""

    private override init() {
        super.init()
        loadReplacements()

        observer.observeKey("NSUserDictionaryReplacementItems") { [weak self] in
            self?.loadReplacements()
        }
        observer.observeKey("NSAutomaticTextReplacementEnabled") { [weak self] in
            self?.loadReplacements()
        }
    }
}

extension iTermTextReplacementManager {
    // Track what the user has typed so we only do replacement when inserting text.
    @objc(didInsert:)
    func didInsert(_ string: String) {
        if maxShortcutLength == 0 {
            return
        }
        inserted.append(string)
        let overage = inserted.count - maxShortcutLength
        if overage > 0 {
            inserted.removeFirst(overage)
        }
    }

    @objc var anyReplacementIsEligible: Bool {
        return replacements.keys.contains {
            shouldReplace(shortcut: $0)
        }
    }

    @objc(shouldReplaceShortcut:)
    func shouldReplace(shortcut: String) -> Bool {
        return inserted.hasSuffix(shortcut)
    }

    @objc var hasReplacements: Bool {
        return !replacements.isEmpty
    }

    /// Apply text replacements to the given string.
    /// Only replaces complete matches (the entire input must match a shortcut).
    @objc public func applyReplacements(to text: String) -> String? {
        return replacements[text]
    }

    @objc(hasReplacementsWithSuffix:)
    public func hasReplacements(suffix: String) -> Bool {
        return replacements.keys.contains { word in
            word.hasSuffix(suffix)
        }
    }
    // MARK: - Private

    private func loadReplacements() {
        replacements.removeAll()
        inserted = ""

        // NSUserDictionaryReplacementItems is an array of dictionaries with "on", "replace", "with" keys
        guard let items = UserDefaults.standard.array(forKey: "NSUserDictionaryReplacementItems") as? [[String: Any]] else {
            return
        }

        for item in items {
            // "on" indicates if this replacement is enabled (1 = enabled)
            let isEnabled = (item["on"] as? Int) == 1
            guard isEnabled,
                  let shortcut = item["replace"] as? String,
                  let replacement = item["with"] as? String else {
                continue
            }
            replacements[shortcut] = replacement
        }
        maxShortcutLength = replacements.keys.map(\.count).max() ?? 0
    }
}

