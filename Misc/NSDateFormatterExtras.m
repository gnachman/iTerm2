//
//  NSDateFormatterExtras.m
//  iTerm
//
//  Created by George Nachman on 10/26/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "NSDateFormatterExtras.h"

@implementation NSDateFormatter (Extras)

+ (NSString *)dateDifferenceStringFromDate:(NSDate *)date
{
    NSDate *now = [NSDate date];
    double theTime = [date timeIntervalSinceDate:now];
    theTime *= -1;
    if (theTime < 60) {
        return @"Moments ago";
    } else if (theTime < 3600) {
        int diff = round(theTime / 60);
        if (diff == 1) {
            return [NSString stringWithFormat:@"1 minute ago", diff];
        }
        return [NSString stringWithFormat:@"%d minutes ago", diff];
    } else if (theTime < 86400) {
        int diff = round(theTime / 60 / 60);
        if (diff == 1) {
            return [NSString stringWithFormat:@"1 hour ago", diff];
        }
        return [NSString stringWithFormat:@"%d hours ago", diff];
    } else if (theTime < 604800) {
        int diff = round(theTime / 60 / 60 / 24);
        if (diff == 1) {
            return [NSString stringWithFormat:@"Yesterday", diff];
        }
        if (diff == 7) {
            return [NSString stringWithFormat:@"Last week", diff];
        }
        return[NSString stringWithFormat:@"%d days ago", diff];
    } else {
        int diff = round(theTime / 60 / 60 / 24 / 7);
        if (diff == 1) {
            return [NSString stringWithFormat:@"Last week", diff];
   
        }
        return [NSString stringWithFormat:@"%d weeks ago", diff];
    }   
}

@end