//
//  TabContentModelTests.swift
//  ModernTests
//
//  Rich tab content is a global layout of line slots (how many lines and how
//  big, which fixes the tab height) plus per-profile overrides of what each
//  line shows and how it is styled. These tests cover decoding the stored
//  values and resolving a profile's lines against the built-in defaults.
//

import XCTest
@testable import iTerm2SharedARC

final class TabContentModelTests: XCTestCase {
    // MARK: - Layout

    func testDefaultLayoutHasFourBuiltInSlots() {
        let layout = TabContentLayout.defaultLayout
        XCTAssertEqual(layout.slots.map(\.identifier),
                       [TabContentSlot.titleID,
                        TabContentSlot.subtitleID,
                        TabContentSlot.directoryID,
                        TabContentSlot.jobID])
        XCTAssertEqual(layout.slots.first?.size, .regular)
        XCTAssertTrue(layout.slots.dropFirst().allSatisfy { $0.size == .small })
    }

    func testLayoutRoundTripsThroughPropertyList() {
        let layout = TabContentLayout(slots: [
            TabContentSlot(identifier: "a", size: .large),
            TabContentSlot(identifier: "b", size: .small)])
        XCTAssertEqual(TabContentLayout(propertyList: layout.propertyList), layout)
    }

    // A damaged or foreign value must not leave tabs with no lines at all.
    func testUnreadableLayoutFallsBackToDefault() {
        XCTAssertEqual(TabContentLayout(propertyList: "garbage"), .defaultLayout)
        XCTAssertEqual(TabContentLayout(propertyList: [] as [Any]), .defaultLayout)
        XCTAssertEqual(TabContentLayout(propertyList: nil), .defaultLayout)
    }

    // One bad entry is dropped rather than discarding the user's whole layout.
    func testLayoutSkipsMalformedEntries() {
        let plist: [Any] = [["id": "a", "size": "large"],
                            ["size": "small"],
                            "nonsense",
                            ["id": "b", "size": "enormous"]]
        let layout = TabContentLayout(propertyList: plist)
        XCTAssertEqual(layout.slots, [TabContentSlot(identifier: "a", size: .large),
                                      TabContentSlot(identifier: "b", size: .regular)])
    }

    // Slot identifiers key the per-profile overrides, so a duplicate would make
    // two lines share one override.
    func testLayoutDropsDuplicateIdentifiers() {
        let plist: [Any] = [["id": "a", "size": "large"],
                            ["id": "a", "size": "small"]]
        XCTAssertEqual(TabContentLayout(propertyList: plist).slots,
                       [TabContentSlot(identifier: "a", size: .large)])
    }

    // MARK: - Resolving a profile's lines

    func testBuiltInDefaults() {
        let lines = TabContentResolver.resolve(layout: .defaultLayout,
                                               overrides: nil,
                                               profileSubtitleFormat: "")
        XCTAssertEqual(lines.count, 4)

        XCTAssertEqual(lines[0].format, "\\(tab.title)")
        XCTAssertTrue(lines[0].style.bold)
        XCTAssertFalse(lines[0].style.collapsesWhenEmpty)

        // An empty subtitle is common. Keeping its space stops the lines
        // below from jumping when a subtitle comes and goes.
        XCTAssertFalse(lines[1].style.collapsesWhenEmpty)

        XCTAssertEqual(lines[2].format, "\\(path)")
        XCTAssertEqual(lines[2].style.truncation, .middle)
        XCTAssertTrue(lines[2].style.collapsesWhenEmpty)
        XCTAssertTrue(lines[2].style.secondary)
    }

    // The job line is lightweight HTML by default so it can show the status
    // in the color its program gave it. Its values are escaped so they can't
    // be read as markup. Other built-in lines are plain text.
    func testJobLineDefaultsToHTML() {
        let lines = TabContentResolver.resolve(layout: .defaultLayout, overrides: nil, profileSubtitleFormat: "")
        XCTAssertEqual(lines.map(\.style.html), [false, false, false, true])
        XCTAssertEqual(lines[3].format,
                       "\\(iterm2.escape_html(string: jobName?)) <font color=\"\\(statusColor)\">\\(iterm2.escape_html(string: status?))</font>")
        XCTAssertFalse(TabContentLineStyle.userAddedDefault.html)
    }

