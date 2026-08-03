//
//  iTermHTTPConnectionWriteContractTests.m
//  ModernTests
//
//  Regression test for the -writeAsynchronously:queue:completion: contract:
//  the completion must run exactly once even when the write cannot be submitted
//  because the stream is already gone. iTermWebSocketConnection relies on this
//  to release a pong-backpressure slot; a dropped completion would permanently
//  leak the slot and eventually wedge all frame processing on the connection.
//

#import <XCTest/XCTest.h>

#include <fcntl.h>
#include <unistd.h>

#import "iTermHTTPConnection.h"

@interface iTermHTTPConnectionWriteContractTests : XCTestCase
@end

@implementation iTermHTTPConnectionWriteContractTests

// After the stream has been closed the write cannot be submitted, but the
// completion must still fire (with an error) so callers awaiting it are not
// stuck forever.
- (void)testCompletionRunsAfterStreamClosed {
    int fd = open("/dev/null", O_WRONLY);
    XCTAssertGreaterThanOrEqual(fd, 0, @"sanity: opening /dev/null should succeed");

    // The connection takes ownership of fd and closes it when its stream is torn
    // down.
    iTermHTTPConnection *conn = [[iTermHTTPConnection alloc] initWithFileDescriptor:fd
                                                                     clientAddress:nil
                                                                              euid:nil];
    // Drop the stream, mimicking a teardown that races an in-flight write.
    [conn closeConnection];

    const char bytes[] = "x";
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
    dispatch_data_t data = dispatch_data_create(bytes, sizeof(bytes), queue,
                                                DISPATCH_DATA_DESTRUCTOR_DEFAULT);

    XCTestExpectation *fired = [self expectationWithDescription:@"completion fired"];
    __block int reportedError = 0;
    [conn writeAsynchronously:data
                        queue:queue
                   completion:^(bool done, dispatch_data_t _Nullable unwritten, int error) {
        reportedError = error;
        // Fulfilling twice would trip XCTest, which also guards "exactly once".
        [fired fulfill];
    }];

    // Generous timeout: we are proving the callback happens at all, not timing
    // how fast it happens, so a slow CI machine cannot make this flaky.
    [self waitForExpectationsWithTimeout:10 handler:nil];
    XCTAssertNotEqual(reportedError, 0,
                      @"a write that could not be submitted should report an error");
}

@end
