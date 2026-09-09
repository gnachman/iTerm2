//
//  NSDateFormatterExtras.m
//  iTerm
//
//  Created by George Nachman on 10/26/10.
//  Copyright 2010 George Nachman. All rights reserved.
//

#import "NSDateFormatterExtras.h"

@implementation NSDateFormatter (Extras)

// The relative-time methods keep the original hand-written English wording for an English UI, and
// defer to the OS's locale-aware NSRelativeDateTimeFormatter for every other UI language rather than
// reimplementing per-language plural and word-order rules. Gate on the actual UI localization (not
// the region), so non-English phrasing appears only when the UI itself is non-English. Returns nil
// for English (use the hand-written code below), otherwise the UI language identifier to format in.
+ (NSString *)it_relativeTimeNonEnglishLanguage {
    // The UI language is fixed for the life of the process, so compute the result once and cache it
    // (nil for an English UI). This runs per visible row when relative timestamps are shown.
    static NSString *result;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *language = [[NSBundle mainBundle] preferredLocalizations].firstObject ?: @"en";
        if ([language isEqualToString:@"Base"] ||
            [language isEqualToString:@"en"] ||
            [language hasPrefix:@"en-"] ||
            [language hasPrefix:@"en_"]) {
            result = nil;
        } else {
            // MRC: own the string; preferredLocalizations.firstObject is autoreleased.
            result = [language copy];
        }
    });
    return result;
}

+ (NSString *)durationString:(NSTimeInterval)duration {
    return [self durationString:duration
             nonEnglishLanguage:[self it_relativeTimeNonEnglishLanguage]
                         locale:[NSLocale currentLocale]];
}

// Exposed for testing. `nonEnglishLanguage` is nil for an English UI (in which case the
// separator is always a colon, matching the previous English output and the relative-time
// methods in this file), and the language identifier otherwise (in which case the separator
// follows `locale`'s region: a colon in most locales, a period in e.g. Finnish and Norwegian
// Nynorsk). The H:MM shape (unpadded hours) is kept rather than NSDateComponentsFormatter,
// which would pad to “01:05”.
// Extracts the hour/minute separator for `locale` by templating “Hmm” and scanning out the
// characters between the hour and minute fields. The result depends only on `locale`, so cache it
// keyed by locale identifier: this method runs per row in several popups, and dateFormatFromTemplate:
// is not cheap. A bare dispatch_once would be wrong because the testable overload passes arbitrary
// locales.
+ (NSString *)it_durationSeparatorForLocale:(NSLocale *)locale {
    static NSMutableDictionary<NSString *, NSString *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // This file is compiled MRC (non-ARC target), so a dispatch_once static must own its
        // object; the autoreleased +[NSMutableDictionary dictionary] would be freed after the pool
        // drains, leaving a dangling static.
        cache = [[NSMutableDictionary alloc] init];
    });
    NSString *key = locale.localeIdentifier ?: @"";
    @synchronized (cache) {
        NSString *cached = cache[key];
        if (cached) {
            return cached;
        }
    }
    NSString *separator = @":";
    NSString *template = [NSDateFormatter dateFormatFromTemplate:@"Hmm" options:0 locale:locale];
    if (template.length > 0) {
        // Walk the ICU pattern rather than scanning raw characters, so a quoted literal separator
        // letter (e.g. a hypothetical “HH'h'mm”) is unquoted instead of stopping the scan on its
        // letter. ICU quoting: a single quote opens/closes a literal run, and “''” is an escaped
        // apostrophe. Collect the literal text that appears after the hour field and before the
        // minute field.
        NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
        NSMutableString *sep = [NSMutableString string];
        BOOL seenHour = NO;
        BOOL inQuote = NO;
        const NSUInteger length = template.length;
        for (NSUInteger i = 0; i < length; i++) {
            const unichar c = [template characterAtIndex:i];
            if (c == '\'') {
                if (i + 1 < length && [template characterAtIndex:i + 1] == '\'') {
                    if (seenHour) {
                        [sep appendString:@"'"];  // escaped apostrophe
                    }
                    i++;
                } else {
                    inQuote = !inQuote;
                }
                continue;
            }
            if (inQuote) {
                if (seenHour) {
                    [sep appendFormat:@"%C", c];  // literal inside quotes
                }
                continue;
            }
            if ([letters characterIsMember:c]) {
                if (c == 'H' || c == 'h' || c == 'k' || c == 'K') {
                    seenHour = YES;
                } else if (c == 'm' && seenHour) {
                    break;  // reached the minute field; the separator run is complete
                }
                continue;
            }
            if (seenHour) {
                [sep appendFormat:@"%C", c];  // literal separator outside quotes
            }
        }
        if (sep.length > 0) {
            separator = sep;
        }
    }
    @synchronized (cache) {
        cache[key] = separator;
    }
    return separator;
}

