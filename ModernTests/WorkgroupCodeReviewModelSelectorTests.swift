//
//  WorkgroupCodeReviewModelSelectorTests.swift
//  ModernTests
//
//  Covers the Code Review Model toolbar item: the `codeReviewModelFlag`
//  template value, the toolbar-item model (Codable + registry), its presence
//  in the Claude Code preset, and the one-time backfill that adds it to
//  existing installs.
//

import XCTest
@testable import iTerm2SharedARC

final class WorkgroupCodeReviewModelSelectorTests: XCTestCase {

    // MARK: - Flag

    func test_flag_emptyForDefault() {
        XCTAssertEqual(WorkgroupCodeReviewModelSelectorItem.codeReviewModelFlag(
            for: WorkgroupCodeReviewModelSelectorItem.defaultModel), "")
    }

    func test_flag_emptyForBlank() {
        XCTAssertEqual(WorkgroupCodeReviewModelSelectorItem.codeReviewModelFlag(for: "  "), "")
    }

    func test_flag_quotesModel() {
        XCTAssertEqual(WorkgroupCodeReviewModelSelectorItem.codeReviewModelFlag(for: "opus"),
                       "--model 'opus'")
    }

    func test_flag_trimsAndEscapesShellMetacharacters() {
        XCTAssertEqual(WorkgroupCodeReviewModelSelectorItem.codeReviewModelFlag(for: " a'b;c "),
                       "--model 'a'\\''b;c'")
    }

    // MARK: - Default for new workgroups

    func test_defaultForNewWorkgroups_roundTripAndClear() {
        let key = "WorkgroupCodeReviewDefaultModel"
        let defaults = iTermUserDefaults.userDefaults()
        let saved = defaults.object(forKey: key)
        defer { defaults.set(saved, forKey: key) }

        WorkgroupCodeReviewModelSelectorItem.defaultModelForNewWorkgroups = "sonnet"
        XCTAssertEqual(WorkgroupCodeReviewModelSelectorItem.defaultModelForNewWorkgroups, "sonnet")
        WorkgroupCodeReviewModelSelectorItem.defaultModelForNewWorkgroups =
            WorkgroupCodeReviewModelSelectorItem.defaultModel
        XCTAssertNil(defaults.object(forKey: key), "Clearing removes the key")
        XCTAssertEqual(WorkgroupCodeReviewModelSelectorItem.defaultModelForNewWorkgroups,
                       WorkgroupCodeReviewModelSelectorItem.defaultModel)
    }

    // MARK: - Star button

    private final class RecordingDelegate: WorkgroupCodeReviewModelSelectorItemDelegate {
        var models: [String] = []
        func codeReviewModelDidChange(model: String,
                                      sender: WorkgroupCodeReviewModelSelectorItem) {
            models.append(model)
        }
    }

    // Typed-but-uncommitted text must be committed (reaching the delegate,
    // i.e. the workgroup's model) before the star can make it the default,
    // so the saved default never disagrees with the model the next review
    // uses.
    func test_star_commitsPendingEditBeforeSettingDefault() throws {
        let key = "WorkgroupCodeReviewDefaultModel"
        let defaults = iTermUserDefaults.userDefaults()
        let saved = defaults.object(forKey: key)
        let recentsKey = "NoSyncWorkgroupCodeReviewModelRecents"
        let savedRecents = defaults.object(forKey: recentsKey)
        defer {
            defaults.set(saved, forKey: key)
            defaults.set(savedRecents, forKey: recentsKey)
        }
        defaults.removeObject(forKey: key)

        let item = WorkgroupCodeReviewModelSelectorItem(identifier: "m", priority: 1)
        let delegate = RecordingDelegate()
        item.modelSelectorDelegate = delegate
        item.display("opus")
        let comboBox = try XCTUnwrap(item.view.subviewsRecursive.compactMap { $0 as? NSComboBox }.first)
        let star = try XCTUnwrap(item.view.subviewsRecursive.compactMap { $0 as? NSButton }
            .first { !($0 is NSComboBox) && $0.superview !== comboBox })

        comboBox.stringValue = "son"
        XCTAssertEqual(item.committedValue, "opus", "Typing alone doesn't commit")

        star.performClick(nil)
        XCTAssertEqual(delegate.models, ["son"], "The pending edit is committed first")
        XCTAssertEqual(item.committedValue, "son")
        XCTAssertEqual(WorkgroupCodeReviewModelSelectorItem.defaultModelForNewWorkgroups, "son")
    }

