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

#pragma mark - Identifier that names an unavailable item

// Mirrors Edit > Actions > "Move Session to Tab" (a user-defined action, which has no stable
// identifier) and Session > "Move Session to Tab" (the real item, which has one). The action
// item comes first in document order. The walker must not fire it for a binding that names
// the real item: it is a different item, and it can do something else.
static NSMenu *ITMakeMoveSessionMenu(ITWalkerFiredRecorder *recorder,
                                     NSMenuItem **outAction,
                                     NSMenuItem **outReal) {
    NSMenuItem *action = ITMakeLeaf(@"Move Session to Tab", nil, recorder);
    NSMenu *actionsSubmenu = [[NSMenu alloc] init];
    actionsSubmenu.autoenablesItems = NO;
    [actionsSubmenu addItem:action];
    NSMenuItem *actions = [[NSMenuItem alloc] init];
    actions.title = @"Actions";
    actions.enabled = YES;
    actions.submenu = actionsSubmenu;

    NSMenuItem *real = ITMakeLeaf(@"Move Session to Tab", @"Move Session to Tab", recorder);
    real.identifier = @"Move Session to Tab";
    NSMenu *sessionSubmenu = [[NSMenu alloc] init];
    sessionSubmenu.autoenablesItems = NO;
    [sessionSubmenu addItem:real];
    NSMenuItem *session = [[NSMenuItem alloc] init];
    session.title = @"Session";
    session.enabled = YES;
    session.submenu = sessionSubmenu;

    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    [menu addItem:actions];
    [menu addItem:session];
    if (outAction) {
        *outAction = action;
    }
    if (outReal) {
        *outReal = real;
    }
    return menu;
}

- (void)testIdentifierOfEnabledItemFiresThatItemNotEarlierTitleDuplicate {
    ITWalkerFiredRecorder *recorder = [[ITWalkerFiredRecorder alloc] init];
    NSMenuItem *real = nil;
    NSMenu *menu = ITMakeMoveSessionMenu(recorder, NULL, &real);

    const BOOL result = [menu it_selectMenuItemWithTitle:@"Move Session to Tab"
                                              identifier:@"Move Session to Tab"];
    XCTAssertTrue(result);
    XCTAssertEqualObjects(recorder.fired, real);
}

- (void)testIdentifierOfDisabledItemDoesNotFallBackToTitleDuplicate {
    ITWalkerFiredRecorder *recorder = [[ITWalkerFiredRecorder alloc] init];
    NSMenuItem *real = nil;
    NSMenu *menu = ITMakeMoveSessionMenu(recorder, NULL, &real);
    real.enabled = NO;

    const BOOL result = [menu it_selectMenuItemWithTitle:@"Move Session to Tab"
                                              identifier:@"Move Session to Tab"];
    XCTAssertFalse(result, @"A disabled target must report no selection");
    XCTAssertNil(recorder.fired, @"The identifier names a disabled item; no title duplicate may fire");
}

- (void)testIdentifierOfHiddenItemDoesNotFallBackToTitleDuplicate {
    ITWalkerFiredRecorder *recorder = [[ITWalkerFiredRecorder alloc] init];
    NSMenuItem *real = nil;
    NSMenu *menu = ITMakeMoveSessionMenu(recorder, NULL, &real);
    real.hidden = YES;

    const BOOL result = [menu it_selectMenuItemWithTitle:@"Move Session to Tab"
                                              identifier:@"Move Session to Tab"];
    XCTAssertFalse(result);
    XCTAssertNil(recorder.fired);
}

// An identifier that names no live item is stale, and the title fallback stays available.
- (void)testIdentifierOfNoItemStillFallsBackToTitle {
    ITWalkerFiredRecorder *recorder = [[ITWalkerFiredRecorder alloc] init];
    NSMenuItem *action = nil;
    NSMenu *menu = ITMakeMoveSessionMenu(recorder, &action, NULL);

    const BOOL result = [menu it_selectMenuItemWithTitle:@"Move Session to Tab"
                                              identifier:@"Removed Identifier"];
    XCTAssertTrue(result);
    XCTAssertEqualObjects(recorder.fired, action);
}

// -[NSMenu update] on the root does not validate the items of a submenu. The enabled state
// of the target can be the value from the last time that its submenu was open. The walker
// must refresh the submenu before it reads isEnabled.
- (void)testStaleDisabledStateInSubmenuIsRefreshed {
    ITWalkerFiredRecorder *recorder = [[ITWalkerFiredRecorder alloc] init];
    NSMenuItem *real = nil;
    NSMenu *menu = ITMakeMoveSessionMenu(recorder, NULL, &real);
    real.menu.autoenablesItems = YES;
    real.enabled = NO;

    const BOOL result = [menu it_selectMenuItemWithTitle:@"Move Session to Tab"
                                              identifier:@"Move Session to Tab"];
    XCTAssertTrue(result);
    XCTAssertEqualObjects(recorder.fired, real);
}

@end
