//
//  TabContentModel.swift
//  iTerm2SharedARC
//
//  Rich tab content: a tab cell shows a list of lines, each an interpolated
//  string with its own styling. The configuration has two parts:
//
//  - A global layout (TabContentLayout): which line slots exist, in what
//    order, and how big each is. Line count and sizes fix the tab height,
//    which must be the same for every tab, so they can't vary by profile.
//  - Per-profile overrides (KEY_TAB_CONTENT_LINES): what each slot shows and
//    how it's styled. Any field a profile doesn't set falls back to the
//    built-in default for that slot.
//
//  See docs/rich-tabs-design.md.
//

import AppKit

@objc(iTermTabContentLineSize)
enum TabContentLineSize: Int, CaseIterable {
    case large
    case regular
    case small

    var storageValue: String {
        switch self {
        case .large: return "large"
        case .regular: return "regular"
        case .small: return "small"
        }
    }

    fileprivate init(storageValue: String) {
        self = Self.allCases.first { $0.storageValue == storageValue } ?? .regular
    }

    // Font size relative to the tab bar's normal title font.
    var scale: CGFloat {
        switch self {
        case .large: return 1.15
        case .regular: return 1.0
        case .small: return 0.85
        }
    }
}

@objc(iTermTabContentTruncation)
enum TabContentTruncation: Int, CaseIterable {
    case end
    case middle
    case start

    var storageValue: String {
        switch self {
        case .end: return "end"
        case .middle: return "middle"
        case .start: return "start"
        }
    }

    fileprivate init?(storageValue: String) {
        guard let value = Self.allCases.first(where: { $0.storageValue == storageValue }) else {
            return nil
        }
        self = value
    }
}

struct TabContentSlot: Equatable {
    static let titleID = "builtin.title"
    static let subtitleID = "builtin.subtitle"
    static let directoryID = "builtin.directory"
    static let jobID = "builtin.job"
    static let statusDetailID = "builtin.statusDetail"
    // Presets that show one session value each. None is in the default layout.
    static let hostID = "builtin.host"
    static let sessionNameID = "builtin.sessionName"
    static let profileNameID = "builtin.profileName"
    static let commandLineID = "builtin.commandLine"
    static let lastCommandID = "builtin.lastCommand"
    static let badgeID = "builtin.badge"
    static let tmuxPaneTitleID = "builtin.tmuxPaneTitle"

    // How many lines a slot's text can wrap onto.
    static let maximumLinesRange = 1...3

    var identifier: String
    var size: TabContentLineSize
    // The slot always takes the height of this many lines.
    var maximumLines: Int

    init(identifier: String, size: TabContentLineSize, maximumLines: Int = 1) {
        self.identifier = identifier
        self.size = size
        self.maximumLines = min(max(maximumLines, Self.maximumLinesRange.lowerBound),
                                Self.maximumLinesRange.upperBound)
    }

    // Extra space under a line before the next. The title gets some, so it
    // reads as a heading for the lines under it.
    static let titleSpacing: CGFloat = 3

    static func spacingAfter(identifier: String) -> CGFloat {
        return identifier == titleID ? titleSpacing : 0
    }

    // The slot a built-in line gets when the user adds it. A program's status
    // detail usually runs to a few lines.
    static func preset(identifier: String) -> TabContentSlot {
        if identifier == statusDetailID {
            return TabContentSlot(identifier: identifier, size: .small, maximumLines: 3)
        }
        let size = TabContentLayout.defaultLayout.slots.first { $0.identifier == identifier }?.size ?? .small
        return TabContentSlot(identifier: identifier, size: size)
    }
}

struct TabContentLayout: Equatable {
    var slots: [TabContentSlot]

    static let defaultLayout = TabContentLayout(slots: [
        TabContentSlot(identifier: TabContentSlot.titleID, size: .regular),
        TabContentSlot(identifier: TabContentSlot.subtitleID, size: .small),
        TabContentSlot(identifier: TabContentSlot.directoryID, size: .small),
        TabContentSlot(identifier: TabContentSlot.jobID, size: .small)])

    private enum Key {
        static let identifier = "id"
        static let size = "size"
        static let maximumLines = "lines"
    }

    init(slots: [TabContentSlot]) {
        self.slots = slots
    }

