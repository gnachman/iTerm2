//
//  TabGroupContent.swift
//  iTerm2SharedARC
//
//  The rich content lines a collapsed tab group's chip shows on behalf of its
//  hidden members (see docs/rich-tabs-design.md):
//
//  - Title and subtitle are left out. The chip shows the group's name instead.
//  - Jobs become a list of the distinct job names, and statuses a count of
//    each, as in “claude, vimdiff, zsh” and “1 Waiting, 2 Working”.
//  - Anything else shows only when every member has the same value.
//

import AppKit

// A snapshot of a session's evaluated lines, for Objective-C callers that
// pass them along to the combiner.
@objc(iTermTabContentSnapshot)
final class TabContentSnapshot: NSObject {
    let lines: [EvaluatedTabContentLine]

    init(lines: [EvaluatedTabContentLine]) {
        self.lines = lines
    }
}

@objc(iTermTabGroupContent)
final class TabGroupContent: NSObject {
    private static let excludedSlots: Set<String> = [TabContentSlot.titleID, TabContentSlot.subtitleID]

    // Whether collapsed chips show lines with a window's settings. Depends
    // only on the settings, not on what tabs show.
    @objc(showsRichContentWithConfiguration:)
    static func showsRichContent(configuration: TabContentConfiguration) -> Bool {
        guard configuration.enabled else {
            return false
        }
        return configuration.limitedLayout.slots.contains { !excludedSlots.contains($0.identifier) }
    }

    // The chip's lines for a window's settings, or nil when rich content is
    // off or the layout has nothing the chip shows. Each snapshot is one
    // member's.
    @objc(combinedLinesForSnapshots:configuration:)
    static func combinedLines(snapshots: [TabContentSnapshot],
                              configuration: TabContentConfiguration) -> [PSMTabRichLine]? {
        guard showsRichContent(configuration: configuration) else {
            return nil
        }
        let lines = combine(layout: configuration.limitedLayout,
                            members: snapshots.map(\.lines),
                            statusPriority: { StatusPrioritySettings.shared.priority(for: $0) })
        return lines.isEmpty ? nil : lines
    }

    // Lines like combinedLines(snapshots:configuration:) gives but with no
    // text, for sizing a chip. They depend only on the settings.
    @objc(sizingLinesWithConfiguration:)
    static func sizingLines(configuration: TabContentConfiguration) -> [PSMTabRichLine]? {
        guard showsRichContent(configuration: configuration) else {
            return nil
        }
        return combine(layout: configuration.limitedLayout, members: [], statusPriority: { _ in 0 })
    }

    // One line per slot in the layout the chip shows, so the number of lines
    // depends only on the layout. statusPriority ranks status text, lower
    // first.
    static func combine(layout: TabContentLayout,
                        members: [[EvaluatedTabContentLine]],
                        statusPriority: (String) -> Int) -> [PSMTabRichLine] {
        return layout.slots.compactMap { slot -> PSMTabRichLine? in
            guard !excludedSlots.contains(slot.identifier) else {
                return nil
            }
            let lines = members.compactMap { lines in
                lines.first { $0.slotIdentifier == slot.identifier }
            }
            guard let first = lines.first else {
                return placeholder(for: slot)
            }
            return first.richLine(text: combinedText(lines, statusPriority: statusPriority))
        }
    }

    private static func placeholder(for slot: TabContentSlot) -> PSMTabRichLine {
        let style = TabContentResolver.builtInDefaults[slot.identifier] ?? .userAddedDefault
        let line = ResolvedTabContentLine(slotIdentifier: slot.identifier,
                                          size: slot.size,
                                          format: style.text,
                                          style: style,
                                          maximumLines: slot.maximumLines)
        return EvaluatedTabContentLine(line: line, values: []).richLine
    }

