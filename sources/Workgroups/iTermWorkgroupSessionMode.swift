//
//  iTermWorkgroupSessionMode.swift
//  iTerm2SharedARC
//

import Foundation

@objc(iTermWorkgroupSessionMode)
enum iTermWorkgroupSessionMode: Int, Codable, Equatable, CaseIterable {
    case regular
    case codeReview
    // Like .regular, but the spawn defers running the command until
    // the workgroup's git poller reports at least one pending change.
    // While waiting, the session shows a placeholder overlay; as soon
    // as the poller observes a non-empty fileStatuses list the command
    // is launched. Intended for diff-style peers that have nothing to
    // show when the working tree is clean.
    case diff

    private enum StringValue: String, Codable {
        case regular
        case codeReview
        case diff
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(StringValue.self)
        switch s {
        case .regular: self = .regular
        case .codeReview: self = .codeReview
        case .diff: self = .diff
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .regular: try c.encode(StringValue.regular)
        case .codeReview: try c.encode(StringValue.codeReview)
        case .diff: try c.encode(StringValue.diff)
        }
    }

    var localizedTitle: String {
        switch self {
        case .regular:
            return String(localized: "WorkgroupSessionMode.Regular", defaultValue: "Regular", comment: "Workgroup session mode: an ordinary terminal session (as opposed to Code Review or Diff). Shown in the Mode popup of a workgroup session.")
        case .codeReview:
            return String(localized: "WorkgroupSessionMode.CodeReview", defaultValue: "Code Review", comment: "Workgroup session mode: a session that runs a code review. Shown in the Mode popup of a workgroup session.")
        case .diff:
            return String(localized: "WorkgroupSessionMode.Diff", defaultValue: "Diff", comment: "Workgroup session mode: a session that shows a diff of changes. Shown in the Mode popup of a workgroup session.")
        }
    }
}
