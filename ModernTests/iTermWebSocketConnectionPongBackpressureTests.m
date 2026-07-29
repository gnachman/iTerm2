//
//  iTermWebSocketConnectionPongBackpressureTests.m
//  ModernTests
//
//  Regression test for pong backpressure: a peer that floods ping frames but
//  never reads the resulting pongs must not be able to wedge the connection.
//  An earlier version blocked the connection's work queue waiting for outbound
//  room; because teardown also runs on that queue, a non-draining peer made the
//  connection un-abortable and pinned an fd plus a worker thread. The connection
//  must instead tear itself down once outstanding pongs exceed the cap.
//

#import <XCTest/XCTest.h>

#include <fcntl.h>
#include <unistd.h>

#import "iTermHTTPConnection.h"
#import "iTermWebSocketConnection.h"

// A stand-in HTTP connection that hands the reader a fixed blob of frames once
// and then models a peer that never drains: writes are accepted but their
// completion never fires (exactly what dispatch_io does while the socket send
// buffer stays full), so no pong ever flushes.
@interface iTermPongBackpressureFakeConnection : iTermHTTPConnection
@end

@implementation iTermPongBackpressureFakeConnection {
    NSMutableData *_frames;
    BOOL _delivered;
    dispatch_semaphore_t _readGate;  // Unblocks the reader once the stream closes.
}

- (instancetype)initWithFrames:(NSData *)frames {
    // /dev/null keeps super's stream setup inert; all I/O is overridden below.
    int fd = open("/dev/null", O_WRONLY);
    self = [super initWithFileDescriptor:fd clientAddress:nil euid:nil];
    if (self) {
        _frames = [frames mutableCopy];
        _readGate = dispatch_semaphore_create(0);
    }
    return self;
}

- (NSMutableData *)readSynchronously {
    if (!_delivered) {
        _delivered = YES;
        return _frames;
    }
    // Block like a real blocking read until the connection is torn down, then
    // report EOF so the reader loop exits.
    dispatch_semaphore_wait(_readGate, DISPATCH_TIME_FOREVER);
    return nil;
}

- (BOOL)sendResponseWithCode:(int)code reason:(NSString *)reason headers:(NSDictionary *)headers {
    return YES;  // Pretend the 101 upgrade response was written.
}

- (void)writeAsynchronously:(dispatch_data_t)data
                      queue:(dispatch_queue_t)queue
                 completion:(void (^)(bool done, dispatch_data_t _Nullable data, int error))completion {
    // Never invoke completion: the peer is not reading, so this write never
    // flushes.
}

- (void)closeConnection {
    [super closeConnection];
    dispatch_semaphore_signal(_readGate);
}

@end

@interface iTermPongBackpressureDelegate : NSObject <iTermWebSocketConnectionDelegate>
@property (nonatomic, copy) void (^onTerminate)(void);
@end

@implementation iTermPongBackpressureDelegate
- (void)webSocketConnectionDidTerminate:(iTermWebSocketConnection *)webSocketConnection {
    if (self.onTerminate) {
        self.onTerminate();
    }
}
- (void)webSocketConnection:(iTermWebSocketConnection *)webSocketConnection didReadFrame:(iTermWebSocketFrame *)frame {
}
@end

@interface iTermWebSocketConnectionPongBackpressureTests : XCTestCase
@end

@implementation iTermWebSocketConnectionPongBackpressureTests

// Feed more ping frames than the outstanding-pong cap through a peer that never
// drains pongs, and assert the connection still terminates. If pong
// backpressure blocked the work queue, teardown (which runs on that queue) would
// never happen and this would time out.
- (void)testPongFloodFromNonDrainingPeerStillTearsDown {
    // Each frame: FIN + ping opcode, masked, zero-length payload, 4 mask bytes.
    const uint8_t ping[] = { 0x89, 0x80, 0x00, 0x00, 0x00, 0x00 };
    const int pingCount = 300;  // Comfortably over the 256 outstanding-pong cap.
    NSMutableData *frames = [NSMutableData data];
    for (int i = 0; i < pingCount; i++) {
        [frames appendBytes:ping length:sizeof(ping)];
    }

    iTermPongBackpressureFakeConnection *fake =
        [[iTermPongBackpressureFakeConnection alloc] initWithFrames:frames];

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"ws://localhost/"]];
    request.HTTPMethod = @"GET";
    request.allHTTPHeaderFields = @{
        @"host": @"localhost",
        @"origin": @"ws://localhost/",
        @"upgrade": @"websocket",
        @"connection": @"Upgrade",
        @"sec-websocket-protocol": @"api.iterm2.com",
        @"sec-websocket-version": @"13",
        @"sec-websocket-key": @"dGhlIHNhbXBsZSBub25jZQ==",
        @"x-iterm2-library-version": @"python 0.24",
    };

    NSString *reason = nil;
    iTermWebSocketConnection *conn =
        [iTermWebSocketConnection newWebSocketConnectionForRequest:request
                                                       connection:fake
                                                           reason:&reason];
    XCTAssertNotNil(conn, @"sanity: upgrade should succeed (reason=%@)", reason);

    // delegate and delegateQueue are weak on the connection; keep strong local
    // references alive for the duration of the test.
    iTermPongBackpressureDelegate *delegate = [[iTermPongBackpressureDelegate alloc] init];
    dispatch_queue_t delegateQueue = dispatch_queue_create("test.ws.delegate", NULL);

    XCTestExpectation *terminated = [self expectationWithDescription:@"connection terminated"];
    __block BOOL fulfilled = NO;
    delegate.onTerminate = ^{
        if (!fulfilled) {
            fulfilled = YES;
            [terminated fulfill];
        }
    };
    conn.delegate = delegate;
    conn.delegateQueue = delegateQueue;

    [conn handleRequest:request completion:^{}];

    // Generous timeout: we are proving teardown happens at all, not timing it.
    [self waitForExpectationsWithTimeout:10 handler:nil];

    // Keep everything alive until the wait resolves.
    (void)delegate;
    (void)delegateQueue;
    (void)conn;
    (void)fake;
}

@end
