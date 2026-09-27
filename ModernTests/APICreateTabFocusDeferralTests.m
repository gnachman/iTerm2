//
//  APICreateTabFocusDeferralTests.m
//  ModernTests
//
//  Covers the client-library-version gate that decides whether the CreateTab
//  focus-deferral workaround applies. The workaround exists only for iterm2
//  Python library versions < 2.23 (older versions lose the selection of a
//  freshly API-created window); 2.23+ carry the selection in ListSessionsResponse
//  and must not be gated on. See iTermAPICreateTabFocusDeferral for the full story.
//

#import <XCTest/XCTest.h>

#import "Api.pbobjc.h"
#import "iTermAPICreateTabFocusDeferral.h"

@interface APICreateTabFocusDeferralTests : XCTestCase
@end

@implementation APICreateTabFocusDeferralTests

- (void)testAffectedRangeIsGatedOn {
    // Only [2.21, 2.23) is affected: the guard shipped in 2.21, the fix in 2.23.
    XCTAssertTrue([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python 2.21"]);  // lower bound (inclusive)
    XCTAssertTrue([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python 2.22"]);
}

- (void)testPreGuardVersionsAreNotGatedOn {
    // 2.20 and earlier predate the re-entrancy guard, so they reconcile correctly
    // and must NOT be gated on. Numeric-aware ordering matters here: 2.9 and 2.10
    // are OLDER than 2.21 (a decimal/lexical compare would wrongly call them newer).
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python 2.20"]);
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python 2.10"]);
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python 2.9"]);
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python 1.5"]);
}

- (void)testFixedAndNewerVersionsAreNotGatedOn {
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python 2.23"]);  // fixed (exclusive)
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python 2.24"]);
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python 2.100"]);
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python 3.0"]);
}

- (void)testUnknownOrMalformedIsNotGatedOn {
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:nil]);   // in-process
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@""]);
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python"]);
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"2.22"]);  // no name
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python 2.22 extra"]);
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"ruby 2.22"]);
    XCTAssertFalse([iTermAPICreateTabFocusDeferral libraryVersionIsAffected:@"python two.two"]);
}

// Collects "kind:id->connGuid" strings delivered to the replay block, so tests
// can assert both the replayed values and that they targeted the right connection.
static NSArray<NSString *> *replayed(iTermAPICreateTabFocusDeferral *deferral,
                                     iTermAPICreateTabFocusDeferralToken *token,
                                     NSString *tabId,
                                     NSString *sessionId) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    [deferral endCreateTabWithToken:token
                      selectedTabId:tabId
                    activeSessionId:sessionId
                             replay:^(ITMFocusChangedNotification *n, NSString *connGuid) {
        if (n.selectedTab.length) {
            [out addObject:[NSString stringWithFormat:@"tab:%@->%@", n.selectedTab, connGuid]];
        }
        if (n.session.length) {
            [out addObject:[NSString stringWithFormat:@"session:%@->%@", n.session, connGuid]];
        }
    }];
    return out;
}

- (void)testUnaffectedClientNeverHoldsOrReplays {
    iTermAPICreateTabFocusDeferral *d = [[iTermAPICreateTabFocusDeferral alloc] init];
    iTermAPICreateTabFocusDeferralToken *token =
        [d beginCreateTabForConnectionGuid:@"connA" libraryVersion:@"python 2.23"];
    XCTAssertNil(token);
    XCTAssertFalse([d shouldHoldFocusNotificationForConnectionGuid:@"connA"]);
    XCTAssertEqualObjects(replayed(d, token, @"7", @"sess"), @[]);  // no-op
}

