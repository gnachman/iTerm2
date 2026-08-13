//
//  ComposerTabRouter.swift
//  iTerm2SharedARC
//
//  Parses composer text for a leading @-address (e.g. “@2 cmd”, “@2.3 cmd”,
//  “@w3.2.1 cmd”, “@all cmd”, “@wall cmd”) so the composer can send commands
//  to other tabs, panes, and windows. Pure logic; no UI or session access.
//

import Foundation

@objc(iTermComposerTabRouteKind)
enum ComposerTabRouteKind: Int {
    // No address prefix; send the text unchanged to the composer's own session.
    case none
    // Leading \@ was removed; send payload to the composer's own session.
    case escaped
    // Send payload to a specific window/tab/pane (see ComposerTabRoute fields).
    case target
    // Send payload to every other session in the current window.
    case all
    // Send payload to every other session in every window.
    case allWindows
}

@objc(iTermComposerTabRoute)
class ComposerTabRoute: NSObject {
    @objc let kind: ComposerTabRouteKind
    // For kind == .target. -1 means unspecified: current window / the
    // window's active tab / the tab's active pane. Explicit values are
    // 1-based as displayed; out-of-range values (including 0) are rejected
    // at resolution time, not parse time.
    @objc let windowNumber: Int
    @objc let tabNumber: Int
    @objc let paneNumber: Int
    @objc let payload: String

    init(kind: ComposerTabRouteKind,
         windowNumber: Int = -1,
         tabNumber: Int = -1,
         paneNumber: Int = -1,
         payload: String) {
        self.kind = kind
        self.windowNumber = windowNumber
        self.tabNumber = tabNumber
        self.paneNumber = paneNumber
        self.payload = payload
    }
}

@objc(iTermComposerTabRouter)
class ComposerTabRouter: NSObject {
    // Routing triggers only on ^@<address><whitespace><non-empty payload>
    // where <address> is digits[.digits], w+digits[.digits[.digits]],
    // “all”, or “wall”. Anything else falls through as .none so ordinary
    // text (@2fa/cli, @alligator, bare @2) is never hijacked.
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
        if address == "wall" {
            return ComposerTabRoute(kind: .allWindows, payload: payload)
        }

        var numberPart = address[...]
        let isWindowForm = numberPart.hasPrefix("w")
        if isWindowForm {
            numberPart = numberPart.dropFirst()
        }
        let parts = numberPart.split(separator: ".", omittingEmptySubsequences: false)
        let maxParts = isWindowForm ? 3 : 2
        guard parts.count >= 1, parts.count <= maxParts else {
            return ComposerTabRoute(kind: .none, payload: text)
        }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part) else {
                return ComposerTabRoute(kind: .none, payload: text)
            }
            numbers.append(number)
        }
        if isWindowForm {
            return ComposerTabRoute(kind: .target,
                                    windowNumber: numbers[0],
                                    tabNumber: numbers.count > 1 ? numbers[1] : -1,
                                    paneNumber: numbers.count > 2 ? numbers[2] : -1,
                                    payload: payload)
        }
        return ComposerTabRoute(kind: .target,
                                tabNumber: numbers[0],
                                paneNumber: numbers.count > 1 ? numbers[1] : -1,
                                payload: payload)
    }
}
