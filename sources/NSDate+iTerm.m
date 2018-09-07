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
        [[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease];
    NSDateComponents *components =
        [calendar components:(NSCalendarUnitMonth | NSCalendarUnitDay) fromDate:[self date]];
    result = (components.month == 4 && components.day == 1);
    lastComputation = now;
  }
  return result;
}

+ (NSTimeInterval)it_timeSinceBoot {
    const int64_t elapsed = mach_absolute_time();
    static dispatch_once_t onceToken;
    static mach_timebase_info_data_t sTimebaseInfo;
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&sTimebaseInfo);
    });

    const double nanoseconds = elapsed * sTimebaseInfo.numer / sTimebaseInfo.denom;
    const double nanosPerSecond = 1000.0 * 1000.0 * 1000.0;
    return nanoseconds / nanosPerSecond;
}

@end