    // A fresh user (no saved default, field on `default`) starts with a
    // disabled star. Typing a name must enable it so the click can commit
    // the text and save it; otherwise they'd have to press Return first.
    func test_star_freshStateTypingEnablesAndSaves() throws {
        let key = "WorkgroupCodeReviewDefaultModel"
        let defaults = iTermUserDefaults.userDefaults()
        let saved = defaults.object(forKey: key)
        let recentsKey = "NoSyncWorkgroupCodeReviewModelRecents"
        let savedRecents = defaults.object(forKey: recentsKey)
        defer {
            defaults.set(saved, forKey: key)
            defaults.set(savedRecents, forKey: recentsKey)
        }
        defaults.removeObject(forKey: key)

        let item = WorkgroupCodeReviewModelSelectorItem(identifier: "m", priority: 1)
        let delegate = RecordingDelegate()
        item.modelSelectorDelegate = delegate
        let comboBox = try XCTUnwrap(item.view.subviewsRecursive.compactMap { $0 as? NSComboBox }.first)
        let star = try XCTUnwrap(item.view.subviewsRecursive.compactMap { $0 as? NSButton }
            .first { !($0 is NSComboBox) && $0.superview !== comboBox })
        XCTAssertFalse(star.isEnabled, "Nothing to do on a fresh `default`")

        comboBox.stringValue = "opus"
        // What the field posts on a keystroke.
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification,
                                        object: comboBox)
        XCTAssertTrue(star.isEnabled, "Typed text enables the star")

