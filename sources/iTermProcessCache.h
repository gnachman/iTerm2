//
//  iTermProcessCache.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import <Foundation/Foundation.h>
#import "iTermProcessCollection.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermProcessCache : NSObject

+ (instancetype)sharedInstance;

- (iTermProcessInfo *)processInfoForPid:(pid_t)pid;
- (void)setNeedsUpdate:(BOOL)needsUpdate;
- (iTermProcessInfo *)deepestForegroundJobForPid:(pid_t)pid;
- (void)registerTrackedPID:(pid_t)pid;
- (void)unregisterTrackedPID:(pid_t)pid;


@end

NS_ASSUME_NONNULL_END