    // Decodes the stored preference. Malformed entries and duplicate
    // identifiers are dropped. If nothing usable remains, this is the default
    // layout, so a damaged value never leaves tabs with no lines.
    init(propertyList: Any?) {
        var slots = [TabContentSlot]()
        var seen = Set<String>()
        for entry in (propertyList as? [Any]) ?? [] {
            guard let dict = entry as? [String: Any],
                  let identifier = dict[Key.identifier] as? String,
                  !identifier.isEmpty,
                  !seen.contains(identifier) else {
                continue
            }
            seen.insert(identifier)
            let size = TabContentLineSize(storageValue: (dict[Key.size] as? String) ?? "")
            let maximumLines = (dict[Key.maximumLines] as? Int) ?? 1
            slots.append(TabContentSlot(identifier: identifier, size: size, maximumLines: maximumLines))
        }
        self = slots.isEmpty ? Self.defaultLayout : TabContentLayout(slots: slots)
    }

    // The slots that fit in at most limit lines, counting each line a slot
    // can wrap to. A slot that wraps keeps as many of its lines as fit. All of
    // them when limit is nil.
    func slots(limitedToLines limit: Int?) -> [TabContentSlot] {
        guard let limit else {
            return slots
        }
        var remaining = limit
        var result = [TabContentSlot]()
        for slot in slots where remaining > 0 {
            let lines = min(slot.maximumLines, remaining)
            result.append(TabContentSlot(identifier: slot.identifier, size: slot.size, maximumLines: lines))
            remaining -= lines
        }
        return result
    }

    var propertyList: [[String: Any]] {
        // One line is the default, so it's left out, as it was before slots
        // could wrap.
        return slots.map { slot in
            var dict: [String: Any] = [Key.identifier: slot.identifier, Key.size: slot.size.storageValue]
            if slot.maximumLines != 1 {
                dict[Key.maximumLines] = slot.maximumLines
            }
            return dict
        }
    }
}

// How one line looks. text is an interpolated string evaluated in the
// session's scope.
struct TabContentLineStyle: Equatable {
    var text: String
    // nil means the tab bar's normal text color.
    var color: NSColor?
    // Used instead of color in dark mode. nil means color is used in both.
    var darkColor: NSColor? = nil
    // Draw in the tab bar's secondary text color. Ignored when color is set.
    var secondary: Bool
    var bold: Bool
    var italic: Bool
    var truncation: TabContentTruncation
    // When the line evaluates to nothing, the lines below move up into its
    // space. The row keeps its height either way.
    var collapsesWhenEmpty: Bool
    // The evaluated text is lightweight HTML (<b>, <i>, <u>, <font color>)
    // rather than plain text. Values go through iterm2.escape_html() so they
    // can't be read as markup.
    var html: Bool = false

    // A small dimmed line showing text, gone when it's empty.
    static func preset(_ text: String) -> TabContentLineStyle {
        var style = userAddedDefault
        style.text = text
        return style
    }

    static let userAddedDefault = TabContentLineStyle(text: "",
                                                      color: nil,
                                                      secondary: true,
                                                      bold: false,
                                                      italic: false,
                                                      truncation: .end,
                                                      collapsesWhenEmpty: true)
}

struct ResolvedTabContentLine {
    var slotIdentifier: String
    var size: TabContentLineSize
    var format: String
    var style: TabContentLineStyle
    var maximumLines = 1
}

enum TabContentResolver {
    // Keys of a profile's per-slot override dictionary.
    enum Key {
        static let text = "text"
        static let color = "color"
        // Applies only while separateColors is true, so turning separate
        // colors off keeps it for next time.
        static let darkColor = "darkColor"
        static let separateColors = "separateColors"
        static let secondary = "secondary"
        static let bold = "bold"
        static let italic = "italic"
        static let truncation = "truncation"
        static let collapsesWhenEmpty = "collapse"
        static let html = "html"
    }