        star.performClick(nil)
        XCTAssertEqual(delegate.models, ["opus"])
        XCTAssertEqual(WorkgroupCodeReviewModelSelectorItem.defaultModelForNewWorkgroups, "opus")
    }

    // MARK: - Toolbar item model

    func test_codable_roundTrip() throws {
        let items: [iTermWorkgroupToolbarItem] = [.modeSwitcher, .codeReviewModelSelector]
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([iTermWorkgroupToolbarItem].self, from: data)
        XCTAssertEqual(decoded, items)
    }

    func test_registry_includesItem() {
        let metadata = iTermWorkgroupToolbarItemRegistry.metadata(
            forKind: .codeReviewModelSelector)
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?.hasParameters, false)
        XCTAssertEqual(metadata?.defaultValue, .codeReviewModelSelector)
    }

    func test_injectAutoItems_keepsItem() {
        let injected = WorkgroupToolbarBuilder.injectAutoItems(
            into: [.modeSwitcher, .reload(nil), .codeReviewModelSelector])
        XCTAssertTrue(injected.contains(.codeReviewModelSelector))
    }

    // MARK: - Preset

    func test_preset_reviewPeerHasItemAndVariable() {
        let wg = WorkgroupPresets.buildCodingAgentPlusDiffPlusCodeReview()
        let review = wg.sessions.first { $0.mode == .codeReview }
        XCTAssertNotNil(review)
        XCTAssertTrue(review!.toolbarItems.contains(.codeReviewModelSelector))
        XCTAssertTrue(review!.command.hasPrefix("claude \\(codeReviewModelFlag) \\(codeReviewPrompt)"))
    }

    // MARK: - Backfill transform

    private let legacyCommand =
        "claude \\(codeReviewPrompt) --append-system-prompt-file '\\(codeReviewSystemPromptFile)' --settings '\\(codeReviewSettingsFile)'"

    private func legacyClaudeCodeWorkgroup(
        workgroupID: String = ClaudeCodeWorkgroupTemplate.ID.workgroup,
        command: String? = nil,
        reviewItems: [iTermWorkgroupToolbarItem] = [.modeSwitcher, .reload(nil), .autoSendClippingsWhenIdle]
    ) -> iTermWorkgroup {
        let root = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.main,
            parentID: nil, kind: .root, profileGUID: nil, command: "",
            urlString: "", toolbarItems: [.modeSwitcher], displayName: "Chat")
        let review = iTermWorkgroupSessionConfig(
            uniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.review,
            parentID: ClaudeCodeWorkgroupTemplate.ID.main, kind: .peer,
            profileGUID: nil, command: command ?? legacyCommand, urlString: "",
            toolbarItems: reviewItems, displayName: "Code Review",
            mode: .codeReview)
        return iTermWorkgroup(uniqueIdentifier: workgroupID,
                              name: "Claude Code", sessions: [root, review])
    }

    private func review(_ workgroups: [iTermWorkgroup]?) -> iTermWorkgroupSessionConfig? {
        return workgroups?.first?.session(
            withUniqueIdentifier: ClaudeCodeWorkgroupTemplate.ID.review)
    }

    func test_backfill_addsItemAfterReloadAndVariable() {
        let migrated = iTermWorkgroupModel.addingModelSelectorToClaudeCodeReviewPeer(
            [legacyClaudeCodeWorkgroup()])
        XCTAssertEqual(review(migrated)?.toolbarItems,
                       [.modeSwitcher, .reload(nil), .codeReviewModelSelector, .autoSendClippingsWhenIdle])
        XCTAssertEqual(review(migrated)?.command,
                       "claude \\(codeReviewModelFlag) \\(codeReviewPrompt) --append-system-prompt-file '\\(codeReviewSystemPromptFile)' --settings '\\(codeReviewSettingsFile)'")
    }

    func test_backfill_appendsItemWithoutReload() {
        let migrated = iTermWorkgroupModel.addingModelSelectorToClaudeCodeReviewPeer(
            [legacyClaudeCodeWorkgroup(reviewItems: [.modeSwitcher])])
        XCTAssertEqual(review(migrated)?.toolbarItems, [.modeSwitcher, .codeReviewModelSelector])
    }

    func test_backfill_leavesCustomCommandAlone() {
        let custom = "my-reviewer \\(codeReviewPrompt)"
        let migrated = iTermWorkgroupModel.addingModelSelectorToClaudeCodeReviewPeer(
            [legacyClaudeCodeWorkgroup(command: custom)])
        XCTAssertEqual(review(migrated)?.command, custom)
        XCTAssertTrue(review(migrated)?.toolbarItems.contains(.codeReviewModelSelector) ?? false)
    }

    func test_backfill_leavesExistingModelFlagAlone() {
        let withModel = legacyCommand + " --model sonnet"
        let migrated = iTermWorkgroupModel.addingModelSelectorToClaudeCodeReviewPeer(
            [legacyClaudeCodeWorkgroup(command: withModel)])
        XCTAssertEqual(review(migrated)?.command, withModel)
    }

    func test_backfill_idempotent() {
        let once = iTermWorkgroupModel.addingModelSelectorToClaudeCodeReviewPeer(
            [legacyClaudeCodeWorkgroup()])
        XCTAssertNotNil(once)
        XCTAssertNil(iTermWorkgroupModel.addingModelSelectorToClaudeCodeReviewPeer(once!))
    }

    func test_backfill_ignoresNonClaudeCodeWorkgroup() {
        XCTAssertNil(iTermWorkgroupModel.addingModelSelectorToClaudeCodeReviewPeer(
            [legacyClaudeCodeWorkgroup(workgroupID: "some-other-workgroup")]))
    }
}

private extension NSView {
    var subviewsRecursive: [NSView] {
        return subviews + subviews.flatMap { $0.subviewsRecursive }
    }
}
