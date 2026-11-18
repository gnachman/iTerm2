//
//  TmuxAttachPinsWindowSizesTests.m
//  ModernTests
//
//  On attach, iTerm2 sets the control client's size so new windows get the profile's size. With
//  per-window sizes (tmux 3.4+, and floats since 3.8), that size also applies to every existing window the client has
//  not sized yet, so sending it first shrank the windows being attached to. tmux clamps floating
//  panes into a shrunken window and they stay there when it grows back: a float at x=68 in a
//  157-column window came back at x=37 after a reattach. Recorded against tmux next-3.9:
//
//    refresh-client -C 80,25       -> %layout-change @0 ...80x25...  (float moved to +39)
//    refresh-client -C @0:157x40   -> %layout-change @0 ...157x40... (float stays at +39)
//
//  The client size must now wait until each window is pinned at its own size.
//  QA finding F-049.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGatewayTestFakes.h"
#import "VT100GridTypes.h"

@interface TmuxGateway (TmuxAttachPinsWindowSizesTests)
- (void)enableWrites;
@end

@interface TmuxController (TmuxAttachPinsWindowSizesTests)
- (void)openWindowsOfSize:(VT100GridSize)size;
- (void)openWindowsOfSize:(VT100GridSize)size growingSplitWindowsToClientSize:(BOOL)growSplitWindows;
- (void)initialListWindowsResponse:(NSString *)response;
@end

@interface TmuxAttachPinsWindowSizesTests : XCTestCase
@end

@implementation TmuxAttachPinsWindowSizesTests {
    TmuxFakeGatewayDelegate *_delegate;
    TmuxRecordingGateway *_gateway;
    TmuxController *_controller;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxFakeGatewayDelegate alloc] init];
    _gateway = [[TmuxRecordingGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    [_gateway enableWrites];
    _controller = [[TmuxController alloc] initWithGateway:_gateway
                                               clientName:@"attach-pins-window-sizes-test"
                                                  profile:@{}
                                             profileModel:nil];
}

- (void)tearDown {
    [[TmuxControllerRegistry sharedInstance] setController:nil forClient:_controller.clientName];
    _controller = nil;
    [super tearDown];
}

- (void)useVersion:(NSString *)version variableWindowSize:(BOOL)variable {
    _gateway.minimumServerVersion = [NSDecimalNumber decimalNumberWithString:version];
    // Normally set when the version is detected.
    [_controller setValue:@(variable) forKey:@"variableWindowSize"];
}

- (NSString *)written {
    return [_delegate.writtenStrings componentsJoinedByString:@""];
}

// One list-windows record in the -listWindowsDetailedFormat field order (tmux 3.2+). The last
// field, @iterm2_wg_parked, is empty: the window holds no parked workgroup peer.
- (NSString *)recordForWindow:(int)wid width:(int)width height:(int)height {
    NSString *layout = [NSString stringWithFormat:@"af3d,%dx%d,0,0,%d", width, height, wid];
    return [self recordForWindow:wid width:width height:height layout:layout];
}

// A window split into two side-by-side panes, %10 and %11.
- (NSString *)recordForSplitWindow:(int)wid width:(int)width height:(int)height {
    const int left = (width - 1) / 2;
    NSString *layout = [NSString stringWithFormat:@"af3d,%dx%d,0,0{%dx%d,0,0,10,%dx%d,%d,0,11}",
                        width, height, left, height, width - left - 1, height, left + 1];
    return [self recordForWindow:wid width:width height:height layout:layout];
}

- (NSString *)recordForWindow:(int)wid width:(int)width height:(int)height layout:(NSString *)layout {
    return [@[ @"s", [NSString stringWithFormat:@"@%d", wid], @"zsh",
               [@(width) stringValue], [@(height) stringValue],
               layout, @"*", @"1", layout, @"off", @"" ] componentsJoinedByString:@"\t"];
}

- (NSUInteger)locationOf:(NSString *)needle in:(NSString *)haystack {
    const NSRange range = [haystack rangeOfString:needle];
    XCTAssertNotEqual(range.location, NSNotFound, @"%@ not sent in %@", needle, haystack);
    return range.location;
}

- (void)testAttachDoesNotShrinkWindowsBeforePinningThem {
    [self useVersion:@"3.8" variableWindowSize:YES];

    [_controller openWindowsOfSize:VT100GridSizeMake(80, 25)];
    XCTAssertFalse([[self written] containsString:@"refresh-client -C 80,25"],
                   @"the provisional client size would shrink the existing windows: %@", [self written]);
    XCTAssertTrue([[self written] containsString:@"list-windows"], @"%@", [self written]);

    [_delegate.writtenStrings removeAllObjects];
    [_controller initialListWindowsResponse:[self recordForWindow:0 width:157 height:40]];
    NSString *written = [self written];
    const NSUInteger grow = [self locationOf:@"refresh-client -C 157,40" in:written];
    const NSUInteger pin = [self locationOf:@"refresh-client -C @0:157x40" in:written];
    const NSUInteger clientSize = [self locationOf:@"refresh-client -C 80,25" in:written];
    XCTAssertLessThan(grow, pin, @"%@", written);
    XCTAssertLessThan(pin, clientSize, @"the window must be pinned before the client size is set: %@", written);
}

// Pinning one window makes tmux size the others by the client size, so before any pin the client
// size becomes the largest window's, which only grows the smaller ones.
- (void)testWindowsOfDifferentSizesAreNeverShrunkBelowTheirOwnSize {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(80, 25)];
    [_delegate.writtenStrings removeAllObjects];

    NSString *response = [@[ [self recordForWindow:0 width:100 height:45],
                             [self recordForWindow:1 width:157 height:30] ] componentsJoinedByString:@"\n"];
    [_controller initialListWindowsResponse:response];
    NSString *written = [self written];
    const NSUInteger grow = [self locationOf:@"refresh-client -C 157,45" in:written];
    const NSUInteger pin0 = [self locationOf:@"refresh-client -C @0:100x45" in:written];
    const NSUInteger pin1 = [self locationOf:@"refresh-client -C @1:157x30" in:written];
    const NSUInteger clientSize = [self locationOf:@"refresh-client -C 80,25" in:written];
    XCTAssertLessThan(grow, pin0, @"%@", written);
    XCTAssertLessThan(grow, pin1, @"%@", written);
    XCTAssertLessThan(pin0, clientSize, @"%@", written);
    XCTAssertLessThan(pin1, clientSize, @"%@", written);
    XCTAssertEqual([written componentsSeparatedByString:@"refresh-client -C "].count, 5u,
                   @"no other size is sent: %@", written);
}

