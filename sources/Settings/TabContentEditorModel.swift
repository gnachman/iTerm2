//
//  TabContentEditorModel.swift
//  iTerm2SharedARC
//
//  The tab content editor's working copy of one profile's rich tab content
//  settings: its layout, line limit, overrides, and subtitle. It saves
//  nothing itself. See TabContentModel.swift for what the pieces mean.
//

import AppKit

extension TabContentSlot {
    static let customPrefix = "custom."
}

final class TabContentEditorModel {
    enum ColorChoice: Equatable {
        case normal
        case secondary
        case custom(NSColor)
    }

    struct Line {
        var slot: TabContentSlot
        var style: TabContentLineStyle
    }

    private(set) var layout: TabContentLayout
    // Keyed by slot identifier.
    private(set) var overrides: [String: [String: Any]]
    // The profile's KEY_SUBTITLE, which the subtitle line shows.
    private(set) var subtitleFormat: String
    // The most lines a tab is tall enough for, or nil for no limit.
    private(set) var lineLimit: Int?
    private let originalLayout: TabContentLayout
    private let originalLineLimit: Int?

    // Whether the layout differs from the one the editor started with.
    var layoutChanged: Bool {
        return layout != originalLayout
    }

    var lineLimitChanged: Bool {
        return lineLimit != originalLineLimit
    }

    // The + menu's presets, in groups: the lines that are on by default and
    // Status Detail, then others that are commonly useful.
    static let presetGroups = [[TabContentSlot.titleID,
                                TabContentSlot.subtitleID,
                                TabContentSlot.directoryID,
                                TabContentSlot.jobID,
                                TabContentSlot.statusDetailID],
                               [TabContentSlot.hostID,
                                TabContentSlot.sessionNameID,
                                TabContentSlot.profileNameID,
                                TabContentSlot.commandLineID,
                                TabContentSlot.lastCommandID,
                                TabContentSlot.badgeID,
                                TabContentSlot.tmuxPaneTitleID]]

    static let builtInIdentifiers = presetGroups.flatMap { $0 }

    init(layout: TabContentLayout, overrides: Any?, subtitleFormat: String, lineLimit: Int? = nil) {
        self.layout = layout
        self.originalLayout = layout
        self.lineLimit = lineLimit
        self.originalLineLimit = lineLimit
        var decoded = [String: [String: Any]]()
        for (key, value) in (overrides as? [String: Any]) ?? [:] {
            if let fields = value as? [String: Any] {
                decoded[key] = fields
            }
        }
        self.overrides = decoded
        self.subtitleFormat = subtitleFormat
    }

    var lines: [Line] {
        let resolved = TabContentResolver.resolve(layout: layout,
                                                  overrides: overrides,
                                                  profileSubtitleFormat: subtitleFormat)
        return zip(layout.slots, resolved).map { Line(slot: $0, style: $1.style) }
    }

    static func isBuiltIn(_ identifier: String) -> Bool {
        return builtInIdentifiers.contains(identifier)
    }

    static func displayName(for identifier: String) -> String {
        switch identifier {
        case TabContentSlot.titleID:
            return String(localized: "TabContentEditor.TitleLine",
                          defaultValue: "Title",
                          comment: "Name of the built-in tab content line that shows the tab title")
        case TabContentSlot.subtitleID:
            return String(localized: "TabContentEditor.SubtitleLine",
                          defaultValue: "Subtitle",
                          comment: "Name of the built-in tab content line that shows the profile’s subtitle")
        case TabContentSlot.directoryID:
            return String(localized: "TabContentEditor.DirectoryLine",
                          defaultValue: "Directory",
                          comment: "Name of the built-in tab content line that shows the current directory")
        case TabContentSlot.jobID:
            return String(localized: "TabContentEditor.JobLine",
                          defaultValue: "Job and Status",
                          comment: "Name of the built-in tab content line that shows the running job and its status")
        case TabContentSlot.statusDetailID:
            return String(localized: "TabContentEditor.StatusDetailLine",
                          defaultValue: "Status Detail",
                          comment: "Name of the built-in tab content line that shows the detail text a program reports along with its status, such as what Claude Code is doing")
        case TabContentSlot.hostID:
            return String(localized: "TabContentEditor.HostLine",
                          defaultValue: "Host",
                          comment: "Name of a tab content line that shows the name of the computer the session is on")
        case TabContentSlot.sessionNameID:
            return String(localized: "TabContentEditor.SessionNameLine",
                          defaultValue: "Session Name",
                          comment: "Name of a tab content line that shows the session’s name, as in its title bar")
        case TabContentSlot.profileNameID:
            return String(localized: "TabContentEditor.ProfileNameLine",
                          defaultValue: "Profile Name",
                          comment: "Name of a tab content line that shows the name of the session’s profile")
        case TabContentSlot.commandLineID:
            return String(localized: "TabContentEditor.CommandLineLine",
                          defaultValue: "Command Line",
                          comment: "Name of a tab content line that shows the running command and its arguments")
        case TabContentSlot.lastCommandID:
            return String(localized: "TabContentEditor.LastCommandLine",
                          defaultValue: "Last Command",
                          comment: "Name of a tab content line that shows the last command entered at the shell prompt")
        case TabContentSlot.badgeID:
            return String(localized: "TabContentEditor.BadgeLine",
                          defaultValue: "Badge",
                          comment: "Name of a tab content line that shows the session’s badge text")
        case TabContentSlot.tmuxPaneTitleID:
            return String(localized: "TabContentEditor.TmuxPaneTitleLine",
                          defaultValue: "tmux Pane Title",
                          comment: "Name of a tab content line that shows the title of a tmux pane. Don’t translate tmux, the name of a program.")
        default:
            return String(localized: "TabContentEditor.CustomLine",
                          defaultValue: "Custom",
                          comment: "Name of a tab content line the user added")
        }
    }

