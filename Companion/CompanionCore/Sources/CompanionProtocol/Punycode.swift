//
//  Punycode.swift
//  CompanionCore
//
//  Minimal RFC 3492 Punycode / IDNA-ASCII host encoder. Just enough to render a
//  hostname in its ASCII ("xn--") form so a Unicode homograph in an untrusted
//  relay host (e.g. a Cyrillic lookalike) is visible to the user before they
//  agree to pair. Encode-only; we never need to decode.
//

import Foundation

public enum Punycode {
    private static let base: UInt32 = 36
    private static let tmin: UInt32 = 1
    private static let tmax: UInt32 = 26
    private static let skew: UInt32 = 38
    private static let damp: UInt32 = 700
    private static let initialBias: UInt32 = 72
    private static let initialN: UInt32 = 128

    /// Encode a hostname label-by-label: any dot-separated label containing
    /// non-ASCII becomes "xn--<punycode>"; pure-ASCII labels pass through
    /// unchanged. Empty input returns empty.
    public static func encodedHost(_ host: String) -> String {
        host.split(separator: ".", omittingEmptySubsequences: false)
            .map { label -> String in
                let s = String(label)
                return s.unicodeScalars.allSatisfy { $0.isASCII } ? s : "xn--" + encode(s)
            }
            .joined(separator: ".")
    }

    private static func digit(_ d: UInt32) -> Character {
        // 0..25 -> 'a'..'z', 26..35 -> '0'..'9'
        let scalar = d < 26 ? UInt8(97 + d) : UInt8(48 + d - 26)
        return Character(UnicodeScalar(scalar))
    }

    private static func adapt(_ delta: UInt32, _ numPoints: UInt32, _ firstTime: Bool) -> UInt32 {
        var delta = firstTime ? delta / damp : delta / 2
        delta += delta / numPoints
        var k: UInt32 = 0
        while delta > ((base - tmin) * tmax) / 2 {
            delta /= (base - tmin)
            k += base
        }
        return k + (((base - tmin + 1) * delta) / (delta + skew))
    }

    /// Encode a single label into the part that follows "xn--". Hostnames are
    /// short, so the unbounded-overflow handling from the RFC is unnecessary.
    private static func encode(_ input: String) -> String {
        let codePoints = input.unicodeScalars.map { $0.value }
        var n = initialN
        var delta: UInt32 = 0
        var bias = initialBias
        var output = ""

        var basicCount: UInt32 = 0
        for cp in codePoints where cp < 0x80 {
            output.unicodeScalars.append(UnicodeScalar(cp)!)
            basicCount += 1
        }
        var handled = basicCount
        if basicCount > 0 { output.append("-") }

        while handled < UInt32(codePoints.count) {
            var m = UInt32.max
            for cp in codePoints where cp >= n && cp < m { m = cp }
            delta += (m - n) * (handled + 1)
            n = m
            for cp in codePoints {
                if cp < n { delta += 1 }
                if cp == n {
                    var q = delta
                    var k = base
                    while true {
                        let t: UInt32 = k <= bias ? tmin : (k >= bias + tmax ? tmax : k - bias)
                        if q < t { break }
                        output.append(digit(t + ((q - t) % (base - t))))
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
        return output
    }
}
