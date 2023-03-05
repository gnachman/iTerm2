//
//  NSDate+NSDate_iTerm.h
//  iTerm2
//
//  Created by George Nachman on 10/22/15.
//
//

#import <Foundation/Foundation.h>

@interface NSDate (iTerm)

+ (BOOL)isAprilFools;
+ (NSTimeInterval)it_timeSinceBoot;
+ (NSDate *)it_dateWithTimeSinceBoot:(NSTimeInterval)t;
+ (NSTimeInterval)durationOfBlock:(void (^ NS_NOESCAPE)(void))block;
+ (NSTimeInterval)it_timeIntervalForAbsoluteTime:(uint64_t)time;

@end
