//
//  BidiMirroringTests.m
//  ModernTests
//
//  Tests for UBA rule L4 mirroring: a character with a Bidi_Mirroring_Glyph
//  counterpart must be drawn as that counterpart when its resolved direction
//  is right-to-left. Mirroring is display-only; the model keeps the logical
//  character.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "iTermCharacterSets.h"
#import "iTermMutableAttributedStringBuilder.h"

@interface BidiMirroringTests : XCTestCase
@end

@implementation BidiMirroringTests

#pragma mark - iTermBidiMirroredCounterpart

- (void)testMirroredPairs {
    XCTAssertEqual(iTermBidiMirroredCounterpart('('), ')');
    XCTAssertEqual(iTermBidiMirroredCounterpart(')'), '(');
    XCTAssertEqual(iTermBidiMirroredCounterpart('['), ']');
    XCTAssertEqual(iTermBidiMirroredCounterpart(']'), '[');
    XCTAssertEqual(iTermBidiMirroredCounterpart('{'), '}');
    XCTAssertEqual(iTermBidiMirroredCounterpart('}'), '{');
    XCTAssertEqual(iTermBidiMirroredCounterpart('<'), '>');
    XCTAssertEqual(iTermBidiMirroredCounterpart('>'), '<');
    // Guillemets are Bidi_Mirrored=Yes in Unicode (BidiMirroring.txt pairs
    // 00AB with 00BB), so Persian «...» quoting mirrors too.
    XCTAssertEqual(iTermBidiMirroredCounterpart(0x00AB), 0x00BB);  // «
    XCTAssertEqual(iTermBidiMirroredCounterpart(0x00BB), 0x00AB);  // »
    // Mathematical angle brackets, from the far end of the table.
    XCTAssertEqual(iTermBidiMirroredCounterpart(0x27E8), 0x27E9);
    XCTAssertEqual(iTermBidiMirroredCounterpart(0x27E9), 0x27E8);
}

- (void)testNonMirroredCharactersAreIdentity {
    XCTAssertEqual(iTermBidiMirroredCounterpart('A'), 'A');
    XCTAssertEqual(iTermBidiMirroredCounterpart(0x0627), 0x0627);  // ا
    XCTAssertEqual(iTermBidiMirroredCounterpart('!'), '!');
    XCTAssertEqual(iTermBidiMirroredCounterpart('~'), '~');
    XCTAssertEqual(iTermBidiMirroredCounterpart('5'), '5');
    // Plain quotation marks are not mirrorable, unlike guillemets.
    XCTAssertEqual(iTermBidiMirroredCounterpart('"'), '"');
}

- (void)testEveryMirrorRoundTrips {
    // L4 mirroring is an involution: applying it twice must return the
    // original character, for every BMP code point.
    for (unsigned int cp = 0; cp <= 0xFFFF; cp++) {
        const unichar mirrored = iTermBidiMirroredCounterpart((unichar)cp);
        if (mirrored != cp) {
            XCTAssertEqual(iTermBidiMirroredCounterpart(mirrored), cp,
                           @"U+%04X mirrors to U+%04X which does not mirror back", cp, mirrored);
        }
    }
}

// Mirroring is applied at draw time by the text-drawing helper, driven by the
// per-cell decision BidiDisplayInfo computes from CoreText's real bidi
// resolution. That decision (including the case of brackets around embedded
// LTR runs, which must NOT mirror) is covered by BidiMirrorSelectionTests.

@end
