//
//  iTermFileDescriptorMultiClientChild.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/15/20.
//

#import <Foundation/Foundation.h>

#import "iTermMultiServerProtocol.h"
#import "iTermResult.h"
#import "iTermThreadSafety.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermFileDescriptorMultiClientChild : NSObject
// Immutable properties. Can be accessed on any thread.
@property (atomic, readonly) pid_t pid;
@property (atomic, readonly) NSString *executablePath;
@property (atomic, readonly) NSArray<NSString *> *args;
@property (atomic, readonly) NSDictionary<NSString *, NSString *> *environment;
@property (atomic, readonly) BOOL utf8;
@property (atomic, readonly) NSString *initialDirectory;
@property (atomic, readonly) int fd;
@property (atomic, readonly) NSString *tty;

// Mutable properties. Must only be accessed on the child's thread.
@property (nonatomic, readonly) BOOL hasTerminated;
@property (nonatomic, readonly) BOOL haveWaited;  // only for non-preemptive waits
@property (nonatomic, readonly) BOOL haveSentPreemptiveWait;
@property (nonatomic) int terminationStatus;  // only defined if haveWaited is YES

- (instancetype)initWithReport:(iTermMultiServerReportChild *)report
                        thread:(iTermThread *)thread NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)addWaitCallback:(iTermCallback<id, iTermResult<NSNumber *> *> *)callback;
- (void)invokeAllWaitCallbacks:(iTermResult<NSNumber *> *)status;

// Must be called on child's thread.
- (void)willWaitPreemptively;

// Must be called on child's thread.
- (void)didTerminate;

@end

NS_ASSUME_NONNULL_END
