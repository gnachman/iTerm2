//
//  NSURL.m
//  iTerm2
//
//  Created by George Nachman on 4/24/16.
//
//

#import "NSURL+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSURL(iTerm)

- (NSURL *)URLByRemovingFragment {
    if (self.fragment) {
        NSString *string = self.absoluteString;
        NSRange range = [string rangeOfString:@"#"];
        if (range.location != NSNotFound) {
            NSString *stringWithoutFragment = [string substringToIndex:range.location];
            return [NSURL URLWithString:stringWithoutFragment];
        }
    }
    return self;
}

- (NSURL *)URLByAppendingQueryParameter:(NSString *)queryParameter {
    if (!queryParameter.length) {
        return self;
    }
    
    NSURL *urlWithoutFragment = [self URLByRemovingFragment];
    NSString *fragment;
    if (self.fragment) {
        fragment = [@"#" stringByAppendingString:self.fragment];
    } else {
        fragment = @"";
    }
    
    NSString *separator;
    if (self.query) {
        if (self.query.length > 0) {
            separator = @"&";
        } else {
            separator = @"";
        }
    } else {
        separator = @"?";
    }
    
    NSArray *components = @[ urlWithoutFragment.absoluteString, separator, queryParameter, fragment ];
    NSString *string = [components componentsJoinedByString:@""];
    
    return [NSURL URLWithString:string];
}

+ (NSURL *)URLWithUserSuppliedString:(NSString *)string {
    NSCharacterSet *nonAsciiCharacterSet = [NSCharacterSet characterSetWithRange:NSMakeRange(128, 0x10FFFF - 128)];
    if ([string rangeOfCharacterFromSet:nonAsciiCharacterSet].location != NSNotFound) {
        NSUInteger fragmentIndex = [string rangeOfString:@"#"].location;
        if (fragmentIndex != NSNotFound) {
            // Don't want to percent encode a #.
            NSString *before = [[string substringToIndex:fragmentIndex] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            NSString *after = [[string substringFromIndex:fragmentIndex + 1] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            NSString *combined = [NSString stringWithFormat:@"%@#%@", before, after];
            return [NSURL URLWithString:combined];
        } else {
            return [NSURL URLWithString:[string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
        }
    } else {
        return [NSURL URLWithString:string];
    }
}

@end

NS_ASSUME_NONNULL_END
