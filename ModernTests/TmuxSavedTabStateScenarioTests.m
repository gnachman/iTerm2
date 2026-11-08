//
//  TmuxSavedTabStateScenarioTests.m
//  ModernTests
//
//  User-level scenarios for the custom tab titles and tab groups a tmux session saves in its
//  @per_tab_settings and @tab_groups options. Each test plays out what a user does and checks what
//  ends up saved on the tmux server, which is what the next attach restores.
//
//  The controller talks to a recording gateway instead of a tmux server. Its tabs are supplied by
//  the test, and tmux's replies are delivered by calling the controller's response handlers.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "NSStringITerm.h"
#import "PTYTab.h"
#import "TmuxController.h"
#import "TmuxControllerRegistry.h"
#import "TmuxGatewayTestFakes.h"

@interface TmuxController (SavedTabStateScenarioTesting)
- (void)getPerTabSettingsResponse:(NSString *)result;
- (void)getTabGroupsResponse:(NSString *)result;
- (NSArray<PTYTab *> *)allTabs;
@end

@interface TmuxGateway (SavedTabStateScenarioTesting)
- (void)enableWrites;
@end

#pragma mark - Fakes

// A tmux tab with a custom title and tab group set by the test.
@interface TmuxScenarioTab : PTYTab
@property (nonatomic, weak) TmuxController *scenarioController;
@property (nonatomic) int scenarioWindow;
@property (nonatomic, copy) NSString *customTitle;
@end

@implementation TmuxScenarioTab

- (BOOL)isTmuxTab {
    return YES;
}

- (TmuxController *)tmuxController {
    return self.scenarioController;
}

- (int)tmuxWindow {
    return self.scenarioWindow;
}

- (NSString *)tmuxPerTabSetting {
    if (!self.customTitle) {
        return nil;
    }
    return [NSString stringWithFormat:@"t=%@", [self.customTitle base64EncodedWithEncoding:NSUTF8StringEncoding]];
}

@end

// A controller whose open tabs are the test's instead of those in the app's windows.
@interface TmuxScenarioController : TmuxController
@property (nonatomic, readonly) NSMutableArray<TmuxScenarioTab *> *openTabs;
@end

@implementation TmuxScenarioController

- (instancetype)initWithGateway:(TmuxGateway *)gateway {
    self = [super initWithGateway:gateway clientName:@"saved-tab-state-scenario" profile:@{} profileModel:nil];
    if (self) {
        _openTabs = [NSMutableArray array];
    }
    return self;
}

- (NSArray<PTYTab *> *)allTabs {
    return self.openTabs;
}

@end

#pragma mark - Tests

@interface TmuxSavedTabStateScenarioTests : XCTestCase
@end

