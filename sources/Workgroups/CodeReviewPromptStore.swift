//
//  CodeReviewPromptStore.swift
//  iTerm2SharedARC
//
//  Persistent collection of named code-review prompts. Replaces the
//  single kPreferenceKeyAIPromptCodeReview default — that key is read
//  once on first launch and migrated into the list as a “Default”
//  entry so users keep whatever they previously customized.
//

import Foundation

struct CodeReviewSavedPrompt: Codable, Equatable {
    var uuid: String
    var name: String
    var text: String

    init(uuid: String = UUID().uuidString,
         name: String,
         text: String) {
        self.uuid = uuid
        self.name = name
        self.text = text
    }
}

@objc(iTermCodeReviewPromptStore)
final class CodeReviewPromptStore: NSObject {
    @objc static let shared = CodeReviewPromptStore()

    // Posted when something visible from the pulldown menu list
    // changes — adds, removes, renames, reorders, undo-restores.
    // Body-only edits do NOT post this; observers that only render
    // the menu can subscribe to just this one and ignore per-keystroke
    // body updates from the manager window.
    @objc static let structureDidChangeNotification =
        Notification.Name("iTermCodeReviewPromptStoreStructureDidChange")

    // Posted when a prompt’s body text changes without affecting the
    // pulldown’s name list. Fires once per keystroke in the manager
    // window’s body editor — keep observers cheap.
    @objc static let bodyDidChangeNotification =
        Notification.Name("iTermCodeReviewPromptStoreBodyDidChange")

    private static let promptsKey = "CodeReviewSavedPrompts"
    private static let lastSelectedKey = "NoSyncCodeReviewLastSelectedPromptUUID"

    private(set) var prompts: [CodeReviewSavedPrompt]

    var lastSelectedUUID: String? {
        get {
            iTermUserDefaults.userDefaults().string(forKey: Self.lastSelectedKey)
        }
        set {
            let ud = iTermUserDefaults.userDefaults()
            if let newValue {
                ud.set(newValue, forKey: Self.lastSelectedKey)
            } else {
                ud.removeObject(forKey: Self.lastSelectedKey)
            }
        }
    }

    private override init() {
        let ud = iTermUserDefaults.userDefaults()
        if let data = ud.data(forKey: Self.promptsKey),
           let saved = try? JSONDecoder().decode([CodeReviewSavedPrompt].self,
                                                  from: data) {
            prompts = saved
        } else {
            // Migrate the legacy single-prompt default into a named
            // entry so the user’s customization survives the upgrade.
            let legacy = iTermPreferences.string(forKey: kPreferenceKeyAIPromptCodeReview) ?? ""
            let seedText = legacy.isEmpty ? Self.builtInDefaultText : legacy
            let seedName = "Default"
            prompts = [CodeReviewSavedPrompt(name: seedName, text: seedText)]
        }
        super.init()
        // Persist the migrated seed so next launch sees the new key.
        // First-launch seeding doesn’t need to fire either change
        // notification — no observers exist yet at this point.
        if ud.data(forKey: Self.promptsKey) == nil {
            persist()
        }
    }

    // The factory default text shipped with iTerm2. Falls back to the
    // empty string if the registered default disappears for some reason
    // — in practice iTermPreferences seeds it on +initialize.
    private static var builtInDefaultText: String {
        return iTermPreferences.string(forKey: kPreferenceKeyAIPromptCodeReview) ?? ""
    }

    private enum ChangeKind {
        case structure
        case body
    }

    private func setPrompts(_ newValue: [CodeReviewSavedPrompt],
                             kind: ChangeKind) {
        prompts = newValue
        persist()
        let name: Notification.Name
        switch kind {
        case .structure:
            name = Self.structureDidChangeNotification
        case .body:
            name = Self.bodyDidChangeNotification
        }
        NotificationCenter.default.post(name: name, object: self)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(prompts) {
            iTermUserDefaults.userDefaults().set(data, forKey: Self.promptsKey)
        }
    }

    // MARK: - Lookup

    func index(ofUUID uuid: String) -> Int? {
        return prompts.firstIndex { $0.uuid == uuid }
    }

    func prompt(uuid: String) -> CodeReviewSavedPrompt? {
        return prompts.first { $0.uuid == uuid }
    }

    // The prompt to preselect when an overlay opens: the one most
    // recently chosen, or the first one if that UUID no longer exists.
    @objc var defaultPromptText: String {
        if let uuid = lastSelectedUUID,
           let p = prompt(uuid: uuid) {
            return p.text
        }
        return prompts.first?.text ?? ""
    }

    // MARK: - Mutation

    @discardableResult
    func add(name: String, text: String) -> Int {
        var updated = prompts
        let entry = CodeReviewSavedPrompt(name: name, text: text)
        updated.append(entry)
        setPrompts(updated, kind: .structure)
        return updated.count - 1
    }

    func remove(at indexes: IndexSet) {
        var updated = prompts
        for i in indexes.sorted().reversed() where i >= 0 && i < updated.count {
            updated.remove(at: i)
        }
        setPrompts(updated, kind: .structure)
    }

    func reorder(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < prompts.count,
              destinationIndex >= 0, destinationIndex < prompts.count,
              sourceIndex != destinationIndex else {
            return
        }
        var updated = prompts
        let item = updated.remove(at: sourceIndex)
        updated.insert(item, at: destinationIndex)
        setPrompts(updated, kind: .structure)
    }

    func updateName(_ name: String, at index: Int) {
        guard index >= 0, index < prompts.count else { return }
        var updated = prompts
        updated[index].name = name
        // Names show up in the pulldown — structural change.
        setPrompts(updated, kind: .structure)
    }

    func updateText(_ text: String, at index: Int) {
        guard index >= 0, index < prompts.count else { return }
        var updated = prompts
        updated[index].text = text
        setPrompts(updated, kind: .body)
    }

    // Replace the entire collection — used by the CRUD undo path.
    // Treated as structural since names/order/count may all differ.
    func restore(_ entries: [CodeReviewSavedPrompt]) {
        setPrompts(entries, kind: .structure)
    }
}
