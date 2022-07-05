//
//  LineBufferTests.swift
//  iTerm2XCTests
//
//  Created by George Nachman on 12/8/21.
//

import XCTest

extension ScreenCharArray {
    static func create(string: String,
                       predecessor: (sct: screen_char_t, value: String, doubleWidth: Bool)?,
                       foreground: screen_char_t,
                       background: screen_char_t,
                       continuation: screen_char_t,
                       metadata: iTermMetadata,
                       ambiguousIsDoubleWidth: Bool,
                       normalization: iTermUnicodeNormalization,
                       unicodeVersion: Int) -> (sca: ScreenCharArray,
                                                predecessor: screen_char_t?,
                                                foundDWC: Bool) {
        let augmented = predecessor != nil
        let augmentedString = (predecessor?.value ?? " ") + string
        let malloced = malloc(3 * augmentedString.utf16.count * MemoryLayout<screen_char_t>.size)!
        let buffer = malloced.assumingMemoryBound(to: screen_char_t.self)
        var len = Int32(0)
        var cursorIndex = Int32(0)
        var foundDWC: ObjCBool = ObjCBool(false)
        var firstChar: screen_char_t? = nil
        var secondChar: screen_char_t? = nil
        withUnsafeMutablePointer(to: &len) { lenPtr in
            withUnsafeMutablePointer(to: &cursorIndex) { cursorIndexPtr in
                withUnsafeMutablePointer(to: &foundDWC) { foundDWCPtr in
                    StringToScreenChars(augmentedString,
                                        buffer,
                                        foreground,
                                        background,
                                        lenPtr,
                                        ambiguousIsDoubleWidth,
                                        cursorIndexPtr,
                                        foundDWCPtr,
                                        normalization,
                                        unicodeVersion,
                                        false)
                }
            }
        }
        if len > 0 {
            firstChar = buffer[0]
            if len > 1 {
                secondChar = buffer[1]
            }
        }
        var bufferOffset = 0
        var modifiedPredecessor: screen_char_t? = nil
        if augmented, let firstChar = firstChar, let predecessor = predecessor {
            modifiedPredecessor = predecessor.sct
            modifiedPredecessor!.code = firstChar.code
            modifiedPredecessor!.complexChar = firstChar.complexChar
            bufferOffset += 1

            // Does the augmented result begin with a double-width character? If so skip over the
            // DWC_RIGHT when appending. I *think* this is redundant with the `predecessorIsDoubleWidth`
            // test but I'm reluctant to remove it because it could break something.
            if let secondChar = secondChar {
            let augmentedResultBeginsWithDoubleWidthCharacter = (augmented &&
                                                                 len > 1 &&
                                                                 secondChar.code == DWC_RIGHT &&
                                                                 secondChar.complexChar == 0)
                if ((augmentedResultBeginsWithDoubleWidthCharacter || predecessor.doubleWidth) &&
                    len > 1 &&
                    secondChar.code == DWC_RIGHT) {
                    // Skip over a preexisting DWC_RIGHT in the predecessor.
                    bufferOffset += 1
                }
            }
        } else if (firstChar?.complexChar ?? 0) == 0 {
            // We infer that the first character in |string| was not a combining mark. If it were, it
            // would have combined with the space we added to the start of |augmentedString|. Skip past
            // the space.
            bufferOffset += 1
        }
        let sca = ScreenCharArray(line: buffer,
                                  offset: bufferOffset,
                                  length: len - Int32(bufferOffset),
                                  metadata: iTermMetadataMakeImmutable(metadata),
                                  continuation: continuation,
                                  freeOnRelease: true)
        return (sca: sca,
                predecessor: modifiedPredecessor,
                foundDWC: foundDWC.boolValue)
    }
}

public extension screen_char_t {
    static var zero = screen_char_t(code: 0,
                                    foregroundColor: UInt32(ALTSEM_DEFAULT),
                                    fgGreen: 0,
                                    fgBlue: 0,
                                    backgroundColor: UInt32(ALTSEM_DEFAULT),
                                    bgGreen: 0,
                                    bgBlue: 0,
                                    foregroundColorMode: ColorModeAlternate.rawValue,
                                    backgroundColorMode: ColorModeAlternate.rawValue,
                                    complexChar: 0,
                                    bold: 0,
                                    faint: 0,
                                    italic: 0,
                                    blink: 0,
                                    underline: 0,
                                    image: 0,
                                    strikethrough: 0,
                                    underlineStyle: VT100UnderlineStyle.single,
                                    invisible: 0,
                                    inverse: 0,
                                    guarded: 0,
                                    unused: 0)

