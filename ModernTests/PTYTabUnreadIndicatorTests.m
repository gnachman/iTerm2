#import <XCTest/XCTest.h>

#import "PTYSession.h"
#import "PTYTab.h"

@interface PTYTab (UnreadIndicatorTesting)
- (void)resetLabelAttributesIfAppropriate;
- (BOOL)isForegroundTab;
- (void)updateIcon;
@end

@interface UnreadIndicatorTestSession : PTYSession
@property(nonatomic) BOOL permitsNotification;
@property(nonatomic) NSUInteger notificationPolicyQueries;
@end

@implementation UnreadIndicatorTestSession
- (BOOL)shouldPostUserNotification {
    self.notificationPolicyQueries++;
    return self.permitsNotification;
}
@end

@interface UnreadIndicatorTestTab : PTYTab
@property(nonatomic, copy) NSArray<PTYSession *> *testSessions;
@property(nonatomic) BOOL selectedForTest;
@property(nonatomic) NSUInteger iconUpdates;
@end

@implementation UnreadIndicatorTestTab
- (NSArray<PTYSession *> *)sessions {
    return self.testSessions ?: @[];
}
- (BOOL)isForegroundTab {
    return self.selectedForTest;
}
- (void)updateIcon {
    // The reset and state transition are real; drawing needs a live window.
    self.iconUpdates++;
}
@end

@interface PTYTabUnreadIndicatorTests : XCTestCase
@property(nonatomic, strong) UnreadIndicatorTestSession *session;
@property(nonatomic, strong) UnreadIndicatorTestTab *tab;
@end

@implementation PTYTabUnreadIndicatorTests

- (void)setUp {
    [super setUp];
    self.session = [[UnreadIndicatorTestSession alloc] initSynthetic:NO];
    self.tab = [[UnreadIndicatorTestTab alloc] initWithRoot:[[NSSplitView alloc] initWithFrame:NSZeroRect]
                                                 sessions:nil];
    self.tab.testSessions = @[self.session];
    self.tab.selectedForTest = YES;
}

- (void)tearDown {
    self.tab = nil;
    self.session = nil;
    [super tearDown];
}

- (void)seedState:(PTYTabState)state {
    // Reproduce a previously displayed indicator without constructing a window.
    [self.tab setValue:@(state) forKey:@"state"];
    self.tab.iconUpdates = 0;
}

- (void)testSelectingAnIdleTabClearsItsUnreadIndicator {
    [self seedState:kPTYTabIdleState];
    self.session.havePostedIdleNotification = YES;
    self.session.havePostedNewOutputNotification = NO;
    // PseudoTerminal clears this flag before updating the selected tab's label.
    self.session.newOutput = NO;

    [self.tab resetLabelAttributesIfAppropriate];

    XCTAssertEqual(self.tab.state, (PTYTabState)0);
    XCTAssertEqual(self.tab.iconUpdates, 1u);
}

- (void)testClearedSessionFlagDoesNotLeaveANewOutputIndicator {
    [self seedState:kPTYTabNewOutputState];
    self.session.newOutput = NO;
    self.session.havePostedNewOutputNotification = NO;

    [self.tab resetLabelAttributesIfAppropriate];

    XCTAssertEqual(self.tab.state, (PTYTabState)0);
    XCTAssertEqual(self.tab.iconUpdates, 1u);
}

- (void)testUnviewedBackgroundIndicatorIsPreserved {
    [self seedState:kPTYTabIdleState];
    self.tab.selectedForTest = NO;
    self.session.permitsNotification = YES;

    [self.tab resetLabelAttributesIfAppropriate];

    XCTAssertEqual(self.tab.state, kPTYTabIdleState);
    XCTAssertEqual(self.tab.iconUpdates, 0u);
}

- (void)testBackgroundIndicatorIsPreservedWhenNotificationsAreDisabled {
    [self seedState:kPTYTabIdleState];
    self.tab.selectedForTest = NO;
    self.session.permitsNotification = NO;

    [self.tab resetLabelAttributesIfAppropriate];

    XCTAssertEqual(self.tab.state, kPTYTabIdleState);
    XCTAssertEqual(self.tab.iconUpdates, 0u);
}

- (void)testSelectionInAnInactiveWindowStillHonorsNotificationPolicy {
    [self seedState:kPTYTabIdleState];
    self.session.permitsNotification = YES;

    [self.tab resetLabelAttributesIfAppropriate];

    XCTAssertEqual(self.tab.state, kPTYTabIdleState);
    XCTAssertEqual(self.tab.iconUpdates, 0u);
}

- (void)testClearingUnreadStatePreservesTheBell {
    [self seedState:kPTYTabIdleState | kPTYTabBellState];

    [self.tab resetLabelAttributesIfAppropriate];

    XCTAssertEqual(self.tab.state, kPTYTabBellState);
    XCTAssertEqual(self.tab.iconUpdates, 1u);
}

- (void)testQuietTabWithoutUnreadStateKeepsTheFastPath {
    [self seedState:0];

    [self.tab resetLabelAttributesIfAppropriate];

    XCTAssertEqual(self.tab.state, (PTYTabState)0);
    XCTAssertEqual(self.session.notificationPolicyQueries, 0u);
    XCTAssertEqual(self.tab.iconUpdates, 0u);
}

@end
