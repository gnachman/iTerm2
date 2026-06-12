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
            return NSLocalizedString("Regular", comment: "Workgroup session mode")
        case .codeReview:
            return NSLocalizedString("Code Review", comment: "Workgroup session mode")
        case .diff:
            return NSLocalizedString("Diff", comment: "Workgroup session mode")
        }
    }
}
