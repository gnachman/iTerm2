//
//  RailroadText.swift
//  iTerm2
//
//  Swift port of nodes/text.rs from the railroad crate 0.3.12
//  (https://github.com/lukaslueg/railroad), Copyright (c) 2018 Lukas Lueg,
//  MIT License.
//

import Foundation

/// Terminal-column width of a string, like the `unicode-width` crate's
/// `UnicodeWidthStr::width`: wide and fullwidth characters count 2,
/// combining marks and zero-width characters count 0, everything else 1.
enum RailroadTextWidth {
    static func columns(_ s: String) -> Int {
        var total = 0
        for scalar in s.unicodeScalars {
            total += width(of: scalar)
        }
        return total
    }

    static func width(of scalar: Unicode.Scalar) -> Int {
        let v = scalar.value
        if v == 0 {
            return 0
        }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format:
            return 0
        default:
            break
        }
        if v == 0x200B || (0x1160...0x11FF).contains(v) {
            return 0
        }
        if isWide(v) {
            return 2
        }
        return 1
    }

    private static func isWide(_ v: UInt32) -> Bool {
        switch v {
        case 0x1100...0x115F, 0x231A...0x231B, 0x2329...0x232A, 0x23E9...0x23EC,
             0x23F0, 0x23F3, 0x25FD...0x25FE, 0x2614...0x2615, 0x2648...0x2653,
             0x267F, 0x2693, 0x26A1, 0x26AA...0x26AB, 0x26BD...0x26BE,
             0x26C4...0x26C5, 0x26CE, 0x26D4, 0x26EA, 0x26F2...0x26F3, 0x26F5,
             0x26FA, 0x26FD, 0x2705, 0x270A...0x270B, 0x2728, 0x274C, 0x274E,
             0x2753...0x2755, 0x2757, 0x2795...0x2797, 0x27B0, 0x27BF,
             0x2B1B...0x2B1C, 0x2B50, 0x2B55, 0x2E80...0x303E, 0x3041...0x33FF,
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF, 0xA960...0xA97F,
             0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F,
             0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x16FE0...0x16FE4, 0x17000...0x18CFF,
             0x1B000...0x1B2FF, 0x1F004, 0x1F0CF, 0x1F18E, 0x1F191...0x1F19A,
             0x1F200...0x1F251, 0x1F300...0x1F64F, 0x1F680...0x1F6FF,
             0x1F7E0...0x1F7EB, 0x1F90C...0x1F9FF, 0x1FA70...0x1FAFF,
             0x20000...0x2FFFD, 0x30000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}

/// A rounded box with literal text. Port of `Terminal`.
struct RailroadTerminal: RailroadNode {
    var label: String
    var attributes: [String: String] = [:]

    var entryHeight: Int { 11 }
    var height: Int { entryHeight * 2 }
    var width: Int { Railroad.textWidth(label) * 8 + 20 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        out.group(class: "terminal", attributes: attributes) {
            out.textBox(x: x, y: y, width: width, height: height, entryHeight: entryHeight, label: label, rounded: true)
        }
    }
}

/// A square box naming another rule. Port of `NonTerminal`.
struct RailroadNonTerminal: RailroadNode {
    var label: String
    var attributes: [String: String] = [:]

    var entryHeight: Int { 11 }
    var height: Int { entryHeight * 2 }
    var width: Int { Railroad.textWidth(label) * 8 + 20 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        out.group(class: "nonterminal", attributes: attributes) {
            out.textBox(x: x, y: y, width: width, height: height, entryHeight: entryHeight, label: label, rounded: false)
        }
    }
}

/// Free text without a box. Port of `Comment`.
struct RailroadComment: RailroadNode {
    var text: String
    var attributes: [String: String] = [:]

    var entryHeight: Int { 10 }
    var height: Int { 20 }
    var width: Int { Railroad.textWidth(text) * 7 + 10 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        let tag = out.startElement("text")
        tag.attrs(attributes)
        tag.attr("class", "comment")
        tag.attr("x", x + width / 2)
        tag.attr("y", y + 15)
        tag.finish()
        out.writeText(text)
        out.endElement("text")
    }
}
