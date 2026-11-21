//
//  DrawingNullabilityTests.swift
//  ModernTests
//
//  Documents the nullability claims in sources/Drawing that the nullability
//  sanitizer found false (unit H3 of docs/swift-migration/nullability-triage.md).
//  The code accepts or produces nil by design; these tests pin what Swift sees.
//

import XCTest
@testable import iTerm2SharedARC

final class DrawingNullabilityTests: XCTestCase {
    // -[iTermImageWrapper initWithImage:] only reads the image's size (zero for
    // nil, so it skips the downscale) and stores it; the badge renderer wraps
    // a nil badge image this way. Passing nil compiles only because the
    // parameter is optional, and the image property is then nil. While the
    // property was claimed nonnull, Swift held that nil as a non-optional
    // NSImage.
    func testWrapperOfNilImageHasNoImage() {
        let image: NSImage? = nil
        let wrapper = iTermImageWrapper(image: image)
        let wrapped: NSImage? = wrapper.image
        XCTAssertNil(wrapped)
    }

    // +withImage: only forwards to -initWithImage:.
    func testWithNilImageHasNoImage() {
        let image: NSImage? = nil
        let wrapped: NSImage? = iTermImageWrapper.withImage(image).image
        XCTAssertNil(wrapped)
    }

    func testWrapperOfAnImageHoldsIt() {
        let image = NSImage(size: NSSize(width: 4, height: 3))
        let wrapper = iTermImageWrapper(image: image)
        XCTAssertTrue(wrapper.image === image)
    }
}

final class DrawingHelperColorNullabilityTests: XCTestCase {
    // -[PTYTextView drawingHelperColorForCode:...] returns a color map lookup.
    // A text view without a data source has no color map, so the lookup is
    // nil. While the protocol claimed the return nonnull, Swift held that nil
    // as a non-optional NSColor. Stored into an optional in a Development
    // build it reads as nil (a class reference's nil is the optional's empty
    // case), so this test passed before the claim changed as well as after;
    // it pins the run-time value, and the test below pins the type.
    func testColorFromATextViewWithoutAColorMapIsNil() throws {
        let textView = try XCTUnwrap(PTYTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertNil(textView.colorMap)
        let color: NSColor? = textView.drawingHelperColor(forCode: Int32(ALTSEM_DEFAULT),
                                                          green: 0,
                                                          blue: 0,
                                                          colorMode: ColorModeAlternate,
                                                          bold: false,
                                                          faint: false,
                                                          isBackground: true)
        XCTAssertNil(color)
    }

    // The return is optional at compile time: conditional binding compiles
    // only on an optional.
    func testColorIsOptionalAtCompileTime() throws {
        let colorMap = iTermColorMap()
        let textView = try XCTUnwrap(PTYTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100)))
        textView.colorMap = colorMap
        colorMap.setColor(NSColor.red, forKey: kColorMapBackground)
        guard let color = textView.drawingHelperColor(forCode: Int32(ALTSEM_DEFAULT),
                                                      green: 0,
                                                      blue: 0,
                                                      colorMode: ColorModeAlternate,
                                                      bold: false,
                                                      faint: false,
                                                      isBackground: true) else {
            return XCTFail("The background color is in the map")
        }
        XCTAssertEqual(color.usingColorSpace(.sRGB)?.redComponent ?? 0, 1, accuracy: 0.01)
    }
}

final class BidiDisplayInfoNullabilityTests: XCTestCase {
    private var savedBidi = false

    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        let deadline = Date().addingTimeInterval(0.5)
        while iTermPreferences.bidiEnabled() != enabled && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
    }

    override func setUp() {
        super.setUp()
        savedBidi = iTermPreferences.bool(forKey: kPreferenceKeyBidi)
        // With bidi off the initializer returns nil before it looks at the
        // dictionary, so it is on for these tests.
        setBidiPreference(true)
    }

    override func tearDown() {
        setBidiPreference(savedBidi)
        super.tearDown()
    }

    // A saved line without bidi info has no "bidi" entry
    // (ScreenCharArrayKeyBidiInfo), and -[ScreenCharArray initWithDictionary:]
    // passes the missing value, nil, to -[iTermBidiDisplayInfo
    // initWithDictionary:]. The result was and is nil; this passes before and
    // after the parameter became optional.
    func testSavedLineWithoutBidiInfoRestoresWithoutBidiInfo() {
        let sca = screenCharArrayWithDefaultStyle("abc", eol: EOL_HARD)
        var dictionary = sca.dictionaryValue
        dictionary.removeValue(forKey: "bidi")
        let restored = ScreenCharArray(dictionary: dictionary)
        XCTAssertEqual(restored.stringValue, "abc")
        XCTAssertNil(restored.bidiInfo)
    }

    // Passing nil compiles only because the parameter is optional.
    func testNilDictionaryGivesNoInfo() {
        let dictionary: NSDictionary? = nil
        XCTAssertNil(BidiDisplayInfoObjc(dictionary))
    }
}
