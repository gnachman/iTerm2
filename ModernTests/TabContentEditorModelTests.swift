//
//  TabContentEditorModelTests.swift
//  ModernTests
//
//  The tab content editor edits a working copy of the global layout and one
//  profile's overrides. These tests pin down what each edit writes.
//

import XCTest
@testable import iTerm2SharedARC

final class TabContentEditorModelTests: XCTestCase {
    private func makeModel(layout: TabContentLayout = .defaultLayout,
                           overrides: Any? = nil,
                           subtitle: String = "\\(session.name)") -> TabContentEditorModel {
        return TabContentEditorModel(layout: layout, overrides: overrides, subtitleFormat: subtitle)
    }

    private func index(_ model: TabContentEditorModel, _ id: String) -> Int {
        return model.layout.slots.firstIndex { $0.identifier == id }!
    }

    // HTML is a per-profile setting like bold. Matching the built-in default
    // isn't a customization.
    func testHTMLIsAProfileOverride() {
        let model = makeModel()
        let directory = index(model, TabContentSlot.directoryID)
        model.setHTML(true, at: directory)
        XCTAssertEqual(model.overrides[TabContentSlot.directoryID]?["html"] as? Bool, true)
        XCTAssertTrue(model.lines[directory].style.html)
        model.setHTML(false, at: directory)
        XCTAssertNil(model.overrides[TabContentSlot.directoryID])

        let job = index(model, TabContentSlot.jobID)
        model.setHTML(true, at: job)
        XCTAssertNil(model.overrides[TabContentSlot.jobID], "the job line is HTML by default")
    }

    // The preview stands in for escaped values and the status color too.
    func testPreviewOfEscapedValues() {
        XCTAssertEqual(TabContentEditorModel.previewText(for: "\\(iterm2.escape_html(string: jobName?)) <font color=\"\\(statusColor)\">\\(iterm2.escape_html(string: status?))</font>"),
                       "claude <font color=\"#34c759\">Working</font>")
    }

    func testLineLimit() {
        let model = TabContentEditorModel(layout: .defaultLayout, overrides: nil, subtitleFormat: "", lineLimit: 3)
        XCTAssertEqual(model.lineLimit, 3)
        XCTAssertFalse(model.lineLimitChanged)
        model.setLineLimit(0)
        XCTAssertNil(model.lineLimit, "0 means no limit")
        XCTAssertTrue(model.lineLimitChanged)
        model.setLineLimit(3)
        XCTAssertFalse(model.lineLimitChanged, "back where it started")
    }

    func testLinesResolveLikeTabsDo() {
        let model = makeModel(overrides: [TabContentSlot.directoryID: ["bold": true]])
        let expected = TabContentResolver.resolve(layout: .defaultLayout,
                                                  overrides: [TabContentSlot.directoryID: ["bold": true]],
                                                  profileSubtitleFormat: "\\(session.name)")
        XCTAssertEqual(model.lines.map(\.style.text), expected.map(\.style.text))
        XCTAssertEqual(model.lines.map(\.style.bold), expected.map(\.style.bold))
    }

    // Editing one field records only that field, so the others keep
    // following the built-in default.
    func testEditingAFieldOverridesOnlyThatField() {
        let model = makeModel()
        let i = index(model, TabContentSlot.directoryID)
        XCTAssertFalse(model.isCustomized(at: i))
        model.setBold(true, at: i)
        XCTAssertEqual(model.overrides[TabContentSlot.directoryID] as NSDictionary?,
                       ["bold": true] as NSDictionary)
        XCTAssertTrue(model.isCustomized(at: i))
        XCTAssertTrue(model.lines[i].style.bold)
    }

    func testTextAndStyleFieldsAreStored() {
        let model = makeModel()
        let i = index(model, TabContentSlot.jobID)
        model.setText("\\(user.x)", at: i)
        model.setItalic(true, at: i)
        model.setTruncation(.start, at: i)
        model.setCollapsesWhenEmpty(false, at: i)
        let resolved = TabContentResolver.resolve(layout: model.layout,
                                                  overrides: model.overrides,
                                                  profileSubtitleFormat: model.subtitleFormat)[i]
        XCTAssertEqual(resolved.style.text, "\\(user.x)")
        XCTAssertTrue(resolved.style.italic)
        XCTAssertEqual(resolved.style.truncation, .start)
        XCTAssertFalse(resolved.style.collapsesWhenEmpty)
    }

