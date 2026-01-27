//
//  MockTaskNotifierTask.m
//  iTerm2SharedARC
//
//  Test-only mock implementation of iTermTask protocol for testing TaskNotifier behavior.
//

#import "MockTaskNotifierTask.h"
#import <fcntl.h>
#import <unistd.h>

@implementation MockTaskNotifierTask {
    NSInteger _processReadCallCount;
    NSInteger _processWriteCallCount;
    NSInteger _brokenPipeCallCount;
    NSInteger _didRegisterCallCount;
    NSInteger _writeTaskCoprocessCallCount;
    NSData *_lastCoprocessData;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fd = -1;
        _pid = 0;
        _pidToWaitOn = 0;
        _hasCoprocess = NO;
        _coprocess = nil;
        _wantsRead = YES;
        _wantsWrite = NO;
        _writeBufferHasRoom = YES;
        _hasBrokenPipe = NO;
        _sshIntegrationActive = NO;
        _dispatchSourceEnabled = NO;
        _simulateLegacyTask = NO;
    }
    return self;
}

#pragma mark - iTermTask Required Methods

- (void)processRead {
    _processReadCallCount++;
}

- (void)processWrite {
    _processWriteCallCount++;
}

- (void)brokenPipe {
    _brokenPipeCallCount++;
}

- (void)writeTask:(NSData *)data coprocess:(BOOL)isCoprocess {
    if (isCoprocess) {
        _writeTaskCoprocessCallCount++;
        _lastCoprocessData = [data copy];
    }
}

- (void)didRegister {
    _didRegisterCallCount++;
}

#pragma mark - iTermTask Optional Methods

- (BOOL)useDispatchSource {
    return self.dispatchSourceEnabled;
}

#pragma mark - Override respondsToSelector for Legacy Simulation

- (BOOL)respondsToSelector:(SEL)aSelector {
    // If simulating a legacy task, pretend we don't implement useDispatchSource
    if (self.simulateLegacyTask && aSelector == @selector(useDispatchSource)) {
        return NO;
    }
    return [super respondsToSelector:aSelector];
}

#pragma mark - Call Count Accessors

- (NSInteger)processReadCallCount {
    return _processReadCallCount;
}

- (NSInteger)processWriteCallCount {
    return _processWriteCallCount;
}

- (NSInteger)brokenPipeCallCount {
    return _brokenPipeCallCount;
}

- (NSInteger)didRegisterCallCount {
    return _didRegisterCallCount;
}

- (NSInteger)writeTaskCoprocessCallCount {
    return _writeTaskCoprocessCallCount;
}

- (NSData *)lastCoprocessData {
    return _lastCoprocessData;
}

#pragma mark - Test Helpers

- (void)reset {
    _processReadCallCount = 0;
    _processWriteCallCount = 0;
    _brokenPipeCallCount = 0;
    _didRegisterCallCount = 0;
    _writeTaskCoprocessCallCount = 0;
    _lastCoprocessData = nil;
    _dispatchSourceEnabled = NO;
    _simulateLegacyTask = NO;
    _wantsRead = YES;
    _wantsWrite = NO;
    _hasCoprocess = NO;
    _hasBrokenPipe = NO;
}

- (BOOL)waitForProcessReadCalls:(NSInteger)count timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (_processReadCallCount < count && [[NSDate date] compare:deadline] == NSOrderedAscending) {
        [NSThread sleepForTimeInterval:0.01];
    }
    return _processReadCallCount >= count;
}

- (BOOL)waitForCoprocessWriteCalls:(NSInteger)count timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (_writeTaskCoprocessCallCount < count && [[NSDate date] compare:deadline] == NSOrderedAscending) {
        [NSThread sleepForTimeInterval:0.01];
    }
    return _writeTaskCoprocessCallCount >= count;
}

- (void)closeFd {
    if (self.fd >= 0) {
        close(self.fd);
        self.fd = -1;
    }
}

#pragma mark - Factory Methods

+ (MockTaskNotifierTask *)createPipeTaskWithWriteFd:(int *)writeFd {
    int fds[2];
    if (pipe(fds) != 0) {
        return nil;
    }

    // Set non-blocking on read end
    int flags = fcntl(fds[0], F_GETFL);
    fcntl(fds[0], F_SETFL, flags | O_NONBLOCK);

    MockTaskNotifierTask *task = [[MockTaskNotifierTask alloc] init];
    task.fd = fds[0];  // Read end

    if (writeFd) {
        *writeFd = fds[1];  // Write end
    } else {
        close(fds[1]);  // Close write end if not needed
    }

    return task;
}

@end