+ (NSString *)durationString:(NSTimeInterval)duration
          nonEnglishLanguage:(NSString *)nonEnglishLanguage
                      locale:(NSLocale *)locale {
    int seconds = duration;
    int minutes = seconds / 60;
    int hours = minutes / 60;
    int remainderMinutes = minutes - hours * 60;
    NSString *separator = @":";
    if (nonEnglishLanguage) {
        separator = [self it_durationSeparatorForLocale:locale];
    }
    return [NSString stringWithFormat:@"%d%@%02d", hours, separator, remainderMinutes];
}

+ (NSString *)dateDifferenceStringFromDate:(NSDate *)date {
    return [self dateDifferenceStringFromDate:date options:0];
}

+ (NSString *)dateDifferenceStringFromDate:(NSDate *)date
                                   options:(iTermDateDifferenceOptions)options {
    const BOOL lowerCase = (options & iTermDateDifferenceOptionsLowercase) != 0;
    NSString *language = [self it_relativeTimeNonEnglishLanguage];
    if (language) {
        // The formatter's configuration (style, units, and locale) depends only on the process's fixed
        // UI language, not on any per-call argument, so build it once and reuse it. All call sites are
        // on the main thread. This avoids allocating a formatter and locale on every call (up to 32
        // times per keystroke in the composer, and per row in several popups).
        static NSRelativeDateTimeFormatter *formatter;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [[NSRelativeDateTimeFormatter alloc] init];
            formatter.dateTimeStyle = NSRelativeDateTimeFormatterStyleNamed;  // “yesterday”, “last week”
            formatter.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleFull;  // “2 days ago”
            formatter.locale = [NSLocale localeWithLocaleIdentifier:language];
        });
        NSString *string = [formatter localizedStringForDate:date relativeToDate:[NSDate date]];
        // The lowercase option distinguishes standalone use (capitalized) from mid-sentence use.
        // Uppercase the first grapheme for the standalone case; other cases are left as produced.
        if (!lowerCase && string.length > 0) {
            const NSRange first = [string rangeOfComposedCharacterSequenceAtIndex:0];
            string = [string stringByReplacingCharactersInRange:first
                                                     withString:[[string substringWithRange:first] localizedUppercaseString]];
        }
        return string;
    }
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
    NSString *language = [self it_relativeTimeNonEnglishLanguage];
    if (language) {
        // NSDateComponentsFormatter throws on a non-finite input, so guard NaN/inf before handing it
        // the value.
        if (!isfinite(theTime)) {
            return @"";
        }
        // This method's contract is a BARE duration with no relative marker (“5 min”, not “5 min
        // ago”): callers such as the Suppressed Alerts menu supply the marker themselves via their
        // own localized frame. So use NSDateComponentsFormatter (largest localized unit), NOT
        // NSRelativeDateTimeFormatter, which would bake in an “ago”/“il y a” and double the marker.
        // The formatter's configuration depends only on the process's fixed UI language, not on any
        // per-call argument, so build it once and reuse it (this runs per row in several popups). All
        // call sites are on the main thread.
        static NSDateComponentsFormatter *formatter;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [[NSDateComponentsFormatter alloc] init];
            formatter.unitsStyle = NSDateComponentsFormatterUnitsStyleAbbreviated;
            formatter.allowedUnits = (NSCalendarUnitSecond | NSCalendarUnitMinute | NSCalendarUnitHour |
                                      NSCalendarUnitDay | NSCalendarUnitWeekOfMonth);
            formatter.maximumUnitCount = 1;
            NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
            calendar.locale = [NSLocale localeWithLocaleIdentifier:language];
            formatter.calendar = calendar;
        });
        // stringFromTimeInterval: is nullable (e.g. an unformattable input); coalesce to @"" since
        // this method is under NS_ASSUME_NONNULL.
        return [formatter stringFromTimeInterval:theTime] ?: @"";
    }
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

