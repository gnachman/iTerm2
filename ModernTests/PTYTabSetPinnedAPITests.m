//
//  PTYTabSetPinnedAPITests.m
//  ModernTests
//
//  The Python API pins a tab by invoking the tab-scoped method
//  iterm2.set_pinned(pinned:). These tests call it through the tab's method
//  registry with iTermCallMethodOnObject, the dispatch the API server uses, with a real PseudoTerminal
//  as the tab's delegate so the request runs the same code as the Pin Tab menu
//  item (-[PseudoTerminal _setPinned:forTab:]).
//

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"
#import "SessionView.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "iTermObject.h"

@interface PTYTabSetPinnedAPITests : XCTestCase
@end

@implementation PTYTabSetPinnedAPITests {
    PseudoTerminal *_term;
    NSMutableArray<TmuxController *> *_tmuxControllers;
}

- (void)setUp {
    [super setUp];
    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    _term = [[PseudoTerminal alloc] initWithSmartLayout:NO
                                             windowType:WINDOW_TYPE_NORMAL
                                        savedWindowType:WINDOW_TYPE_NORMAL
                                             percentage:(iTermPercentage){0, 0}
                                                 screen:-1
                                                profile:profile];
    _tmuxControllers = [NSMutableArray array];
}

- (void)tearDown {
    // -[TmuxController initWithGateway:...] registers the controller with the
    // shared registry; remove it so it does not leak into other tests.
    for (TmuxController *controller in _tmuxControllers) {
        [[TmuxControllerRegistry sharedInstance] setController:nil forClient:controller.clientName];
    }
    _tmuxControllers = nil;
    _term = nil;
    [super tearDown];
}

- (PTYTab *)makeTab {
    PTYSession *session = [[PTYSession alloc] initSynthetic:NO];
    session.view = [[SessionView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    PTYTab *tab = [[PTYTab alloc] initWithSession:session parentWindow:nil];
    tab.delegate = _term;
    return tab;
}

- (PTYTab *)makeTmuxTab {
    PTYTab *tab = [self makeTab];
    TmuxController *controller = [[TmuxController alloc] initWithGateway:nil
                                                              clientName:@"test"
                                                                 profile:@{}
                                                            profileModel:nil];
    [_tmuxControllers addObject:controller];
    [tab setValue:controller forKey:@"tmuxController_"];
    XCTAssertTrue(tab.isTmuxTab, @"test setup: the tab must take the tmux branch");
    return tab;
}

// Invokes iterm2.set_pinned on the tab and returns the error it completed with.
- (NSError *)invokeSetPinned:(BOOL)pinned onTab:(PTYTab *)tab {
    __block BOOL called = NO;
    __block NSError *result = nil;
    // PTYTab adopts iTermObject in a class extension, so it is not visible here.
    id<iTermObject> object = (id<iTermObject>)tab;
    iTermCallMethodOnObject(object, @"iterm2.set_pinned", @{ @"pinned": @(pinned) }, ^(id value, NSError *error) {
        called = YES;
        result = error;
    });
    XCTAssertTrue(called, @"set_pinned must complete synchronously");
    return result;
}

- (void)testSetPinnedPinsAndUnpins {
    PTYTab *tab = [self makeTab];
    XCTAssertFalse(tab.isPinned);

    XCTAssertNil([self invokeSetPinned:YES onTab:tab]);
    XCTAssertTrue(tab.isPinned);

    XCTAssertNil([self invokeSetPinned:NO onTab:tab]);
    XCTAssertFalse(tab.isPinned);
}

- (void)testSetPinnedIsIdempotent {
    PTYTab *tab = [self makeTab];
    XCTAssertNil([self invokeSetPinned:YES onTab:tab]);
    XCTAssertNil([self invokeSetPinned:YES onTab:tab]);
    XCTAssertTrue(tab.isPinned, @"pinning an already-pinned tab must leave it pinned, not toggle it");
}

// The Pin Tab menu item is not offered for tmux tabs; the API must refuse too.
- (void)testSetPinnedRefusesTmuxTab {
    PTYTab *tab = [self makeTmuxTab];
    NSError *error = [self invokeSetPinned:YES onTab:tab];
    XCTAssertNotNil(error, @"pinning a tmux tab must fail");
    XCTAssertFalse(tab.isPinned);
}

// A tab whose window is gone must say so, not claim to be a tmux tab.
- (void)testSetPinnedWithoutWindowReportsIt {
    PTYTab *tab = [self makeTab];
    tab.delegate = nil;
    NSError *error = [self invokeSetPinned:YES onTab:tab];
    XCTAssertNotNil(error);
    XCTAssertFalse([error.localizedDescription containsString:@"tmux"], @"got: %@", error.localizedDescription);
    XCTAssertFalse(tab.isPinned);
}

@end
