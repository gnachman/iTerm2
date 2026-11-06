//
//  WorkgroupCodeReviewModelSelectorItem.swift
//  iTerm2SharedARC
//

import AppKit

protocol WorkgroupCodeReviewModelSelectorItemDelegate: AnyObject {
    func codeReviewModelDidChange(model: String,
                                  sender: WorkgroupCodeReviewModelSelectorItem)
}

// Combo-box toolbar item for picking the model a code-review session's
// `claude` command runs with. The pick is exposed to the command template as
// `\(codeReviewModelFlag)` (see codeReviewModelFlag(for:)) and takes effect
// on the next review; it does not restart a review in progress. The presets
// are Claude Code's model aliases, which track the latest version of each
// family so the list doesn't go stale, and the field is editable so a full
// model ID works too. A star button after the field sets the model new
// workgroups start with (defaultModelForNewWorkgroups).
final class WorkgroupCodeReviewModelSelectorItem: WorkgroupRecentsComboBoxItem {
    weak var modelSelectorDelegate: WorkgroupCodeReviewModelSelectorItemDelegate?
    // Set by the workgroup builder so the delegate can demux which
    // peer's selector fired.
    var ownerPeerID: String?

    // Means “whatever claude would pick on its own,” so it produces no
    // --model flag at all rather than `--model default`, which would still
    // override a model set in the user's settings or environment.
    static let defaultModel = "default"

    // Posted when defaultModelForNewWorkgroups changes so every selector's
    // star reflects it, not just the one that was clicked.
    static let defaultModelForNewWorkgroupsDidChange =
        Notification.Name("iTermWorkgroupCodeReviewDefaultModelDidChange")

    private let defaultButton: NSButton

    // User-defaults key for defaultModelForNewWorkgroups. Not NoSync: it's
    // a real setting.
    private static let defaultModelForNewWorkgroupsKey = "WorkgroupCodeReviewDefaultModel"

    // The model a workgroup's code reviews use until someone picks another
    // in the toolbar. Set with the star button. Unset means defaultModel.
    static var defaultModelForNewWorkgroups: String {
        get {
            let saved = iTermUserDefaults.userDefaults().string(forKey: defaultModelForNewWorkgroupsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? defaultModel : saved
        }
        set {
            let defaults = iTermUserDefaults.userDefaults()
            if newValue == defaultModel {
                defaults.removeObject(forKey: defaultModelForNewWorkgroupsKey)
            } else {
                defaults.set(newValue, forKey: defaultModelForNewWorkgroupsKey)
            }
            NotificationCenter.default.post(name: defaultModelForNewWorkgroupsDidChange,
                                            object: nil)
        }
    }

    private static let configuration = WorkgroupRecentsComboBoxItem.Configuration(
        defaultValue: defaultModel,
        presets: ["fable", "opus", "sonnet", "haiku"],
        recentsKey: "NoSyncWorkgroupCodeReviewModelRecents")

    init(identifier: String, priority: Int) {
        defaultButton = NSButton(title: "", target: nil, action: nil)
        defaultButton.isBordered = false
        defaultButton.imagePosition = .imageOnly
        defaultButton.imageScaling = .scaleProportionallyDown
        defaultButton.refusesFirstResponder = true
        defaultButton.setButtonType(.momentaryPushIn)
        super.init(identifier: identifier,
                   priority: priority,
                   configuration: Self.configuration,
                   toolTip: String(localized: "WorkgroupCodeReviewModelSelector.ToolTip",
                                   defaultValue: "Model for the next code review",
                                   comment: "Tooltip for the toolbar combo box that picks which AI model a code review uses"),
                   accessory: defaultButton)
        defaultButton.target = self
        defaultButton.action = #selector(toggleDefault(_:))
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(defaultModelDidChange(_:)),
                                               name: Self.defaultModelForNewWorkgroupsDidChange,
                                               object: nil)
        updateDefaultButton()
    }

