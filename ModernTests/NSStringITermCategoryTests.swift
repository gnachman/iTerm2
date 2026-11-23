//
//  NSStringITermCategoryTests.swift
//  ModernTests
//
//  Ported from iTerm2XCTests/iTermNSStringCategoryTest.m. Covers the NSString (iTerm) category:
//  vim special characters, shell command splitting, trailing trimming, URL ranges, enclosing
//  brackets, glob matching, quote-and-backslash splitting, $$VARIABLES$$, swifty substrings,
//  and caret-letter control characters.
//

import XCTest
@testable import iTerm2SharedARC

final class NSStringITermCategoryTests: XCTestCase {

    // MARK: - Helpers

    private func vim(_ string: String) -> String {
        return (string as NSString).expandingVimSpecialCharacters()
    }

    private func char(_ value: Int) -> String {
        return String(UnicodeScalar(UInt8(value)))
    }

    private func shellComponents(_ string: String) -> [String] {
        return (string as NSString).componentsInShellCommand()
    }

    private func trimTrailing(_ string: String, charactersIn chars: String) -> String {
        return (string as NSString).trimmingTrailingCharacters(from: CharacterSet(charactersIn: chars))
    }

    private func trimTrailingWhitespace(_ string: String) -> String {
        return (string as NSString).it_stringByTrimmingTrailingWhitespace()
    }

    private func urlSubstring(_ string: String) -> String {
        let nsstring = string as NSString
        return nsstring.substring(with: nsstring.rangeOfURLInString())
    }

    private func removingBrackets(_ string: String) -> String {
        return (string as NSString).removingEnclosingBrackets()
    }

    private func glob(_ string: String, _ pattern: String) -> Bool {
        return (string as NSString).stringMatchesGlobPattern(pattern, caseSensitive: false)
    }

    private func split(_ string: String, escapes: [AnyHashable: Any] = [:]) -> [String] {
        return (string as NSString).componentsBySplittingString(withQuotesAndBackslashEscaping: escapes) as? [String] ?? []
    }

    private func doubleDollar(_ string: String) -> Set<String> {
        let set = (string as NSString).doubleDollarVariables()
        return Set(set.compactMap { $0 as? String })
    }

    private func swiftyParts(_ string: String) -> [(String, Bool)] {
        var result = [(String, Bool)]()
        (string as NSString).enumerateSwiftySubstrings { _, substring, isLiteral, _ in
            result.append((substring, isLiteral))
        }
        return result
    }