@implementation TmuxSavedTabStateScenarioTests {
    TmuxFakeGatewayDelegate *_delegate;
    TmuxRecordingGateway *_gateway;
    TmuxScenarioController *_controller;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxFakeGatewayDelegate alloc] init];
    _gateway = [[TmuxRecordingGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    _gateway.acceptNotifications = YES;
    [_gateway enableWrites];
    _controller = [[TmuxScenarioController alloc] initWithGateway:_gateway];
}

- (void)tearDown {
    [[TmuxControllerRegistry sharedInstance] setController:nil forClient:_controller.clientName];
    _controller = nil;
    [super tearDown];
}

#pragma mark - Hidden windows keep their custom titles

// You rename window @3's tab to “logs”, hide @3, then do something else that saves. Showing @3
// again, or reattaching, restores “logs”.
- (void)testHiddenWindowKeepsTitleSetDuringThisAttach {
    [self attachToSession:1 savedTitles:@{} savedGroups:@{}];
    [self openTabForWindow:1];
    TmuxScenarioTab *logs = [self openTabForWindow:3];

    [self renameTab:logs to:@"logs"];
    [self hideWindowOfTab:logs];
    [self openTabForWindow:7];
    [self doSomethingThatSaves];

    XCTAssertEqualObjects([self savedTitlesForSession:1], (@{ @3: @"logs" }));
    XCTAssertEqualObjects([self titleWindowWouldOpenWith:3], @"logs");
}

// The title was saved by an earlier attach.
- (void)testHiddenWindowKeepsTitleFromEarlierAttach {
    [self attachToSession:1 savedTitles:@{ @3: @"logs" } savedGroups:@{}];
    [self openTabForWindow:1];
    [self doSomethingThatSaves];

    XCTAssertEqualObjects([self savedTitlesForSession:1], (@{ @3: @"logs" }));
}

// Control: an open tab still decides its own window's title.
- (void)testRemovingTitleFromOpenTabRemovesSavedTitle {
    [self attachToSession:1 savedTitles:@{ @3: @"logs" } savedGroups:@{}];
    TmuxScenarioTab *logs = [self openTabForWindow:3];
    logs.customTitle = @"logs";

    [self renameTab:logs to:nil];

    XCTAssertEqualObjects([self savedTitlesForSession:1], (@{}));
}

#pragma mark - Switching sessions keeps the new session's titles

// You're in session A and switch the client to session B, whose @1 is titled “build”. Saves
// during the switch must not touch B's titles, and B's @1 opens as “build”.
- (void)testSwitchingSessionsKeepsNewSessionsTitles {
    [self attachToSession:1 savedTitles:@{ @1: @"A one" } savedGroups:@{}];
    [self openTabForWindow:1].customTitle = @"A one";

    [self switchClientToSession:2];
    XCTAssertNil([self savedTitlesForSession:2], @"nothing may be saved before B's titles are read");

    [self tmuxDeliversSavedTitles:@{ @1: @"build" } savedGroups:@{}];
    XCTAssertEqualObjects([self titleWindowWouldOpenWith:1], @"build");
    [self doSomethingThatSaves];
    XCTAssertEqualObjects([self savedTitlesForSession:2], (@{ @1: @"build" }));
}

#pragma mark - Switching sessions keeps the new session's tab groups

// Session A has @3 in group “Old”. Session B has @1 and @2 in group “Mine”. After switching, B's
// windows are in B's groups and A's group never reaches B.
- (void)testSwitchingSessionsKeepsNewSessionsGroups {
    [self attachToSession:1 savedTitles:@{} savedGroups:@{ @3: @"Old" }];
    [self putTab:[self openTabForWindow:3] inGroup:@"Old"];

    [self switchClientToSession:2];
    XCTAssertNil([self savedGroupsForSession:2], @"nothing may be saved before B's groups are read");

    [self tmuxDeliversSavedTitles:@{} savedGroups:@{ @1: @"Mine", @2: @"Mine" }];
    [self doSomethingThatSaves];
    XCTAssertEqualObjects([self savedGroupsForSession:2], (@{ @1: @"Mine", @2: @"Mine" }));
}

#pragma mark - Closed windows' titles are cleaned up

// @3 closes in tmux while its tab is still going away. Its title is forgotten and the lingering
// tab can't bring it back.
- (void)testClosedWindowsTitleIsForgotten {
    [self attachToSession:1 savedTitles:@{ @1: @"main", @3: @"logs" } savedGroups:@{}];
    [self openTabForWindow:1].customTitle = @"main";
    [self openTabForWindow:3].customTitle = @"logs";

    [self tmuxReportsWindowClosed:3];
    XCTAssertEqualObjects([self savedTitlesForSession:1], (@{ @1: @"main" }));

    [self doSomethingThatSaves];
    XCTAssertEqualObjects([self savedTitlesForSession:1], (@{ @1: @"main" }));
}

// `move-window` takes @3 to another session and back. It keeps its ID, so once it's back in this
// session its tab's title changes must be saved again.
- (void)testWindowMovedAwayAndBackSavesNewTitle {
    [self attachToSession:1 savedTitles:@{} savedGroups:@{}];
    TmuxScenarioTab *tab = [self openTabForWindow:3];

    [self tmuxReportsWindowClosed:3];
    [_controller.openTabs removeObject:tab];
    [self tmuxReportsWindowAdded:3];
    TmuxScenarioTab *reopened = [self openTabForWindow:3];
    [self renameTab:reopened to:@"logs"];

    XCTAssertEqualObjects([self savedTitlesForSession:1], (@{ @3: @"logs" }));
}

// Same for its tab group.
- (void)testWindowMovedAwayAndBackSavesNewGroup {
    [self attachToSession:1 savedTitles:@{} savedGroups:@{}];
    TmuxScenarioTab *tab = [self openTabForWindow:3];

    [self tmuxReportsWindowClosed:3];
    [_controller.openTabs removeObject:tab];
    [self tmuxReportsWindowAdded:3];
    [self putTab:[self openTabForWindow:3] inGroup:@"Mine"];
    [self doSomethingThatSaves];

    XCTAssertEqualObjects([self savedGroupsForSession:1], (@{ @3: @"Mine" }));
}

#pragma mark - Actions

- (void)attachToSession:(int)sessionID
            savedTitles:(NSDictionary<NSNumber *, NSString *> *)titles
            savedGroups:(NSDictionary<NSNumber *, NSString *> *)groups {
    [_controller sessionChangedTo:[NSString stringWithFormat:@"session%d", sessionID] sessionId:sessionID];
    [self tmuxDeliversSavedTitles:titles savedGroups:groups];
    // As once the initial windows have opened and had their groups restored.
    [_controller setValue:@YES forKey:@"_haveOpenedInitialWindows"];
}

// tmux's replies to the show-options commands sent on attach.
- (void)tmuxDeliversSavedTitles:(NSDictionary<NSNumber *, NSString *> *)titles
                    savedGroups:(NSDictionary<NSNumber *, NSString *> *)groups {
    [_controller getPerTabSettingsResponse:[self perTabSettingsWithTitles:titles]];
    [_controller getTabGroupsResponse:[self tabGroupsOptionWithGroups:groups]];
}

- (void)switchClientToSession:(int)sessionID {
    // The old session's tabs close as the controller tears them down.
    [_controller.openTabs removeAllObjects];
    [_controller sessionChangedTo:[NSString stringWithFormat:@"session%d", sessionID] sessionId:sessionID];
    // Saves queued while the old tabs closed run before the new session's options arrive.
    [self doSomethingThatSaves];
}

- (TmuxScenarioTab *)openTabForWindow:(int)window {
    TmuxScenarioTab *tab = [[TmuxScenarioTab alloc] init];
    tab.scenarioController = _controller;
    tab.scenarioWindow = window;
    [_controller.openTabs addObject:tab];
    return tab;
}

- (void)renameTab:(TmuxScenarioTab *)tab to:(NSString *)title {
    tab.customTitle = title;
    [_controller savePerTabSettings];
}

// Each group's ID is its name.
- (void)putTab:(TmuxScenarioTab *)tab inGroup:(NSString *)name {
    tab.tabGroupID = name;
    tab.tabGroupName = name;
}

// A hidden window has no tab.
- (void)hideWindowOfTab:(TmuxScenarioTab *)tab {
    [_controller.openTabs removeObject:tab];
    [_controller saveAffinities];
}

// Opening a window, resizing, and many other actions save everything.
- (void)doSomethingThatSaves {
    [_controller saveAffinities];
}

- (void)tmuxReportsWindowClosed:(int)window {
    [_controller tmuxWindowDidClose:window];
}

- (void)tmuxReportsWindowAdded:(int)window {
    [_controller tmuxWindowDidAdd:window];
}

#pragma mark - Observations

// The custom title a tab opened for `window` would get.
- (NSString *)titleWindowWouldOpenWith:(int)window {
    return [self titleFromSetting:[_controller perTabSettingsForTabWithWindowID:window]];
}

// Window ID -> custom title, as last saved in the session's @per_tab_settings, or nil if never saved.
- (NSDictionary<NSNumber *, NSString *> *)savedTitlesForSession:(int)sessionID {
    NSString *value = [self lastSavedValueOfOption:@"@per_tab_settings" session:sessionID];
    if (!value) {
        return nil;
    }
    NSMutableDictionary<NSNumber *, NSString *> *titles = [NSMutableDictionary dictionary];
    for (NSString *entry in [value componentsSeparatedByString:@";"]) {
        NSRange colon = [entry rangeOfString:@":"];
        if (colon.location == NSNotFound) {
            continue;
        }
        titles[@([entry substringToIndex:colon.location].intValue)] =
            [self titleFromSetting:[entry substringFromIndex:NSMaxRange(colon)]];
    }
    return titles;
}

// Window ID -> group name, as last saved in the session's @tab_groups, or nil if never saved.
- (NSDictionary<NSNumber *, NSString *> *)savedGroupsForSession:(int)sessionID {
    NSString *value = [self lastSavedValueOfOption:@"@tab_groups" session:sessionID];
    if (!value) {
        return nil;
    }
    if (value.length == 0) {
        return @{};
    }
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding]
                                                         options:0
                                                           error:nil];
    NSMutableDictionary<NSNumber *, NSString *> *groups = [NSMutableDictionary dictionary];
    [root[@"tabs"] enumerateKeysAndObjectsUsingBlock:^(NSString *windowID, NSString *groupID, BOOL *stop) {
        groups[@(windowID.intValue)] = root[@"groups"][groupID][@"name"];
    }];
    return groups;
}

