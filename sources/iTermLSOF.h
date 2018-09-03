//
//  iTermLSOF.h
//  iTerm2
//
//  Created by George Nachman on 11/8/16.
//
//

#import <Foundation/Foundation.h>

@class iTermSocketAddress;

int iTermProcPidInfoWrapper(int pid, int flavor, uint64_t arg,  void *buffer, int buffersize);

@interface iTermLSOF : NSObject

+ (pid_t)processIDWithConnectionFromAddress:(iTermSocketAddress *)socketAddress;
+ (NSString *)commandForProcess:(pid_t)pid execName:(NSString **)execName;
+ (NSArray<NSNumber *> *)allPids;
+ (pid_t)ppidForPid:(pid_t)childPid;
+ (NSString *)nameOfProcessWithPid:(pid_t)thePid isForeground:(BOOL *)isForeground;
+ (NSString *)workingDirectoryOfProcess:(pid_t)pid;
+ (void)asyncWorkingDirectoryOfProcess:(pid_t)pid block:(void (^)(NSString *pwd))block;
+ (pid_t)pidOfFirstChildOf:(pid_t)parentPid;

@end
