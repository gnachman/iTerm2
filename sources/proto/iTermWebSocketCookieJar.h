//
//  iTermWebSocketCookieJar.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import <Foundation/Foundation.h>

@interface iTermWebSocketCookieJar : NSObject

+ (instancetype)sharedInstance;
- (BOOL)consumeCookie:(NSString *)cookie;
- (NSString *)randomStringForCookie;
- (void)removeCookie:(NSString *)cookie;
- (void)addCookie:(NSString *)cookie;

@end
