//
//  PTYTabMakeActiveRemovedTabTests.m
//  ModernTests
//
//  tmux can report that a window became current (%session-window-changed) just after iTerm2 took
//  its tab out of the window, as when closing a member of a tmux workgroup tears it down. Making
//  that tab active asked the tab view to select an item it no longer had, which raises
//  NSInternalInconsistencyException (“No such item with identifier”) and crashed iTerm2.
//  QA finding F-618.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "PTYSession.h"
#import "PTYSplitView.h"
#import "PTYTab.h"
#import "SessionView.h"

// Stands in for the tab's window controller, whose tab view no longer holds the tab.
@interface PTYTabMakeActiveFakeWindowController : NSObject
@property(nonatomic, strong) NSTabView *tabView;
@end

@implementation PTYTabMakeActiveFakeWindowController
@end

@interface PTYTabMakeActiveRemovedTabTests : XCTestCase
@end

@implementation PTYTabMakeActiveRemovedTabTests

- (PTYTab *)tabWithWindowController:(PTYTabMakeActiveFakeWindowController *)windowController {
    PTYSession *session = [[PTYSession alloc] initSynthetic:NO];
    session.view = [[SessionView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    PTYSplitView *root = [[PTYSplitView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    [root addSubview:session.view];
    NSMapTable<SessionView *, PTYSession *> *map = [NSMapTable strongToStrongObjectsMapTable];
    [map setObject:session forKey:session.view];
    PTYTab *tab = [[PTYTab alloc] initWithRoot:root sessions:map];
    session.delegate = tab;
    [tab setValue:windowController forKey:@"realParentWindow_"];
    return tab;
}

- (void)testMakingARemovedTabActiveDoesNothing {
    PTYTabMakeActiveFakeWindowController *windowController = [[PTYTabMakeActiveFakeWindowController alloc] init];
    windowController.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    NSTabViewItem *other = [[NSTabViewItem alloc] initWithIdentifier:@"other"];
    [windowController.tabView addTabViewItem:other];
    PTYTab *tab = [self tabWithWindowController:windowController];

    XCTAssertNoThrow([tab makeActive]);
    XCTAssertEqual(windowController.tabView.selectedTabViewItem, other);
    [tab setValue:nil forKey:@"realParentWindow_"];
}

// Control: a tab still in its tab view is selected.
- (void)testMakingATabActiveSelectsIt {
    PTYTabMakeActiveFakeWindowController *windowController = [[PTYTabMakeActiveFakeWindowController alloc] init];
    windowController.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
    [windowController.tabView addTabViewItem:[[NSTabViewItem alloc] initWithIdentifier:@"other"]];
    PTYTab *tab = [self tabWithWindowController:windowController];
    NSTabViewItem *mine = [[NSTabViewItem alloc] initWithIdentifier:tab];
    [windowController.tabView addTabViewItem:mine];

    [tab makeActive];
    XCTAssertEqual(windowController.tabView.selectedTabViewItem, mine);
    [tab setValue:nil forKey:@"realParentWindow_"];
}

@end
