//
//  iTermVersionComparator.m
//  iTerm2
//
//  Created by George Nachman on 2/20/17.
//
//

#import "iTermVersionComparator.h"
#import "DebugLogging.h"

@implementation iTermVersionComparator

- (NSComparisonResult)compareVersion:(NSString *)versionA toVersion:(NSString *)versionB {
    ELog(@"Sparkle: Compare %@ and %@", versionA, versionB);
    NSString *betaSuffix = @".beta";
    if ([versionA hasSuffix:betaSuffix] && ![versionB hasSuffix:betaSuffix]) {
        ELog(@"Stripping beta suffix from %@", versionA);
        // a = wa.xa.ya.beta
        // b = wb.xb.yb
        // Compare only wa.xa and wb.xb. We want this to hold:
        //   3.1.0 > 3.1.999.beta
        //   3.0.0 < 3.1.0.beta.
        versionA = [self iterm_firstTwoPartsOfVersion:versionA];
        versionB = [self iterm_firstTwoPartsOfVersion:versionB];
        NSComparisonResult result = [super compareVersion:versionA toVersion:versionB];
        if (result == NSOrderedSame) {
            result = NSOrderedAscending;
        }
        [self iterm_logComparisonBetweenVersion:versionA andVersion:versionB withResult:result];
        return result;
    } else if ([versionB hasSuffix:betaSuffix] && ![versionA hasSuffix:betaSuffix]) {
        // Don't duplicate the logic above when A is non-beta and B is beta. Recurse and invert.
        ELog(@"Sparkle: Inverting comparison between %@ and %@", versionA, versionB);
        NSComparisonResult result = [self iterm_invertResult:[self compareVersion:versionB toVersion:versionA]];
        [self iterm_logComparisonBetweenVersion:versionA andVersion:versionB withResult:result];
        return result;
    } else {
        // Normal case.
        NSComparisonResult result = [super compareVersion:versionA toVersion:versionB];
        [self iterm_logComparisonBetweenVersion:versionA andVersion:versionB withResult:result];
        return result;
    }
}

- (void)iterm_logComparisonBetweenVersion:(NSString *)versionA andVersion:(NSString *)versionB withResult:(NSComparisonResult)result {
    switch (result) {
        case NSOrderedAscending:
            ELog(@"Sparkle: %@ < %@", versionA, versionB);
            break;

        case NSOrderedDescending:
            ELog(@"Sparkle: %@ > %@", versionA, versionB);
            break;

        case NSOrderedSame:
            ELog(@"Sparkle: %@ = %@", versionA, versionB);
            break;
    }
}

- (NSComparisonResult)iterm_invertResult:(NSComparisonResult)result {
    switch (result) {
        case NSOrderedAscending:
            return NSOrderedDescending;
        case NSOrderedSame:
            return result;
        case NSOrderedDescending:
            return NSOrderedAscending;
    }
    return result;
}

- (NSString *)iterm_firstTwoPartsOfVersion:(NSString *)version {
    NSArray *parts = [version componentsSeparatedByString:@"."];
    if (parts.count > 2) {
        parts = [parts subarrayWithRange:NSMakeRange(0, 2)];
    }
    return [parts componentsJoinedByString:@"."];
}

@end
