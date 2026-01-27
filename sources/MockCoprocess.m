//
//  MockCoprocess.m
//  iTerm2SharedARC
//
//  Mock implementation of Coprocess for testing TaskNotifier coprocess handling.
//  Subclass of Coprocess that uses pipes instead of spawning a subprocess.
//

#import "MockCoprocess.h"
#import <fcntl.h>
#import <unistd.h>

@implementation MockCoprocess {
    int _testWriteFd;  // External: test code writes here to simulate coprocess output
    int _testReadFd;   // External: test code reads here to see writes to coprocess
}

+ (MockCoprocess *)createPipeCoprocess {
    // Create two pipes:
    // 1. readPipe: coprocess output -> main process reads
    //    readPipe[0] = inputFd (TaskNotifier reads here via readFileDescriptor)
    //    readPipe[1] = testWriteFd (test code writes here to simulate coprocess output)
    //
    // 2. writePipe: main process writes -> coprocess input
    //    writePipe[0] = testReadFd (test code reads here to see writes)
    //    writePipe[1] = outputFd (TaskNotifier writes here via writeFileDescriptor)

    int readPipe[2];
    int writePipe[2];

    if (pipe(readPipe) != 0) {
        return nil;
    }

    if (pipe(writePipe) != 0) {
        close(readPipe[0]);
        close(readPipe[1]);
        return nil;
    }

    // Set non-blocking on the read end (inputFd - where TaskNotifier reads)
    int flags = fcntl(readPipe[0], F_GETFL);
    fcntl(readPipe[0], F_SETFL, flags | O_NONBLOCK);

    // Set non-blocking on the write end (outputFd - where TaskNotifier writes)
    flags = fcntl(writePipe[1], F_GETFL);
    fcntl(writePipe[1], F_SETFL, flags | O_NONBLOCK);

    MockCoprocess *coprocess = [[MockCoprocess alloc] init];
    if (!coprocess) {
        close(readPipe[0]);
        close(readPipe[1]);
        close(writePipe[0]);
        close(writePipe[1]);
        return nil;
    }

    // Set up the Coprocess FDs (inherited properties)
    coprocess.inputFd = readPipe[0];     // TaskNotifier reads here (readFileDescriptor)
    coprocess.outputFd = writePipe[1];   // TaskNotifier writes here (writeFileDescriptor)
    coprocess.pid = getpid();            // Use current process PID (no real child)

    // Set up the test FDs
    coprocess->_testWriteFd = readPipe[1];  // Test writes here to simulate coprocess output
    coprocess->_testReadFd = writePipe[0];  // Test reads here to verify writes to coprocess

    return coprocess;
}

- (void)dealloc {
    [self closeTestFds];
}

#pragma mark - Properties

- (int)testWriteFd {
    return _testWriteFd;
}

- (int)testReadFd {
    return _testReadFd;
}

#pragma mark - Test Helpers

- (void)closeTestFds {
    if (_testWriteFd >= 0) {
        close(_testWriteFd);
        _testWriteFd = -1;
    }
    if (_testReadFd >= 0) {
        close(_testReadFd);
        _testReadFd = -1;
    }
}

@end
