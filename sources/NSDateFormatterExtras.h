// This code copied from:
// http://stackoverflow.com/questions/902950/iphone-convert-date-string-to-a-relative-time-stamp
// By Carl Coryell-Martin and Gilean.

#import <Cocoa/Cocoa.h>

typedef NS_OPTIONS(NSUInteger, iTermDateDifferenceOptions) {
    iTermDateDifferenceOptionsLowercase = (1 << 0)
};

NS_ASSUME_NONNULL_BEGIN

@interface NSDateFormatter (Extras)
+ (NSString *)dateDifferenceStringFromDate:(NSDate * _Nonnull)date;
+ (NSString *)compactDateDifferenceStringFromDate:(NSDate * _Nonnull)date;
+ (NSString *)durationString:(NSTimeInterval)duration;
+ (NSString *)dateDifferenceStringFromDate:(NSDate *)date
                                   options:(iTermDateDifferenceOptions)options;
+ (NSString *)compactDateDifferenceStringFromTimeDelta:(NSTimeInterval)theTime;
+ (NSString *)highResolutionCompactRelativeTimeStringFromSeconds:(NSTimeInterval)seconds;

@end

NS_ASSUME_NONNULL_END
