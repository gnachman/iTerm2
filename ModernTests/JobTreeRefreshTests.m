//
//  JobTreeRefreshTests.m
//  ModernTests
//
//  Toolbelt > Jobs took its session's root pid and process info provider only when the toolbelt
//  was refreshed. A tmux pane on an SSH Integration host gets its provider later, when the
//  connection is framing or has recovered, so the tool kept reading a provider without the pane's
//  processes and stayed empty while the tab showed the pane's job. Each periodic refresh now asks
//  its host for them again. QA finding F-612.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "iTermJobTreeViewController.h"

// The job tree asks its provider only for a pid's process info.
@interface JobTreeRefreshFakeProvider : NSObject
@end

@implementation JobTreeRefreshFakeProvider
- (id)processInfoForPid:(pid_t)pid {
    return nil;
}
@end

@interface iTermJobTreeViewController (JobTreeRefreshTests)
- (void)periodicRefresh;
@end

@interface JobTreeRefreshTests : XCTestCase
@end

@implementation JobTreeRefreshTests

- (void)testEachPeriodicRefreshTakesTheCurrentPidAndProvider {
    id<ProcessInfoProvider> stale = (id<ProcessInfoProvider>)[[JobTreeRefreshFakeProvider alloc] init];
    id<ProcessInfoProvider> current = (id<ProcessInfoProvider>)[[JobTreeRefreshFakeProvider alloc] init];
    iTermJobTreeViewController *controller =
        [[iTermJobTreeViewController alloc] initWithProcessID:300 processInfoProvider:stale];
    __block int calls = 0;
    controller.willRefresh = ^(iTermJobTreeViewController *tree) {
        calls += 1;
        tree.pid = 301;
        tree.processInfoProvider = current;
    };
    [controller periodicRefresh];
    XCTAssertEqual(calls, 1);
    XCTAssertEqual((id)controller.processInfoProvider, (id)current);
    XCTAssertEqual(controller.pid, 301);
}

@end
