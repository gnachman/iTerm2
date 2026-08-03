//
//  PTYSessionClipping+Formatting.swift
//  iTerm2SharedARC
//

import Foundation

extension PTYSessionClipping {
    // The text a clipping contributes when it is sent to a terminal:
    // "**title**\ndetail", or just the detail when the title is blank.
    // Shared by the Clippings panel's "Send to terminal" action and the
    // code-review auto-send-on-idle toolbar toggle so both render a
    // clipping identically.
    @objc var formattedForSending: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return detail
        }
        return "**\(trimmedTitle)**\n\(detail)"
    }
}

extension Sequence where Element == PTYSessionClipping {
    // Joins clippings with the user-configurable clipping separator (an
    // advanced setting, vim-special-character expanded so `\n` etc. work).
    func joinedForSending() -> String {
        let separator = (iTermAdvancedSettingsModel.clippingSeparator() as NSString)
            .expandingVimSpecialCharacters()
        return map { $0.formattedForSending }.joined(separator: separator)
    }
}
