//
//  StatusPriorityPopoverLayoutTests.swift
//  ModernTests
//
//  The Session Status gear popover had a fixed 280pt width and a fixed 44pt Notify column, so in
//  German the Notify header read “Bena…” and “Arbeitsgruppenstatus zusammenführen” was clipped
//  (QA finding F-496). The popover now sizes itself to its localized titles.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class StatusPriorityPopoverLayoutTests: XCTestCase {
    private let languages = ["en", "de", "ja", "pt-BR", "ru", "zh-Hans"]

    private struct Titles {
        var notify: String
        var mergeWorkgroups: String
        var showStatusInTabSubtitle: String
        var instructions: String
    }

    private func catalog() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("xcstrings/Localizable.xcstrings"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(json["strings"] as? [String: Any])
    }

    private func value(_ key: String, language: String, in strings: [String: Any]) throws -> String {
        let entry = try XCTUnwrap(strings[key] as? [String: Any], key)
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
        let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return try XCTUnwrap(unit?["value"] as? String, "\(key) \(language)")
    }

    private func titles(_ language: String) throws -> Titles {
        let strings = try catalog()
        return Titles(notify: try value("StatusPriority.NotifyColumn", language: language, in: strings),
                      mergeWorkgroups: try value("StatusPriority.MergeWorkgroups", language: language, in: strings),
                      showStatusInTabSubtitle: try value("StatusPriority.ShowStatusInTabSubtitle", language: language, in: strings),
                      instructions: try value("StatusPriority.InstructionsLabel", language: language, in: strings))
    }

    private func layout(_ titles: Titles) -> StatusPriorityPopoverLayout {
        return StatusPriorityPopoverLayout(notifyTitle: titles.notify,
                                           checkboxTitles: [titles.mergeWorkgroups,
                                                            titles.showStatusInTabSubtitle],
                                           instructions: titles.instructions)
    }

    func testCheckboxesFit() throws {
        for language in languages {
            let titles = try titles(language)
            let layout = layout(titles)
            for title in [titles.mergeWorkgroups, titles.showStatusInTabSubtitle] {
                let needed = NSButton(checkboxWithTitle: title, target: nil, action: nil).fittingSize.width
                XCTAssertLessThanOrEqual(needed,
                                         layout.width - 2 * StatusPriorityPopoverLayout.margin,
                                         "\(language): \(title)")
            }
        }
    }

    func testNotifyHeaderFits() throws {
        for language in languages {
            let titles = try titles(language)
            let layout = layout(titles)
            let font = NSTableHeaderCell(textCell: titles.notify).font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            let textWidth = (titles.notify as NSString).size(withAttributes: [.font: font]).width
            // A header cell insets its text a few points on each side.
            XCTAssertLessThanOrEqual(textWidth + 8, layout.notifyColumnWidth, "\(language): \(titles.notify)")
        }
    }

    func testInstructionsFit() throws {
        for language in languages {
            let titles = try titles(language)
            let layout = layout(titles)
            let label = NSTextField(wrappingLabelWithString: titles.instructions)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.preferredMaxLayoutWidth = layout.width - 2 * StatusPriorityPopoverLayout.margin
            XCTAssertLessThanOrEqual(label.fittingSize.height, layout.labelHeight, language)
        }
    }

    func testPatternColumnKeepsRoom() throws {
        for language in languages {
            let layout = layout(try titles(language))
            XCTAssertGreaterThanOrEqual(layout.width - 2 * StatusPriorityPopoverLayout.margin - layout.notifyColumnWidth,
                                        120,
                                        language)
        }
    }

    func testEnglishKeepsItsOriginalSize() throws {
        let layout = layout(try titles("en"))
        XCTAssertEqual(layout.width, StatusPriorityPopoverLayout.minimumWidth)
        XCTAssertEqual(layout.notifyColumnWidth, StatusPriorityPopoverLayout.minimumNotifyColumnWidth)
        XCTAssertEqual(layout.labelHeight, StatusPriorityPopoverLayout.minimumLabelHeight)
        XCTAssertEqual(layout.height, StatusPriorityPopoverLayout.minimumHeight)
    }

    // Builds the real popover content with each language's titles and checks that nothing in it
    // is narrower than its text needs.
    func testPopoverViewFitsTranslations() throws {
        for language in languages {
            let titles = try titles(language)
            let vc = StatusPriorityViewController(
                titles: .init(instructions: titles.instructions,
                              showStatusInTabSubtitle: titles.showStatusInTabSubtitle,
                              mergeWorkgroups: titles.mergeWorkgroups,
                              notify: titles.notify))
            let view = vc.view
            XCTAssertEqual(view.frame.size.width, layout(titles).width, language)

            let checkboxes = view.subviews.compactMap { $0 as? NSButton }.filter {
                [titles.mergeWorkgroups, titles.showStatusInTabSubtitle].contains($0.title)
            }
            XCTAssertEqual(checkboxes.count, 2, language)
            for checkbox in checkboxes {
                XCTAssertGreaterThanOrEqual(checkbox.frame.width, checkbox.fittingSize.width,
                                            "\(language): \(checkbox.title)")
            }

            let tableView = try XCTUnwrap(view.subviews.compactMap {
                ($0 as? NSScrollView)?.documentView as? NSTableView
            }.first, language)
            let notifyColumn = try XCTUnwrap(tableView.tableColumns.first { $0.title == titles.notify },
                                             language)
            let font = notifyColumn.headerCell.font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            let textWidth = (titles.notify as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(textWidth + 8, notifyColumn.width, "\(language): \(titles.notify)")

            let label = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first {
                $0.stringValue == titles.instructions
            }, language)
            label.preferredMaxLayoutWidth = label.frame.width
            XCTAssertGreaterThanOrEqual(label.frame.height, label.fittingSize.height, language)
        }
    }

    // The fixed layout this replaced could not hold the German titles.
    func testGermanNeedsMoreThanTheOldFixedLayout() throws {
        let layout = layout(try titles("de"))
        XCTAssertGreaterThan(layout.width, StatusPriorityPopoverLayout.minimumWidth)
        XCTAssertGreaterThan(layout.notifyColumnWidth, StatusPriorityPopoverLayout.minimumNotifyColumnWidth)
    }
}
