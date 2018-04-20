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

- (instancetype)init {
    self = [super init];
    if (self) {
        _cookies = [NSMutableSet set];
    }
    return self;
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

    [_cookies addObject:cookie];
    return cookie;
}

@end
