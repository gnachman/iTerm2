//
//  TmuxDashboardParkedWindowTests.m
//  ModernTests
//
//  A window holding a parked tmux workgroup peer is not a hidden window: it is not offered to be
//  opened, and killing it ends the workgroup. The tmux Dashboard listed such windows with the
//  hidden ones, where Open in Tabs did nothing and “–” killed them. QA finding F-655.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "NSData+iTerm.h"
#import "TmuxDashboardController.h"
#import "TSVParser.h"

@interface TmuxDashboardParkedWindowTests : XCTestCase
@end

@implementation TmuxDashboardParkedWindowTests

// TmuxWorkgroupState.ParkedTag(instanceID:).encoded, which ModernTests can't call from here.
- (NSString *)parkedTagForInstance:(NSString *)instanceID {
    NSString *json = [NSString stringWithFormat:@"{\"i\":\"%@\",\"v\":1}", instanceID];
    NSString *tag = [@"p_" stringByAppendingString:[[json dataUsingEncoding:NSUTF8StringEncoding] it_hexEncoded]];
    // The same check the app makes.
    Class attacher = NSClassFromString(@"iTermTmuxWorkgroupAttacher");
    XCTAssertNotNil(attacher);
    SEL selector = NSSelectorFromString(@"isParkedWindowTag:");
    BOOL (*isParked)(id, SEL, NSString *) = (BOOL (*)(id, SEL, NSString *))[attacher methodForSelector:selector];
    XCTAssertTrue(isParked(attacher, selector, tag), @"%@ must decode as a parked tag", tag);
    return tag;
}

// A record in TmuxController's listWindowsDetailedFormat on tmux 3.2 and later.
- (NSString *)recordForWindow:(int)window name:(NSString *)name parked:(NSString *)parked {
    NSString *layout = [NSString stringWithFormat:@"af3d,80x24,0,0,%d", window];
    return [@[ @"s", [NSString stringWithFormat:@"@%d", window], name, @"80", @"24",
               layout, @"", @"0", layout, @"off", parked ] componentsJoinedByString:@"\t"];
}

- (void)testParkedWindowsAreNotListed {
    NSArray<NSString *> *fields = @[ @"session_name", @"window_id", @"window_name", @"window_width",
                                     @"window_height", @"window_layout", @"window_flags",
                                     @"window_active", @"window_visible_layout",
                                     @"pane_border_status", @"iterm2_wg_parked" ];
    NSString *response = [@[ [self recordForWindow:1 name:@"plain" parked:@""],
                             [self recordForWindow:2 name:@"peer" parked:[self parkedTagForInstance:@"I"]],
                             [self recordForWindow:3 name:@"other" parked:@""] ] componentsJoinedByString:@"\n"];
    TSVDocument *doc = [response tsvDocumentWithFields:fields workAroundTabBug:NO];
    XCTAssertNotNil(doc);
    NSArray *windows = [TmuxDashboardController dashboardWindowsFromDocument:doc];
    NSArray *expected = @[ @[ @"plain", @"1" ], @[ @"other", @"3" ] ];
    XCTAssertEqualObjects(windows, expected);
}

@end