// tmux -CC new makes an 80x24 window because a control client has no size yet. Pinning it at its
// own size kept it there instead of the tmux profile's size (issue 13218). A window smaller than
// the client size grows to it, which never clamps a float.
- (void)testWindowSmallerThanTheClientSizeGrowsToIt {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(180, 40)];
    [_delegate.writtenStrings removeAllObjects];

    [_controller initialListWindowsResponse:[self recordForWindow:9 width:80 height:24]];
    NSString *written = [self written];
    const NSUInteger grow = [self locationOf:@"refresh-client -C 180,40" in:written];
    const NSUInteger pin = [self locationOf:@"refresh-client -C @9:180x40" in:written];
    XCTAssertLessThan(grow, pin, @"%@", written);
    XCTAssertFalse([written containsString:@"80x24"], @"the window must not be pinned at its old size: %@", written);
    XCTAssertFalse([written containsString:@"80,24"], @"%@", written);
}

// Each dimension is handled on its own: wider than the client keeps its width, shorter grows.
- (void)testWindowLargerInOneDimensionAndSmallerInTheOtherIsOnlyGrown {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(180, 40)];
    [_delegate.writtenStrings removeAllObjects];

    [_controller initialListWindowsResponse:[self recordForWindow:0 width:200 height:30]];
    NSString *written = [self written];
    const NSUInteger grow = [self locationOf:@"refresh-client -C 200,40" in:written];
    const NSUInteger pin = [self locationOf:@"refresh-client -C @0:200x40" in:written];
    const NSUInteger clientSize = [self locationOf:@"refresh-client -C 180,40" in:written];
    XCTAssertLessThan(grow, pin, @"%@", written);
    XCTAssertLessThan(pin, clientSize, @"%@", written);
}

// Notifications are off during attach, so the %layout-change for a window that grew is not seen.
// The initial listing is stale, so windows are listed again and opened from the new listing.
- (void)testGrowingAWindowListsWindowsAgain {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(180, 40)];
    [_delegate.writtenStrings removeAllObjects];

    [_controller initialListWindowsResponse:[self recordForWindow:9 width:80 height:24]];
    NSString *written = [self written];
    const NSUInteger pin = [self locationOf:@"refresh-client -C @9:180x40" in:written];
    const NSUInteger relist = [self locationOf:@"list-windows -F" in:written];
    XCTAssertLessThan(pin, relist, @"%@", written);

    // The second listing reflects the new size and is not pinned again.
    [_delegate.writtenStrings removeAllObjects];
    [_controller initialListWindowsResponse:[self recordForWindow:9 width:180 height:40]];
    written = [self written];
    XCTAssertFalse([written containsString:@"refresh-client -C"], @"%@", written);
    XCTAssertFalse([written containsString:@"list-windows -F"], @"%@", written);
}

