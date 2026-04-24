//
//  NSDateFormatterExtras.m
//  iTerm
//
//  Created by George Nachman on 10/26/10.
//  Copyright 2010 George Nachman. All rights reserved.
//

#import "NSDateFormatterExtras.h"

@implementation NSDateFormatter (Extras)

+ (NSString *)durationString:(NSTimeInterval)duration {
    int seconds = duration;
    int minutes = seconds / 60;
    int hours = minutes / 60;
    int remainderMinutes = minutes - hours * 60;
    return [NSString stringWithFormat:@"%d:%02d", hours, remainderMinutes];
}

+ (NSString *)dateDifferenceStringFromDate:(NSDate *)date {
    return [self dateDifferenceStringFromDate:date options:0];
}

+ (NSString *)dateDifferenceStringFromDate:(NSDate *)date
                                   options:(iTermDateDifferenceOptions)options {
    const BOOL lowerCase = (options & iTermDateDifferenceOptionsLowercase) != 0;
    NSDate *now = [NSDate date];
    double theTime = [date timeIntervalSinceDate:now];
    theTime *= -1;
    if (theTime < 60) {
        if (lowerCase) {
            return @"moments ago";
        } else {
            return @"Moments ago";
        }
    } else if (theTime < 3600) {
        int diff = round(theTime / 60);
        if (diff == 1) {
            return [NSString stringWithFormat:@"1 minute ago"];
        }
        return [NSString stringWithFormat:@"%d minutes ago", diff];
    } else if (theTime < 86400) {
        int diff = round(theTime / 60 / 60);
        if (diff == 1) {
            return [NSString stringWithFormat:@"1 hour ago"];
        }
        return [NSString stringWithFormat:@"%d hours ago", diff];
    } else if (theTime < 604800) {
        int diff = round(theTime / 60 / 60 / 24);
        if (diff == 1) {
            if (lowerCase) {
                return @"yesterday";
            } else {
                return @"Yesterday";
            }
        }
        if (diff == 7) {
            if (lowerCase) {
                return @"one week ago";
            } else {
                return @"One week ago";
            }
        }
        return[NSString stringWithFormat:@"%d days ago", diff];
    } else {
        int diff = round(theTime / 60 / 60 / 24 / 7);
        if (diff == 1) {
            if (lowerCase) {
                return @"last week";
            } else {
                return @"Last week";
            }

        }
        return [NSString stringWithFormat:@"%d weeks ago", diff];
    }
}

+ (NSString *)compactDateDifferenceStringFromDate:(NSDate *)date
{
    NSDate *now = [NSDate date];
    double theTime = [date timeIntervalSinceDate:now];
    theTime *= -1;
    return [self compactDateDifferenceStringFromTimeDelta:theTime];
}

+ (NSString *)compactDateDifferenceStringFromTimeDelta:(NSTimeInterval)theTime {
    if (theTime < 60) {
        return @"< 1 min";
    } else if (theTime < 3600) {
        int diff = round(theTime / 60);
        if (diff == 1) {
            return [NSString stringWithFormat:@"1 min"];
        }
        return [NSString stringWithFormat:@"%d min", diff];
    } else if (theTime < 86400) {
        int diff = round(theTime / 60 / 60);
        if (diff == 1) {
            return [NSString stringWithFormat:@"1 hour"];
        }
        return [NSString stringWithFormat:@"%d hrs", diff];
    } else if (theTime < 604800) {
        int diff = round(theTime / 60 / 60 / 24);
        if (diff == 1) {
            return [NSString stringWithFormat:@"1 day"];
        }
        if (diff == 7) {
            return [NSString stringWithFormat:@"1 week"];
        }
        return[NSString stringWithFormat:@"%d days", diff];
    } else {
        int diff = round(theTime / 60 / 60 / 24 / 7);
        if (diff == 1) {
            return [NSString stringWithFormat:@"1 week"];

        }
        return [NSString stringWithFormat:@"%d wks", diff];
    }
}

+ (NSString *)highResolutionCompactRelativeTimeStringFromSeconds:(NSTimeInterval)seconds {
    const BOOL negative = (seconds < 0);
    const NSTimeInterval interval = fabs(seconds);

    if (interval == 0) {
        return @"Baseline";
    }

    // < 10 sec → "X.yyy sec"
    if (interval < 10) {
        return [NSString stringWithFormat:@"%@%0.3f sec",
                negative ? @"-" : @"+",
                interval];
    }

    // < 1 min → “X sec”
    if (interval < 60) {
        int sec = (int)interval;
        return [NSString stringWithFormat:@"%@%d sec",
                negative ? @"-" : @"+",
                sec];
    }

    // < 1 hr → “X min”
    if (interval < 3600) {
        int mins = (int)(interval / 60);
        return [NSString stringWithFormat:@"%@%d min",
                negative ? @"-" : @"+",
                mins];
    }

    // < 1 day → “H:MM:SS”
    if (interval < 86400) {
        int hrs  = (int)(interval / 3600);
        int mins = ((int)interval % 3600) / 60;
        int secs = (int)interval % 60;
        NSString *t = [NSString stringWithFormat:@"%d:%02d:%02d", hrs, mins, secs];
        return negative ? [@"-" stringByAppendingString:t] : [@"+" stringByAppendingString:t];
    }

    // ≥ 1 day → pick two largest non-zero of [yr, mon, wk, day, hr, min, sec]
    NSInteger secsInYr  = 31536000;  // 365 d
    NSInteger secsInMo  = 2592000;   // 30 d
    NSInteger secsInWk  = 604800;
    NSInteger secsInDay = 86400;

    NSInteger rem = (NSInteger)interval;
    NSInteger vals[] = {
        rem / secsInYr,
        (rem % secsInYr) / secsInMo,
        (rem % secsInMo) / secsInWk,
        (rem % secsInWk) / secsInDay,
        (rem % secsInDay) / 3600,
        (rem % 3600) / 60,
        rem % 60
    };
    const char *units[] = { "yr", "mon", "wk", "day", "hr", "min", "sec" };

    NSMutableArray<NSString*> *comps = [NSMutableArray array];
    for (int i = 0; i < 7; i++) {
        if (vals[i] > 0) {
            [comps addObject:
             [NSString stringWithFormat:@"%ld %s", (long)vals[i], units[i]]];
        }
        if (comps.count == 2) break;
    }

    NSString *out = comps.count > 0 ? ([comps componentsJoinedByString:@", "]) : @"0 sec";

    return negative ? [@"-" stringByAppendingString:out] : [@"+" stringByAppendingString:out];
}
@end
