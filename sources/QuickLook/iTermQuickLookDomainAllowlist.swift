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
    // Entries that could be normalized. An entry that cannot be (such as ".") is dropped.
    let entries: [String]
    // Set by the secure setting that lets hover preview every domain. Private addresses still
    // need an entry of their own.
    let allowsAllDomains: Bool

    init(entries: [String], allowsAllDomains: Bool) {
        self.entries = entries.compactMap { Self.normalizedEntry($0) }
        self.allowsAllDomains = allowsAllDomains
    }

    // The saved allowlist and the secure allow-all setting.
    static func fromSettings() -> iTermQuickLookDomainAllowlist {
        return iTermQuickLookDomainAllowlist(entries: savedEntries(),
                                             allowsAllDomains: SecureUserDefaults.instance.quickLookHoverAllowsAllDomains.value)
    }

    // The entries as saved in user defaults: an array of strings. A string (the format before the
    // table) is split on commas and whitespace.
    static func savedEntries() -> [String] {
        let value = iTermPreferences.object(forKey: kPreferenceKeyQuickLookHoverDomainAllowlist)
        if let array = value as? [String] {
            return array
        }
        if let string = value as? String {
            let separators = CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines)
            return string.components(separatedBy: separators).filter { !$0.isEmpty }
        }
        return []
    }

    // The saved domains, normalized, without duplicates, in their saved order.
    static func savedDomains() -> [String] {
        var seen = Set<String>()
        return savedEntries().compactMap { entry in
            guard let domain = normalizedEntry(entry), !seen.contains(domain) else {
                return nil
            }
            seen.insert(domain)
            return domain
        }
    }

    // Where domain goes in a sorted list of domains.
    static func insertionIndex(of domain: String, in domains: [String]) -> Int {
        return domains.firstIndex {
            $0.localizedStandardCompare(domain) == .orderedDescending
        } ?? domains.count
    }

    // Adds a domain to the saved list in sorted position. Does nothing if it is already listed.
    static func saveDomain(_ domain: String) {
        var domains = savedDomains()
        guard !domains.contains(domain) else {
            return
        }
        domains.insert(domain, at: insertionIndex(of: domain, in: domains))
        iTermPreferences.setObject(domains, forKey: kPreferenceKeyQuickLookHoverDomainAllowlist)
    }

    // The domain to offer to allow when the allowlist kept url from previewing: its host without a
    // leading “www.”, so the offer covers the site’s other subdomains too. Nil for a URL that isn’t
    // a web address.
    static func domainToOffer(for url: URL) -> String? {
        guard isWebURL(url), let host = url.host, let domain = normalizedEntry(host) else {
            return nil
        }
        let www = "www."
        if domain.hasPrefix(www), domain.count > www.count {
            return String(domain.dropFirst(www.count))
        }
        return domain
    }

    // True for http and https addresses, the only ones a preview loads or hands on.
    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    func allows(_ url: URL) -> Bool {
        guard Self.isWebURL(url), let host = url.host.flatMap({ Self.normalizedHost($0) }) else {
            return false
        }
        if entries.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return true
        }
        // Resting the pointer on program output must not send requests to the local network or this
        // Mac unless the user named the host.
        return allowsAllDomains && !Self.isPrivateHost(host)
    }

    // The host an entry names, in the form allows() compares. Accepts what people paste: a scheme,
    // a path, a port, user info, or a leading "*." or ".". Nil when nothing usable is left.
    static func normalizedEntry(_ entry: String) -> String? {
        var string = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = string.range(of: "://") {
            string = String(string[range.upperBound...])
        }
        if let index = string.firstIndex(where: { "/?#".contains($0) }) {
            string = String(string[..<index])
        }
        if let index = string.lastIndex(of: "@") {
            string = String(string[string.index(after: index)...])
        }
        if string.hasPrefix("[") {
            // An IPv6 literal, possibly with a port.
            if let close = string.firstIndex(of: "]") {
                string = String(string[string.index(after: string.startIndex)..<close])
            }
        } else if let colon = string.lastIndex(of: ":"), string.filter({ $0 == ":" }).count == 1 {
            string = String(string[..<colon])
        }
        while string.hasPrefix("*.") {
            string.removeFirst(2)
        }
        while string.hasPrefix(".") {
            string.removeFirst()
        }
        return normalizedHost(string)
    }

    // Lowercases, drops trailing dots and converts an internationalized name to its ASCII (punycode)
    // form so that "bücher.de" and "xn--bcher-kva.de" compare equal.
    static func normalizedHost(_ string: String) -> String? {
        var host = string.lowercased()
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        if host.isEmpty || host.contains(where: { $0.isWhitespace || "*/@".contains($0) }) {
            return nil
        }
        if host.contains(":") {
            // IPv6 literal.
            return host
        }
        return host.components(separatedBy: ".").map { label in
            label.unicodeScalars.allSatisfy({ $0.isASCII }) ? label : punycodeLabel(label)
        }.joined(separator: ".")
    }

    // Loopback, link-local, private and carrier-grade NAT addresses, and names that only resolve on
    // a local network (localhost, .local, single-label intranet names). DNS can still map a public
    // name to a private address; this doesn't resolve names.
    static func isPrivateHost(_ host: String) -> Bool {
        if host.contains(":") {
            return isPrivateIPv6(host)
        }
        if endsInNumber(host) {
            // WebKit parses this host as an IPv4 address, so classify the address it would load.
            // inet_aton accepts the same forms: one to four parts, each decimal, 0x hex or
            // leading-zero octal (127.1, 0x7f.0.0.1, 0177.0.0.1, 0x7f000001).
            var address = in_addr()
            guard inet_aton(host, &address) != 0 else {
                // WebKit rejects a host like this, so nothing would load. Don't call it public.
                return true
            }
            return isPrivateIPv4(UInt32(bigEndian: address.s_addr))
        }
        if !host.contains(".") {
            return true
        }
        return host == "localhost" ||
            host.hasSuffix(".localhost") ||
            host.hasSuffix(".local") ||
            host.hasSuffix(".internal") ||
            host.hasSuffix(".home.arpa")
    }

    // Whether the WHATWG URL parser, which WebKit uses, treats host as an IPv4 address: its last
    // label is all decimal digits, or 0x followed by hex digits. Foundation's URL leaves such hosts
    // as written, so 127.1 must not be mistaken for a domain name.
    private static func endsInNumber(_ host: String) -> Bool {
        var labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count > 1 && labels.last?.isEmpty == true {
            // The parser ignores one trailing dot.
            labels.removeLast()
        }
        guard let last = labels.last, !last.isEmpty else {
            return false
        }
        if last.allSatisfy({ $0.isASCII && $0.isNumber }) {
            return true
        }
        let lower = last.lowercased()
        return lower.hasPrefix("0x") && lower.dropFirst(2).allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    // address is in host byte order.
    private static func isPrivateIPv4(_ address: UInt32) -> Bool {
        let first = (address >> 24) & 0xff
        let second = (address >> 16) & 0xff
        switch (first, second) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168):
            return true
        case (172, 16...31), (100, 64...127):
            return true
        default:
            return false
        }
    }

    private static func isPrivateIPv6(_ host: String) -> Bool {
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else {
            // Not a literal we understand; don't treat it as public.
            return true
        }
        let bytes = withUnsafeBytes(of: address) { Array($0) }
        if bytes[0..<15].allSatisfy({ $0 == 0 }) && (bytes[15] == 1 || bytes[15] == 0) {
            // ::1 and ::
            return true
        }
        if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 {
            // fe80::/10 link-local
            return true
        }
        if (bytes[0] & 0xfe) == 0xfc {
            // fc00::/7 unique local
            return true
        }
        if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
            // IPv4-mapped
            return isPrivateHost(bytes[12...15].map { String($0) }.joined(separator: "."))
        }
        return false
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