    private func assertSwiftyParts(_ string: String,
                                   equal expected: [(String, Bool)],
                                   file: StaticString = #filePath,
                                   line: UInt = #line) {
        let actual = swiftyParts(string)
        XCTAssertEqual(actual.count, expected.count, "Got \(actual)", file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a.0, e.0, file: file, line: line)
            XCTAssertEqual(a.1, e.1, "isLiteral for \(a.0)", file: file, line: line)
        }
    }

    private func caret(_ string: String) -> String {
        return (string as NSString).replacingControlCharactersWithCaretLetter()
    }

    // MARK: - Vim special characters

    func testVimSpecialChars_NoSpecialChars() {
        XCTAssertEqual(vim("Foo"), "Foo")
    }

    func testVimSpecialChars_TerminalBackslash() {
        XCTAssertEqual(vim("Foo\\"), "Foo")
    }

    func testVimSpecialChars_ThreeDigitOctal() {
        XCTAssertEqual(vim("prefix\\101suffix"), "prefixAsuffix")
    }

    func testVimSpecialChars_TwoDigitOctal() {
        XCTAssertEqual(vim("prefix\\60suffix"), "prefix0suffix")
    }

    func testVimSpecialChars_OneDigitOctal() {
        XCTAssertEqual(vim("prefix\\5suffix"), "prefix" + char(5) + "suffix")
    }

    func testVimSpecialChars_TwoDigitHex() {
        XCTAssertEqual(vim("prefix\\x41suffix"), "prefixAsuffix")
    }

    func testVimSpecialChars_OneDigitHex() {
        XCTAssertEqual(vim("prefix\\x5suffix"), "prefix" + char(5) + "suffix")
    }

    func testVimSpecialChars_FourDigitUnicode() {
        XCTAssertEqual(vim("prefix\\u6C34suffix"), "prefix\u{6C34}suffix")
    }

    func testVimSpecialChars_Backspace() {
        XCTAssertEqual(vim("prefix\\bsuffix"), "prefix" + char(0x7f) + "suffix")
    }

    func testVimSpecialChars_Escape() {
        XCTAssertEqual(vim("prefix\\esuffix"), "prefix" + char(27) + "suffix")
    }

    func testVimSpecialChars_FormFeed() {
        XCTAssertEqual(vim("prefix\\fsuffix"), "prefix" + char(12) + "suffix")
    }

    func testVimSpecialChars_Newline() {
        XCTAssertEqual(vim("prefix\\nsuffix"), "prefix\nsuffix")
    }

    func testVimSpecialChars_Return() {
        XCTAssertEqual(vim("prefix\\rsuffix"), "prefix\rsuffix")
    }

    func testVimSpecialChars_Tab() {
        XCTAssertEqual(vim("prefix\\tsuffix"), "prefix\tsuffix")
    }

    func testVimSpecialChars_Backslash() {
        XCTAssertEqual(vim("prefix\\\\suffix"), "prefix\\suffix")
    }

    func testVimSpecialChars_DoubleQuote() {
        XCTAssertEqual(vim("prefix\\\"suffix"), "prefix\"suffix")
    }

    func testVimSpecialChars_ControlKey() {
        XCTAssertEqual(vim("prefix\\<C-A>suffix"), "prefix" + char(1) + "suffix")
    }

    func testVimSpecialChars_MetaKey() {
        XCTAssertEqual(vim("prefix\\<M-A>suffix"), "prefix" + char(27) + "Asuffix")
    }

    func testVimSpecialChars_Multiples() {
        XCTAssertEqual(vim("\\x41x\\x41x\\x41"), "AxAxA")
    }

    func testVimSpecialChars_Sequential() {
        XCTAssertEqual(vim("\\x41\\x41"), "AA")
    }

    // MARK: - componentsInShellCommand

    func testParseShellCommand_SingleWord() {
        XCTAssertEqual(shellComponents("foo"), ["foo"])
    }

    func testParseShellCommand_TwoWords() {
        XCTAssertEqual(shellComponents("foo bar"), ["foo", "bar"])
    }

    func testParseShellCommand_ExtraWhitespaceIsIgnored() {
        XCTAssertEqual(shellComponents("   foo    bar   "), ["foo", "bar"])
    }

    func testParseShellCommand_BackslashEscapesSpace() {
        XCTAssertEqual(shellComponents("foo\\ bar"), ["foo bar"])
    }

    func testParseShellCommand_BackslashNIsNewline() {
        XCTAssertEqual(shellComponents("foo\\n bar"), ["foo\n", "bar"])
    }

    func testParseShellCommand_BackslashTIsTab() {
        XCTAssertEqual(shellComponents("foo\\t bar"), ["foo\t", "bar"])
    }

    func testParseShellCommand_BackslashEscapesDoubleQuote() {
        XCTAssertEqual(shellComponents("foo\\\" bar"), ["foo\"", "bar"])
    }

    func testParseShellCommand_DoubleQuotesGroupWords() {
        XCTAssertEqual(shellComponents("\"foo bar\""), ["foo bar"])
    }

    func testParseShellCommand_DoubleQuotesWithSurroundingWhitespace() {
        XCTAssertEqual(shellComponents("   \"foo bar\"   "), ["foo bar"])
    }

    func testParseShellCommand_DoubleQuotesPreserveInnerWhitespace() {
        XCTAssertEqual(shellComponents("   \"foo  bar\"   "), ["foo  bar"])
    }

    func testParseShellCommand_BackslashIsLiteralInsideDoubleQuotes() {
        XCTAssertEqual(shellComponents("   \"foo\\ bar\"   "), ["foo\\ bar"])
    }

    func testParseShellCommand_UnterminatedDoubleQuote() {
        XCTAssertEqual(shellComponents("   \"foo bar"), ["foo bar"])
    }

    func testParseShellCommand_EscapedDoubleQuotesDoNotGroup() {
        XCTAssertEqual(shellComponents("\\\"foo bar\\\""), ["\"foo", "bar\""])
    }

    func testParseShellCommand_BareTildeIsExpanded() {
        XCTAssertEqual(shellComponents("~"), [("~" as NSString).expandingTildeInPath])
    }

    func testParseShellCommand_MidwordTildeIsNotExpanded() {
        XCTAssertEqual(shellComponents("a~"), ["a~"])
    }

    func testParseShellCommand_QuotedTildeIsNotExpanded() {
        XCTAssertEqual(shellComponents("\"~\""), ["~"])
    }

    func testParseShellCommand_EscapedTildeIsNotExpanded() {
        XCTAssertEqual(shellComponents("\\~"), ["~"])
    }

    // MARK: - stringByTrimmingTrailingCharactersFromCharacterSet

    func testTrimTrailingCharset_CharacterNotAtEndIsKept() {
        XCTAssertEqual(trimTrailing("abc", charactersIn: "a"), "abc")
    }

    func testTrimTrailingCharset_TrailingCharacterIsRemoved() {
        XCTAssertEqual(trimTrailing("abc", charactersIn: "c"), "ab")
    }

    func testTrimTrailingCharset_NoMatchLeavesStringAlone() {
        XCTAssertEqual(trimTrailing("abc", charactersIn: "x"), "abc")
    }

    func testTrimTrailingCharset_MultipleTrailingCharactersAreRemoved() {
        XCTAssertEqual(trimTrailing("abc", charactersIn: "bc"), "a")
    }

    func testTrimTrailingCharset_AllCharactersRemovedGivesEmptyString() {
        XCTAssertEqual(trimTrailing("abc", charactersIn: "abc"), "")
    }

    // MARK: - it_stringByTrimmingTrailingWhitespace

    func testTrimTrailingWhitespace_NoWhitespace() {
        XCTAssertEqual(trimTrailingWhitespace("abc"), "abc")
    }

    func testTrimTrailingWhitespace_OneTrailingSpace() {
        XCTAssertEqual(trimTrailingWhitespace("abc "), "abc")
    }

    func testTrimTrailingWhitespace_TwoTrailingSpaces() {
        XCTAssertEqual(trimTrailingWhitespace("abc  "), "abc")
    }

    func testTrimTrailingWhitespace_LeadingSpaceIsKept() {
        XCTAssertEqual(trimTrailingWhitespace(" abc "), " abc")
        XCTAssertEqual(trimTrailingWhitespace(" abc  "), " abc")
    }

    func testTrimTrailingWhitespace_NonBreakingSpaceIsWhitespace() {
        XCTAssertEqual(trimTrailingWhitespace("abc \u{00a0}"), "abc")
    }

    func testTrimTrailingWhitespace_SurrogatePairIsNotTruncated() {
        // There used to be a bug that surrogate pairs got truncated.
        XCTAssertEqual(trimTrailingWhitespace("abc 🔥"), "abc 🔥")
    }

    func testTrimTrailingWhitespace_NewlineIsKept() {
        XCTAssertEqual(trimTrailingWhitespace("abc\n"), "abc\n")
        XCTAssertEqual(trimTrailingWhitespace("   "), "")
        XCTAssertEqual(trimTrailingWhitespace(""), "")
    }

    // MARK: - Selectors an Apple framework also implements

    // Each of these selectors is implemented by an Apple framework on the same
    // class (CoreHandwriting, libmecabra, AnnotationKit, CoreFoundation,
    // PencilKit, PDFKit and others, found on macOS 27.0). A category method
    // with the same selector replaces Apple's, or is replaced by it, for every
    // instance in the process, so the app's methods carry an it_ prefix. This
    // fails if code outside the system's images (the app, a framework it
    // embeds, or the tests) implements one of the unprefixed selectors again.
    func testCollidingSelectorsAreNotImplementedOutsideTheSystem() {
        let cases: [(AnyClass, String)] = [
            (NSString.self, "lastComposedCharacter"),
            (NSString.self, "firstCharacter"),
            (NSString.self, "stringByTrimmingLeadingWhitespace"),
            (NSString.self, "stringByTrimmingTrailingWhitespace"),
            (NSArray.self, "objectPassingTest:"),
            (NSMutableArray.self, "removeObjectsPassingTest:"),
            (NSImage.self, "CGImage"),
        ]
        for (cls, name) in cases {
            for image in Self.imagesImplementing(sel_registerName(name), on: cls) {
                XCTAssertTrue(Self.isSystemImage(image),
                              "-[\(cls) \(name)] is implemented by \(image); give the app's method an it_ prefix")
            }
        }
    }

    // The renamed methods are the app's own, so the check above is not
    // passing merely because it cannot see the app's image.
    func testRenamedSelectorsAreImplementedByTheApp() {
        let cases: [(AnyClass, String)] = [
            (NSString.self, "it_lastComposedCharacter"),
            (NSString.self, "it_firstCharacter"),
            (NSString.self, "it_stringByTrimmingLeadingWhitespace"),
            (NSString.self, "it_stringByTrimmingTrailingWhitespace"),
            (NSArray.self, "it_objectPassingTest:"),
            (NSMutableArray.self, "it_removeObjectsPassingTest:"),
            (NSImage.self, "it_CGImage"),
        ]
        for (cls, name) in cases {
            let images = Self.imagesImplementing(sel_registerName(name), on: cls)
            XCTAssertEqual(images.count, 1, "-[\(cls) \(name)]: \(images)")
            for image in images {
                XCTAssertFalse(Self.isSystemImage(image), "-[\(cls) \(name)] is implemented by \(image)")
            }
        }
    }

    private static func isSystemImage(_ path: String) -> Bool {
        return path.hasPrefix("/System/") || path.hasPrefix("/usr/lib/")
    }

    // The path of the image that holds each implementation of `selector` in
    // the method list of `cls` itself (categories included, superclasses not).
    private static func imagesImplementing(_ selector: Selector, on cls: AnyClass) -> [String] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            return []
        }
        defer {
            free(methods)
        }
        var result = [String]()
        for i in 0..<Int(count) where method_getName(methods[i]) == selector {
            let imp = method_getImplementation(methods[i])
            var info = Dl_info()
            if dladdr(unsafeBitCast(imp, to: UnsafeRawPointer.self), &info) != 0,
               let fname = info.dli_fname {
                result.append(String(cString: fname))
            } else {
                result.append("(unknown image)")
            }
        }
        return result
    }

    func testFirstCharacter() {
        XCTAssertEqual(("" as NSString).it_firstCharacter(), 0)
        XCTAssertEqual(("ab" as NSString).it_firstCharacter(), 0x61)
        XCTAssertEqual(("\u{1F600}x" as NSString).it_firstCharacter(), 0x1F600)
        XCTAssertEqual(("e\u{301}" as NSString).it_firstCharacter(), 0x65)
    }

    func testFirstCharacter_UnpairedSurrogates() {
        func string(_ units: [unichar]) -> NSString {
            return units.withUnsafeBufferPointer { NSString(characters: $0.baseAddress!, length: $0.count) }
        }
        // A lone high surrogate is returned as is.
        XCTAssertEqual(string([0xD800]).it_firstCharacter(), 0xD800)
        // A high surrogate followed by something other than a low surrogate gives 0.
        XCTAssertEqual(string([0xD800, 0x78]).it_firstCharacter(), 0)
        // A lone low surrogate is returned as is.
        XCTAssertEqual(string([0xDC00, 0x78]).it_firstCharacter(), 0xDC00)
    }

    func testLastComposedCharacter() {
        XCTAssertEqual(("abc" as NSString).it_lastComposedCharacter(), "c")
        XCTAssertEqual(("ae\u{301}" as NSString).it_lastComposedCharacter(), "e\u{301}")
        XCTAssertEqual(("a\u{1F600}" as NSString).it_lastComposedCharacter(), "\u{1F600}")
        // The app's segmentation gives a halfwidth katakana voiced sound mark
        // a cell of its own, where Apple's composed character sequence keeps
        // it with the katakana before it.
        XCTAssertEqual(("\u{FF76}\u{FF9E}" as NSString).it_lastComposedCharacter(), "\u{FF9E}")
    }

    func testTrimLeadingWhitespace() {
        func trim(_ string: String) -> String {
            return (string as NSString).it_stringByTrimmingLeadingWhitespace()
        }
        XCTAssertEqual(trim(""), "")
        XCTAssertEqual(trim("abc"), "abc")
        XCTAssertEqual(trim("  abc  "), "abc  ")
        XCTAssertEqual(trim("\t abc"), "abc")
        XCTAssertEqual(trim("\u{00a0}abc"), "abc")
        // Newlines are not whitespace here.
        XCTAssertEqual(trim("\nabc"), "\nabc")
        XCTAssertEqual(trim("   "), "")
        XCTAssertEqual(trim(" \u{1F525}"), "\u{1F525}")
    }

    func testCGImage() throws {
        let image = NSImage(size: NSSize(width: 4, height: 3), flipped: false) { rect in
            NSColor.red.set()
            rect.fill()
            return true
        }
        let expected = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let actual = image.it_CGImage().takeUnretainedValue()
        XCTAssertEqual(actual.width, expected.width)
        XCTAssertEqual(actual.height, expected.height)

        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                 pixelsWide: 6,
                                                 pixelsHigh: 5,
                                                 bitsPerSample: 8,
                                                 samplesPerPixel: 4,
                                                 hasAlpha: true,
                                                 isPlanar: false,
                                                 colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0,
                                                 bitsPerPixel: 0))
        let bitmapImage = NSImage(size: NSSize(width: 3, height: 2.5))
        bitmapImage.addRepresentation(rep)
        let cgImage = bitmapImage.it_CGImage().takeUnretainedValue()
        XCTAssertEqual(cgImage.width, 6)
        XCTAssertEqual(cgImage.height, 5)
    }

    // MARK: - rangeOfURLInString

    func testRangeOfURLInString_WithScheme() {
        let strings = ["http://example.com",
                       "(http://example.com)",
                       "*http://example.com",
                       "http://example.com.",
                       "(http://example.com).",
                       "(http://example.com.)",
                       "*(http://example.com.)"]
        for string in strings {
            XCTAssertEqual(urlSubstring(string), "http://example.com", "Input: \(string)")
        }
    }

    func testRangeOfURLInString_WithoutScheme() {
        let strings = ["example.com",
                       "(example.com)",
                       "example.com.",
                       "(example.com).",
                       "(example.com.)"]
        for string in strings {
            XCTAssertEqual(urlSubstring(string), "example.com", "Input: \(string)")
        }
    }

    // MARK: - stringByRemovingEnclosingBrackets

    func testRemovingEnclosingBrackets_NoBrackets() {
        XCTAssertEqual(removingBrackets("abc"), "abc")
    }

    func testRemovingEnclosingBrackets_Parens() {
        XCTAssertEqual(removingBrackets("(abc)"), "abc")
    }

    func testRemovingEnclosingBrackets_AngleBrackets() {
        XCTAssertEqual(removingBrackets("<abc>"), "abc")
    }

    func testRemovingEnclosingBrackets_SquareBrackets() {
        XCTAssertEqual(removingBrackets("[abc]"), "abc")
    }

    func testRemovingEnclosingBrackets_CurlyBraces() {
        XCTAssertEqual(removingBrackets("{abc}"), "abc")
    }

    func testRemovingEnclosingBrackets_SingleQuotes() {
        XCTAssertEqual(removingBrackets("'abc'"), "abc")
    }

    func testRemovingEnclosingBrackets_DoubleQuotes() {
        XCTAssertEqual(removingBrackets("\"abc\""), "abc")
    }

    func testRemovingEnclosingBrackets_MismatchedBracketsAreKept() {
        XCTAssertEqual(removingBrackets("(abc("), "(abc(")
        XCTAssertEqual(removingBrackets("<abc<"), "<abc<")
        XCTAssertEqual(removingBrackets("[abc["), "[abc[")
        XCTAssertEqual(removingBrackets("{abc{"), "{abc{")
    }

    func testRemovingEnclosingBrackets_SingleCharacter() {
        XCTAssertEqual(removingBrackets("a"), "a")
        XCTAssertEqual(removingBrackets("(a)"), "a")
    }

    func testRemovingEnclosingBrackets_EmptyResults() {
        XCTAssertEqual(removingBrackets(""), "")
        XCTAssertEqual(removingBrackets("()"), "")
        XCTAssertEqual(removingBrackets("([])"), "")
    }

    func testRemovingEnclosingBrackets_NestedBracketsAreAllRemoved() {
        XCTAssertEqual(removingBrackets("<[abc]>"), "abc")
    }

    func testRemovingEnclosingBrackets_ImproperlyNestedBracketsAreKept() {
        XCTAssertEqual(removingBrackets("<[abc>]"), "<[abc>]")
    }

    // MARK: - stringMatchesGlobPattern (case insensitive)

    func testGlob_EmptyString() {
        XCTAssertTrue(glob("", ""))
        XCTAssertFalse(glob("", "abc"))
    }

    func testGlob_ExactMatch() {
        XCTAssertTrue(glob("abc", "abc"))
    }

    func testGlob_WildcardInMiddle() {
        XCTAssertTrue(glob("abc", "a*c"))
        XCTAssertTrue(glob("abc", "a*b*c"))
    }

    func testGlob_WildcardAtEnd() {
        XCTAssertTrue(glob("abc", "a*"))
        XCTAssertTrue(glob("abc", "a*b*c*"))
    }

    func testGlob_WildcardAtStart() {
        XCTAssertTrue(glob("abc", "*c"))
        XCTAssertTrue(glob("abc", "*bc"))
        XCTAssertTrue(glob("abc", "*a*b*c"))
    }

    func testGlob_WildcardsOnBothSides() {
        XCTAssertTrue(glob("abc", "*b*"))
        XCTAssertTrue(glob("abc", "*a*b*c*"))
    }

    func testGlob_RepeatedWildcards() {
        XCTAssertTrue(glob("abc", "**c"))
        XCTAssertTrue(glob("abc", "***a****b****c****"))
    }

    func testGlob_NonMatches() {
        XCTAssertFalse(glob("abc", ""))
        XCTAssertFalse(glob("abc", "a"))
        XCTAssertFalse(glob("abc", "x"))
        XCTAssertFalse(glob("abc", "a*b"))
        XCTAssertFalse(glob("abc", "*b"))
        XCTAssertFalse(glob("abc", "***a****b**x**c****"))
    }

    func testGlob_LongerStrings() {
        XCTAssertTrue(glob("abcdefghi", "a*d*g*i"))
        XCTAssertTrue(glob("abcdefghi", "a*d*g*"))
        XCTAssertFalse(glob("abcdefghi", "a*q*g*"))
    }

    func testGlob_CaseInsensitive() {
        XCTAssertTrue(glob("abc", "ABC"))
        XCTAssertTrue(glob("abc", "A*C"))
        XCTAssertTrue(glob("ABC", "abc"))
        XCTAssertTrue(glob("ABC", "a*c"))
        XCTAssertFalse(glob("ABC", "a*x"))
    }

    // MARK: - componentsBySplittingStringWithQuotesAndBackslashEscaping

    func testSplitWithQuotes_Basic() {
        XCTAssertEqual(split("foo bar"), ["foo", "bar"])
    }

    func testSplitWithQuotes_BackslashEscapesMidlineSpace() {
        XCTAssertEqual(split("foo\\ bar"), ["foo bar"])
    }

    func testSplitWithQuotes_BackslashEscapesLeadingTrailingSpace() {
        XCTAssertEqual(split("\\ foo bar\\ "), [" foo", "bar "])
    }

    func testSplitWithQuotes_BackslashEscapesSingleQuote() {
        XCTAssertEqual(split("foo\\' bar"), ["foo'", "bar"])
    }

    func testSplitWithQuotes_BackslashEscapesDoubleQuote() {
        XCTAssertEqual(split("foo\\\" bar"), ["foo\"", "bar"])
    }

    func testSplitWithQuotes_BackslashEscapesBackslash() {
        XCTAssertEqual(split("foo\\\\ bar"), ["foo\\", "bar"])
    }

    func testSplitWithQuotes_CustomEscapes() {
        let escapes: [AnyHashable: Any] = [NSNumber(value: 49): "bar"]  // 49 is '1'
        XCTAssertEqual(split("foo \\1", escapes: escapes), ["foo", "bar"])
    }

    func testSplitWithQuotes_QuotedCustomEscapes() {
        let escapes: [AnyHashable: Any] = [NSNumber(value: 49): "bar"]  // 49 is '1'
        XCTAssertEqual(split("foo \"\\1\"", escapes: escapes), ["foo", "bar"])
    }

    func testSplitWithQuotes_DoubleQuotesWithSpace() {
        XCTAssertEqual(split("foo\" \"bar"), ["foo bar"])
    }

    func testSplitWithQuotes_DoubleQuotesWithSingleQuote() {
        XCTAssertEqual(split("foo\"'\"bar"), ["foo'bar"])
    }

    func testSplitWithQuotes_DoubleQuotesWithEscapedDoubleQuote() {
        XCTAssertEqual(split("foo\"\\\"\"bar"), ["foo\"bar"])
    }

    func testSplitWithQuotes_SingleQuotesWithEscapedLetter() {
        XCTAssertEqual(split("foo'\\q'bar"), ["foo\\qbar"])
    }

    func testSplitWithQuotes_SingleQuotesWithSpace() {
        XCTAssertEqual(split("foo' 'bar"), ["foo bar"])
    }

    func testSplitWithQuotes_SingleQuotesWithDoubleQuote() {
        XCTAssertEqual(split("foo'\"'bar"), ["foo\"bar"])
    }

    func testSplitWithQuotes_SingleQuotesWithEscapedSingleQuote() {
        XCTAssertEqual(split("foo'\\''bar'"), ["foo\\bar"])
    }

    func testSplitWithQuotes_MismatchedDoubleQuotes() {
        XCTAssertEqual(split("foo\" bar"), ["foo bar"])
    }

    func testSplitWithQuotes_MismatchedSingleQuotes() {
        XCTAssertEqual(split("foo' bar"), ["foo bar"])
    }

    func testSplitWithQuotes_OrphanBackslash() {
        XCTAssertEqual(split("foo bar\\"), ["foo", "bar"])
    }

    func testSplitWithQuotes_ExpandTilde() {
        let actual = split("~/foo bar")
        XCTAssertEqual(actual.count, 2)
        XCTAssertFalse(actual.first?.hasPrefix("~") ?? true)
    }

    func testSplitWithQuotes_MidlineTilde() {
        XCTAssertEqual(split("fo~o bar"), ["fo~o", "bar"])
    }

    func testSplitWithQuotes_EscapedTilde() {
        XCTAssertEqual(split("\\~/foo bar"), ["~/foo", "bar"])
    }

    func testSplitWithQuotes_DoubleQuotedTilde() {
        XCTAssertEqual(split("\"~/foo\" bar"), ["~/foo", "bar"])
    }

    func testSplitWithQuotes_SingleQuotedTilde() {
        XCTAssertEqual(split("'~/foo' bar"), ["~/foo", "bar"])
    }

    func testSplitWithQuotes_TrimSpace() {
        XCTAssertEqual(split("  foo   bar  "), ["foo", "bar"])
    }

    func testSplitWithQuotes_BackslashInQuotes() {
        XCTAssertEqual(split("\"foo\\ bar\" 'foo\\ bar'"), ["foo\\ bar", "foo\\ bar"])
    }

    // MARK: - doubleDollarVariables

    func testDoubleDollarVariables_OneTrivialCapture() {
        XCTAssertEqual(doubleDollar("blah $$FOO$$ blah"), ["$$FOO$$"])
    }

    func testDoubleDollarVariables_TwoCaptures() {
        XCTAssertEqual(doubleDollar("blah $$FOO$$ blah $$BAR$$ baz"), ["$$FOO$$", "$$BAR$$"])
    }

    func testDoubleDollarVariables_EscapedCaptures() {
        XCTAssertEqual(doubleDollar("blah $$$$ blah $$$$ baz"), ["$$$$"])
    }

    func testDoubleDollarVariables_OneBigCapture() {
        XCTAssertEqual(doubleDollar("$$ foo bar baz $$"), ["$$ foo bar baz $$"])
    }

    func testDoubleDollarVariables_Unterminated() {
        XCTAssertEqual(doubleDollar("echo $$"), [])
    }

    // MARK: - enumerateSwiftySubstrings

    func testEnumerateSwiftySubstrings_Literal() {
        assertSwiftyParts("xyz", equal: [("xyz", true)])
    }

    func testEnumerateSwiftySubstrings_LiteralAndExpression() {
        assertSwiftyParts("abc\\(def)ghi", equal: [("abc", true), ("def", false), ("ghi", true)])
    }

    func testEnumerateSwiftySubstrings_LiteralWithEscapedCharacters() {
        assertSwiftyParts("a\\b\\\\", equal: [("a\\b\\\\", true)])
    }

    func testEnumerateSwiftySubstrings_ExpressionContainingStringWithParens() {
        assertSwiftyParts("\\(foo(\"bar(((\"))", equal: [("foo(\"bar(((\")", false)])
    }

    func testEnumerateSwiftySubstrings_ExpressionContainingNestedExpression() {
        assertSwiftyParts("\\(foo(\"bar\\(inner(x,y))\"))",
                          equal: [("foo(\"bar\\(inner(x,y))\")", false)])
    }

    func testEnumerateSwiftySubstrings_ExpressionContainingNestedExpressionWithString() {
        assertSwiftyParts("\\(foo(\"bar\\(inner(\"innerstring\",y))\"))",
                          equal: [("foo(\"bar\\(inner(\"innerstring\",y))\")", false)])
    }

    func testEnumerateSwiftySubstrings_UnclosedExpression() {
        assertSwiftyParts("\\(foo(\"bar\\(inner(\"innerstring\",y",
                          equal: [("foo(\"bar\\(inner(\"innerstring\",y", true)])
    }

    // MARK: - stringByReplacingControlCharactersWithCaretLetter

    func testReplaceControlCharactersWithCaretLetter_Empty() {
        XCTAssertEqual(caret(""), "")
    }

    func testReplaceControlCharactersWithCaretLetter_JustAControlCharacter() {
        XCTAssertEqual(caret(char(1)), "^A")
    }

    func testReplaceControlCharactersWithCaretLetter_Delete() {
        XCTAssertEqual(caret(char(0x7f)), "^?")
    }

    func testReplaceControlCharactersWithCaretLetter_JustTwoControlCharacters() {
        XCTAssertEqual(caret(char(1) + char(2)), "^A^B")
    }

    func testReplaceControlCharactersWithCaretLetter_MixOfRegularAndControlCharacters() {
        XCTAssertEqual(caret("12" + char(1) + "34" + char(2) + "56"), "12^A34^B56")
    }

    // MARK: - stringByReplacingControlCharactersWithSpace

    private func spaced(_ string: String) -> String {
        return (string as NSString).replacingControlCharactersWithSpace()
    }

    func testReplaceControlCharactersWithSpace_C0DelAndC1() {
        XCTAssertEqual(spaced("a\u{0}b\nc\u{1b}d\u{7f}e\u{85}f\u{9f}g"), "a b c d e f g")
    }

    func testReplaceControlCharactersWithSpace_NoControlsReturnsInput() {
        XCTAssertEqual(spaced("plain text"), "plain text")
    }

    // An astral format character (U+E0001 is a surrogate pair) right before a
    // newline must not cause the newline to be skipped.
    func testReplaceControlCharactersWithSpace_AstralFormatCharacterBeforeNewline() {
        XCTAssertEqual(spaced("x\u{E0001}\nab"), "x\u{E0001} ab")
    }

    // A string ending in an astral format character must not crash.
    func testReplaceControlCharactersWithSpace_EndsInAstralFormatCharacter() {
        XCTAssertEqual(spaced("a\u{E007F}"), "a\u{E007F}")
        XCTAssertEqual(spaced("\n\u{E007F}"), " \u{E007F}")
    }

    // A subdivision flag ends in U+E007F; it must survive intact.
    func testReplaceControlCharactersWithSpace_SubdivisionFlagUnchanged() {
        let flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        XCTAssertEqual(spaced("title " + flag), "title " + flag)
    }

    // Format characters (Cf) are not shell threats and must pass through.
    func testReplaceControlCharactersWithSpace_FormatCharactersUnchanged() {
        let zwjFamily = "\u{1F468}\u{200D}\u{1F469}"
        XCTAssertEqual(spaced(zwjFamily), zwjFamily)
        let rlm = "abc\u{200F}def"
        XCTAssertEqual(spaced(rlm), rlm)
        let others = "\u{200B}\u{200E}\u{00AD}\u{FEFF}"
        XCTAssertEqual(spaced(others), others)
    }

    func testReportUnsafeControlCharacterSetExcludesFormatCharacters() {
        let set = NSString.it_reportUnsafeControlCharacterSet()
        XCTAssertTrue(set.contains(UnicodeScalar(0x0A)!))
        XCTAssertTrue(set.contains(UnicodeScalar(0x7F)!))
        XCTAssertTrue(set.contains(UnicodeScalar(0x9F)!))
        XCTAssertFalse(set.contains(UnicodeScalar(0x20)!))
        XCTAssertFalse(set.contains(UnicodeScalar(0xA0)!))
        XCTAssertFalse(set.contains(UnicodeScalar(0x200D)!))
        XCTAssertFalse(set.contains(UnicodeScalar(0xE0001)!))
    }
}
