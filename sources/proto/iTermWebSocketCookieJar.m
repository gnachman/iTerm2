//
//  iTermWebSocketCookieJar.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import "iTermWebSocketCookieJar.h"

@implementation iTermWebSocketCookieJar {
    NSMutableSet<NSString *> *_cookies;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (BOOL)consumeCookie:(NSString *)cookie {
    if ([_cookies containsObject:cookie]) {
        [_cookies removeObject:cookie];
        return YES;
    } else {
        return NO;
    }
}

- (NSString *)newCookie {
    NSString *cookie = [[NSUUID UUID] UUIDString];
    [_cookies addObject:cookie];
    return cookie;
}

@end
