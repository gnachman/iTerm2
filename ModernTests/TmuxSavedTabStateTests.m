//
//  TmuxSavedTabStateTests.m
//  ModernTests
//
//  A tmux session's per-tab settings (such as custom tab titles) and tab groups are saved in its
//  @per_tab_settings and @tab_groups options. Bugs these tests cover:
//  - Each save of @per_tab_settings was built from open tabs only, so a hidden window lost its
//    custom title the next time anything was saved.
//  - Switching the client to another session wrote the old session's settings and groups into the
//    new session's options before they were read, so the new session's were lost.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "PTYTab.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGatewayTestFakes.h"

@interface TmuxController (SavedTabStateTesting)
- (void)getPerTabSettingsResponse:(NSString *)result;
- (void)getTabGroupsResponse:(NSString *)result;
@end

@interface TmuxGateway (SavedTabStateTesting)
- (void)enableWrites;
@end

// A tmux tab whose controller, window id, and per-tab setting are fixed by the test.
@interface TmuxSavedStateSpyTab : PTYTab
@property (nonatomic, strong) TmuxController *spyController;
@property (nonatomic) int spyWindow;
@property (nonatomic, copy) NSString *spyPerTabSetting;
@end

@implementation TmuxSavedStateSpyTab

- (BOOL)isTmuxTab {
    return self.spyController != nil;
}

- (TmuxController *)tmuxController {
    return self.spyController;
}

- (int)tmuxWindow {
    return self.spyWindow;
}

- (NSString *)tmuxPerTabSetting {
    return self.spyPerTabSetting;
}

@end

@interface TmuxSavedTabStateTests : XCTestCase
@end

@implementation TmuxSavedTabStateTests {
    TmuxFakeGatewayDelegate *_delegate;
    TmuxRecordingGateway *_gateway;
    TmuxController *_controller;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxFakeGatewayDelegate alloc] init];
    _gateway = [[TmuxRecordingGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    _gateway.acceptNotifications = YES;
    [_gateway enableWrites];
    _controller = [[TmuxController alloc] initWithGateway:_gateway
                                               clientName:@"saved-tab-state-test"
                                                  profile:@{}
                                             profileModel:nil];
}

- (void)tearDown {
    [[TmuxControllerRegistry sharedInstance] setController:nil forClient:_controller.clientName];
    _controller = nil;
    [super tearDown];
}

- (NSString *)written {
    return [_delegate.writtenStrings componentsJoinedByString:@""];
}

- (TmuxSavedStateSpyTab *)tabForWindow:(int)window setting:(NSString *)setting {
    TmuxSavedStateSpyTab *tab = [[TmuxSavedStateSpyTab alloc] init];
    tab.spyController = _controller;
    tab.spyWindow = window;
    tab.spyPerTabSetting = setting;
    return tab;
}

// The @tab_groups value for one group holding window 3.
static NSString *const kOldSessionGroups = @"{\"groups\":{\"G\":{\"collapsed\":false,\"name\":\"Old\"}},\"tabs\":{\"3\":\"G\"}}";

#pragma mark - Per-tab settings merge

// Window 3 is hidden, so it has no tab, but its saved title must survive.
- (void)testWindowWithoutTabKeepsItsSetting {
    [_controller getPerTabSettingsResponse:@"3:t=YQ=="];
    NSArray *tabs = @[ [self tabForWindow:1 setting:@"t=Yg=="] ];
    XCTAssertEqualObjects([_controller perTabSettingsForTabs:tabs], @"1:t=Yg==;3:t=YQ==");
}

// An open tab is authoritative: removing its title removes the saved one.
- (void)testOpenTabWithoutSettingRemovesSavedSetting {
    [_controller getPerTabSettingsResponse:@"1:t=YQ==;3:t=Yg=="];
    NSArray *tabs = @[ [self tabForWindow:1 setting:nil] ];
    XCTAssertEqualObjects([_controller perTabSettingsForTabs:tabs], @"3:t=Yg==");
}

- (void)testClosedWindowForgetsItsSetting {
    [_controller getPerTabSettingsResponse:@"1:t=YQ==;3:t=Yg=="];
    [_controller tmuxWindowDidClose:3];
    XCTAssertEqualObjects([_controller perTabSettingsForTabs:@[]], @"1:t=YQ==");
}

#pragma mark - Saving before load

// Until the session's settings have been read, a save would overwrite them.
- (void)testPerTabSettingsNotSavedBeforeLoad {
    [_controller savePerTabSettings];
    XCTAssertFalse([self.written containsString:@"@per_tab_settings"]);

    [_controller getPerTabSettingsResponse:@""];
    [_controller savePerTabSettings];
    XCTAssertTrue([self.written containsString:@"@per_tab_settings"]);
}

#pragma mark - Session switch

- (void)testSessionSwitchDoesNotWriteOldPerTabSettingsIntoNewSession {
    [_controller sessionChangedTo:@"old" sessionId:1];
    [_controller getPerTabSettingsResponse:@"3:t=YQ=="];

    [_controller sessionChangedTo:@"new" sessionId:2];
    [_delegate.writtenStrings removeAllObjects];
    [_controller savePerTabSettings];
    XCTAssertFalse([self.written containsString:@"@per_tab_settings"],
                   @"nothing may be saved before the new session's settings are read");

    [_controller getPerTabSettingsResponse:@"5:t=Yw=="];
    XCTAssertEqualObjects([_controller perTabSettingsForTabs:@[]], @"5:t=Yw==",
                          @"the old session's settings must not leak into the new one");
}

- (void)testSessionSwitchDoesNotWriteOldTabGroupsIntoNewSession {
    [_controller sessionChangedTo:@"old" sessionId:1];
    [_controller getTabGroupsResponse:kOldSessionGroups];
    // As after the initial attach to the old session.
    [_controller setValue:@YES forKey:@"_haveOpenedInitialWindows"];

    [_controller sessionChangedTo:@"new" sessionId:2];
    [_delegate.writtenStrings removeAllObjects];
    [_controller saveTabGroups];
    XCTAssertFalse([self.written containsString:@"@tab_groups"],
                   @"nothing may be saved before the new session's groups are read");

    [_controller getTabGroupsResponse:@""];
    [_controller saveTabGroups];
    // An empty value (just the encoding prefix) means the old session's groups did not leak.
    XCTAssertTrue([self.written containsString:@"set -t $2 @tab_groups \"g_\""], @"%@", self.written);
}

@end
