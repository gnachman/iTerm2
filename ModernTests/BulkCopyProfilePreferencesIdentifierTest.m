//
//  BulkCopyProfilePreferencesIdentifierTest.m
//  ModernTests
//
//  Regression test for the localized bulk-copy bug: the "Copy Profile
//  Settings..." sheet used to be given the profile tab views' visible labels
//  and it hid any category checkbox whose label was not in that set. Once the
//  tab labels were localized (for example pt-BR "Cores", "Texto", ...) they no
//  longer matched the English iTermBulkCopyIdentifier* constants, so most
//  category checkboxes were hidden and those settings could never be copied.
//
//  The fix keys on the stable, language-independent xib identifiers instead of
//  the localized labels. These tests exercise the pure mapping function so they
//  pass in every UI language.
//

#import <XCTest/XCTest.h>

#import "BulkCopyProfilePreferencesWindowController.h"

@interface BulkCopyProfilePreferencesIdentifierTest : XCTestCase
@end

@implementation BulkCopyProfilePreferencesIdentifierTest

// The eight stable tab identifiers that the profile preferences tab view items
// carry in the xib. These are intentionally the constant values, not localized
// labels.
- (NSArray<NSString *> *)allBulkCopyTabIdentifiers {
    return @[
        iTermBulkCopyIdentifierColors,
        iTermBulkCopyIdentifierText,
        iTermBulkCopyIdentifierWeb,
        iTermBulkCopyIdentifierWindow,
        iTermBulkCopyIdentifierTerminal,
        iTermBulkCopyIdentifierSession,
        iTermBulkCopyIdentifierKeys,
        iTermBulkCopyIdentifierAdvanced,
    ];
}

// Feeding all eight tab identifiers must keep all eight category constants, so
// awakeFromNib would hide zero checkboxes.
- (void)testAllEightCategoriesAreKept {
    NSMutableSet<NSString *> *kept = [NSMutableSet set];
    for (NSString *tabIdentifier in [self allBulkCopyTabIdentifiers]) {
        NSString *mapped =
            [BulkCopyProfilePreferencesWindowController bulkCopyIdentifierForTabViewItemIdentifier:tabIdentifier];
        XCTAssertNotNil(mapped, @"Tab identifier %@ did not map to a bulk-copy category", tabIdentifier);
        [kept addObject:mapped];
    }

    NSSet<NSString *> *expected = [NSSet setWithArray:self.allBulkCopyTabIdentifiers];
    XCTAssertEqualObjects(kept, expected, @"Not every category checkbox would be shown");
    XCTAssertEqual(kept.count, 8u);
}

// The General tab has no bulk-copy category. Its identifier must map to nil so
// no spurious checkbox is expected.
- (void)testGeneralTabHasNoBulkCopyCategory {
    XCTAssertNil([BulkCopyProfilePreferencesWindowController bulkCopyIdentifierForTabViewItemIdentifier:@"1"]);
    XCTAssertNil([BulkCopyProfilePreferencesWindowController bulkCopyIdentifierForTabViewItemIdentifier:@"General"]);
}

// The mapping must not depend on localized labels. Feeding the localized labels
// that pt-BR would produce must NOT match, proving we key on identifiers rather
// than labels. If the code regressed to keying on labels, these would leak
// through in English but fail in other languages.
- (void)testLocalizedLabelsDoNotMap {
    NSArray<NSString *> *localizedLabels = @[ @"Cores", @"Texto", @"Janela", @"Sessão", @"Avançado", @"Teclas" ];
    for (NSString *label in localizedLabels) {
        XCTAssertNil([BulkCopyProfilePreferencesWindowController bulkCopyIdentifierForTabViewItemIdentifier:label],
                     @"Localized label %@ must not be treated as a bulk-copy identifier", label);
    }
}

// A nil identifier must be tolerated and map to nil.
- (void)testNilIdentifierMapsToNil {
    XCTAssertNil([BulkCopyProfilePreferencesWindowController bulkCopyIdentifierForTabViewItemIdentifier:nil]);
}

@end
