//
//  ContextMenuHexBytesPluralTests.m
//  ModernTests
//
//  VALIDATION test for FINDING 3: the "%@ hex bytes" context-menu item is built
//  with a plain, non-pluralizing catalog entry, so a count of 1 renders
//  "1 hex bytes" instead of the singular "1 hex byte".
//
//  Production site (inline inside a larger builder, no injectable seam):
//    sources/ContextMenu/iTermContextMenuUtilities.m ~466
//      theItem.title = [NSString stringWithFormat:
//          NSLocalizedStringWithDefaultValue(@"ContextMenu.HexBytes", nil,
//              [NSBundle mainBundle], @"%@ hex bytes", ...), @(data.length)];
//
//  The catalog entry sources/Localizable.xcstrings -> "ContextMenu.HexBytes" is
//  a bare stringUnit ("%@ hex bytes") with NO plural variations, unlike the
//  sibling "PasteSpecial.BytesInLines" which uses "%1$#@bytes@ ..." plural
//  substitutions. Two defects compound:
//    1. No one/other plural, so count 1 => "1 hex bytes".
//    2. stringWithFormat: (not localizedStringWithFormat:) with an NSNumber %@,
//       so the number is not formatted with the locale's digit grouping.
//  The fix is the same shape as PasteSpecial.BytesInLines: %1$ld +
//  localizedStringWithFormat: + a one/other plural in the catalog.
//
//  Reachability caveat: the production branch is guarded by `data.length > 4`,
//  so the count is always >= 5 in the live menu and the singular case is not
//  currently user-reachable. The catalog entry is still wrong (it cannot
//  pluralize at all), and this test pins the CORRECT behavior at the catalog
//  level. There is no method/function seam that returns the composed title, so
//  the assertion is made against the catalog string the production code loads.
//
//  EXPECTED RESULT: the singular assertions in testHexBytesSingularForCountOne
//  FAIL against the current catalog (it yields "1 hex bytes"), documenting the
//  missing plural. The control test testPasteSpecialPluralIsWiredForContrast
//  PASSES, proving the plural mechanism works where it was applied.
//

#import <XCTest/XCTest.h>

@interface ContextMenuHexBytesPluralTests : XCTestCase
@end

@implementation ContextMenuHexBytesPluralTests

// Loads the exact catalog format string the production code uses, then formats
// it the way a plural-aware implementation would (localizedStringWithFormat:).
static NSString *HexBytesTitleForCount(long count) {
    // Mirrors the production call: the fixed code uses %1$ld with
    // localizedStringWithFormat:, and the catalog entry now carries a one/other
    // plural, so count 1 inflects to the singular noun.
    NSString *format = NSLocalizedStringWithDefaultValue(@"ContextMenu.HexBytes", nil,
                                                         [NSBundle mainBundle],
                                                         @"%1$ld hex bytes",
                                                         @"Context menu item title showing a count of hexadecimal bytes; %1$ld is a count of hex bytes");
    return [NSString localizedStringWithFormat:format, count];
}

// FAILING test: asserts the correct singular behavior for a count of 1.
- (void)testHexBytesSingularForCountOne {
    NSString *s = HexBytesTitleForCount(1);
    XCTAssertTrue([s containsString:@"hex byte"],
                  @"expected the singular noun 'hex byte' for a count of 1, got: %@", s);
    XCTAssertFalse([s containsString:@"hex bytes"],
                   @"a count of 1 must not use the plural 'hex bytes', got: %@", s);
}

// Plural is correct for counts other than 1 (this already holds today).
- (void)testHexBytesPluralForCountFive {
    NSString *s = HexBytesTitleForCount(5);
    XCTAssertTrue([s containsString:@"hex bytes"],
                  @"expected plural 'hex bytes' for a count of 5, got: %@", s);
}

// Control: the sibling PasteSpecial.BytesInLines entry DOES pluralize, proving
// the plural mechanism is available and was simply not applied to HexBytes.
- (void)testPasteSpecialPluralIsWiredForContrast {
    NSString *format = NSLocalizedStringWithDefaultValue(@"PasteSpecial.BytesInLines", nil,
                                                         [NSBundle mainBundle],
                                                         @"%1$ld bytes in %2$ld lines.",
                                                         @"Paste-special stats label; %1$ld is a byte count, %2$ld is a line count");
    NSString *singular = [NSString localizedStringWithFormat:format, (long)1, (long)1];
    XCTAssertTrue([singular containsString:@"byte"], @"got: %@", singular);
    XCTAssertFalse([singular containsString:@"bytes"],
                   @"PasteSpecial pluralizes; 1 must read singular, got: %@", singular);
}

