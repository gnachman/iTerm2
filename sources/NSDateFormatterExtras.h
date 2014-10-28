// This code copied from:
// http://stackoverflow.com/questions/902950/iphone-convert-date-string-to-a-relative-time-stamp
// By Carl Coryell-Martin and Gilean.

#import <Cocoa/Cocoa.h>

@interface NSDateFormatter (Extras)
+ (NSString *)dateDifferenceStringFromDate:(NSDate *)date;
+ (NSString *)compactDateDifferenceStringFromDate:(NSDate *)date;

@end