// Windows already at least as large as the client size are opened from the first listing.
- (void)testNoWindowGrowsSoWindowsAreNotListedAgain {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(80, 25)];
    [_delegate.writtenStrings removeAllObjects];

    [_controller initialListWindowsResponse:[self recordForWindow:0 width:157 height:40]];
    XCTAssertFalse([[self written] containsString:@"list-windows -F"], @"%@", [self written]);
}

// With no windows to pin, only the deferred client size goes out.
- (void)testEmptyListingSendsOnlyTheClientSize {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(80, 25)];
    [_delegate.writtenStrings removeAllObjects];

    [_controller initialListWindowsResponse:@""];
    NSString *written = [self written];
    XCTAssertTrue([written containsString:@"refresh-client -C 80,25"], @"%@", written);
    XCTAssertEqual([written componentsSeparatedByString:@"refresh-client -C "].count, 2u, @"%@", written);
}

// Without per-window sizes there is nothing to pin, so the client size goes out with the initial
// commands as before.
- (void)testWithoutVariableWindowSizesTheClientSizeIsSentUpFront {
    [self useVersion:@"3.8" variableWindowSize:NO];
    [_controller openWindowsOfSize:VT100GridSizeMake(80, 25)];
    XCTAssertTrue([[self written] containsString:@"refresh-client -C 80,25"], @"%@", [self written]);

    [_delegate.writtenStrings removeAllObjects];
    [_controller initialListWindowsResponse:[self recordForWindow:0 width:157 height:40]];
    XCTAssertFalse([[self written] containsString:@"refresh-client -C"], @"%@", [self written]);
}

// Before tmux 3.8 there are no floating panes, so attach keeps the old behavior.
- (void)testTmux37SendsTheClientSizeUpFront {
    [self useVersion:@"3.7" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(80, 25)];
    XCTAssertTrue([[self written] containsString:@"refresh-client -C 80,25"], @"%@", [self written]);

    [_delegate.writtenStrings removeAllObjects];
    [_controller initialListWindowsResponse:[self recordForWindow:0 width:157 height:40]];
    XCTAssertFalse([[self written] containsString:@"refresh-client -C"], @"%@", [self written]);
}

- (void)testTmux34SendsTheClientSizeUpFront {
    [self useVersion:@"3.4" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(80, 25)];
    XCTAssertTrue([[self written] containsString:@"refresh-client -C 80,25"], @"%@", [self written]);

    [_delegate.writtenStrings removeAllObjects];
    [_controller initialListWindowsResponse:[self recordForWindow:0 width:157 height:40]];
    XCTAssertFalse([[self written] containsString:@"refresh-client -C"], @"%@", [self written]);
}

// Before tmux 3.4, refresh-client cannot size one window, so it keeps the old behavior.
- (void)testBeforeTmux34TheClientSizeIsSentUpFront {
    [self useVersion:@"3.3" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(80, 25)];
    XCTAssertTrue([[self written] containsString:@"refresh-client -C 80,25"], @"%@", [self written]);

    [_delegate.writtenStrings removeAllObjects];
    [_controller initialListWindowsResponse:[self recordForWindow:0 width:157 height:40]];
    XCTAssertFalse([[self written] containsString:@"refresh-client -C"], @"%@", [self written]);
}

// With tmux windows opening as tabs in the attaching window, the client size is measured from that
// window's frame. A tab with split panes needs a larger frame than one pane of the same size, so
// growing a split window to the client size widened the window by a few columns on every attach.
- (void)testSplitWindowIsNotGrownToTheSizeOfTheAttachingWindow {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(186, 50) growingSplitWindowsToClientSize:NO];
    [_delegate.writtenStrings removeAllObjects];

    [_controller initialListWindowsResponse:[self recordForSplitWindow:0 width:180 height:49]];
    NSString *written = [self written];
    const NSUInteger pin = [self locationOf:@"refresh-client -C @0:180x49" in:written];
    const NSUInteger clientSize = [self locationOf:@"refresh-client -C 186,50" in:written];
    XCTAssertLessThan(pin, clientSize, @"%@", written);
    XCTAssertFalse([written containsString:@"186x50"], @"the split window must not grow: %@", written);
    XCTAssertFalse([written containsString:@"list-windows -F"], @"%@", written);
}