// ---------------------------------------------------------------------------
// VALIDATION for FINDING 1: the "UTF-8 bytes" context-menu item beside the
// hex-bytes item is NOT pluralizable, unlike the hex-bytes item.
//
// Production site: sources/ContextMenu/iTermContextMenuUtilities.m ~456
//   theItem.title = [NSString stringWithFormat:
//       NSLocalizedStringWithDefaultValue(@"ContextMenu.Utf8Bytes", nil,
//           [NSBundle mainBundle], @"%1$@ UTF-8 bytes: %2$@", ...),
//       @(data.length), stringValue];
//
// Two defects vs. the adjacent, fixed ContextMenu.HexBytes site (~466), which
// uses +localizedStringWithFormat: with a one/other plural in the catalog:
//   1. The catalog entry ContextMenu.Utf8Bytes is a bare stringUnit
//      ("%1$@ UTF-8 bytes: %2$@") with NO plural variations, so no locale can
//      inflect the "UTF-8 bytes" noun for count. pt-BR hardcodes "bytes UTF-8".
//   2. The count uses %1$@ with an NSNumber via plain +stringWithFormat:
//      (not %1$ld via +localizedStringWithFormat:), so the number is not
//      locale-formatted with digit grouping.
//
// Reachability caveat: the whole numeric-conversion block is guarded by
// `data.length > 1` (iTermContextMenuUtilities.m ~415), so the count is always
// >= 2 in the live menu and the English singular case ("1 UTF-8 byte") is not
// currently user-reachable. This is a parity gap with HexBytes, not an
// English-visible bug. The catalog entry is still unpluralizable for every
// locale, and these tests pin the CORRECT behavior at the catalog level.

// Loads the ContextMenu.Utf8Bytes entry straight from the source catalog JSON,
// resolved from this test file's own path (the same technique the Swift
// LocalizationHygieneTests use with #filePath), so the assertion is made
// against exactly the string the production code compiles into the bundle.
static NSDictionary *Utf8BytesCatalogEntry(void) {
    NSString *thisFile = [NSString stringWithUTF8String:__FILE__];
    NSString *repoRoot = [[thisFile stringByDeletingLastPathComponent]  // ModernTests
                          stringByDeletingLastPathComponent];           // repo root
    NSString *path = [repoRoot stringByAppendingPathComponent:@"sources/Localizable.xcstrings"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        return nil;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSDictionary *strings = json[@"strings"];
    return strings[@"ContextMenu.Utf8Bytes"];
}

// FAILING test: the catalog entry must carry a one/other plural, exactly like
// its sibling ContextMenu.HexBytes. Today it is a bare stringUnit, so this
// fails and enumerates the missing plural.
- (void)testUtf8BytesHasPluralVariations {
    NSDictionary *entry = Utf8BytesCatalogEntry();
    XCTAssertNotNil(entry, @"could not load ContextMenu.Utf8Bytes from sources/Localizable.xcstrings via __FILE__=%s", __FILE__);
    NSDictionary *en = entry[@"localizations"][@"en"];
    XCTAssertNotNil(en, @"ContextMenu.Utf8Bytes has no English localization: %@", entry);
    NSDictionary *plural = en[@"variations"][@"plural"];
    XCTAssertNotNil(plural,
                    @"ContextMenu.Utf8Bytes must pluralize the 'UTF-8 bytes' noun (one/other) like ContextMenu.HexBytes, but it is a bare stringUnit with no plural variations: %@", en);
    XCTAssertNotNil(plural[@"one"], @"missing 'one' plural variation: %@", plural);
    XCTAssertNotNil(plural[@"other"], @"missing 'other' plural variation: %@", plural);
    // The fixed shape uses %1$ld (locale-formatted count) rather than %1$@ (an
    // un-formatted NSNumber), matching HexBytes. Pin that the 'one' variation is
    // an integer specifier so the count is locale-formatted, not %@.
    NSString *oneValue = plural[@"one"][@"stringUnit"][@"value"];
    XCTAssertTrue([oneValue containsString:@"%1$ld"],
                  @"the count should be a locale-formatted integer specifier (%%1$ld), not %%1$@; got: %@", oneValue);
}

// FAILING test: formatting a count of 1 through the live catalog string must
// read the singular noun "UTF-8 byte". With no plural in the catalog the
// runtime returns "%1$@ UTF-8 bytes: %2$@", so a count of 1 renders
// "1 UTF-8 bytes: ..." and this assertion fails.
- (void)testUtf8BytesSingularForCountOne {
    NSString *format = NSLocalizedStringWithDefaultValue(@"ContextMenu.Utf8Bytes", nil,
                                                         [NSBundle mainBundle],
                                                         @"%1$ld UTF-8 bytes: %2$@",
                                                         @"Context menu item showing decoded UTF-8 bytes; %1$ld is a UTF-8 byte count, %2$@ is the decoded string");
    // Mirror the fixed production call: the count is passed as a (long) via
    // localizedStringWithFormat:, so the one/other plural inflects.
    NSString *title = [NSString localizedStringWithFormat:format, (long)1, @"x"];
    XCTAssertTrue([title containsString:@"UTF-8 byte"],
                  @"expected the singular noun 'UTF-8 byte' for a count of 1, got: %@", title);
    XCTAssertFalse([title containsString:@"UTF-8 bytes"],
                   @"a count of 1 must not use the plural 'UTF-8 bytes', got: %@", title);
}

@end
