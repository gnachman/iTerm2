//
//  TabContentEvaluator.swift
//  iTerm2SharedARC
//
//  Evaluates a session's rich tab content lines (see TabContentModel.swift)
//  in the session's variable scope, and reports when the result changes so
//  the tab can redraw.
//

import AppKit

@objc(iTermTabContentEvaluator)
final class TabContentEvaluator: NSObject {
    // A line is evaluated a segment at a time (see TabContentSegment), so a
    // collapsed group can combine its members' jobs and statuses.
    private struct Entry {
        var line: ResolvedTabContentLine
        var segments: [(kind: TabContentSegment.Kind, swiftyString: iTermSwiftyString)]

        func invalidate() {
            for segment in segments {
                segment.swiftyString.invalidate()
            }
        }
    }

    private let scope: iTermVariableScope
    private let onChange: () -> Void
    private var entries = [Entry]()
    // What callers see, rebuilt by refresh(). Tab styles read the lines every
    // time they measure or draw a tab, so they're built once per change.
    private(set) var evaluatedLines = [EvaluatedTabContentLine]()
    @objc private(set) var richLines = [PSMTabRichLine]()
    private var refreshScheduled = false

    @objc init(scope: iTermVariableScope, onChange: @escaping () -> Void) {
        self.scope = scope
        self.onChange = onChange
        super.init()
    }

    deinit {
        invalidate()
    }

    @objc func invalidate() {
        for entry in entries {
            entry.invalidate()
        }
        entries = []
        evaluatedLines = []
        richLines = []
    }

    // Rebuilds from a window's configuration.
    @objc(updateWithConfiguration:)
    func update(configuration: TabContentConfiguration) {
        update(lines: configuration.resolvedLines)
    }

    func update(lines: [ResolvedTabContentLine]) {
        // Reuse a slot's evaluators when its format is unchanged so its value
        // doesn't blank out while it re-evaluates.
        var reusable = [String: Entry]()
        for entry in entries {
            reusable[entry.line.slotIdentifier] = entry
        }
        var newEntries = [Entry]()
        for line in lines {
            // Only claim the old evaluators when they can be reused, so ones
            // whose format changed stay in reusable and are invalidated below.
            if let existing = reusable[line.slotIdentifier],
               existing.line.format == line.format,
               existing.line.style.html == line.style.html {
                reusable.removeValue(forKey: line.slotIdentifier)
                newEntries.append(Entry(line: line, segments: existing.segments))
                continue
            }
            let segments = TabContentSegment.split(line.format).map {
                (kind: $0.kind, swiftyString: makeSwiftyString($0.source, html: line.style.html))
            }
            newEntries.append(Entry(line: line, segments: segments))
        }
        for leftover in reusable.values {
            leftover.invalidate()
        }
        entries = newEntries
        refresh()
    }

    // Publishes the current values, reporting a change only when they
    // differ from what was published before. A profile reload that changes
    // nothing visible then costs the tab bar nothing.
    private func refresh() {
        let lines = entries.map { entry in
            EvaluatedTabContentLine(line: entry.line,
                                    values: entry.segments.map {
                                        EvaluatedTabContentLine.Value(kind: $0.kind,
                                                                      text: $0.swiftyString.evaluatedString ?? "")
                                    })
        }
        guard lines != evaluatedLines else {
            return
        }
        evaluatedLines = lines
        richLines = lines.map(\.richLine)
        onChange()
    }

    // Segments that change together, as when several depend on one variable,
    // cause one refresh.
    private func scheduleRefresh() {
        guard !refreshScheduled else {
            return
        }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            refreshScheduled = false
            refresh()
        }
    }

    // html: the line is HTML, so error text is escaped to show as written.
    private func makeSwiftyString(_ format: String, html: Bool) -> iTermSwiftyString {
        return iTermSwiftyString(string: format,
                                 scope: scope,
                                 sideEffectsAllowed: false) { [weak self] newValue, error in
            // evaluatedString takes the new value only after this returns,
            // so refresh later. That includes the error text below. The
            // observer may also run during init, before the entry exists, in
            // which case update(lines:) refreshes too.
            self?.scheduleRefresh()
            if let error {
                let text = "🐞 \(error.localizedDescription)"
                return html ? EscapeHTMLBuiltInFunction.escape(text) : text
            }
            return newValue ?? ""
        }
    }

    @objc var snapshot: TabContentSnapshot {
        return TabContentSnapshot(lines: evaluatedLines)
    }
}

extension TabContentTruncation {
    var lineBreakMode: NSLineBreakMode {
        switch self {
        case .end: return .byTruncatingTail
        case .middle: return .byTruncatingMiddle
        case .start: return .byTruncatingHead
        }
    }
}

// Rich tab content settings that don't depend on a window.
@objc(iTermTabContentSettings)
final class TabContentSettings: NSObject {
    // Space above and below the block of lines in a tab.
    private static let verticalPadding: CGFloat = 4

    // The tab height rich content needs: every line in the layout, empty or
    // not, up to maximumLines, plus padding. It depends only on the layout,
    // the limit, and the font size, so it is the same for every tab in a
    // window and changes only when the user edits them. Weight doesn't
    // affect it, so making a line bold can't change it.
    static func requiredHeight(layout: TabContentLayout,
                               maximumLines: Int? = nil,
                               baseFontSize: CGFloat) -> CGFloat {
        let lines = layout.slots(limitedToLines: maximumLines).map {
            PSMTabRichLine(text: "",
                           scale: $0.size.scale,
                           bold: false,
                           italic: false,
                           color: nil,
                           secondary: false,
                           lineBreakMode: .byTruncatingTail,
                           collapsesWhenEmpty: false,
                           maximumLines: $0.maximumLines,
                           spacingAfter: TabContentSlot.spacingAfter(identifier: $0.identifier))
        }
        let content = PSMTabRichContentRenderer.contentHeight(lines: lines,
                                                              baseFont: NSFont.systemFont(ofSize: baseFontSize))
        return ceil(content + verticalPadding * 2)
    }