    func testHTMLOverride() {
        let lines = TabContentResolver.resolve(layout: .defaultLayout,
                                               overrides: [TabContentSlot.directoryID: ["html": true],
                                                           TabContentSlot.jobID: ["html": false]],
                                               profileSubtitleFormat: "")
        XCTAssertTrue(lines[2].style.html)
        XCTAssertFalse(lines[3].style.html)
    }

    func testRichLineCarriesHTML() {
        let lines = TabContentResolver.resolve(layout: .defaultLayout, overrides: nil, profileSubtitleFormat: "")
        let job = EvaluatedTabContentLine(line: lines[3], values: [])
        XCTAssertTrue(job.richLine.html)
        XCTAssertFalse(EvaluatedTabContentLine(line: lines[2], values: []).richLine.html)
    }

    // The subtitle line shows the profile's existing subtitle setting until
    // the profile overrides it, so turning rich content on keeps what people
    // already configured.
    func testSubtitleLineDefaultsToProfileSubtitle() {
        let lines = TabContentResolver.resolve(layout: .defaultLayout,
                                               overrides: nil,
                                               profileSubtitleFormat: "\\(user.ticket)")
        XCTAssertEqual(lines[1].format, "\\(user.ticket)")
    }

    func testOverrideReplacesOnlyTheFieldsItSets() {
        let overrides: [String: Any] = [
            TabContentSlot.directoryID: ["text": "\\(hostname)", "bold": true]]
        let lines = TabContentResolver.resolve(layout: .defaultLayout,
                                               overrides: overrides,
                                               profileSubtitleFormat: "")
        XCTAssertEqual(lines[2].format, "\\(hostname)")
        XCTAssertTrue(lines[2].style.bold)
        // Not overridden, so still the built-in default for this line.
        XCTAssertEqual(lines[2].style.truncation, .middle)
        XCTAssertTrue(lines[2].style.collapsesWhenEmpty)
    }

    func testOverrideOfSubtitleLineBeatsProfileSubtitle() {
        let overrides: [String: Any] = [TabContentSlot.subtitleID: ["text": "custom"]]
        let lines = TabContentResolver.resolve(layout: .defaultLayout,
                                               overrides: overrides,
                                               profileSubtitleFormat: "from profile")
        XCTAssertEqual(lines[1].format, "custom")
    }