// A compact signed-duration delta for the timestamp margin (e.g. “+5m3s”, “1y2mo”). The unit
// abbreviations are localizable so translators can supply their language's compact forms; the sign
// and numbers are locale-neutral. There is no NSRelativeDateTimeFormatter equivalent for this
// signed-duration style, and NSDateComponentsFormatter cannot do the sub-second precision.
+ (NSString *)highResolutionCompactRelativeTimeStringFromSeconds:(NSTimeInterval)seconds {
    const BOOL negative = (seconds < 0);
    const NSTimeInterval interval = fabs(seconds);

    // The unit abbreviations and the baseline label depend only on the process's fixed UI language,
    // never on per-call arguments, so cache them once to avoid repeating bundle lookups on every call
    // (this runs once per visible row per redraw when relative timestamps are shown).
    static NSString *baseline;
    static NSString *uS;
    static NSString *uM;
    static NSString *uH;
    static NSString *uD;
    static NSString *uW;
    static NSString *uMo;
    static NSString *uY;
    static NSArray<NSString *> *units;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        baseline = NSLocalizedStringWithDefaultValue(@"DateFormatter.Baseline", nil, [NSBundle mainBundle], @"Baseline", @"Label shown in the timestamp margin for the reference (zero-delta) row");
        // Compact, localizable unit abbreviations (“mo” for month avoids colliding with “m” for minute).
        uS = NSLocalizedStringWithDefaultValue(@"DateFormatter.UnitSecond", nil, [NSBundle mainBundle], @"s", @"Compact abbreviation for seconds in a duration like 5m3s");
        uM = NSLocalizedStringWithDefaultValue(@"DateFormatter.UnitMinute", nil, [NSBundle mainBundle], @"m", @"Compact abbreviation for minutes in a duration like 5m3s");
        uH = NSLocalizedStringWithDefaultValue(@"DateFormatter.UnitHour", nil, [NSBundle mainBundle], @"h", @"Compact abbreviation for hours in a duration like 2h5m");
        uD = NSLocalizedStringWithDefaultValue(@"DateFormatter.UnitDay", nil, [NSBundle mainBundle], @"d", @"Compact abbreviation for days in a duration like 3d4h");
        uW = NSLocalizedStringWithDefaultValue(@"DateFormatter.UnitWeek", nil, [NSBundle mainBundle], @"w", @"Compact abbreviation for weeks in a duration like 2w3d");
        uMo = NSLocalizedStringWithDefaultValue(@"DateFormatter.UnitMonth", nil, [NSBundle mainBundle], @"mo", @"Compact abbreviation for months in a duration like 1y2mo");
        uY = NSLocalizedStringWithDefaultValue(@"DateFormatter.UnitYear", nil, [NSBundle mainBundle], @"y", @"Compact abbreviation for years in a duration like 1y2mo");
        // MRC: own the array (and its elements). An autoreleased @[...] literal would be freed.
        units = [[NSArray alloc] initWithObjects:uY, uMo, uW, uD, uH, uM, uS, nil];
    });

    if (interval == 0) {
        return baseline;
    }
    NSString *sign = negative ? @"-" : @"+";

    // < 10 sec → "X.yyys"
    if (interval < 10) {
        return [NSString stringWithFormat:@"%@%0.3f%@", sign, interval, uS];
    }

    // < 1 min → "Xs"
    if (interval < 60) {
        return [NSString stringWithFormat:@"%@%d%@", sign, (int)interval, uS];
    }

    // < 1 hr → "XmYs" (omit seconds if zero)
    if (interval < 3600) {
        int mins = (int)interval / 60;
        int secs = (int)interval % 60;
        if (secs == 0) {
            return [NSString stringWithFormat:@"%@%d%@", sign, mins, uM];
        }
        return [NSString stringWithFormat:@"%@%d%@%d%@", sign, mins, uM, secs, uS];
    }

    // < 1 day → "XhYmZs" (omit zero components)
    if (interval < 86400) {
        int hrs = (int)interval / 3600;
        int mins = ((int)interval % 3600) / 60;
        int secs = (int)interval % 60;
        NSMutableString *t = [NSMutableString stringWithFormat:@"%@%d%@", sign, hrs, uH];
        if (mins > 0) {
            [t appendFormat:@"%d%@", mins, uM];
        }
        if (secs > 0) {
            [t appendFormat:@"%d%@", secs, uS];
        }
        return t;
    }

    // ≥ 1 day → pick two largest non-zero of [y, mo, w, d, h, m, s]
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

    NSMutableString *out = [NSMutableString string];
    int components = 0;
    for (int i = 0; i < 7 && components < 2; i++) {
        if (vals[i] > 0) {
            [out appendFormat:@"%ld%@", (long)vals[i], units[i]];
            components++;
        }
    }
    if (out.length == 0) {
        [out appendFormat:@"0%@", uS];
    }
    return [sign stringByAppendingString:out];
}
@end