    // The font size most styles draw at. High contrast styles draw larger, so
    // prefer the style's own fontSize when there is one.
    @objc static var defaultFontSize: CGFloat {
        return iTermAdvancedSettingsModel.useCustomTabBarFontSize()
            ? CGFloat(iTermAdvancedSettingsModel.customTabBarFontSize())
            : 11
    }
}

// A window's rich tab content settings. They come from the profile the window
// follows (see KEY_SHOW_RICH_TAB_CONTENT), and apply to every tab in the
// window. Immutable: the window makes a new one when the profile changes.
@objc(iTermTabContentConfiguration)
final class TabContentConfiguration: NSObject {
    @objc let enabled: Bool
    let layout: TabContentLayout
    // The most lines a tab is tall enough for, or nil for no limit.
    let lineLimit: Int?
    // The profile's KEY_TAB_CONTENT_LINES.
    let overrides: NSDictionary?
    // The profile's KEY_SUBTITLE, which the subtitle line shows.
    let subtitleFormat: String

    // The profile keys a configuration is made from. A window keeps a copy
    // of these so it still has them if its profile is deleted.
    @objc static let profileKeys = [KEY_SHOW_RICH_TAB_CONTENT,
                                    KEY_TAB_CONTENT_LAYOUT,
                                    KEY_TAB_CONTENT_MAXIMUM_LINES,
                                    KEY_TAB_CONTENT_LINES,
                                    KEY_SUBTITLE]

    @objc static let disabled = TabContentConfiguration(enabled: false,
                                                        layout: .defaultLayout,
                                                        lineLimit: nil,
                                                        overrides: nil,
                                                        subtitleFormat: "")

    init(enabled: Bool,
         layout: TabContentLayout,
         lineLimit: Int?,
         overrides: NSDictionary?,
         subtitleFormat: String) {
        self.enabled = enabled
        self.layout = layout
        if let lineLimit, lineLimit > 0 {
            self.lineLimit = lineLimit
        } else {
            self.lineLimit = nil
        }
        self.overrides = overrides
        self.subtitleFormat = subtitleFormat
    }

    @objc(initWithProfile:)
    convenience init(profile: [AnyHashable: Any]) {
        let overrides = iTermProfilePreferences.object(forKey: KEY_TAB_CONTENT_LINES, inProfile: profile) as? NSDictionary
        self.init(enabled: iTermProfilePreferences.bool(forKey: KEY_SHOW_RICH_TAB_CONTENT, inProfile: profile),
                  layout: TabContentLayout(propertyList: iTermProfilePreferences.object(forKey: KEY_TAB_CONTENT_LAYOUT,
                                                                                        inProfile: profile)),
                  lineLimit: iTermProfilePreferences.integer(forKey: KEY_TAB_CONTENT_MAXIMUM_LINES, inProfile: profile),
                  overrides: overrides,
                  subtitleFormat: iTermProfilePreferences.string(forKey: KEY_SUBTITLE, inProfile: profile) ?? "")
    }

    // The layout cut to the line limit: what tabs and collapsed groups'
    // chips actually show. Cutting the lines, not just the height, keeps a
    // tab bar that's taller for another reason from showing more.
    var limitedLayout: TabContentLayout {
        guard let lineLimit else {
            return layout
        }
        return TabContentLayout(slots: layout.slots(limitedToLines: lineLimit))
    }

    // What each line shows and how it looks.
    var resolvedLines: [ResolvedTabContentLine] {
        return TabContentResolver.resolve(layout: limitedLayout,
                                          overrides: overrides,
                                          profileSubtitleFormat: subtitleFormat)
    }

    // The minimum tab cell height at the font size the tab style draws at,
    // or 0 when rich content is off.
    @objc(minimumTabHeightWithFontSize:)
    func minimumTabHeight(fontSize: CGFloat) -> CGFloat {
        guard enabled else {
            return 0
        }
        return TabContentSettings.requiredHeight(layout: layout, maximumLines: lineLimit, baseFontSize: fontSize)
    }

    // minimumTabHeight(fontSize:) at the style's font size, plus the height
    // it spends on chrome. 0 when rich content is off.
    @objc(minimumTabHeightForStyle:)
    func minimumTabHeight(style: PSMTabStyle?) -> CGFloat {
        let height = minimumTabHeight(fontSize: style?.fontSize ?? TabContentSettings.defaultFontSize)
        guard height > 0 else {
            return 0
        }
        return height + (style?.richContentChromeHeight ?? 0)
    }

    // minimumTabHeight(fontSize:) at the default font size.
    @objc var minimumTabHeight: CGFloat {
        return minimumTabHeight(fontSize: TabContentSettings.defaultFontSize)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TabContentConfiguration else {
            return false
        }
        return enabled == other.enabled &&
            layout == other.layout &&
            lineLimit == other.lineLimit &&
            (overrides ?? [:]).isEqual(other.overrides ?? [:]) &&
            subtitleFormat == other.subtitleFormat
    }

    override var hash: Int {
        return layout.slots.count &+ (enabled ? 1 : 0)
    }

    override var description: String {
        return "<TabContentConfiguration enabled=\(enabled) slots=\(layout.slots.map(\.identifier)) limit=\(String(describing: lineLimit))>"
    }
}