    // The subtitle slot has no fixed default text: it shows the profile's
    // existing subtitle setting. Its text here is a placeholder that
    // resolve() replaces.
    static let builtInDefaults: [String: TabContentLineStyle] = [
        TabContentSlot.titleID: TabContentLineStyle(text: "\\(tab.title)",
                                                    color: nil,
                                                    secondary: false,
                                                    bold: true,
                                                    italic: false,
                                                    truncation: .end,
                                                    collapsesWhenEmpty: false),
        // Keeps its space when empty, which is common, so the lines below
        // don't jump when a subtitle comes and goes.
        TabContentSlot.subtitleID: TabContentLineStyle(text: "",
                                                       color: nil,
                                                       secondary: true,
                                                       bold: false,
                                                       italic: false,
                                                       truncation: .end,
                                                       collapsesWhenEmpty: false),
        TabContentSlot.directoryID: TabContentLineStyle(text: "\\(path)",
                                                        color: nil,
                                                        secondary: true,
                                                        bold: false,
                                                        italic: false,
                                                        truncation: .middle,
                                                        collapsesWhenEmpty: true),
        // HTML, so the status shows in the color its program gave it.
        TabContentSlot.jobID: TabContentLineStyle(text: "\\(iterm2.escape_html(string: jobName?)) <font color=\"\\(statusColor)\">\\(iterm2.escape_html(string: status?))</font>",
                                                  color: nil,
                                                  secondary: true,
                                                  bold: false,
                                                  italic: false,
                                                  truncation: .end,
                                                  collapsesWhenEmpty: true,
                                                  html: true),
        TabContentSlot.statusDetailID: TabContentLineStyle(text: "\\(statusDetail)",
                                                           color: nil,
                                                           secondary: true,
                                                           bold: false,
                                                           italic: false,
                                                           truncation: .end,
                                                           collapsesWhenEmpty: true),
        TabContentSlot.hostID: .preset("\\(hostname)"),
        TabContentSlot.sessionNameID: .preset("\\(name)"),
        TabContentSlot.profileNameID: .preset("\\(profileName)"),
        TabContentSlot.commandLineID: .preset("\\(commandLine)"),
        TabContentSlot.lastCommandID: .preset("\\(lastCommand)"),
        TabContentSlot.badgeID: .preset("\\(badge)"),
        TabContentSlot.tmuxPaneTitleID: .preset("\\(tmuxPaneTitle)"),
    ]

    // overrides is the profile's KEY_TAB_CONTENT_LINES value: a dictionary
    // from slot identifier to a dictionary of the fields that profile
    // changes. Fields of the wrong type are ignored one by one.
    static func resolve(layout: TabContentLayout,
                        overrides: Any?,
                        profileSubtitleFormat: String) -> [ResolvedTabContentLine] {
        let overridesBySlot = (overrides as? [String: Any]) ?? [:]
        return layout.slots.map { slot in
            var style = builtInDefaults[slot.identifier] ?? .userAddedDefault
            if slot.identifier == TabContentSlot.subtitleID {
                style.text = profileSubtitleFormat
            }
            if let fields = overridesBySlot[slot.identifier] as? [String: Any] {
                apply(fields, to: &style)
            }
            return ResolvedTabContentLine(slotIdentifier: slot.identifier,
                                          size: slot.size,
                                          format: style.text,
                                          style: style,
                                          maximumLines: slot.maximumLines)
        }
    }

    private static func apply(_ fields: [String: Any], to style: inout TabContentLineStyle) {
        if let text = fields[Key.text] as? String {
            style.text = text
        }
        if let colorDict = fields[Key.color] as? NSDictionary, let color = colorDict.colorValue() {
            style.color = color
        }
        // Only a custom color has a dark mode counterpart.
        if style.color != nil,
           fields[Key.separateColors] as? Bool == true,
           let darkDict = fields[Key.darkColor] as? NSDictionary,
           let darkColor = darkDict.colorValue() {
            style.darkColor = darkColor
        }
        if let secondary = fields[Key.secondary] as? Bool {
            style.secondary = secondary
        }
        if let bold = fields[Key.bold] as? Bool {
            style.bold = bold
        }
        if let italic = fields[Key.italic] as? Bool {
            style.italic = italic
        }
        if let truncation = (fields[Key.truncation] as? String).flatMap(TabContentTruncation.init(storageValue:)) {
            style.truncation = truncation
        }
        if let collapses = fields[Key.collapsesWhenEmpty] as? Bool {
            style.collapsesWhenEmpty = collapses
        }
        if let html = fields[Key.html] as? Bool {
            style.html = html
        }
    }
}

// A piece of a line's format: literal text or one \(…) expression. Lines are
// evaluated a segment at a time so a collapsed tab group can combine its
// members' jobs and statuses, which mean something as collections, separately
// from the rest of the line.
struct TabContentSegment: Equatable {
    enum Kind: Equatable {
        case literal
        case job
        case status
        // The status text's color, as a chip colors each status it counts.
        case statusColor
        case other
    }

    var kind: Kind
    // An interpolated string that evaluates to just this segment.
    var source: String

