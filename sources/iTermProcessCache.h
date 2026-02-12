//
//  iTermProcessCache.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import <Foundation/Foundation.h>

#import "iTerm2SharedARC-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@protocol ProcessInfoProvider;
@class iTermProcessCollection;

@interface iTermProcessCache : NSObject<ProcessInfoProvider>

+ (instancetype)sharedInstance;
+ (iTermProcessCollection *)newProcessCollection;

// Update which root PIDs are foreground (high priority).
// Foreground roots get fast incremental updates via process monitors.
// Background roots have their monitors suspended and rely on the 0.5s cadence.
- (void)setForegroundRootPIDs:(NSSet<NSNumber *> *)foregroundPIDs;

@end

NS_ASSUME_NONNULL_END