    // Whether the line differs from how it is when first added.
    func isCustomized(at index: Int) -> Bool {
        let slot = layout.slots[index]
        return overrides[slot.identifier] != nil || slot != TabContentSlot.preset(identifier: slot.identifier)
    }

    // MARK: - Editing a line's content and style

    func setText(_ text: String, at index: Int) {
        if layout.slots[index].identifier == TabContentSlot.subtitleID {
            subtitleFormat = text
            // A text override would hide the subtitle setting.
            setField(TabContentResolver.Key.text, to: nil, at: index)
            return
        }
        setField(TabContentResolver.Key.text, to: text, at: index)
    }

    func setBold(_ value: Bool, at index: Int) {
        setField(TabContentResolver.Key.bold, to: value, at: index)
    }

    func setItalic(_ value: Bool, at index: Int) {
        setField(TabContentResolver.Key.italic, to: value, at: index)
    }

    func setTruncation(_ value: TabContentTruncation, at index: Int) {
        setField(TabContentResolver.Key.truncation, to: value.storageValue, at: index)
    }

    func setCollapsesWhenEmpty(_ value: Bool, at index: Int) {
        setField(TabContentResolver.Key.collapsesWhenEmpty, to: value, at: index)
    }

    func setHTML(_ value: Bool, at index: Int) {
        setField(TabContentResolver.Key.html, to: value, at: index)
    }

    func colorChoice(at index: Int) -> ColorChoice {
        let style = lines[index].style
        if let color = style.color {
            return .custom(color)
        }
        return style.secondary ? .secondary : .normal
    }

    func setColorChoice(_ choice: ColorChoice, at index: Int) {
        switch choice {
        case .normal:
            removeCustomColors(at: index)
            setField(TabContentResolver.Key.secondary, to: false, at: index)
        case .secondary:
            removeCustomColors(at: index)
            setField(TabContentResolver.Key.secondary, to: true, at: index)
        case .custom(let color):
            setField(TabContentResolver.Key.color, to: (color as NSColor).dictionaryValue, at: index)
        }
    }

    private func removeCustomColors(at index: Int) {
        setField(TabContentResolver.Key.color, to: nil, at: index)
        setField(TabContentResolver.Key.darkColor, to: nil, at: index)
        setField(TabContentResolver.Key.separateColors, to: nil, at: index)
    }

    private func field(_ key: String, at index: Int) -> Any? {
        return overrides[layout.slots[index].identifier]?[key]
    }

    // Whether a custom color has a second color for dark mode.
    func usesSeparateColors(at index: Int) -> Bool {
        return field(TabContentResolver.Key.separateColors, at: index) as? Bool == true
    }

    // The dark mode color, kept while separate colors are off.
    func darkColor(at index: Int) -> NSColor? {
        return (field(TabContentResolver.Key.darkColor, at: index) as? NSDictionary)?.colorValue()
    }

    // Turning separate colors on the first time starts the dark color as the
    // light one, so nothing changes until it's picked.
    func setUsesSeparateColors(_ value: Bool, at index: Int) {
        guard case .custom(let color) = colorChoice(at: index) else {
            return
        }
        if value, darkColor(at: index) == nil {
            setDarkColor(color, at: index)
        }
        setField(TabContentResolver.Key.separateColors, to: value ? true : nil, at: index)
    }

    func setDarkColor(_ color: NSColor, at index: Int) {
        setField(TabContentResolver.Key.darkColor, to: color.dictionaryValue, at: index)
    }

    // Back to how the line is when first added: its size, how many lines it
    // wraps to, what it shows, and how it looks. It keeps its place.
    func reset(at index: Int) {
        let identifier = layout.slots[index].identifier
        overrides.removeValue(forKey: identifier)
        layout.slots[index] = TabContentSlot.preset(identifier: identifier)
    }

    // Records a field for this profile. A value equal to the built-in default
    // removes the field instead, so it isn't a customization.
    private func setField(_ key: String, to value: Any?, at index: Int) {
        let identifier = layout.slots[index].identifier
        var fields = overrides[identifier] ?? [:]
        if let value, !Self.isDefault(value, key: key, slot: identifier) {
            fields[key] = value
        } else {
            fields.removeValue(forKey: key)
        }
        overrides[identifier] = fields.isEmpty ? nil : fields
    }