    private static func combinedText(_ lines: [EvaluatedTabContentLine],
                                     statusPriority: (String) -> Int) -> String {
        // Text means something different in HTML than in plain text, so
        // members that disagree on that can't be combined piece by piece. The
        // line shows only when they all show the same text, ignoring spaces at
        // the ends, written for the first member's format.
        let html = lines[0].style.html
        guard lines.allSatisfy({ $0.style.html == html }) else {
            let visible = identicalOrEmpty(lines.map { $0.richLine.visibleText.trimmingCharacters(in: .whitespacesAndNewlines) })
            return html ? EscapeHTMLBuiltInFunction.escape(visible) : visible
        }
        // Segments only line up when every member uses the same format.
        guard lines.allSatisfy({ $0.format == lines[0].format }) else {
            return identicalOrEmpty(lines.map(\.text))
        }
        // An HTML line with a status and its color counts each status in its
        // own color, so a chip shows a mix. The line's own color for the
        // status is then left empty, the normal color, so it doesn't color
        // the separators between them.
        let values = lines[0].values
        let colorIndex = values.firstIndex { $0.kind == .statusColor }
        let statusColors: [String]? = (html && values.contains { $0.kind == .status })
            ? colorIndex.map { i in lines.map { $0.values[i].text } }
            : nil
        let pieces = values.indices.map { i -> String in
            let texts = lines.map { $0.values[i].text }
            switch lines[0].values[i].kind {
            case .literal:
                return texts[0]
            case .job:
                return jobs(texts)
            case .status:
                // Priority patterns are for the status as reported, not its
                // escaped form.
                return statuses(texts,
                                colors: statusColors,
                                priority: html ? { statusPriority(EscapeHTMLBuiltInFunction.unescape($0)) } : statusPriority)
            case .statusColor:
                return statusColors == nil ? identicalOrEmpty(texts) : ""
            case .other:
                return identicalOrEmpty(texts)
            }
        }
        return lines[0].flattened(pieces.joined())
    }

    private static func identicalOrEmpty(_ texts: [String]) -> String {
        guard let first = texts.first, texts.allSatisfy({ $0 == first }) else {
            return ""
        }
        return first
    }

    private static var separator: String {
        return String(localized: "TabGroupContent.ListSeparator",
                      defaultValue: ", ",
                      comment: "Separates items in a short list on a collapsed tab group, as in “claude, vim, zsh”")
    }

    // The distinct job names in alphabetical order.
    private static func jobs(_ texts: [String]) -> String {
        let names = Set(texts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: separator)
    }

    // How many members have each status, most urgent first, then most common.
    // colors, when given, are each member's status color: each count is drawn
    // in its status's color (the first member's with that status that has
    // one), as HTML.
    private static func statuses(_ texts: [String],
                                 colors: [String]?,
                                 priority: (String) -> Int) -> String {
        var order = [String]()
        var counts = [String: Int]()
        var colorOfStatus = [String: String]()
        for (i, text) in texts.map({ $0.trimmingCharacters(in: .whitespaces) }).enumerated() where !text.isEmpty {
            if counts[text] == nil {
                order.append(text)
            }
            counts[text, default: 0] += 1
            if colorOfStatus[text] == nil, let color = colors?[i], !color.isEmpty {
                colorOfStatus[text] = color
            }
        }
        let ranked = order.enumerated().sorted { a, b in
            let (pa, pb) = (priority(a.element), priority(b.element))
            if pa != pb {
                return pa < pb
            }
            let (ca, cb) = (counts[a.element]!, counts[b.element]!)
            if ca != cb {
                return ca > cb
            }
            return a.offset < b.offset
        }
        return ranked.map { _, status in
            let count = counts[status]!
            let text = String(localized: "TabGroupContent.StatusCount",
                              defaultValue: "\(count) \(status)",
                              comment: "How many tabs in a collapsed tab group have a status, as in “2 Working”. The status text comes from the program running in the tab.")
            guard let color = colorOfStatus[status] else {
                return text
            }
            return "<font color=\"\(EscapeHTMLBuiltInFunction.escape(color))\">\(text)</font>"
        }.joined(separator: separator)
    }
}
