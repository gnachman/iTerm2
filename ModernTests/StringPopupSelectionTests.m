//
//  StringPopupSelectionTests.m
//  ModernTests
//
//  A Settings popup whose items stand for strings showed nothing selected when the saved value
//  wasn't in its menu, as with a Dynamic Profile naming a progress bar color scheme that doesn't
//  exist. -indexOfItemWithRepresentedObject: returns -1, not NSNotFound, so the old check passed
//  it to -selectItemAtIndex:, which cleared the selection (QA finding F-265). Such a value now
//  shows the default instead, if the default is in the menu.
//

#import <XCTest/XCTest.h>

#import "NSPopUpButton+iTerm.h"

@interface StringPopupSelectionTests : XCTestCase
@end

@implementation StringPopupSelectionTests {
    NSPopUpButton *_popup;
}

- (void)setUp {
    [super setUp];
    _popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 24) pullsDown:NO];
    for (NSString *value in @[ @"Default", @"Red", @"Blue" ]) {
        [_popup addItemWithTitle:value];
        _popup.lastItem.representedObject = value;
    }
    [_popup selectItemAtIndex:2];
}

- (void)testSelectsTheItemForTheValue {
    [_popup it_selectItemWithRepresentedObject:@"Red" fallback:@"Default"];
    XCTAssertEqualObjects(_popup.selectedItem.representedObject, @"Red");
}

- (void)testUnknownValueSelectsTheFallback {
    [_popup it_selectItemWithRepresentedObject:@"NoSuchScheme" fallback:@"Default"];
    XCTAssertEqualObjects(_popup.selectedItem.representedObject, @"Default");
}

- (void)testUnknownValueAndFallbackShowsNoSelection {
    [_popup it_selectItemWithRepresentedObject:@"NoSuchScheme" fallback:@"AlsoMissing"];
    XCTAssertNil(_popup.selectedItem);
}

// The keyboard locale popup is blank on purpose when no locale is set.
- (void)testNilValueLeavesTheSelectionAlone {
    [_popup it_selectItemWithRepresentedObject:nil fallback:@"Red"];
    XCTAssertEqualObjects(_popup.selectedItem.representedObject, @"Blue");
}

- (void)testNullValueLeavesTheSelectionAlone {
    [_popup it_selectItemWithRepresentedObject:[NSNull null] fallback:[NSNull null]];
    XCTAssertEqualObjects(_popup.selectedItem.representedObject, @"Blue");
}

@end
