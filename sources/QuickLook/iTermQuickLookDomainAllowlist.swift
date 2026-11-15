//
//  iTermQuickLookDomainAllowlist.swift
//  iTerm2SharedARC
//
//  Decides which web URLs may open a Quick Look popover on hover.
//

import Foundation

// Raw values are stored in user defaults (kPreferenceKeyQuickLookHoverMode); do not renumber.
@objc enum iTermQuickLookHoverMode: Int {
    case off = 0
    case hover = 1
    case commandHover = 2
}

struct iTermQuickLookDomainAllowlist {
    // Entries that could be normalized. An entry that cannot be (for example an invalid internationalized
    // name) is absent here, so it never matches, but it still counts toward isEmpty.
    private let entries: [String]
    private let suppliedEntryCount: Int

    // Entries are separated by commas and/or whitespace. A list with no entries allows every web URL.
    // A list with at least one entry restricts, even if none of its entries are usable: it fails closed.
    init(string: String) {
        let separators = CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines)
        let tokens = string.components(separatedBy: separators).filter { !$0.isEmpty }
        suppliedEntryCount = tokens.count
        entries = tokens.compactMap { Self.normalizedHost($0) }
    }

    var isEmpty: Bool {
        return suppliedEntryCount == 0
    }

    func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        if isEmpty {
            return true
        }
        guard let host = url.host.flatMap({ Self.normalizedHost($0) }) else {
            return false
        }
        return entries.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // Lowercases, drops trailing dots and converts an internationalized name to its ASCII (punycode)
    // form so that "bücher.de" and "xn--bcher-kva.de" compare equal.
    private static func normalizedHost(_ string: String) -> String? {
        var host = string.lowercased()
        while host.hasSuffix(".") {
            host.removeLast()
        }
        if host.isEmpty {
            return nil
        }
        return host.components(separatedBy: ".").map { label in
            label.unicodeScalars.allSatisfy({ $0.isASCII }) ? label : punycodeLabel(label)
        }.joined(separator: ".")
    }

    // RFC 3492 encoding of one label, prefixed with "xn--". Deterministic and independent of how
    // the OS's URL parser treats raw non-ASCII hosts.
    private static func punycodeLabel(_ label: String) -> String {
        let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700
        let scalars = label.unicodeScalars.map { Int($0.value) }
        var output = scalars.filter { $0 < 128 }.map { Character(UnicodeScalar(UInt8($0))) }
        let basicCount = output.count
        var handled = basicCount
        if basicCount > 0 {
            output.append("-")
        }
        func digit(_ d: Int) -> Character {
            return Character(UnicodeScalar(UInt8(d < 26 ? d + 97 : d - 26 + 48)))
        }
        func adapt(_ delta: Int, _ points: Int, _ first: Bool) -> Int {
            var d = first ? delta / damp : delta / 2
            d += d / points
            var k = 0
            while d > ((base - tMin) * tMax) / 2 {
                d /= base - tMin
                k += base
            }
            return k + (base - tMin + 1) * d / (d + skew)
        }
        var n = 128, delta = 0, bias = 72
        while handled < scalars.count {
            let m = scalars.filter { $0 >= n }.min()!
            delta += (m - n) * (handled + 1)
            n = m
            for c in scalars {
                if c < n {
                    delta += 1
                } else if c == n {
                    var q = delta
                    var k = base
                    while true {
                        let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                        if q < t {
                            break
                        }
                        output.append(digit(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    output.append(digit(q))
                    bias = adapt(delta, handled + 1, handled == basicCount)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }
        return "xn--" + String(output)
    }
}