- (void)testSingleAffectedCreateHoldsOnlyItsOwnConnection {
    iTermAPICreateTabFocusDeferral *d = [[iTermAPICreateTabFocusDeferral alloc] init];
    iTermAPICreateTabFocusDeferralToken *token =
        [d beginCreateTabForConnectionGuid:@"connA" libraryVersion:@"python 2.22"];
    XCTAssertNotNil(token);
    // Held for the originating connection only...
    XCTAssertTrue([d shouldHoldFocusNotificationForConnectionGuid:@"connA"]);
    // ...never for any other connection, or an unknown one.
    XCTAssertFalse([d shouldHoldFocusNotificationForConnectionGuid:@"connB"]);
    XCTAssertFalse([d shouldHoldFocusNotificationForConnectionGuid:nil]);

    // Replay targets connA.
    XCTAssertEqualObjects(replayed(d, token, @"7", @"sessA"),
                          (@[@"tab:7->connA", @"session:sessA->connA"]));
    XCTAssertFalse([d shouldHoldFocusNotificationForConnectionGuid:@"connA"]);  // released
}

- (void)testBackgroundTabReplaysSessionButNotSelectedTab {
    iTermAPICreateTabFocusDeferral *d = [[iTermAPICreateTabFocusDeferral alloc] init];
    iTermAPICreateTabFocusDeferralToken *token =
        [d beginCreateTabForConnectionGuid:@"connA" libraryVersion:@"python 2.22"];
    // nil selectedTabId => the new tab did not become current.
    XCTAssertEqualObjects(replayed(d, token, nil, @"sessB"), (@[@"session:sessB->connA"]));
}

- (void)testConcurrentCreatesOnDistinctConnectionsAreIndependent {
    iTermAPICreateTabFocusDeferral *d = [[iTermAPICreateTabFocusDeferral alloc] init];
    iTermAPICreateTabFocusDeferralToken *a =
        [d beginCreateTabForConnectionGuid:@"connA" libraryVersion:@"python 2.22"];
    iTermAPICreateTabFocusDeferralToken *b =
        [d beginCreateTabForConnectionGuid:@"connB" libraryVersion:@"python 2.22"];
    XCTAssertTrue([d shouldHoldFocusNotificationForConnectionGuid:@"connA"]);
    XCTAssertTrue([d shouldHoldFocusNotificationForConnectionGuid:@"connB"]);

    // A ends: replays to connA and releases only connA; connB still held.
    XCTAssertEqualObjects(replayed(d, a, @"1", @"s1"),
                          (@[@"tab:1->connA", @"session:s1->connA"]));
    XCTAssertFalse([d shouldHoldFocusNotificationForConnectionGuid:@"connA"]);
    XCTAssertTrue([d shouldHoldFocusNotificationForConnectionGuid:@"connB"]);

    // B ends: replays to connB.
    XCTAssertEqualObjects(replayed(d, b, @"2", @"s2"),
                          (@[@"tab:2->connB", @"session:s2->connB"]));
    XCTAssertFalse([d shouldHoldFocusNotificationForConnectionGuid:@"connB"]);
}

- (void)testOverlappingCreatesOnSameConnectionBalanceViaCountedSet {
    iTermAPICreateTabFocusDeferral *d = [[iTermAPICreateTabFocusDeferral alloc] init];
    // One connection with two concurrent creates in flight (e.g. asyncio.gather).
    iTermAPICreateTabFocusDeferralToken *t1 =
        [d beginCreateTabForConnectionGuid:@"connA" libraryVersion:@"python 2.22"];
    iTermAPICreateTabFocusDeferralToken *t2 =
        [d beginCreateTabForConnectionGuid:@"connA" libraryVersion:@"python 2.22"];
    XCTAssertTrue([d shouldHoldFocusNotificationForConnectionGuid:@"connA"]);

    // First create ends: still held because the second is in flight, and it
    // replays its OWN ids to connA (not the second create's).
    XCTAssertEqualObjects(replayed(d, t1, @"1", @"s1"),
                          (@[@"tab:1->connA", @"session:s1->connA"]));
    XCTAssertTrue([d shouldHoldFocusNotificationForConnectionGuid:@"connA"]);

    // Second create ends: released.
    XCTAssertEqualObjects(replayed(d, t2, @"2", @"s2"),
                          (@[@"tab:2->connA", @"session:s2->connA"]));
    XCTAssertFalse([d shouldHoldFocusNotificationForConnectionGuid:@"connA"]);
}

@end
