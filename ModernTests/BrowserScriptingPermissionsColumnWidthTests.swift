//
//  BrowserScriptingPermissionsColumnWidthTests.swift
//  ModernTests
//
//  QA finding F-361: the website permissions panel gave its Permission and
//  Allowed columns fixed widths that suited English, so German and Russian
//  clipped “JavaScript ausführen”, “Выполнение JavaScript” and the
//  “Разрешено” header. These check that the columns are sized for each
//  shipped translation.
//

import XCTest
@testable import iTerm2SharedARC

final class BrowserScriptingPermissionsColumnWidthTests: XCTestCase {
    private func strings(_ language: String) -> [String: String] {
        guard let path = Bundle.main.path(forResource: "Localizable",
                                          ofType: "strings",
                                          inDirectory: nil,
                                          forLocalization: language),
              let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
            XCTFail("No Localizable.strings for \(language)")
            return [:]
        }
        return table
    }

    private func column(titled title: String) -> NSTableColumn {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Test"))
        column.title = title
        return column
    }

    private func textWidth(_ text: String) -> CGFloat {
        return (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
    }

    func testColumnsFitEveryLanguage() {
        for language in ["de", "ja", "pt-BR", "ru", "zh-Hans"] {
            let table = strings(language)
            guard let permissionTitle = table["BrowserScriptingPermissions.PermissionColumn"],
                  let allowedTitle = table["BrowserScriptingPermissions.AllowedColumn"],
                  let runJavaScript = table["BrowserScriptingPermissions.RunJavaScript"],
                  let loadURLs = table["BrowserScriptingPermissions.LoadURLs"] else {
                XCTFail("Missing strings for \(language)")
                continue
            }
            let permissionColumn = column(titled: permissionTitle)
            let permissionWidth = iTermBrowserScriptingPermissionsWindowController.width(
                toFit: permissionColumn, cellTexts: [runJavaScript, loadURLs], minimum: 130)
            XCTAssertGreaterThanOrEqual(permissionWidth, permissionColumn.headerCell.cellSize.width, language)
            for name in [runJavaScript, loadURLs] {
                XCTAssertGreaterThan(permissionWidth, textWidth(name), "\(language): \(name)")
            }

            let allowedColumn = column(titled: allowedTitle)
            let allowedWidth = iTermBrowserScriptingPermissionsWindowController.width(
                toFit: allowedColumn, cellTexts: [], minimum: 60)
            XCTAssertGreaterThanOrEqual(allowedWidth, allowedColumn.headerCell.cellSize.width, "\(language): \(allowedTitle)")
        }
    }

    func testRussianNeedsMoreThanTheOldWidths() {
        // Guards the premise: QA saw these clipped at 130 and 60 points.
        let table = strings("ru")
        XCTAssertGreaterThan(textWidth(table["BrowserScriptingPermissions.RunJavaScript"] ?? ""), 130 - 12)
        XCTAssertGreaterThan(column(titled: table["BrowserScriptingPermissions.AllowedColumn"] ?? "").headerCell.cellSize.width, 60)
    }

    func testEnglishKeepsTheOriginalWidths() {
        let permissionWidth = iTermBrowserScriptingPermissionsWindowController.width(
            toFit: column(titled: "Permission"), cellTexts: ["Run JavaScript", "Load URLs"], minimum: 130)
        XCTAssertEqual(permissionWidth, 130)
        let allowedWidth = iTermBrowserScriptingPermissionsWindowController.width(
            toFit: column(titled: "Allowed"), cellTexts: [], minimum: 60)
        XCTAssertEqual(allowedWidth, 60)
    }
}