    // A line the user added has no built-in default. It starts empty and
    // collapses, so adding it changes nothing until it is given text.
    func testUserAddedSlotStartsEmptyAndCollapses() {
        let layout = TabContentLayout(slots: [TabContentSlot(identifier: "user.1", size: .small)])
        let lines = TabContentResolver.resolve(layout: layout,
                                               overrides: nil,
                                               profileSubtitleFormat: "")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].format, "")
        XCTAssertTrue(lines[0].style.collapsesWhenEmpty)
        XCTAssertEqual(lines[0].size, .small)
    }

    func testResolvedLinesFollowLayoutOrderAndSizes() {
        let layout = TabContentLayout(slots: [
            TabContentSlot(identifier: TabContentSlot.jobID, size: .large),
            TabContentSlot(identifier: TabContentSlot.titleID, size: .small)])
        let lines = TabContentResolver.resolve(layout: layout,
                                               overrides: nil,
                                               profileSubtitleFormat: "")
        XCTAssertEqual(lines.map(\.slotIdentifier), [TabContentSlot.jobID, TabContentSlot.titleID])
        XCTAssertEqual(lines.map(\.size), [.large, .small])
    }

    func testOverrideColorAndTruncationDecode() {
        let color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let overrides: [String: Any] = [
            TabContentSlot.titleID: ["color": color.dictionaryValue,
                                     "truncation": "start",
                                     "italic": true]]
        let lines = TabContentResolver.resolve(layout: .defaultLayout,
                                               overrides: overrides,
                                               profileSubtitleFormat: "")
        let resolved = try? XCTUnwrap(lines[0].style.color)
        XCTAssertEqual(resolved?.usingColorSpace(.sRGB)?.redComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(lines[0].style.truncation, .start)
        XCTAssertTrue(lines[0].style.italic)
    }

    // A line can have a second color for dark mode. It applies only while
    // separate colors are on, so turning them off keeps it for next time.
    func testDarkColorAppliesOnlyWithSeparateColors() {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        func resolved(separate: Any?) -> TabContentLineStyle {
            var fields: [String: Any] = ["color": red.dictionaryValue, "darkColor": blue.dictionaryValue]
            fields["separateColors"] = separate
            return TabContentResolver.resolve(layout: .defaultLayout,
                                              overrides: [TabContentSlot.titleID: fields],
                                              profileSubtitleFormat: "")[0].style
        }
        let separate = resolved(separate: true)
        XCTAssertEqual(separate.darkColor?.usingColorSpace(.sRGB)?.blueComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(separate.color?.usingColorSpace(.sRGB)?.redComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertNil(resolved(separate: false).darkColor)
        XCTAssertNil(resolved(separate: nil).darkColor)
        XCTAssertNil(resolved(separate: "yes").darkColor)

        // A dark color without a light one isn't a custom color.
        let noLight: [String: Any] = ["darkColor": blue.dictionaryValue, "separateColors": true]
        XCTAssertNil(TabContentResolver.resolve(layout: .defaultLayout,
                                                overrides: [TabContentSlot.titleID: noLight],
                                                profileSubtitleFormat: "")[0].style.darkColor)
    }

    // The tab bar gets both colors and picks one as it draws.
    func testRichLineCarriesTheDarkColor() {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let fields: [String: Any] = ["color": red.dictionaryValue, "darkColor": blue.dictionaryValue, "separateColors": true]
        let line = TabContentResolver.resolve(layout: .defaultLayout,
                                              overrides: [TabContentSlot.titleID: fields],
                                              profileSubtitleFormat: "")[0]
        let rich = EvaluatedTabContentLine(line: line, values: []).richLine(text: "x")
        XCTAssertEqual(rich.darkColor?.usingColorSpace(.sRGB)?.blueComponent ?? 0, 1, accuracy: 0.01)
    }

    // Wrong types in a hand-edited plist fall back to defaults instead of
    // crashing or producing a half-decoded line.
    func testOverrideWithWrongTypesIsIgnoredFieldByField() {
        let overrides: [String: Any] = [
            TabContentSlot.titleID: ["text": 42, "bold": "yes", "truncation": "sideways"],
            TabContentSlot.jobID: "not a dictionary"]
        let lines = TabContentResolver.resolve(layout: .defaultLayout,
                                               overrides: overrides,
                                               profileSubtitleFormat: "")
        XCTAssertEqual(lines[0].format, "\\(tab.title)")
        XCTAssertTrue(lines[0].style.bold)
        XCTAssertEqual(lines[0].style.truncation, .end)
        XCTAssertEqual(lines[3].format, TabContentResolver.builtInDefaults[TabContentSlot.jobID]?.text)
    }

    // MARK: - Height

    // Height comes only from the layout: the number of lines and their sizes.
    func testRequiredHeightGrowsWithLinesAndSize() {
        let one = TabContentSettings.requiredHeight(
            layout: TabContentLayout(slots: [TabContentSlot(identifier: "a", size: .regular)]),
            baseFontSize: 11)
        let two = TabContentSettings.requiredHeight(
            layout: TabContentLayout(slots: [TabContentSlot(identifier: "a", size: .regular),
                                             TabContentSlot(identifier: "b", size: .small)]),
            baseFontSize: 11)
        let twoLarge = TabContentSettings.requiredHeight(
            layout: TabContentLayout(slots: [TabContentSlot(identifier: "a", size: .regular),
                                             TabContentSlot(identifier: "b", size: .large)]),
            baseFontSize: 11)
        XCTAssertGreaterThan(two, one)
        XCTAssertGreaterThan(twoLarge, two)
    }

    func testRequiredHeightFitsTheContentWithPadding() {
        let layout = TabContentLayout.defaultLayout
        let font = NSFont.systemFont(ofSize: 11)
        let lines = layout.slots.map {
            PSMTabRichLine(text: "x", scale: $0.size.scale, bold: false, italic: false, color: nil,
                           secondary: false, lineBreakMode: .byTruncatingTail, collapsesWhenEmpty: false)
        }
        let content = PSMTabRichContentRenderer.contentHeight(lines: lines, baseFont: font)
        XCTAssertGreaterThan(TabContentSettings.requiredHeight(layout: layout, baseFontSize: 11), content)
    }

    func testLargerFontNeedsMoreHeight() {
        let layout = TabContentLayout.defaultLayout
        XCTAssertGreaterThan(TabContentSettings.requiredHeight(layout: layout, baseFontSize: 14),
                             TabContentSettings.requiredHeight(layout: layout, baseFontSize: 11))
    }

    // MARK: - Lines that wrap

    // A slot can wrap onto more than one line. That affects the tab's
    // height, so it's part of the global layout, like size.
    func testMaximumLinesRoundTripsAndDefaultsToOne() {
        let layout = TabContentLayout(slots: [
            TabContentSlot(identifier: "a", size: .small, maximumLines: 3),
            TabContentSlot(identifier: "b", size: .small)])
        XCTAssertEqual(TabContentLayout(propertyList: layout.propertyList), layout)
        XCTAssertEqual(layout.slots[1].maximumLines, 1)
        // One line is the default, so it isn't written out.
        XCTAssertNil(layout.propertyList[1]["lines"])
    }

    func testMaximumLinesIsClamped() {
        let layout = TabContentLayout(propertyList: [["id": "a", "lines": 9],
                                                     ["id": "b", "lines": 0],
                                                     ["id": "c", "lines": "two"]])
        XCTAssertEqual(layout.slots.map(\.maximumLines), [3, 1, 1])
    }

    func testRequiredHeightCountsEveryLineASlotCanWrapTo() {
        func height(_ lines: Int) -> CGFloat {
            return TabContentSettings.requiredHeight(
                layout: TabContentLayout(slots: [TabContentSlot(identifier: "a", size: .small, maximumLines: lines)]),
                baseFontSize: 11)
        }
        let one = PSMTabRichContentRenderer.height(
            for: PSMTabRichLine(text: "", scale: TabContentLineSize.small.scale, bold: false, italic: false,
                                color: nil, secondary: false, lineBreakMode: .byTruncatingTail,
                                collapsesWhenEmpty: false),
            baseFont: NSFont.systemFont(ofSize: 11))
        XCTAssertEqual(height(3) - height(1), one * 2, accuracy: 1)
    }

    // MARK: - Limiting tabs to a number of lines

    private var tallLayout: TabContentLayout {
        return TabContentLayout(slots: [TabContentSlot(identifier: "title", size: .regular),
                                        TabContentSlot(identifier: "dir", size: .small),
                                        TabContentSlot(identifier: "detail", size: .small, maximumLines: 3),
                                        TabContentSlot(identifier: "job", size: .small)])
    }

    func testLimitKeepsTheSlotsThatFit() {
        XCTAssertEqual(tallLayout.slots(limitedToLines: nil), tallLayout.slots)
        XCTAssertEqual(tallLayout.slots(limitedToLines: 99), tallLayout.slots)
        XCTAssertEqual(tallLayout.slots(limitedToLines: 2).map(\.identifier), ["title", "dir"])
    }

    // A slot that wraps keeps as many of its lines as fit.
    func testLimitCutsAWrappingSlotShort() {
        let slots = tallLayout.slots(limitedToLines: 4)
        XCTAssertEqual(slots.map(\.identifier), ["title", "dir", "detail"])
        XCTAssertEqual(slots.map(\.maximumLines), [1, 1, 2])
    }

    func testLimitLowersTheRequiredHeight() {
        let limited = TabContentSettings.requiredHeight(layout: tallLayout, maximumLines: 4, baseFontSize: 11)
        let truncated = TabContentSettings.requiredHeight(layout: TabContentLayout(slots: tallLayout.slots(limitedToLines: 4)),
                                                          maximumLines: nil,
                                                          baseFontSize: 11)
        XCTAssertEqual(limited, truncated)
        XCTAssertLessThan(limited, TabContentSettings.requiredHeight(layout: tallLayout, maximumLines: nil, baseFontSize: 11))
    }

    // The title line has room under it, and tabs are tall enough for it.
    // Other lines don't.
    func testTitleLineHasSpacingAfterIt() {
        XCTAssertGreaterThan(TabContentSlot.spacingAfter(identifier: TabContentSlot.titleID), 0)
        XCTAssertEqual(TabContentSlot.spacingAfter(identifier: TabContentSlot.directoryID), 0)
        let withTitle = TabContentLayout(slots: [TabContentSlot(identifier: TabContentSlot.titleID, size: .small),
                                                 TabContentSlot(identifier: TabContentSlot.directoryID, size: .small)])
        let without = TabContentLayout(slots: [TabContentSlot(identifier: TabContentSlot.jobID, size: .small),
                                               TabContentSlot(identifier: TabContentSlot.directoryID, size: .small)])
        XCTAssertEqual(TabContentSettings.requiredHeight(layout: withTitle, baseFontSize: 11),
                       TabContentSettings.requiredHeight(layout: without, baseFontSize: 11) +
                       TabContentSlot.spacingAfter(identifier: TabContentSlot.titleID))
        let lines = TabContentConfiguration(profile: [KEY_SHOW_RICH_TAB_CONTENT: true]).resolvedLines
        let evaluated = lines.map { EvaluatedTabContentLine(line: $0, values: []) }
        XCTAssertEqual(evaluated[0].richLine.spacingAfter, TabContentSlot.spacingAfter(identifier: TabContentSlot.titleID))
        XCTAssertEqual(evaluated[1].richLine.spacingAfter, 0)
    }

    // A window's settings come from a profile. Missing values are the
    // defaults: off, the default layout, and no line limit.
    func testConfigurationDefaults() {
        let configuration = TabContentConfiguration(profile: [:])
        XCTAssertFalse(configuration.enabled)
        XCTAssertEqual(configuration.layout, .defaultLayout)
        XCTAssertNil(configuration.lineLimit)
        XCTAssertEqual(configuration.minimumTabHeight(fontSize: 11), 0, "off needs no height")
    }

    func testConfigurationFromProfile() {
        let layout = TabContentLayout(slots: [TabContentSlot(identifier: TabContentSlot.titleID, size: .large),
                                              TabContentSlot(identifier: TabContentSlot.subtitleID, size: .small),
                                              TabContentSlot(identifier: TabContentSlot.jobID, size: .small)])
        let profile: [AnyHashable: Any] = [
            KEY_SHOW_RICH_TAB_CONTENT: true,
            KEY_TAB_CONTENT_LAYOUT: layout.propertyList,
            KEY_TAB_CONTENT_MAXIMUM_LINES: 2,
            KEY_TAB_CONTENT_LINES: [TabContentSlot.titleID: [TabContentResolver.Key.bold: false]],
            KEY_SUBTITLE: "\\(user.sub)",
        ]
        let configuration = TabContentConfiguration(profile: profile)
        XCTAssertTrue(configuration.enabled)
        XCTAssertEqual(configuration.layout, layout)
        XCTAssertEqual(configuration.lineLimit, 2)
        XCTAssertEqual(configuration.limitedLayout.slots.map(\.identifier),
                       [TabContentSlot.titleID, TabContentSlot.subtitleID])
        let lines = configuration.resolvedLines
        XCTAssertEqual(lines.count, 2, "cut to the limit")
        XCTAssertEqual(lines[0].style.bold, false, "the profile's override")
        XCTAssertEqual(lines[1].format, "\\(user.sub)", "the subtitle line shows the profile's subtitle")
        XCTAssertGreaterThan(configuration.minimumTabHeight(fontSize: 11), 0)
    }

    // 0, the default, means no limit.
    func testConfigurationLineLimitZeroMeansNone() {
        let configuration = TabContentConfiguration(profile: [KEY_TAB_CONTENT_MAXIMUM_LINES: 0])
        XCTAssertNil(configuration.lineLimit)
    }

    // A window redraws only when its settings really change.
    func testConfigurationEquality() {
        let profile: [AnyHashable: Any] = [KEY_SHOW_RICH_TAB_CONTENT: true,
                                           KEY_TAB_CONTENT_LINES: [TabContentSlot.titleID: [TabContentResolver.Key.bold: false]]]
        XCTAssertEqual(TabContentConfiguration(profile: profile), TabContentConfiguration(profile: profile))
        var changed = profile
        changed[KEY_TAB_CONTENT_LINES] = [TabContentSlot.titleID: [TabContentResolver.Key.bold: true]]
        XCTAssertNotEqual(TabContentConfiguration(profile: profile), TabContentConfiguration(profile: changed))
        changed = profile
        changed[KEY_SUBTITLE] = "x"
        XCTAssertNotEqual(TabContentConfiguration(profile: profile), TabContentConfiguration(profile: changed))
        changed = profile
        changed[KEY_SHOW_RICH_TAB_CONTENT] = false
        XCTAssertNotEqual(TabContentConfiguration(profile: profile), TabContentConfiguration(profile: changed))
    }

    // The status detail preset wraps onto three small lines and shows the
    // session's status detail.
    func testStatusDetailPreset() {
        let slot = TabContentSlot.preset(identifier: TabContentSlot.statusDetailID)
        XCTAssertEqual(slot.size, .small)
        XCTAssertEqual(slot.maximumLines, 3)
        let style = TabContentResolver.builtInDefaults[TabContentSlot.statusDetailID]
        XCTAssertEqual(style?.text, "\\(statusDetail)")
        XCTAssertEqual(style?.secondary, true)
        XCTAssertEqual(style?.collapsesWhenEmpty, true)
        XCTAssertFalse(TabContentLayout.defaultLayout.slots.contains { $0.identifier == TabContentSlot.statusDetailID },
                       "it would make every tab three lines taller")
    }

    func testResolvedAndEvaluatedLinesCarryMaximumLines() {
        let layout = TabContentLayout(slots: [TabContentSlot(identifier: "a", size: .small, maximumLines: 2)])
        let resolved = TabContentResolver.resolve(layout: layout,
                                                  overrides: ["a": ["text": "x"]],
                                                  profileSubtitleFormat: "")
        XCTAssertEqual(resolved[0].maximumLines, 2)
        let evaluated = EvaluatedTabContentLine(line: resolved[0]) { _ in "one\ntwo" }
        XCTAssertEqual(evaluated.richLine.maximumLines, 2)
        // A line that can wrap keeps its line breaks.
        XCTAssertEqual(evaluated.text, "one\ntwo")
    }

    func testSingleLineFlattensLineBreaks() {
        let layout = TabContentLayout(slots: [TabContentSlot(identifier: "a", size: .small)])
        let resolved = TabContentResolver.resolve(layout: layout, overrides: ["a": ["text": "x"]], profileSubtitleFormat: "")
        XCTAssertEqual(EvaluatedTabContentLine(line: resolved[0]) { _ in "one\ntwo" }.text, "one two")
    }

    // Blank lines would use up a wrapping line's few lines with nothing.
    func testWrappingLineDropsBlankLines() {
        let layout = TabContentLayout(slots: [TabContentSlot(identifier: "a", size: .small, maximumLines: 3)])
        let resolved = TabContentResolver.resolve(layout: layout, overrides: ["a": ["text": "x"]], profileSubtitleFormat: "")
        XCTAssertEqual(EvaluatedTabContentLine(line: resolved[0]) { _ in "\n\n one\n\n\ntwo \n" }.text, "one\ntwo")
        XCTAssertTrue(EvaluatedTabContentLine(line: resolved[0]) { _ in "\n \n" }.richLine.isBlank)
    }

    // Programs may report detail with Windows line endings or Unicode line
    // separators.
    // In an HTML line that wraps, a row that's only markup is blank too.
    func testWrappingHTMLLineDropsRowsOfOnlyMarkup() {
        var line = ResolvedTabContentLine(slotIdentifier: "x", size: .small, format: "", style: .userAddedDefault, maximumLines: 3)
        line.style.html = true
        let evaluated = EvaluatedTabContentLine(line: line, values: [])
        XCTAssertEqual(evaluated.flattened("a\n<font color=\"\"></font>\nb"), "a\n<font color=\"\"></font>b")
    }

    // Tags in a dropped row still apply: its markup joins the next row, or the
    // previous one at the end.
    func testWrappingHTMLLineKeepsTheMarkupOfDroppedRows() {
        var line = ResolvedTabContentLine(slotIdentifier: "x", size: .small, format: "", style: .userAddedDefault, maximumLines: 3)
        line.style.html = true
        let evaluated = EvaluatedTabContentLine(line: line, values: [])
        XCTAssertEqual(evaluated.flattened("<font color=\"#f00\">\nline1\nline2</font>"),
                       "<font color=\"#f00\">line1\nline2</font>")
        XCTAssertEqual(evaluated.flattened("a <b>bold\n</b>\nrest"), "a <b>bold\n</b>rest")
        XCTAssertEqual(evaluated.flattened("a\n<b></b>"), "a<b></b>", "markup at the end joins the last row")
    }

    func testWrappingLineTreatsEveryKindOfLineBreakAlike() {
        let layout = TabContentLayout(slots: [TabContentSlot(identifier: "a", size: .small, maximumLines: 3)])
        let resolved = TabContentResolver.resolve(layout: layout, overrides: ["a": ["text": "x"]], profileSubtitleFormat: "")
        XCTAssertEqual(EvaluatedTabContentLine(line: resolved[0]) { _ in "a\r\n\r\nb\u{2028}c" }.text, "a\nb\nc")
    }
}