    // The subtitle line shows the profile's subtitle setting, so editing its
    // text edits that setting rather than adding a second copy.
    func testSubtitleTextEditsTheProfileSubtitle() {
        let model = makeModel(subtitle: "old")
        let i = index(model, TabContentSlot.subtitleID)
        model.setText("new", at: i)
        XCTAssertEqual(model.subtitleFormat, "new")
        XCTAssertNil(model.overrides[TabContentSlot.subtitleID])
        XCTAssertEqual(model.lines[i].style.text, "new")
    }

    func testColorChoices() {
        let model = makeModel()
        let i = index(model, TabContentSlot.titleID)
        XCTAssertEqual(model.colorChoice(at: i), .normal)

        model.setColorChoice(.secondary, at: i)
        XCTAssertEqual(model.colorChoice(at: i), .secondary)

        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        model.setColorChoice(.custom(red), at: i)
        guard case .custom(let color) = model.colorChoice(at: i) else {
            XCTFail("expected a custom color")
            return
        }
        XCTAssertEqual(color.usingColorSpace(.sRGB)!.redComponent, 1, accuracy: 0.01)

        model.setColorChoice(.normal, at: i)
        XCTAssertEqual(model.colorChoice(at: i), .normal)
        XCTAssertNil(model.lines[i].style.color)
        XCTAssertFalse(model.lines[i].style.secondary)
    }

