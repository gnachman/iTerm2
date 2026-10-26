//
//  PTYSession+CodeReviewPromptMigration.swift
//  iTerm2SharedARC
//
//  Offers to bring a customized code review system prompt up to date (CodeReviewPromptMigration),
//  the first time a code review starts with one, rather than at launch: that is when it matters.
//  The user sees what would change and decides; Keep My Prompt is remembered for that text.
//

import AppKit

extension PTYSession {
    /// The remembered choice to keep a prompt, by its hash. NoSync: it is state, not a setting.
    private static let keptCodeReviewPromptKey = "NoSyncCodeReviewPromptKeptHash"
    /// Whether any session's offer is on screen.
    private static var codeReviewPromptOfferShowing = false

    /// Calls `proceed` once the user has been offered an update to the code review system prompt
    /// and answered, or at once when there is nothing to offer. The review then runs with
    /// whatever the setting holds.
    ///
    /// The automatic request never asks: it runs unattended, often for a peer not in view, and
    /// must not put up a modal. The next start by the user asks.
    ///
    /// One offer at a time, app-wide: a review that starts elsewhere meanwhile runs with the
    /// prompt as it is rather than asking a second time.
    func offerCodeReviewPromptUpdateIfNeeded(then proceed: @escaping () -> Void) {
        guard !swiftState.codeReviewAutoRequesting, !Self.codeReviewPromptOfferShowing else {
            proceed()
            return
        }
        let defaults = iTermUserDefaults.userDefaults()
        let key = kPreferenceKeyAIPromptCodeReviewSystem
        guard let currentDefault = iTermPreferences.defaultObject(forKey: key) as? String else {
            proceed()
            return
        }
        let outcome = CodeReviewPromptMigration.decide(
            stored: defaults.object(forKey: key) as? String,
            currentDefault: currentDefault,
            keptHash: defaults.string(forKey: Self.keptCodeReviewPromptKey)) { [weak self] stored, proposal in
                guard let self else {
                    return .undecided
                }
                RLog("PTYSession[\(self.guid)]: offering to update the customized code review prompt (reset=\(proposal.resetsToDefault))")
                self.swiftState.codeReviewPromptOfferInProgress = true
                Self.codeReviewPromptOfferShowing = true
                defer {
                    self.swiftState.codeReviewPromptOfferInProgress = false
                    Self.codeReviewPromptOfferShowing = false
                }
                return self.askToUpdateCodeReviewPrompt(from: stored, to: proposal)
            }
        if let prompt = outcome.prompt {
            iTermPreferences.setObject(prompt, forKey: key)
            RLog("PTYSession[\(guid)]: code review prompt updated")
        }
        if let keptHash = outcome.keptHash {
            defaults.set(keptHash, forKey: Self.keptCodeReviewPromptKey)
            RLog("PTYSession[\(guid)]: user kept their code review prompt")
        }
        proceed()
    }

    private func askToUpdateCodeReviewPrompt(from stored: String,
                                             to proposal: CodeReviewPromptMigration.Proposal) -> CodeReviewPromptMigration.Answer {
        let warning = iTermWarning()
        warning.heading = String(localized: "CodeReviewPromptUpdate.Heading",
                                 defaultValue: "Update Your Code Review Prompt?",
                                 comment: "Heading of the offer to update a customized code review system prompt")
        let changes = String(localized: "CodeReviewPromptUpdate.Changes",
                             defaultValue: "The default prompt has changed since then: it runs iTerm2\u{2019}s own it2 command, so reviews work on remote hosts without a current shell integration install, and it tells it2 which tmux pane the review runs in, so reviews work in tmux.",
                             comment: "Explains the two changes to the default code review system prompt that an update brings")
        if proposal.resetsToDefault {
            warning.title = String(localized: "CodeReviewPromptUpdate.ResetBody",
                                   defaultValue: "Your Code Review system prompt in Settings > General > AI > Prompts is a saved copy of an older default.",
                                   comment: "Body of the offer to update a code review system prompt that is a copy of an older default") +
                "\n\n" + changes + "\n\n" +
                String(localized: "CodeReviewPromptUpdate.ResetAction",
                       defaultValue: "Update Prompt replaces it with the current default, which then stays up to date.",
                       comment: "What updating a code review system prompt that is a copy of an older default does")
        } else {
            warning.title = String(localized: "CodeReviewPromptUpdate.MigrateBody",
                                   defaultValue: "You customized your Code Review system prompt in Settings > General > AI > Prompts.",
                                   comment: "Body of the offer to update a customized code review system prompt") +
                "\n\n" + changes + "\n\n" +
                String(localized: "CodeReviewPromptUpdate.MigrateAction",
                       defaultValue: "Update Prompt makes only the changes shown below. The rest of your prompt stays as you wrote it.",
                       comment: "What updating a customized code review system prompt does")
        }
        warning.accessory = Self.codeReviewPromptDiffView(from: stored, to: proposal.text)
        let keep = String(localized: "CodeReviewPromptUpdate.Keep",
                          defaultValue: "Keep My Prompt",
                          comment: "Button that keeps a customized code review system prompt as it is")
        let update = String(localized: "CodeReviewPromptUpdate.Update",
                            defaultValue: "Update Prompt",
                            comment: "Button that updates a customized code review system prompt")
        warning.actionLabels = [update, keep]
        // iTerm2 Buddy can't show what would change, so updating is chosen only here.
        warning.notOfferedRemotelyLabels = [update]
        warning.warningType = .kiTermWarningTypePersistent
        warning.window = view?.window
        switch warning.runModal() {
        case .kiTermWarningSelection0:
            return .update
        case .kiTermWarningSelection1:
            return .keep
        default:
            return .undecided
        }
    }

    /// The lines that change, each removed line followed by what replaces it, in a scrolling
    /// monospace view.
    private static func codeReviewPromptDiffView(from old: String, to new: String) -> NSView {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let text = NSMutableAttributedString()
        for (removed, line) in Self.changedLines(from: old, to: new) {
            text.append(NSAttributedString(string: (removed ? "\u{2212} " : "+ ") + line + "\n",
                                           attributes: [.font: font,
                                                        .foregroundColor: removed ? NSColor.systemRed : NSColor.systemGreen]))
        }
        let size = NSSize(width: 520, height: 180)
        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(text)
        scrollView.documentView = textView
        return scrollView
    }

    /// The lines that differ, in the order they appear: walking both texts together, the old
    /// lines removed at each point, then the new ones that take their place.
    static func changedLines(from old: String, to new: String) -> [(removed: Bool, line: String)] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        let difference = newLines.difference(from: oldLines)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                removed.insert(offset)
            case .insert(let offset, _, _):
                inserted.insert(offset)
            }
        }
        var result = [(removed: Bool, line: String)]()
        var i = 0
        var j = 0
        while i < oldLines.count || j < newLines.count {
            if i < oldLines.count && removed.contains(i) {
                result.append((true, oldLines[i]))
                i += 1
            } else if j < newLines.count && inserted.contains(j) {
                result.append((false, newLines[j]))
                j += 1
            } else {
                i += 1
                j += 1
            }
        }
        return result
    }
}
