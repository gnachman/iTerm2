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

// One list-windows record in the -listWindowsDetailedFormat field order (tmux 2.4+).
- (NSString *)recordForWindow:(int)wid width:(int)width height:(int)height {
    NSString *layout = [NSString stringWithFormat:@"af3d,%dx%d,0,0,%d", width, height, wid];
    return [@[ @"s", [NSString stringWithFormat:@"@%d", wid], @"zsh",
               [@(width) stringValue], [@(height) stringValue],
               layout, @"*", @"1", layout, @"off" ] componentsJoinedByString:@"\t"];
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

@end
