//
//  MockCoprocess.h
//  iTerm2SharedARC
//
//  Mock implementation of Coprocess for testing TaskNotifier coprocess handling.
//  Subclass of Coprocess that uses pipes instead of spawning a subprocess.
//  Only compiled when ITERM_DEBUG is defined.
//

#import "Coprocess.h"

NS_ASSUME_NONNULL_BEGIN

/// Mock Coprocess subclass that uses pipes instead of a real subprocess.
/// Can be used anywhere a Coprocess is expected since it inherits from Coprocess.
/// NOTE: Only available when ITERM_DEBUG is defined at compile time.
@interface MockCoprocess : Coprocess

/// The external write FD - test code writes here to simulate coprocess output.
/// This is the write end of the read pipe (TaskNotifier reads from inputFd/readFileDescriptor).
@property (nonatomic, readonly) int testWriteFd;

/// The external read FD - test code reads here to see data written to coprocess.
/// This is the read end of the write pipe (TaskNotifier writes to outputFd/writeFileDescriptor).
@property (nonatomic, readonly) int testReadFd;

/// Create a MockCoprocess with pipe FDs.
/// Returns nil on failure (pipe creation failed).
+ (nullable MockCoprocess *)createPipeCoprocess;

/// Close the test FDs (call in addition to terminate to clean up test resources).
- (void)closeTestFds;

@end

NS_ASSUME_NONNULL_END