    override func committedValueDidChange() {
        updateDefaultButton()
    }

    override func pendingTextDidChange() {
        updateDefaultButtonEnabled()
    }

    @objc private func defaultModelDidChange(_ notification: Notification) {
        updateDefaultButton()
    }

    // Filled star: the committed model is what new workgroups start with.
    // Text still being typed doesn't change the star's look until it's
    // committed, but it does decide whether the star is enabled (see
    // updateDefaultButtonEnabled).
    // Clicking an outline star makes the shown model the default; clicking a
    // filled one clears the default. When the shown model is `default` and
    // no default is saved, the star is filled but disabled, since there's
    // nothing to clear.
    private func updateDefaultButton() {
        let current = committedValue
        let savedDefault = Self.defaultModelForNewWorkgroups
        let isDefault = current == savedDefault
        let image = NSImage(systemSymbolName: (isDefault ? SFSymbol.starFill : SFSymbol.star).rawValue,
                            accessibilityDescription: String(localized: "WorkgroupCodeReviewModelSelector.DefaultButton.AccessibilityDescription",
                                                             defaultValue: "Default model for new workgroups",
                                                             comment: "Accessibility description for the star button that sets the default code review model"))
        defaultButton.image = image
        updateDefaultButtonEnabled()
        defaultButton.contentTintColor = isDefault ? .controlAccentColor : .secondaryLabelColor
        if !isDefault {
            defaultButton.toolTip = String(localized: "WorkgroupCodeReviewModelSelector.DefaultButton.Make",
                                           defaultValue: "Use “\(current)” for code reviews in new workgroups",
                                           comment: "Tooltip for the star button when clicking it makes the shown model the default for new workgroups; the value is a model name such as opus")
        } else if savedDefault == Self.defaultModel {
            defaultButton.toolTip = String(localized: "WorkgroupCodeReviewModelSelector.DefaultButton.IsClaudeDefault",
                                           defaultValue: "New workgroups use Claude’s default model",
                                           comment: "Tooltip for the disabled star button: no default model is set, so claude picks its own")
        } else {
            defaultButton.toolTip = String(localized: "WorkgroupCodeReviewModelSelector.DefaultButton.Clear",
                                           defaultValue: "New workgroups use “\(current)”. Click to use Claude’s default model instead.",
                                           comment: "Tooltip for the filled star button: the shown model is the default for new workgroups, and clicking clears it; the value is a model name such as opus")
        }
    }

    // Disabled only when a click could do nothing: the field (including
    // any uncommitted text) says `default` and no default is saved. Uses the
    // live text so that typing a name over a disabled star enables it, and
    // the click reaches toggleDefault, which commits the text first.
    private func updateDefaultButtonEnabled() {
        defaultButton.isEnabled = !(currentValue == Self.defaultModel
                                    && Self.defaultModelForNewWorkgroups == Self.defaultModel)
    }

    @objc private func toggleDefault(_ sender: Any?) {
        // The button refuses first responder, so clicking it doesn't end
        // editing. Commit first so a half-typed name goes through the normal
        // path (recents, delegate, the workgroup's model) before it can
        // become the default.
        commitPendingEdit()
        let current = committedValue
        let newDefault = current == Self.defaultModelForNewWorkgroups ? Self.defaultModel : current
        RLog("WorkgroupCodeReviewModelSelectorItem: default model for new workgroups is now \(newDefault)")
        Self.defaultModelForNewWorkgroups = newDefault
    }

    override func valueDidCommit(_ value: String) {
        modelSelectorDelegate?.codeReviewModelDidChange(model: value, sender: self)
    }

    // The value of the `codeReviewModelFlag` template variable for `model`:
    // empty for the default, otherwise a shell-quoted --model argument.
    static func codeReviewModelFlag(for model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != defaultModel else {
            return ""
        }
        return "--model " + iTermWorkgroupSessionConfig.shellSingleQuoted(trimmed)
    }
}

