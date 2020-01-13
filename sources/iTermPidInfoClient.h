//
//  iTermPidInfoClient.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/11/20.
//

#import <Foundation/Foundation.h>
#include <libproc.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermPidInfoClient : NSObject

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;

- (int)getPidInfoForProcessID:(int)pid
                       flavor:(int)flavor
                          arg:(uint64_t)arg
                       buffer:(void *)callerBuffer
                   buffersize:(int)bufferSize;

- (void)getMaximumNumberOfFileDescriptorsForProcess:(pid_t)pid
                                         completion:(void (^)(size_t count))completion;

- (void)getFileDescriptorsForProcess:(pid_t)pid
                               queue:(dispatch_queue_t)queue
                          completion:(void (^)(int count, struct proc_fdinfo *fds))completion;

- (void)getPortsInProcess:(pid_t)pid
                    queue:(dispatch_queue_t)queue
               completion:(void (^)(int count, struct proc_fileportinfo *fds))completion;

- (void)getWorkingDirectoryOfProcessWithID:(pid_t)pid
                                     queue:(dispatch_queue_t)queue
                                completion:(void (^)(NSString *rawDir))completion;

@end


NS_ASSUME_NONNULL_END
