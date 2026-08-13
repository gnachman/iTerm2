//
//  ComposerTabRouter.swift
//  iTerm2SharedARC
//
//  Parses composer text for a leading @-address (e.g. “@2 cmd”, “@all cmd”)
//  so the composer can send commands to other tabs. Pure logic; no UI or
//  session access.
//

import Foundation

@objc(iTermComposerTabRouteKind)
enum ComposerTabRouteKind: Int {
    // No address prefix; send the text unchanged to the composer's own session.
    case none
    // Leading \@ was removed; send payload to the composer's own session.
    case escaped
    // Send payload to the 1-based tabNumber in the current window.
    case tab
    // Send payload to every other tab in the current window.
    case all
}

@objc(iTermComposerTabRoute)
class ComposerTabRoute: NSObject {
    @objc let kind: ComposerTabRouteKind
    // 1-based; meaningful only when kind == .tab. Out-of-range values
    // (including 0) are rejected at resolution time, not parse time.
    @objc let tabNumber: Int
    @objc let payload: String

    init(kind: ComposerTabRouteKind, tabNumber: Int = 0, payload: String) {
        self.kind = kind
        self.tabNumber = tabNumber
        self.payload = payload
    }
}

@objc(iTermComposerTabRouter)
class ComposerTabRouter: NSObject {
    // Routing triggers only on ^@(digits|all)<whitespace><non-empty payload>.
    // Anything else falls through as .none so ordinary text (@2fa/cli,
    // @alligator, bare @2) is never hijacked.
    @objc static func parse(_ text: String) -> ComposerTabRoute {
        if text.hasPrefix("\\@") {
            return ComposerTabRoute(kind: .escaped, payload: String(text.dropFirst()))
        }
        guard text.hasPrefix("@") else {
            return ComposerTabRoute(kind: .none, payload: text)
        }
        let body = text.dropFirst()
        let address = body.prefix { !$0.isWhitespace }
        let afterAddress = body.dropFirst(address.count)
        guard let separator = afterAddress.first, separator.isWhitespace else {
            return ComposerTabRoute(kind: .none, payload: text)
        }
        let payload = String(afterAddress.drop { $0.isWhitespace })
        guard !payload.isEmpty else {
            return ComposerTabRoute(kind: .none, payload: text)
        }
        if address == "all" {
            return ComposerTabRoute(kind: .all, payload: payload)
        }
        if !address.isEmpty,
           address.allSatisfy({ $0.isASCII && $0.isNumber }),
           let number = Int(address) {
            return ComposerTabRoute(kind: .tab, tabNumber: number, payload: payload)
        }
        return ComposerTabRoute(kind: .none, payload: text)
    }
}