    static let defaultForeground = screen_char_t(code: 0,
                                                 foregroundColor: UInt32(ALTSEM_DEFAULT),
                                                 fgGreen: 0,
                                                 fgBlue: 0,
                                                 backgroundColor: 0,
                                                 bgGreen: 0,
                                                 bgBlue: 0,
                                                 foregroundColorMode: ColorModeAlternate.rawValue,
                                                 backgroundColorMode: 0,
                                                 complexChar: 0,
                                                 bold: 0,
                                                 faint: 0,
                                                 italic: 0,
                                                 blink: 0,
                                                 underline: 0,
                                                 image: 0,
                                                 strikethrough: 0,
                                                 underlineStyle: .single,
                                                 invisible: 0,
                                                 inverse: 0,
                                                 guarded: 0,
                                                 unused: 0)

    static let defaultBackground = screen_char_t(code: 0,
                                                 foregroundColor: 0,
                                                 fgGreen: 0,
                                                 fgBlue: 0,
                                                 backgroundColor: UInt32(ALTSEM_DEFAULT),
                                                 bgGreen: 0,
                                                 bgBlue: 0,
                                                 foregroundColorMode: 0,
                                                 backgroundColorMode: ColorModeAlternate.rawValue,
                                                 complexChar: 0,
                                                 bold: 0,
                                                 faint: 0,
                                                 italic: 0,
                                                 blink: 0,
                                                 underline: 0,
                                                 image: 0,
                                                 strikethrough: 0,
                                                 underlineStyle: .single,
                                                 invisible: 0,
                                                 inverse: 0,
                                                 guarded: 0,
                                                 unused: 0)

    func with(code: unichar) -> screen_char_t {
        return screen_char_t(code: code,
                             foregroundColor: foregroundColor,
                             fgGreen: fgGreen,
                             fgBlue: fgBlue,
                             backgroundColor: backgroundColor,
                             bgGreen: bgGreen,
                             bgBlue: bgBlue,
                             foregroundColorMode: foregroundColorMode,
                             backgroundColorMode: backgroundColorMode,
                             complexChar: 0,
                             bold: bold,
                             faint: faint,
                             italic: italic,
                             blink: blink,
                             underline: underline,
                             image: 0,
                             strikethrough: strikethrough,
                             underlineStyle: underlineStyle,
                             invisible: invisible,
                             inverse: inverse,
                             guarded: guarded,
                             unused: unused)
    }
}

class LineBufferTests: XCTestCase {
    private func screenCharArrayWithDefaultStyle(_ string: String, eol: Int32) -> ScreenCharArray {
        return ScreenCharArray.create(string: string,
                                      predecessor: nil,
                                      foreground: screen_char_t.defaultForeground,
                                      background: screen_char_t.defaultBackground,
                                      continuation: screen_char_t.defaultForeground.with(code: unichar(eol)),
                                      metadata: iTermMetadataDefault(),
                                      ambiguousIsDoubleWidth: false,
                                      normalization: .none,
                                      unicodeVersion: 9).sca
    }

    func testBasic() throws {
        let linebuffer = LineBuffer()
        let width = Int32(80)
        let hello = screenCharArrayWithDefaultStyle("Hello world",
                                                    eol: EOL_HARD)
        let goodbye = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                      eol: EOL_HARD)
        linebuffer.append(hello,
                          width: width)
        linebuffer.append(goodbye,
                          width: width)

