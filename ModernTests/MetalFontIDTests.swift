//
//  MetalFontIDTests.swift
//  ModernTests
//
//  -[NSFont it_metalFontID] maps fonts to small integer IDs for the GPU renderer's glyph keys,
//  using a bijection keyed by the NSFont. A font made by it_fontByAddingToPointSize: (Cmd-+ and
//  Cmd--) is -isEqual: to the same font made any other way, but has a different -hash, because
//  CTFontCreateCopyWithAttributes with an explicit matrix puts a matrix attribute in its
//  descriptor that -hash includes and -isEqual: ignores. Keys whose equality and hash disagree
//  violate Hashable. When inserting one grows the dictionary, Swift traps with
//  KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS.
//

import XCTest
@testable import iTerm2SharedARC

final class MetalFontIDTests: XCTestCase {
    private func plainFont(_ name: String = "Menlo-Regular", size: CGFloat = 13) throws -> NSFont {
        return try XCTUnwrap(NSFont(name: name, size: size))
    }

    // The same font and size, made the way Cmd-+ makes it.
    private func zoomedFont(_ name: String = "Menlo-Regular", size: CGFloat = 13) throws -> NSFont {
        return try plainFont(name, size: size - 1).it_fontByAdding(toPointSize: 1)
    }

    // The AppKit behavior the bug depends on. If this stops holding, AppKit fixed it.
    func testZoomedFontIsEqualToPlainFontButHashesDifferently() throws {
        let plain = try plainFont()
        let zoomed = try zoomedFont()
        XCTAssertTrue(plain.isEqual(zoomed))
        XCTAssertTrue(zoomed.isEqual(plain))
        if plain.hash == zoomed.hash {
            throw XCTSkip("NSFont's -hash now agrees with -isEqual: for zoomed fonts")
        }
    }

    // Equal fonts must get the same ID. Before the fix, the lookup for the zoomed font usually
    // misses (its hash puts it in a different bucket), so it gets a second ID, and inserting
    // that duplicate key is what traps when it grows the dictionary.
    func testZoomedAndPlainFontsShareMetalFontID() throws {
        let plain = try plainFont("Menlo-Regular", size: 17)
        let zoomed = try zoomedFont("Menlo-Regular", size: 17)
        XCTAssertEqual(plain.it_metalFontID, zoomed.it_metalFontID)
    }

    func testFontWithMetalIDRoundTrips() throws {
        let zoomed = try zoomedFont("Menlo-Regular", size: 19)
        let font = try XCTUnwrap(NSFont.it_font(withMetalID: zoomed.it_metalFontID))
        XCTAssertTrue(font.isEqual(zoomed))
    }

    func testDifferentFontsGetDifferentIDs() throws {
        let menlo13 = try plainFont("Menlo-Regular", size: 13)
        let menlo14 = try plainFont("Menlo-Regular", size: 14)
        let monaco13 = try plainFont("Monaco", size: 13)
        XCTAssertNotEqual(menlo13.it_metalFontID, menlo14.it_metalFontID)
        XCTAssertNotEqual(menlo13.it_metalFontID, monaco13.it_metalFontID)
    }

    // Interleaves new fonts with plain/zoomed pairs so that inserts cross several dictionary
    // growth boundaries, which is when a duplicate key traps. Every pair must share one stable ID.
    // Before the fix this usually crashes the test process.
    func testPlainAndZoomedFontsStayConsistentAcrossDictionaryGrowth() throws {
        for size in stride(from: 20, to: 84, by: 1) {
            let plain = try plainFont("Menlo-Regular", size: CGFloat(size))
            let filler = try plainFont("Monaco", size: CGFloat(size))
            _ = filler.it_metalFontID
            let zoomed = try zoomedFont("Menlo-Regular", size: CGFloat(size))
            let plainID = plain.it_metalFontID
            XCTAssertEqual(zoomed.it_metalFontID, plainID, "size \(size)")
            XCTAssertEqual(plain.it_metalFontID, plainID, "size \(size)")
        }
    }

    // Fonts that render differently must keep different IDs even though they share a name and
    // size. A variation axis is in the descriptor, and so is a non-identity matrix.
    func testVariationFontGetsItsOwnID() throws {
        let skia = try plainFont("Skia-Regular", size: 13)
        let descriptor = skia.fontDescriptor.addingAttributes([.variation: [2003265652: 1.5]])
        let varied = try XCTUnwrap(NSFont(descriptor: descriptor, size: 13))
        XCTAssertFalse(varied.isEqual(skia), "Precondition")
        XCTAssertNotEqual(varied.it_metalFontID, skia.it_metalFontID)
    }

    // PTYFontInfo stores the ID so the renderer doesn't have to look it up for every run.
    func testFontInfoStoresMetalFontID() throws {
        let zoomed = try zoomedFont("Menlo-Regular", size: 21)
        let fontInfo = PTYFontInfo(font: zoomed)
        XCTAssertEqual(fontInfo.metalFontID, zoomed.it_metalFontID)
        XCTAssertEqual((fontInfo.copy() as! PTYFontInfo).metalFontID, zoomed.it_metalFontID)
    }

    func testSkewedFontGetsItsOwnID() throws {
        let plain = try plainFont("Menlo-Regular", size: 15)
        var skew = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
        let skewed = CTFontCreateCopyWithAttributes(plain, 15, &skew, nil) as NSFont
        XCTAssertNotEqual(skewed.it_metalFontID, plain.it_metalFontID)
    }
}

// Objects whose own equality is too fine for the bijection: these are all "the same" if their
// names match, regardless of serial.
private final class Named: NSObject, BijectionIdentifiable {
    let name: String
    let serial: Int
    init(_ name: String, _ serial: Int) {
        self.name = name
        self.serial = serial
    }
    var bijectionIdentity: AnyHashable { AnyHashable(name) }
}

final class BijectionIdentifiableTests: XCTestCase {
    func testLookupUsesIdentityAndReturnsLinkedObject() throws {
        let bijection = ObjCBijection()
        let first = Named("a", 1)
        bijection.link(1 as NSNumber, first)

        let lookalike = Named("a", 2)
        XCTAssertEqual(bijection.object(forRight: lookalike) as? NSNumber, 1)
        let right = try XCTUnwrap(bijection.object(forLeft: 1 as NSNumber)?.base as? Named)
        XCTAssertTrue(right === first)
    }

    func testRelinkingReplacesStaleEntries() throws {
        let bijection = ObjCBijection()
        bijection.link(1 as NSNumber, Named("a", 1))
        bijection.link(1 as NSNumber, Named("b", 2))
        XCTAssertNil(bijection.object(forRight: Named("a", 3)))
        let right = try XCTUnwrap(bijection.object(forLeft: 1 as NSNumber)?.base as? Named)
        XCTAssertEqual(right.serial, 2)

        bijection.link(2 as NSNumber, Named("b", 4))
        XCTAssertNil(bijection.object(forLeft: 1 as NSNumber))
        XCTAssertEqual(bijection.object(forRight: Named("b", 5)) as? NSNumber, 2)
    }

    func testObjectsWithoutIdentityUseTheirOwnEquality() {
        let bijection = ObjCBijection()
        bijection.link("x" as NSString, 7 as NSNumber)
        XCTAssertEqual(bijection.object(forLeft: "x" as NSString) as? NSNumber, 7)
        XCTAssertEqual(bijection.object(forRight: 7 as NSNumber) as? String, "x")
    }
}
