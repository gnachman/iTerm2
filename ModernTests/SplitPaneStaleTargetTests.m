//
//  SplitPaneStaleTargetTests.m
//  ModernTests
//
//  Splitting a pane is asynchronous: -asyncSplitVertically:... captures the target session, looks up
//  the current directory, and only then splits. If the target left the window meanwhile (closed,
//  moved to another window), the split fell back to the current tab and PTYTab asserted that the
//  target's view was in its split tree (assert([[parentSplit subviews] count] != 0)). A split whose
//  target is not in this window must fail cleanly instead.
//

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"
#import "iTermSessionFactory.h"

// Declared in PseudoTerminal.m.
@interface PseudoTerminal (SplitTesting)
- (PTYSession *)splitVertically:(BOOL)isVertical
                         before:(BOOL)before
                        profile:(Profile *)theBookmark
                  targetSession:(PTYSession *)targetSession
                         oldCWD:(NSString *)oldCWD
                    parentScope:(iTermVariableScope *)parentScope
                     completion:(void (^)(PTYSession *, BOOL))completion;
@end

// Creates sessions as usual but never launches a process.
@interface SplitSpySessionFactory : iTermSessionFactory
@property (nonatomic) NSInteger sessionsCreated;
@property (nonatomic) NSInteger launches;
@end

@implementation SplitSpySessionFactory
- (PTYSession *)newSessionWithProfile:(Profile *)profile parent:(PTYSession *)parent {
    self.sessionsCreated += 1;
    return [super newSessionWithProfile:profile parent:parent];
}
- (void)attachOrLaunchWithRequest:(iTermSessionAttachOrLaunchRequest *)request {
    self.launches += 1;
}
@end

@interface SplitSpyTerminal : PseudoTerminal
@property (nonatomic, strong) SplitSpySessionFactory *spyFactory;
@end

@implementation SplitSpyTerminal
- (iTermSessionFactory *)sessionFactory {
    return self.spyFactory;
}
@end

@interface SplitPaneStaleTargetTests : XCTestCase
@end

@implementation SplitPaneStaleTargetTests {
    SplitSpyTerminal *_term;
    Profile *_profile;
}

- (void)setUp {
    [super setUp];
    _profile = [[ProfileModel sharedInstance] defaultBookmark];
    _term = [[SplitSpyTerminal alloc] initWithSmartLayout:NO
                                               windowType:WINDOW_TYPE_NORMAL
                                          savedWindowType:WINDOW_TYPE_NORMAL
                                               percentage:(iTermPercentage){0, 0}
                                                   screen:-1
                                                  profile:_profile];
    _term.spyFactory = [[SplitSpySessionFactory alloc] init];
    [_term.window setFrame:NSMakeRect(0, 0, 1200, 900) display:NO];
    PTYSession *first = [_term.spyFactory newSessionWithProfile:_profile parent:nil];
    [_term addSessionInNewTab:first];
    _term.spyFactory.sessionsCreated = 0;
}

- (void)tearDown {
    [_term.window close];
    _term = nil;
    [super tearDown];
}

- (void)testPrecondition {
    XCTAssertNotNil(_term.currentTab);
}

- (void)testSplitWithTargetNotInWindowFailsCleanly {
    // A session that isn't in this window, like one closed while the split looked up the cwd.
    PTYSession *stranger = [_term.spyFactory newSessionWithProfile:_profile parent:nil];
    _term.spyFactory.sessionsCreated = 0;
    __block BOOL completionCalled = NO;
    __block BOOL completionOK = YES;
    PTYSession *result = [_term splitVertically:YES
                                         before:NO
                                        profile:_profile
                                  targetSession:stranger
                                         oldCWD:nil
                                    parentScope:nil
                                     completion:^(PTYSession *session, BOOL ok) {
        completionCalled = YES;
        completionOK = ok;
    }];
    XCTAssertNil(result);
    XCTAssertEqual(_term.spyFactory.sessionsCreated, 0);
    XCTAssertEqual(_term.spyFactory.launches, 0);
    XCTAssertTrue(completionCalled);
    XCTAssertFalse(completionOK);
    XCTAssertEqual(_term.currentTab.sessions.count, 1);
}

// A session that moved to another window has a tab, just not in this window.
- (void)testSplitWithTargetInAnotherWindowFailsCleanly {
    SplitSpyTerminal *other = [[SplitSpyTerminal alloc] initWithSmartLayout:NO
                                                                  windowType:WINDOW_TYPE_NORMAL
                                                             savedWindowType:WINDOW_TYPE_NORMAL
                                                                  percentage:(iTermPercentage){0, 0}
                                                                      screen:-1
                                                                     profile:_profile];
    other.spyFactory = [[SplitSpySessionFactory alloc] init];
    [other.window setFrame:NSMakeRect(0, 0, 1200, 900) display:NO];
    PTYSession *elsewhere = [other.spyFactory newSessionWithProfile:_profile parent:nil];
    [other addSessionInNewTab:elsewhere];

    PTYSession *result = [_term splitVertically:YES
                                         before:NO
                                        profile:_profile
                                  targetSession:elsewhere
                                         oldCWD:nil
                                    parentScope:nil
                                     completion:nil];
    XCTAssertNil(result);
    XCTAssertEqual(_term.spyFactory.sessionsCreated, 0);
    XCTAssertEqual(_term.currentTab.sessions.count, 1);
    XCTAssertEqual(other.currentTab.sessions.count, 1);
    [other.window close];
}

// The normal case still splits.
- (void)testSplitWithTargetInWindowSplits {
    PTYSession *target = _term.currentTab.activeSession;
    PTYSession *result = [_term splitVertically:YES
                                         before:NO
                                        profile:_profile
                                  targetSession:target
                                         oldCWD:nil
                                    parentScope:nil
                                     completion:nil];
    XCTAssertNotNil(result);
    XCTAssertEqual(_term.currentTab.sessions.count, 2);
    XCTAssertEqual(_term.spyFactory.launches, 1);
}

- (void)testSplitWithNilTargetFailsCleanly {
    PTYSession *result = [_term splitVertically:YES
                                         before:NO
                                        profile:_profile
                                  targetSession:nil
                                         oldCWD:nil
                                    parentScope:nil
                                     completion:nil];
    XCTAssertNil(result);
    XCTAssertEqual(_term.spyFactory.sessionsCreated, 0);
    XCTAssertEqual(_term.currentTab.sessions.count, 1);
}

@end