        XCTAssertEqual(linebuffer.numLines(withWidth: width),
                       2)
        XCTAssertEqual(linebuffer.wrappedLine(at: 0, width: width),
                       hello)
        XCTAssertEqual(linebuffer.wrappedLine(at: 1, width: width),
                       goodbye)
    }

    func testBasic_Wraps() throws {
        let linebuffer = LineBuffer()
        let width = Int32(4)
        let linesToAppend = [("Hello world", EOL_HARD),
                             ("Goodbye cruel world", EOL_HARD)]
        for tuple in linesToAppend {
            linebuffer.append(screenCharArrayWithDefaultStyle(tuple.0,
                                                              eol: tuple.1),
                              width: width)
        }

        let expectedLines = [
            screenCharArrayWithDefaultStyle("Hell", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("o wo", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("rld\0", eol: EOL_HARD),
            screenCharArrayWithDefaultStyle("Good", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("bye ", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("crue", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("l wo", eol: EOL_SOFT),
            screenCharArrayWithDefaultStyle("rld\0", eol: EOL_HARD)
        ]

        let actualLines = (0..<expectedLines.count).map {
            linebuffer.wrappedLine(at: Int32($0), width: width).padded(toLength: width, eligibleForDWC: false)
        }

        XCTAssertEqual(actualLines, expectedLines)
    }

    func testCopyOnWrite_ModifySecond() throws {
        let first = LineBuffer()
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)

        let second = first.copy()
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        second.append(s2, width: width)

        XCTAssertEqual(first.allScreenCharArrays, [s1])
        XCTAssertEqual(second.allScreenCharArrays, [s1, s2])
    }

    func testCopyOnWrite_ModifyFirst() throws {
        let first = LineBuffer()
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)

        let second = first.copy()
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        first.append(s2, width: width)

        XCTAssertEqual(first.allScreenCharArrays, [s1, s2])
        XCTAssertEqual(second.allScreenCharArrays, [s1])
    }

    func testCopyOnWrite_ModifyBoth() throws {
        let first = LineBuffer()
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)

        let second = first.copy()
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        second.append(s1, width: width)
        first.append(s2, width: width)

        XCTAssertEqual(first.allScreenCharArrays, [s1, s2])
        XCTAssertEqual(second.allScreenCharArrays, [s1, s1])
    }

    func testCopyOnWrite_CopyOfCopy() throws {
        let first = LineBuffer()
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)

        let second = first.copy()
        let third = second.copy()

        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        second.append(s2, width: width)

        let s3 = screenCharArrayWithDefaultStyle("I like traffic lights",
                                                 eol: EOL_HARD)

        third.append(s3, width: width)

        XCTAssertEqual(first.allScreenCharArrays, [s1])
        XCTAssertEqual(second.allScreenCharArrays, [s1, s2])
        XCTAssertEqual(third.allScreenCharArrays, [s1, s3])
    }

    func testCopyOnWrite_ClientKeepsOwnerAliveUntilWriteToSecond() throws {
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        let first = LineBuffer()
        first.append(s1, width: width)
        let second = first.copy()

        XCTAssertEqual(first.testOnlyBlock(at: 0).numberOfClients(), 1)
        XCTAssertFalse(first.testOnlyBlock(at: 0).hasOwner())

        XCTAssertEqual(second.testOnlyBlock(at: 0).numberOfClients(), 0)
        XCTAssertTrue(second.testOnlyBlock(at: 0).hasOwner())

        second.append(s1, width: width)

        XCTAssertEqual(first.testOnlyBlock(at: 0).numberOfClients(), 0)
        XCTAssertFalse(first.testOnlyBlock(at: 0).hasOwner())

        XCTAssertEqual(second.testOnlyBlock(at: 0).numberOfClients(), 0)
        XCTAssertFalse(second.testOnlyBlock(at: 0).hasOwner())
    }

    func testCopyOnWrite_ClientKeepsOwnerAliveUntilWriteToFirst() throws {
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        let first = LineBuffer()
        first.append(s1, width: width)
        let second = first.copy()

        XCTAssertEqual(first.testOnlyBlock(at: 0).numberOfClients(), 1)
        XCTAssertFalse(first.testOnlyBlock(at: 0).hasOwner())

        XCTAssertEqual(second.testOnlyBlock(at: 0).numberOfClients(), 0)
        XCTAssertTrue(second.testOnlyBlock(at: 0).hasOwner())

        first.append(s1, width: width)

        XCTAssertEqual(first.testOnlyBlock(at: 0).numberOfClients(), 0)
        XCTAssertFalse(first.testOnlyBlock(at: 0).hasOwner())

        XCTAssertEqual(second.testOnlyBlock(at: 0).numberOfClients(), 0)
        XCTAssertFalse(second.testOnlyBlock(at: 0).hasOwner())
    }

    func testCopyOnWrite_Pop() throws {
        let first = LineBuffer()
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)
        first.append(s2, width: width)

        let second = first.copy()
        let buffer = UnsafeMutablePointer<screen_char_t>.allocate(capacity: Int(width))
        defer {
            buffer.deallocate()
        }

        let sca = second.popLastLine(withWidth: width)
        XCTAssertEqual(sca, s2.padded(toLength: width, eligibleForDWC: false))

        XCTAssertEqual(first.allScreenCharArrays, [s1, s2])
        XCTAssertEqual(second.allScreenCharArrays, [s1])
    }

    func testCopyOnWrite_Truncate() throws {
        let first = LineBuffer()
        first.setMaxLines(2)
        let width = Int32(80)
        let s1 = screenCharArrayWithDefaultStyle("Hello world",
                                                 eol: EOL_HARD)
        let s2 = screenCharArrayWithDefaultStyle("Goodbye cruel world",
                                                 eol: EOL_HARD)
        first.append(s1, width: width)
        first.append(s2, width: width)

        let second = first.copy()
        second.dropExcessLines(withWidth: 12)

        XCTAssertEqual(first.allScreenCharArrays, [s1, s2])
        XCTAssertEqual(second.allScreenCharArrays, [s2])
    }
}

extension LineBuffer {
    var allScreenCharArrays: [ScreenCharArray] {
        return (0..<numberOfUnwrappedLines()).compactMap { i in
            unwrappedLine(at: Int32(i))
        }
    }
}