    // The variable path inside iterm2.escape_html(string: …) (with or without
    // the namespace, and with or without a trailing ? for a value that may not
    // be set), or nil if expression isn't one.
    private static let escapedVariableRegex =
        try? NSRegularExpression(pattern: #"^\s*(?:iterm2\.)?escape_html\(\s*string\s*:\s*([A-Za-z_][A-Za-z0-9_.]*)\??\s*\)\s*$"#)

    static func escapedVariable(inExpression expression: String) -> String? {
        guard let regex = escapedVariableRegex,
              let match = regex.firstMatch(in: expression, range: NSRange(expression.startIndex..., in: expression)),
              let range = Range(match.range(at: 1), in: expression) else {
            return nil
        }
        return String(expression[range])
    }

    // An escaped job or status is still a job or status: escaping is
    // one-to-one, so the escaped values combine the same way.
    private static func kind(ofExpression expression: String) -> Kind {
        switch (escapedVariable(inExpression: expression) ?? expression).trimmingCharacters(in: .whitespaces) {
        case "jobName", "session.jobName":
            return .job
        case "status", "session.status":
            return .status
        case "statusColor", "session.statusColor":
            return .statusColor
        default:
            return .other
        }
    }

    static func split(_ format: String) -> [TabContentSegment] {
        var segments = [TabContentSegment]()
        (format as NSString).enumerateSwiftySubstrings { _, substring, isLiteral, _ in
            if isLiteral {
                segments.append(TabContentSegment(kind: .literal, source: substring))
            } else {
                segments.append(TabContentSegment(kind: kind(ofExpression: substring),
                                                  source: "\\(" + substring + ")"))
            }
        }
        // The parser drops or unescapes some malformed input. Evaluating
        // segments that don't add up to the format could show something
        // different from the format as a whole, so keep it in one piece.
        guard segments.map(\.source).joined() == format else {
            return [TabContentSegment(kind: .other, source: format)]
        }
        return segments
    }
}

// One line's evaluated value, kept segment by segment.
struct EvaluatedTabContentLine: Equatable {
    struct Value: Equatable {
        var kind: TabContentSegment.Kind
        var text: String
    }

    var slotIdentifier: String
    var size: TabContentLineSize
    var format: String
    var style: TabContentLineStyle
    var maximumLines: Int
    var values: [Value]

    init(line: ResolvedTabContentLine, values: [Value]) {
        slotIdentifier = line.slotIdentifier
        size = line.size
        format = line.format
        style = line.style
        maximumLines = line.maximumLines
        self.values = values
    }

    // evaluate gives the current value of a segment's source.
    init(line: ResolvedTabContentLine, evaluate: (String) -> String) {
        self.init(line: line,
                  values: TabContentSegment.split(line.format).map {
                      Value(kind: $0.kind, text: evaluate($0.source))
                  })
    }

    // A line that can't wrap is drawn on one line, so its newlines are
    // flattened the way -[PTYSession subtitle] does. One that can wrap keeps
    // them, but not blank lines, which would use up its few lines.
    func flattened(_ text: String) -> String {
        guard maximumLines == 1 else {
            // Any kind of line break: \r\n, \r, and Unicode separators too.
            // In HTML, a row of only markup is blank too, but its tags still
            // apply, so they join the next row, or the previous one at the
            // end.
            var rows = [String]()
            var pendingMarkup = ""
            for row in text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) {
                let visible = style.html ? NSAttributedString.fromLightweightHTML(row, attributes: [:]).string : row
                if visible.trimmingCharacters(in: .whitespaces).isEmpty {
                    if style.html {
                        pendingMarkup += row
                    }
                    continue
                }
                rows.append(pendingMarkup + row)
                pendingMarkup = ""
            }
            if !pendingMarkup.isEmpty {
                if rows.isEmpty {
                    rows.append(pendingMarkup)
                } else {
                    rows[rows.count - 1] += pendingMarkup
                }
            }
            return rows.joined(separator: "\n")
        }
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    var text: String {
        return flattened(values.map(\.text).joined())
    }

    func richLine(text: String) -> PSMTabRichLine {
        return PSMTabRichLine(text: text,
                              scale: size.scale,
                              bold: style.bold,
                              italic: style.italic,
                              color: style.color,
                              darkColor: style.darkColor,
                              secondary: style.secondary,
                              lineBreakMode: style.truncation.lineBreakMode,
                              collapsesWhenEmpty: style.collapsesWhenEmpty,
                              maximumLines: maximumLines,
                              html: style.html,
                              spacingAfter: TabContentSlot.spacingAfter(identifier: slotIdentifier))
    }

    var richLine: PSMTabRichLine {
        return richLine(text: text)
    }
}
