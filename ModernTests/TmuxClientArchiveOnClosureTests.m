//
//  TmuxClientArchiveOnClosureTests.m
//  ModernTests
//
//  With Archive On Closure on, closing a tmux integration pane wrote an archive anyway. -terminate
//  clears the session's tmux mode before -hardStop decides whether to archive, so the check that a
//  tmux client isn't archived never saw one. The archive could not be restored, so it only piled
//  up. QA findings F-104 and F-335.
//

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "PTYSession.h"
#import "ProfileModel.h"
#import "SessionView.h"
#import "TaskNotifier.h"

@interface TmuxClientArchiveOnClosureTests : XCTestCase
@end

@implementation TmuxClientArchiveOnClosureTests {
    NSString *_archiveDirectory;
}

- (void)setUp {
    [super setUp];
    _archiveDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_archiveDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_archiveDirectory error:nil];
    [super tearDown];
}

- (PTYSession *)archivingSession {
    PTYSession *session = [[PTYSession alloc] initSynthetic:NO];
    session.view = [[SessionView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    NSMutableDictionary *profile = [[[ProfileModel sharedInstance] defaultBookmark] mutableCopy];
    profile[KEY_ARCHIVE] = @YES;
    profile[KEY_ARCHIVEDIR] = _archiveDirectory;
    [session setProfile:profile];
    return session;
}

- (NSArray<NSString *> *)archives {
    return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_archiveDirectory error:nil] ?: @[];
}

- (void)testClosingATmuxClientWritesNoArchive {
    PTYSession *session = [self archivingSession];
    [session setTmuxPane:1];
    XCTAssertTrue(session.isTmuxClient);
    id<iTermTask> task = (id<iTermTask>)session.shell;

    [session terminate];

    if (task) {
        [[TaskNotifier sharedInstance] deregisterTask:task];
    }
    XCTAssertEqualObjects([self archives], @[]);
}

// The setup above does archive a session that isn't a tmux client.
- (void)testANonTmuxSessionIsArchived {
    PTYSession *session = [self archivingSession];
    XCTAssertFalse(session.isTmuxClient);
    // -hardStop releases the view to balance a retain that -terminate takes. This calls it
    // without -terminate, so take that retain here or the view is over-released.
    CFBridgingRetain(session.view);
    [session hardStop];
    XCTAssertEqual([self archives].count, 1u);
}

@end
