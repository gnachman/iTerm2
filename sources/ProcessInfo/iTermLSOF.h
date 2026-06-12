//
//  iTermLSOF.h
//  iTerm2
//
//  Created by George Nachman on 11/8/16.
//
//

#import <Foundation/Foundation.h>

@class iTermSocketAddress;
@protocol iTermProcessDataSource;

int iTermProcPidInfoWrapper(int pid, int flavor, uint64_t arg,  void *buffer, int buffersize);

// One open file descriptor of a process.
@interface iTermProcessFileDescriptor : NSObject
// The file descriptor number.
@property (nonatomic) int fd;
// A short human-readable kind: "file", "TCP", "UDP", "unix", "pipe", "kqueue", etc.
@property (nonatomic, copy) NSString *type;
// For files: the path. For network sockets: "local → remote (STATE)". For unix
// sockets: the socket path. Empty when there is nothing useful to show.
@property (nonatomic, copy) NSString *detail;
@end

@interface iTermLSOF : NSObject

+ (NSArray<NSString *> *)commandLineArgumentsForProcess:(pid_t)pid execName:(NSString **)execName;
+ (NSString *)commandForProcess:(pid_t)pid execName:(NSString **)execName;
// The process's environment as an array of "KEY=VALUE" strings, or nil if it
// could not be read (e.g. the process is owned by another user). Extracted from
// the same KERN_PROCARGS2 buffer as the command line.
+ (NSArray<NSString *> *)environmentForProcess:(pid_t)pid;
// The process's open file descriptors (files, sockets, pipes, etc.), or nil if
// they could not be read (e.g. the process is owned by another user).
+ (NSArray<iTermProcessFileDescriptor *> *)fileDescriptorsForProcess:(pid_t)pid;
+ (NSString *)displayCommandForProcess:(pid_t)pid execName:(NSString **)execName;
+ (NSArray<NSNumber *> *)allPids;
+ (pid_t)ppidForPid:(pid_t)childPid;
+ (NSString *)nameOfProcessWithPid:(pid_t)thePid isForeground:(BOOL *)isForeground;
+ (NSString *)workingDirectoryOfProcess:(pid_t)pid;
+ (void)asyncWorkingDirectoryOfProcess:(pid_t)pid
                                 queue:(dispatch_queue_t)queue
                                 block:(void (^)(NSString *pwd))block;
+ (pid_t)pidOfFirstChildOf:(pid_t)parentPid;
+ (NSDate *)startTimeForProcess:(pid_t)pid;
+ (id<iTermProcessDataSource>)processDataSource;

@end
