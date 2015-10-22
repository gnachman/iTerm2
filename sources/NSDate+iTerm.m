//
//  NSDate+NSDate_iTerm.m
//  iTerm2
//
//  Created by George Nachman on 10/22/15.
//
//

#import "NSDate+iTerm.h"

@implementation NSDate (iTerm)

+ (BOOL)isAprilFools {
  static NSTimeInterval lastComputation;
  static BOOL result;
  NSTimeInterval now = [self timeIntervalSinceReferenceDate];
  if (now - lastComputation > 3600) {
    // Check no more than once an hour. This could be much more efficient, but doing anything with
    // time is fraught with bugs and peril, so we'll just keep it simple.
    NSCalendar *calendar =
        [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar] autorelease];
    NSDateComponents *components =
        [calendar components:(NSMonthCalendarUnit | NSDayCalendarUnit) fromDate:[self date]];
    result = (components.month == 4 && components.day == 1);
    lastComputation = now;
  }
  return result;
}

@end