    private static func isDefault(_ value: Any, key: String, slot identifier: String) -> Bool {
        let style = TabContentResolver.builtInDefaults[identifier] ?? .userAddedDefault
        switch key {
        case TabContentResolver.Key.text:
            // The subtitle's default text is the profile's subtitle, not a
            // fixed value.
            return identifier != TabContentSlot.subtitleID && (value as? String) == style.text
        case TabContentResolver.Key.secondary:
            return (value as? Bool) == style.secondary
        case TabContentResolver.Key.bold:
            return (value as? Bool) == style.bold
        case TabContentResolver.Key.italic:
            return (value as? Bool) == style.italic
        case TabContentResolver.Key.truncation:
            return (value as? String) == style.truncation.storageValue
        case TabContentResolver.Key.collapsesWhenEmpty:
            return (value as? Bool) == style.collapsesWhenEmpty
        case TabContentResolver.Key.html:
            return (value as? Bool) == style.html
        default:
            // Built-in defaults have no color.
            return false
        }
    }

    // MARK: - Editing the layout

    func setSize(_ size: TabContentLineSize, at index: Int) {
        layout.slots[index].size = size
    }

    func setMaximumLines(_ maximumLines: Int, at index: Int) {
        layout.slots[index] = TabContentSlot(identifier: layout.slots[index].identifier,
                                             size: layout.slots[index].size,
                                             maximumLines: maximumLines)
    }

    // nil or a number below 1 means no limit.
    func setLineLimit(_ limit: Int?) {
        if let limit, limit > 0 {
            lineLimit = limit
        } else {
            lineLimit = nil
        }
    }

    var availableBuiltIns: [String] {
        let present = Set(layout.slots.map(\.identifier))
        return Self.builtInIdentifiers.filter { !present.contains($0) }
    }

    func addBuiltIn(_ identifier: String) {
        guard availableBuiltIns.contains(identifier) else {
            return
        }
        layout.slots.append(TabContentSlot.preset(identifier: identifier))
    }

    // Returns the new line's index.
    @discardableResult
    func addCustom() -> Int {
        let identifier = TabContentSlot.customPrefix + UUID().uuidString
        layout.slots.append(TabContentSlot(identifier: identifier, size: .small))
        return layout.slots.count - 1
    }

    var canRemove: Bool {
        return layout.slots.count > 1
    }

    func remove(at index: Int) {
        guard canRemove else {
            return
        }
        let slot = layout.slots.remove(at: index)
        overrides.removeValue(forKey: slot.identifier)
    }

    // to is the destination index after removal.
    func move(from: Int, to: Int) {
        let slot = layout.slots.remove(at: from)
        layout.slots.insert(slot, at: to)
    }

    // MARK: - Preview

    // Stand-ins for common variables, so the preview reads like a real tab.
    private static let sampleValues: [String: String] = [
        // Localization unneeded: sample data for a preview
        "tab.title": "project",
        "path": "~/project",
        "jobName": "claude",
        "status": "Working",
        "session.name": "project",
        "hostname": "localhost",
        "username": "user",
        "session.path": "~/project",
        "session.jobName": "claude",
        "session.hostname": "localhost",
        "session.username": "user",
        "name": "project",
        "profileName": "Default",
        "commandLine": "claude --resume",
        "lastCommand": "make test",
        "badge": "build",
        "tmuxPaneTitle": "server",
        "statusColor": "#34c759",
        "session.statusColor": "#34c759",
        "statusDetail": "Reading the tab bar’s layout code to find where rows get their height",
        "session.statusDetail": "Reading the tab bar’s layout code to find where rows get their height",
    ]

    // A format with each \(…) replaced by a stand-in: a sample value for a
    // well-known variable, or else the last word of the expression.
    static func previewText(for format: String) -> String {
        var result = ""
        var rest = Substring(format)
        while let start = rest.range(of: "\\(") {
            result += rest[..<start.lowerBound]
            var depth = 1
            var i = start.upperBound
            while i < rest.endIndex && depth > 0 {
                switch rest[i] {
                case "(": depth += 1
                case ")": depth -= 1
                default: break
                }
                if depth > 0 {
                    i = rest.index(after: i)
                }
            }
            guard i < rest.endIndex else {
                // Unterminated: show it as typed.
                result += rest[start.lowerBound...]
                return result
            }
            let expression = rest[start.upperBound..<i].trimmingCharacters(in: .whitespaces)
            result += sampleValue(for: expression)
            rest = rest[rest.index(after: i)...]
        }
        result += rest
        return result
    }

    private static func sampleValue(for expression: String) -> String {
        if let value = sampleValues[expression] {
            return value
        }
        if let variable = TabContentSegment.escapedVariable(inExpression: expression) {
            return EscapeHTMLBuiltInFunction.escape(sampleValue(for: variable))
        }
        let callee = expression.split(separator: "(", maxSplits: 1).first.map(String.init) ?? expression
        return callee.split(separator: ".").last.map(String.init) ?? callee
    }
}
