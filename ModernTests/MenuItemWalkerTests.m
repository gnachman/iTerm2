//
//  MenuItemWalkerTests.m
//  ModernTests
//
//  FINDING 1 (round 3): the "Select Menu Item" walker fires the WRONG
//  duplicate-titled item, a regression from the ambiguity fix. These drive
//  -[NSMenu it_selectMenuItemWithTitle:identifier:] directly (an ObjC category,
//  so the test is ObjC to import the header). NSMenu+iTerm.m resolves a legacy
//  title-only binding whose title is ambiguous (two "Reset" leaves, both with
//  the English accessibility identifier "Reset") to nil because byTitle.count >
//  1; the fallback loop only recurses into items that hasSubmenu, so it skips
//  the top-level "Reset" leaf and descends into "Terminal State", whose subtree
//  has a UNIQUE "Reset" and fires THAT one. Master fired the top-level "Reset"
//  (document order). Language-independent, since the axid anchor matches both
//  regardless of the localized visible title. A legacy binding arrives with the
//  identifier normalized to absent: nil, "", and "_NS:<n>" all take the title
//  path and must behave identically.
//
//  EXPECTED: these assertions FAIL against the current code (the nested Reset
//  fires, or nothing fires) and pass once the walker restores document-order
//  resolution.
//

#import <XCTest/XCTest.h>

#import "NSMenu+iTerm.h"

@interface ITWalkerFiredRecorder : NSObject
@property (nonatomic, weak) NSMenuItem *fired;
@end

@implementation ITWalkerFiredRecorder
- (void)record:(id)sender {
    self.fired = (NSMenuItem *)sender;
}
@end

@interface MenuItemWalkerTests : XCTestCase
@end

@implementation MenuItemWalkerTests

// A leaf with a localized visible title, an English accessibility-identifier
// anchor, and a target/action that records when it fires. autoenablesItems is
// off on the menus so the walker's isEnabled filter still sees them selectable.
static NSMenuItem *ITMakeLeaf(NSString *title, NSString *axid, ITWalkerFiredRecorder *recorder) {
    NSMenuItem *item = [[NSMenuItem alloc] init];
    item.title = title;
    if (axid) {
        [item setAccessibilityIdentifier:axid];
    }
    item.target = recorder;
    item.action = @selector(record:);
    item.enabled = YES;
    return item;
}

// Mirrors Session > Reset (top-level leaf) and Session > Terminal State > Reset
// (nested leaf), both carrying the English axid "Reset" and a localized title.
static NSMenu *ITMakeNestedResetMenu(ITWalkerFiredRecorder *recorder,
                                     NSMenuItem **outTop,
                                     NSMenuItem **outNested) {
    NSMenuItem *top = ITMakeLeaf(@"Redefinir", @"Reset", recorder);
    NSMenuItem *nested = ITMakeLeaf(@"Redefinir", @"Reset", recorder);

    NSMenu *terminalStateSubmenu = [[NSMenu alloc] init];
    terminalStateSubmenu.autoenablesItems = NO;
    [terminalStateSubmenu addItem:nested];

    NSMenuItem *terminalState = [[NSMenuItem alloc] init];
    terminalState.title = @"Estado do terminal";
    terminalState.enabled = YES;
    terminalState.submenu = terminalStateSubmenu;

    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    [menu addItem:top];
    [menu addItem:terminalState];
    if (outTop) {
        *outTop = top;
    }
    if (outNested) {
        *outNested = nested;
    }
    return menu;
}

- (void)assertTopLevelResetFiresForIdentifier:(NSString *)identifier {
    ITWalkerFiredRecorder *recorder = [[ITWalkerFiredRecorder alloc] init];
    NSMenuItem *top = nil;
    NSMenuItem *nested = nil;
    NSMenu *menu = ITMakeNestedResetMenu(recorder, &top, &nested);
    const BOOL result = [menu it_selectMenuItemWithTitle:@"Reset" identifier:identifier];
    XCTAssertTrue(result, @"Walker reported no selection for identifier %@", identifier);
    XCTAssertEqualObjects(recorder.fired, top,
                          @"Expected the top-level Reset leaf to fire; nested Terminal State > Reset fired instead (identifier %@)", identifier);
    XCTAssertNotEqualObjects(recorder.fired, nested,
                             @"Nested duplicate fired (silently wrong item) for identifier %@", identifier);
}

- (void)testFinding1_walker_nilIdentifierFiresTopLevelResetLeaf {
    [self assertTopLevelResetFiresForIdentifier:nil];
}

- (void)testFinding1_walker_emptyIdentifierFiresTopLevelResetLeaf {
    [self assertTopLevelResetFiresForIdentifier:@""];
}

- (void)testFinding1_walker_syntheticIdentifierFiresTopLevelResetLeaf {
    [self assertTopLevelResetFiresForIdentifier:@"_NS:1"];
}

// Sibling duplicates under one menu: both leaves are skipped by the
// hasSubmenu-only fallback, so the walker returns NO and fires nothing. Correct
// behavior is to fire the document-order-first item.
- (void)testFinding1_walker_siblingDuplicatesFireDocumentOrderFirst {
    ITWalkerFiredRecorder *recorder = [[ITWalkerFiredRecorder alloc] init];
    NSMenuItem *first = ITMakeLeaf(@"Redefinir", @"Reset", recorder);
    NSMenuItem *second = ITMakeLeaf(@"Redefinir", @"Reset", recorder);
    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    [menu addItem:first];
    [menu addItem:second];

    const BOOL result = [menu it_selectMenuItemWithTitle:@"Reset" identifier:nil];
    XCTAssertTrue(result, @"Ambiguous sibling duplicates returned NO / fired nothing");
    XCTAssertNotNil(recorder.fired, @"No item fired for an ambiguous sibling-duplicate title");
    XCTAssertEqualObjects(recorder.fired, first, @"Expected the document-order-first duplicate to fire");
}

@end
