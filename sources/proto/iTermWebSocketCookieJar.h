//
//  iTermWebSocketCookieJar.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/18/18.
//

#import <Foundation/Foundation.h>

@interface iTermWebSocketCookieJar : NSObject

+ (instancetype)sharedInstance;
- (BOOL)consumeCookie:(NSString *)cookie pathToScript:(out NSString **)pathToScript;
- (NSString *)newCookieForScriptAt:(NSString *)pathToScript;

@end
