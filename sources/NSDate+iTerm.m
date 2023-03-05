//
//  NSDate+NSDate_iTerm.m
//  iTerm2
//
//  Created by George Nachman on 10/22/15.
//
//

#import "NSDate+iTerm.h"
#include <mach/mach_time.h>

@implementation NSDate (iTerm)

+ (BOOL)isAprilFools {
  static NSTimeInterval lastComputation;
  static BOOL result;
  NSTimeInterval now = [self timeIntervalSinceReferenceDate];
  if (now - lastComputation > 3600) {
    // Check no more than once an hour. This could be much more efficient, but doing anything with
    // time is fraught with bugs and peril, so we'll just keep it simple.
    NSCalendar *calendar =
        [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *components =
        [calendar components:(NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:[self date]];
    result = (components.month == 4 && components.day == 1);
    lastComputation = now;
  }
  return result;
}

+ (NSTimeInterval)it_timeSinceBoot {
    return [self it_timeIntervalForAbsoluteTime:mach_absolute_time()];
}

+ (NSTimeInterval)it_timeIntervalForAbsoluteTime:(uint64_t)elapsed {
    static dispatch_once_t onceToken;
    static mach_timebase_info_data_t sTimebaseInfo;
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&sTimebaseInfo);
    });

    const double nanoseconds = elapsed * sTimebaseInfo.numer / sTimebaseInfo.denom;
    const double nanosPerSecond = 1000.0 * 1000.0 * 1000.0;
    return nanoseconds / nanosPerSecond;
}

+ (NSDate *)it_dateWithTimeSinceBoot:(NSTimeInterval)t {
    const NSTimeInterval now = [self it_timeSinceBoot];
    const NSTimeInterval delta = now - t;
    return [NSDate dateWithTimeIntervalSinceNow:-delta];
}

+ (NSTimeInterval)durationOfBlock:(void (^ NS_NOESCAPE)(void))block {
    const uint64_t start = mach_absolute_time();
    block();
    const uint64_t end = mach_absolute_time();
    if (end < start) {
        return 0;
    } else {
        return [self machTimeDeltaToSeconds:end - start];
    }
}

+ (NSTimeInterval)machTimeDeltaToSeconds:(uint64_t)elapsed {
    static mach_timebase_info_data_t sTimebaseInfo;
    if (sTimebaseInfo.denom == 0) {
        mach_timebase_info(&sTimebaseInfo);
    }

    double nanoseconds = elapsed * sTimebaseInfo.numer / sTimebaseInfo.denom;
    return nanoseconds / 1000000000.0;
}

@end