    // Separate colors start with the dark color matching the light one, so
    // turning them on changes nothing until the dark color is picked.
    // Turning them off keeps the dark color for next time; choosing a color
    // that isn't Custom drops it.
    func testSeparateDarkColor() {
        let model = makeModel()
        let i = index(model, TabContentSlot.titleID)
        XCTAssertFalse(model.usesSeparateColors(at: i))
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        model.setColorChoice(.custom(red), at: i)

        model.setUsesSeparateColors(true, at: i)
        XCTAssertTrue(model.usesSeparateColors(at: i))
        XCTAssertEqual(model.lines[i].style.darkColor?.usingColorSpace(.sRGB)?.redComponent ?? 0, 1, accuracy: 0.01)

        let blue = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        model.setDarkColor(blue, at: i)
        XCTAssertEqual(model.lines[i].style.darkColor?.usingColorSpace(.sRGB)?.blueComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(model.lines[i].style.color?.usingColorSpace(.sRGB)?.redComponent ?? 0, 1, accuracy: 0.01,
                       "the light color stays")

        model.setUsesSeparateColors(false, at: i)
        XCTAssertFalse(model.usesSeparateColors(at: i))
        XCTAssertNil(model.lines[i].style.darkColor)
        model.setUsesSeparateColors(true, at: i)
        XCTAssertEqual(model.darkColor(at: i)?.usingColorSpace(.sRGB)?.blueComponent ?? 0, 1, accuracy: 0.01,
                       "the dark color was kept")

        model.setColorChoice(.normal, at: i)
        XCTAssertFalse(model.usesSeparateColors(at: i))
        XCTAssertNil(model.overrides[TabContentSlot.titleID])
    }

    func testResetRemovesTheOverride() {
        let model = makeModel(overrides: [TabContentSlot.directoryID: ["bold": true, "text": "x"]])
        let i = index(model, TabContentSlot.directoryID)
        XCTAssertTrue(model.isCustomized(at: i))
        model.reset(at: i)
        XCTAssertFalse(model.isCustomized(at: i))
        XCTAssertNil(model.overrides[TabContentSlot.directoryID])
        XCTAssertEqual(model.lines[i].style.text, "\\(path)")
    }

    // Overrides for slots not in the layout belong to lines other profiles may
    // still use, or that may come back. The editor keeps them.
    func testOverridesForOtherSlotsArePreserved() {
        let model = makeModel(overrides: ["custom.gone": ["text": "keep"]])
        model.setBold(true, at: 0)
        XCTAssertEqual(model.overrides["custom.gone"] as NSDictionary?, ["text": "keep"] as NSDictionary)
    }

    func testSizeChangesTheLayout() {
        let model = makeModel()
        model.setSize(.large, at: 0)
        XCTAssertEqual(model.layout.slots[0].size, .large)
    }

    func testAddingBuiltInsOnlyOffersMissingOnes() {
        let model = makeModel(layout: TabContentLayout(slots: [
            TabContentSlot(identifier: TabContentSlot.titleID, size: .regular)]))
        XCTAssertEqual(Set(model.availableBuiltIns),
                       Set(TabContentEditorModel.builtInIdentifiers).subtracting([TabContentSlot.titleID]))
        model.addBuiltIn(TabContentSlot.jobID)
        XCTAssertEqual(model.layout.slots.map(\.identifier), [TabContentSlot.titleID, TabContentSlot.jobID])
        XCTAssertEqual(model.layout.slots[1].size, .small)
        XCTAssertFalse(model.availableBuiltIns.contains(TabContentSlot.jobID))
    }

    // Presets: the lines that are on by default and Status Detail, then
    // others that are commonly useful. Each shows the value it's named for.
    func testPresets() {
        XCTAssertEqual(TabContentEditorModel.presetGroups[0],
                       [TabContentSlot.titleID, TabContentSlot.subtitleID, TabContentSlot.directoryID,
                        TabContentSlot.jobID, TabContentSlot.statusDetailID])
        let expected: [String: String] = [
            TabContentSlot.hostID: "\\(hostname)",
            TabContentSlot.sessionNameID: "\\(name)",
            TabContentSlot.profileNameID: "\\(profileName)",
            TabContentSlot.commandLineID: "\\(commandLine)",
            TabContentSlot.lastCommandID: "\\(lastCommand)",
            TabContentSlot.badgeID: "\\(badge)",
            TabContentSlot.tmuxPaneTitleID: "\\(tmuxPaneTitle)",
        ]
        XCTAssertEqual(Set(TabContentEditorModel.presetGroups[1]), Set(expected.keys))
        for (identifier, text) in expected {
            let model = makeModel()
            model.addBuiltIn(identifier)
            XCTAssertEqual(model.lines.last?.slot.identifier, identifier)
            XCTAssertEqual(model.lines.last?.style.text, text, identifier)
            XCTAssertTrue(model.lines.last?.style.collapsesWhenEmpty ?? false, identifier)
            XCTAssertTrue(TabContentEditorModel.isBuiltIn(identifier))
            XCTAssertNotEqual(TabContentEditorModel.displayName(for: identifier),
                              TabContentEditorModel.displayName(for: "custom.x"), identifier)
        }
    }

    // The status detail preset sets up the line so users don't have to know
    // the variable or how many lines it needs.
    func testAddingStatusDetailUsesItsPreset() {
        let model = makeModel()
        XCTAssertTrue(model.availableBuiltIns.contains(TabContentSlot.statusDetailID))
        model.addBuiltIn(TabContentSlot.statusDetailID)
        let slot = model.layout.slots.last!
        XCTAssertEqual(slot.identifier, TabContentSlot.statusDetailID)
        XCTAssertEqual(slot.maximumLines, 3)
        XCTAssertEqual(slot.size, .small)
        XCTAssertEqual(TabContentEditorModel.displayName(for: TabContentSlot.statusDetailID), "Status Detail")
    }

    func testMaximumLinesChangesTheLayout() {
        let model = makeModel()
        model.setMaximumLines(2, at: 0)
        XCTAssertEqual(model.layout.slots[0].maximumLines, 2)
        XCTAssertTrue(model.layoutChanged)
    }

    func testAddingCustomLinesGivesDistinctIdentifiers() {
        let model = makeModel()
        let a = model.addCustom()
        let b = model.addCustom()
        XCTAssertEqual(model.layout.slots.count, 6)
        XCTAssertNotEqual(model.layout.slots[a].identifier, model.layout.slots[b].identifier)
        XCTAssertTrue(model.layout.slots[a].identifier.hasPrefix(TabContentSlot.customPrefix))
        XCTAssertFalse(TabContentEditorModel.isBuiltIn(model.layout.slots[a].identifier))
    }

    func testRemovingDropsTheSlotAndThisProfilesOverride() {
        let model = makeModel(overrides: [TabContentSlot.directoryID: ["bold": true]])
        let i = index(model, TabContentSlot.directoryID)
        model.remove(at: i)
        XCTAssertFalse(model.layout.slots.contains { $0.identifier == TabContentSlot.directoryID })
        XCTAssertNil(model.overrides[TabContentSlot.directoryID])
        XCTAssertTrue(model.availableBuiltIns.contains(TabContentSlot.directoryID))
    }

    // An empty layout would decode as the default, so the last line can't go.
    func testCannotRemoveTheLastLine() {
        let model = makeModel(layout: TabContentLayout(slots: [
            TabContentSlot(identifier: TabContentSlot.titleID, size: .regular),
            TabContentSlot(identifier: TabContentSlot.jobID, size: .small)]))
        XCTAssertTrue(model.canRemove)
        model.remove(at: 0)
        XCTAssertFalse(model.canRemove)
        model.remove(at: 0)
        XCTAssertEqual(model.layout.slots.count, 1)
    }

    func testMove() {
        let model = makeModel()
        model.move(from: 3, to: 0)
        XCTAssertEqual(model.layout.slots.map(\.identifier),
                       [TabContentSlot.jobID, TabContentSlot.titleID, TabContentSlot.subtitleID, TabContentSlot.directoryID])
        model.move(from: 0, to: 3)
        XCTAssertEqual(model.layout.slots.map(\.identifier),
                       [TabContentSlot.titleID, TabContentSlot.subtitleID, TabContentSlot.directoryID, TabContentSlot.jobID])
    }

    // Reset puts the whole line back the way it is when first added, its
    // size and wrapping too, since the profile saves them with the rest.
    func testResetRestoresSizeAndLines() {
        let model = makeModel()
        let i = index(model, TabContentSlot.titleID)
        model.setSize(.large, at: i)
        XCTAssertTrue(model.isCustomized(at: i))
        model.reset(at: i)
        XCTAssertEqual(model.layout.slots[i], TabContentSlot.preset(identifier: TabContentSlot.titleID))
        XCTAssertFalse(model.isCustomized(at: i))
        model.setMaximumLines(2, at: i)
        XCTAssertTrue(model.isCustomized(at: i))
        model.reset(at: i)
        XCTAssertEqual(model.layout.slots[i].maximumLines, 1)
        XCTAssertEqual(model.layout.slots.map(\.identifier),
                       TabContentLayout.defaultLayout.slots.map(\.identifier),
                       "it keeps its place")
    }

    // The preview shows each line's styling with stand-ins for the values.
    func testPreviewText() {
        XCTAssertEqual(TabContentEditorModel.previewText(for: "\\(path)"), "~/project")
        XCTAssertEqual(TabContentEditorModel.previewText(for: "a \\(jobName) b"), "a claude b")
        XCTAssertEqual(TabContentEditorModel.previewText(for: "\\(user.thing)"), "thing")
        XCTAssertEqual(TabContentEditorModel.previewText(for: "\\(f(\"x\"))!"), "f!")
        XCTAssertEqual(TabContentEditorModel.previewText(for: "plain"), "plain")
        XCTAssertEqual(TabContentEditorModel.previewText(for: "\\(unterminated"), "\\(unterminated")
    }

    // Setting a field back to its default value isn't a customization.
    func testSettingTheDefaultValueIsNotACustomization() {
        let model = makeModel()
        let title = index(model, TabContentSlot.titleID)
        model.setColorChoice(.normal, at: title)
        XCTAssertFalse(model.isCustomized(at: title))

        let directory = index(model, TabContentSlot.directoryID)
        model.setBold(true, at: directory)
        model.setBold(false, at: directory)
        XCTAssertFalse(model.isCustomized(at: directory))
        XCTAssertNil(model.overrides[TabContentSlot.directoryID])
    }

    // A stored text override on the subtitle line would hide the profile's
    // subtitle, so typing would seem to do nothing. Editing the text clears it.
    func testSubtitleTextEditClearsStrayTextOverride() {
        let model = makeModel(overrides: [TabContentSlot.subtitleID: ["text": "stray", "bold": true]],
                              subtitle: "old")
        let i = index(model, TabContentSlot.subtitleID)
        model.setText("new", at: i)
        XCTAssertEqual(model.lines[i].style.text, "new")
        XCTAssertEqual(model.overrides[TabContentSlot.subtitleID] as NSDictionary?, ["bold": true] as NSDictionary)
    }

    // OK with no layout edits mustn't store the layout: that would pin the
    // current default and notify every session.
    func testLayoutChanged() {
        let model = makeModel()
        XCTAssertFalse(model.layoutChanged)
        model.setBold(true, at: 0)
        XCTAssertFalse(model.layoutChanged)
        model.setSize(.large, at: 0)
        XCTAssertTrue(model.layoutChanged)
        model.setSize(.regular, at: 0)
        XCTAssertFalse(model.layoutChanged)
    }
}
