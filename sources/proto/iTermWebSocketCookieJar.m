//
//  iTermWebSocketCookieJar.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import "iTermWebSocketCookieJar.h"

@implementation iTermWebSocketCookieJar {
    NSMutableSet<NSString *> *_cookies;
    // Cookies with an expiration date are reusable until they expire.
    // Cookies without an entry here are single-use.
    NSMutableDictionary<NSString *, NSDate *> *_expirationDates;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cookies = [NSMutableSet set];
        _expirationDates = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)consumeCookie:(NSString *)cookie {
    @synchronized(_cookies) {
        if (![_cookies containsObject:cookie]) {
            return NO;
        }
        NSDate *expiration = _expirationDates[cookie];
        if (expiration) {
            // Reusable cookie — check TTL.
            if ([expiration timeIntervalSinceNow] <= 0) {
                [_cookies removeObject:cookie];
                [_expirationDates removeObjectForKey:cookie];
                return NO;
            }
            return YES;
        }
        // Single-use cookie — consume it.
        [_cookies removeObject:cookie];
        return YES;
    }
}

- (NSString *)randomString {
    FILE *fp = fopen("/dev/random", "r");

    if (!fp) {
        return nil;
    }

    const int length = 16;
    NSMutableString *cookie = [NSMutableString string];
    for (int i = 0; i < length; i++) {
        int b = fgetc(fp);
        if (b == EOF) {
            fclose(fp);
            return nil;
        }
        [cookie appendFormat:@"%02x", b];
    }
    fclose(fp);
    return cookie;
}

- (void)addCookie:(NSString *)cookie {
    @synchronized(_cookies) {
        [_cookies addObject:cookie];
    }
}

- (NSString *)randomStringForCookie {
    NSString *cookie = [self randomString];
    [self addCookie:cookie];
    return cookie;
}

- (NSString *)randomStringForReusableCookieWithDuration:(NSTimeInterval)duration {
    NSString *cookie = [self randomString];
    @synchronized(_cookies) {
        [_cookies addObject:cookie];
        _expirationDates[cookie] = [NSDate dateWithTimeIntervalSinceNow:duration];
    }
    return cookie;
}

- (void)removeCookieExpiration:(NSString *)cookie {
    @synchronized(_cookies) {
        [_expirationDates removeObjectForKey:cookie];
    }
}

- (void)removeCookie:(NSString *)cookie {
    @synchronized(_cookies) {
        [_cookies removeObject:cookie];
        [_expirationDates removeObjectForKey:cookie];
    }
}

@end
