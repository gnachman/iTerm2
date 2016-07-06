//
//  iTermWindowOcclusionChangeMonitor.h
//  iTerm2
//
//  Created by George Nachman on 7/6/16.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermWindowOcclusionChangeMonitor : NSObject

// The time when windows' occlusion may have last changed. This depends on
// relevant window classes calling -invalidateCachedOcclusion when window order
// changes since that can't be observed.
@property(nonatomic, readonly) NSTimeInterval timeOfLastOcclusionChange;

+ (instancetype)sharedInstance;

// Resets the timeOfLastOcclusionChange to now.
- (void)invalidateCachedOcclusion;

@end
