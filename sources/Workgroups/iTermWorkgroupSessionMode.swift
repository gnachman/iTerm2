//
//  iTermWorkgroupSessionMode.swift
//  iTerm2SharedARC
//

import Foundation

@objc(iTermWorkgroupSessionMode)
enum iTermWorkgroupSessionMode: Int, Codable, Equatable, CaseIterable {
    case regular
    case codeReview

    private enum StringValue: String, Codable {
        case regular
        case codeReview
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(StringValue.self)
        switch s {
        case .regular: self = .regular
        case .codeReview: self = .codeReview
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .regular: try c.encode(StringValue.regular)
        case .codeReview: try c.encode(StringValue.codeReview)
        }
    }

    var localizedTitle: String {
        switch self {
        case .regular:
            return NSLocalizedString("Regular", comment: "Workgroup session mode")
        case .codeReview:
            return NSLocalizedString("Code Review", comment: "Workgroup session mode")
        }
    }
}