#pragma mark - Encoding

- (NSString *)perTabSettingsWithTitles:(NSDictionary<NSNumber *, NSString *> *)titles {
    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    [titles enumerateKeysAndObjectsUsingBlock:^(NSNumber *window, NSString *title, BOOL *stop) {
        [entries addObject:[NSString stringWithFormat:@"%@:t=%@", window,
                            [title base64EncodedWithEncoding:NSUTF8StringEncoding]]];
    }];
    return [entries componentsJoinedByString:@";"];
}

// Window ID -> group name. Each group's ID is its name.
- (NSString *)tabGroupsOptionWithGroups:(NSDictionary<NSNumber *, NSString *> *)groups {
    if (groups.count == 0) {
        return @"";
    }
    NSMutableDictionary *definitions = [NSMutableDictionary dictionary];
    NSMutableDictionary *tabs = [NSMutableDictionary dictionary];
    [groups enumerateKeysAndObjectsUsingBlock:^(NSNumber *window, NSString *name, BOOL *stop) {
        definitions[name] = @{ @"collapsed": @NO, @"name": name };
        tabs[window.stringValue] = name;
    }];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"groups": definitions, @"tabs": tabs }
                                                   options:0
                                                     error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *)titleFromSetting:(NSString *)setting {
    if (![setting hasPrefix:@"t="]) {
        return nil;
    }
    NSData *data = [[NSData alloc] initWithBase64EncodedString:[setting substringFromIndex:2] options:0];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

// The decoded value of the last `set -t $<session> <option> "..."` sent to tmux.
- (NSString *)lastSavedValueOfOption:(NSString *)option session:(int)sessionID {
    NSString *written = [_delegate.writtenStrings componentsJoinedByString:@""];
    NSString *needle = [NSString stringWithFormat:@"set -t $%d %@ \"", sessionID, option];
    NSRange range = [written rangeOfString:needle options:NSBackwardsSearch];
    if (range.location == NSNotFound) {
        return nil;
    }
    NSString *rest = [written substringFromIndex:NSMaxRange(range)];
    NSString *encoded = [rest substringToIndex:[rest rangeOfString:@"\""].location];
    // Two-character encoding prefix, then hex.
    return [[NSString alloc] initWithData:[[encoded substringFromIndex:2] dataFromHexValues]
                                 encoding:NSUTF8StringEncoding];
}

@end