// A window with one pane fits a tab of the attaching window exactly, so it still grows to the
// client size (issue 13218).
- (void)testWindowWithOnePaneGrowsToTheSizeOfTheAttachingWindow {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(186, 50) growingSplitWindowsToClientSize:NO];
    [_delegate.writtenStrings removeAllObjects];

    [_controller initialListWindowsResponse:[self recordForWindow:9 width:80 height:24]];
    NSString *written = [self written];
    [self locationOf:@"refresh-client -C @9:186x50" in:written];
    [self locationOf:@"list-windows -F" in:written];
}

// tmux 3.8 sends JSON layouts to a client that opted in to them. JSON always has a brace, so a
// window with one pane must not be taken for a split one.
- (void)testWindowWithOnePaneInAJSONLayoutGrowsToTheSizeOfTheAttachingWindow {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(186, 50) growingSplitWindowsToClientSize:NO];
    [_delegate.writtenStrings removeAllObjects];

    NSString *layout = @"{\"V\":2,\"L\":{\"t\":\"p\",\"w\":80,\"h\":24,\"x\":0,\"y\":0,\"a\":true,\"i\":0,\"I\":\"%9\"}}";
    [_controller initialListWindowsResponse:[self recordForWindow:9 width:80 height:24 layout:layout]];
    [self locationOf:@"refresh-client -C @9:186x50" in:[self written]];
}

// Floating panes don't change the frame a tab needs, so a window with one tiled pane and some
// floats grows too.
- (void)testWindowWithOneTiledPaneAndFloatsGrowsToTheSizeOfTheAttachingWindow {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(186, 50) growingSplitWindowsToClientSize:NO];
    [_delegate.writtenStrings removeAllObjects];

    NSString *layout = @"{\"V\":2,\"L\":{\"t\":\"h\",\"w\":80,\"h\":24,\"x\":0,\"y\":0,\"c\":[{\"t\":\"p\",\"w\":80,\"h\":24,\"x\":0,\"y\":0,\"i\":0,\"I\":\"%1\"},{\"t\":\"v\",\"w\":0,\"h\":0,\"x\":0,\"y\":0,\"c\":[{\"t\":\"p\",\"w\":20,\"h\":5,\"x\":3,\"y\":2,\"i\":1,\"z\":0,\"I\":\"%2\"}]}]}}";
    [_controller initialListWindowsResponse:[self recordForWindow:9 width:80 height:24 layout:layout]];
    [self locationOf:@"refresh-client -C @9:186x50" in:[self written]];
}

// A split JSON layout is still taken for a split window.
- (void)testSplitWindowInAJSONLayoutIsNotGrownToTheSizeOfTheAttachingWindow {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(186, 50) growingSplitWindowsToClientSize:NO];
    [_delegate.writtenStrings removeAllObjects];

    NSString *layout = @"{\"V\":2,\"L\":{\"t\":\"h\",\"w\":180,\"h\":49,\"x\":0,\"y\":0,\"c\":[{\"t\":\"p\",\"w\":90,\"h\":49,\"x\":0,\"y\":0,\"i\":0,\"I\":\"%1\"},{\"t\":\"p\",\"w\":89,\"h\":49,\"x\":91,\"y\":0,\"i\":1,\"I\":\"%2\"}]}}";
    [_controller initialListWindowsResponse:[self recordForWindow:0 width:180 height:49 layout:layout]];
    NSString *written = [self written];
    [self locationOf:@"refresh-client -C @0:180x49" in:written];
    XCTAssertFalse([written containsString:@"186x50"], @"%@", written);
}

// When windows open in windows of their own, split windows grow to the client size too.
- (void)testSplitWindowGrowsToTheClientSizeWhenItGetsItsOwnWindow {
    [self useVersion:@"3.8" variableWindowSize:YES];
    [_controller openWindowsOfSize:VT100GridSizeMake(186, 50) growingSplitWindowsToClientSize:YES];
    [_delegate.writtenStrings removeAllObjects];

    [_controller initialListWindowsResponse:[self recordForSplitWindow:0 width:180 height:49]];
    [self locationOf:@"refresh-client -C @0:186x50" in:[self written]];
}

@end
