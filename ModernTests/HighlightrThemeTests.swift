//
//  HighlightrThemeTests.swift
//  ModernTests
//

import XCTest
import Highlightr

final class HighlightrThemeTests: XCTestCase {
    // Highlightr's CSS parser needs whitespace-free CSS, which is how TextViewPortholeRenderer
    // passes it.
    private let css = ".hljs{color:#000000;}.hljs-keyword{color:#ff00ff;}.hljs-title{color:#ffff00;}"

    private func color(of word: String, in text: String, language: String) -> NSColor? {
        let highlightr = Highlightr()!
        highlightr.theme = Theme(themeString: css)
        guard let result = highlightr.highlight(text, as: language, fastRender: true) else {
            return nil
        }
        let range = (result.string as NSString).range(of: word)
        XCTAssertNotEqual(range.location, NSNotFound, "\(word) not in output")
        return result.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }

    private func assertYellow(_ color: NSColor?, file: StaticString = #filePath, line: UInt = #line) {
        guard let rgb = color?.usingColorSpace(.sRGB) else {
            XCTFail("no color", file: file, line: line)
            return
        }
        XCTAssertEqual(rgb.redComponent, 1, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(rgb.greenComponent, 1, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(rgb.blueComponent, 0, accuracy: 0.01, file: file, line: line)
    }

    // highlight.js 11 marks names with two classes, as in class="hljs-title class_". Each class
    // must be looked up on its own, or names lose the theme's .hljs-title color.
    func testClassNameUsesTitleColor() {
        assertYellow(color(of: "Greeter", in: "class Greeter:\n    pass\n", language: "python"))
    }

    func testFunctionNameUsesTitleColor() {
        assertYellow(color(of: "greet", in: "def greet(x):\n    return x\n", language: "python"))
    }

    func testSingleClassSpansStillWork() {
        let rgb = color(of: "def", in: "def greet(x):\n    return x\n", language: "python")?.usingColorSpace(.sRGB)
        XCTAssertEqual(rgb?.redComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(rgb?.greenComponent ?? 1, 0, accuracy: 0.01)
        XCTAssertEqual(rgb?.blueComponent ?? 0, 1, accuracy: 0.01)
    }
}
