//
//  PseudoTerminalTabRenumberTests.m
//  ModernTests
//
//  Regression coverage for the tab-shortcut misordering bug: create tabs
//  1,2,3,4,5, group 2,3,4, then remove 3 from the group. The contiguity
//  repair correctly reorders the tabs to 1,2,4,3,5 (the group's remaining
//  members stay adjacent, the removed tab lands just after them), but the
//  Cmd-N shortcut numbers -- which are assigned by physical position via
//  -updateTabObjectCounts -- were left stale, so they read 1,2,4,3,5 instead
//  of the consecutive 1,2,3,4,5 they must always be.
//
//  Root cause: -tabsDidReorder is the single choke point every reorder path
//  funnels through, but it never requested an object-count refresh. The drag
//  paths call -setNeedsUpdateTabObjectCounts: themselves; the context-menu
//  group-membership paths (remove-from-group, group-tabs, join-group) do not,
//  so a reorder they triggered left the numbers glued to the old positions.
//
//  This test drives the real -tabsDidReorder and asserts it requests a
//  renumber. Reintroducing the bug (dropping the request from -tabsDidReorder)
//  makes it fail. It deliberately avoids building live sessions/tabs: the
//  missing renumber request is a property of the choke point itself, so no tab
//  content is needed to pin it, and the test stays fast and non-flaky.
//

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"

// -setNeedsUpdateTabObjectCounts: is private to PseudoTerminal.m; declare it so
// the spy subclass below can override it (and the compiler can see it).
@interface PseudoTerminal (TabRenumberTesting)
- (void)setNeedsUpdateTabObjectCounts:(BOOL)needsUpdate;
@end

// Records whether a renumber was ever requested, without changing behavior.
@interface TabRenumberSpyTerminal : PseudoTerminal
@property (nonatomic) BOOL didRequestRenumber;
@end

@implementation TabRenumberSpyTerminal
- (void)setNeedsUpdateTabObjectCounts:(BOOL)needsUpdate {
    if (needsUpdate) {
        self.didRequestRenumber = YES;
    }
    [super setNeedsUpdateTabObjectCounts:needsUpdate];
}
@end

@interface PseudoTerminalTabRenumberTests : XCTestCase
@end

@implementation PseudoTerminalTabRenumberTests

- (TabRenumberSpyTerminal *)makeTerminal {
    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    return [[TabRenumberSpyTerminal alloc] initWithSmartLayout:NO
                                                    windowType:WINDOW_TYPE_NORMAL
                                               savedWindowType:WINDOW_TYPE_NORMAL
                                                    percentage:(iTermPercentage){0, 0}
                                                        screen:-1
                                                       profile:profile];
}

// Every reorder must renumber the tabs so the Cmd-N shortcuts stay consecutive
// by physical position. -tabsDidReorder is the choke point all reorder paths
// (drag, keyboard, Python API, and the group-membership context menu) funnel
// through, so it -- not each individual caller -- must request the renumber.
- (void)testTabsDidReorderRequestsRenumber {
    TabRenumberSpyTerminal *term = [self makeTerminal];
    XCTAssertNotNil(term, @"could not construct a terminal window for the test");

    term.didRequestRenumber = NO;
    [term tabsDidReorder];

    XCTAssertTrue(term.didRequestRenumber,
                  @"a reorder must renumber the tabs so Cmd-N shortcuts stay "
                  @"consecutive by position; -tabsDidReorder never requested it, "
                  @"so a remove-from-group reorder leaves the shortcuts stale");
}

@end
