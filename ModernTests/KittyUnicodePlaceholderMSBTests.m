//
//  KittyUnicodePlaceholderMSBTests.m
//  ModernTests
//
//  Regression test for issue 13027: a Kitty Unicode placeholder cell that
//  carries only two diacritics (row, column) and omits the optional third
//  diacritic (the most significant byte of the image id) must be treated as
//  MSB=0. The Kitty spec makes the third diacritic optional while the image id
//  fits in 24 bits, and kitty/Ghostty render such cells. Previously iTerm2 left
//  the MSB at its -1 "absent" sentinel, which became 0xff000000 when shifted,
//  yielding a bogus image id (e.g. 0xff000001 instead of 1) that matched no
//  placement, so the cells drew nothing.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "ScreenChar.h"
#import "iTermTextDrawingHelper.h"

// Defined in ScreenChar.m; not exposed in a header.
void SetComplexCharInScreenChar(screen_char_t *screenChar,
                                NSString *theString,
                                iTermUnicodeNormalization normalization,
                                BOOL isSpacingCombiningMark);

@interface KittyUnicodePlaceholderMSBTests : XCTestCase
@end

@implementation KittyUnicodePlaceholderMSBTests

// Build a single virtual-placeholder screen_char_t for U+10EEEE followed by the
// given diacritics, with a foreground color that carries the low bits of the
// image id.
- (screen_char_t)placeholderCharWithDiacritics:(NSArray<NSNumber *> *)diacritics
                                   imageIdLowByte:(unsigned int)low {
    // U+10EEEE as a surrogate pair (high 0xDBFB, low 0xDEEE), then the diacritics.
    NSMutableArray<NSNumber *> *codeUnits = [NSMutableArray arrayWithArray:@[ @0xDBFB, @0xDEEE ]];
    [codeUnits addObjectsFromArray:diacritics];
    unichar buffer[8];
    for (NSUInteger i = 0; i < codeUnits.count; i++) {
        buffer[i] = (unichar)codeUnits[i].unsignedIntValue;
    }
    NSString *string = [NSString stringWithCharacters:buffer length:codeUnits.count];

    screen_char_t c = { 0 };
    SetComplexCharInScreenChar(&c, string, iTermUnicodeNormalizationNone, NO);
    c.image = 1;
    c.virtualPlaceholder = 1;

    // Sanity check that we reconstruct the placeholder string we put in.
    XCTAssertEqualObjects(ScreenCharToKittyPlaceholder(&c), string);

    // The foreground color carries the low 24 bits of the image id.
    c.foregroundColorMode = ColorModeNormal;
    c.foregroundColor = low;
    c.fgGreen = 0;
    c.fgBlue = 0;
    return c;
}

// A cell with row+column diacritics but no third diacritic should decode to the
// image id from the foreground color alone (MSB=0).
- (void)testTwoDiacriticsTreatsMissingMSBAsZero {
    // Row index 1 (U+030D), column index 2 (U+030E). No MSB diacritic.
    screen_char_t c = [self placeholderCharWithDiacritics:@[ @0x030D, @0x030E ]
                                            imageIdLowByte:1];

    iTermKittyUnicodePlaceholderState state;
    iTermKittyUnicodePlaceholderStateInit(&state);
    iTermKittyUnicodePlaceholderInfo info = { 0 };
    const BOOL ok = iTermDecodeKittyUnicodePlaceholder(&c, nil, &state, &info);

    XCTAssertTrue(ok);
    XCTAssertEqual(info.row, 1);
    XCTAssertEqual(info.column, 2);
    XCTAssertEqual(info.imageID, 1u);
}

// A cell with an explicit third diacritic of index 0 (MSB=0) must decode
// identically. This is the case that already worked and guards against a fix
// that regresses it.
- (void)testExplicitZeroMSBDecodesToImageId {
    // Row 1, column 2, MSB index 0 (U+0305).
    screen_char_t c = [self placeholderCharWithDiacritics:@[ @0x030D, @0x030E, @0x0305 ]
                                            imageIdLowByte:1];

    iTermKittyUnicodePlaceholderState state;
    iTermKittyUnicodePlaceholderStateInit(&state);
    iTermKittyUnicodePlaceholderInfo info = { 0 };
    const BOOL ok = iTermDecodeKittyUnicodePlaceholder(&c, nil, &state, &info);

    XCTAssertTrue(ok);
    XCTAssertEqual(info.row, 1);
    XCTAssertEqual(info.column, 2);
    XCTAssertEqual(info.imageID, 1u);
}

@end
