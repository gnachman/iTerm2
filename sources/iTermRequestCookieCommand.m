//
//  iTermRequestCookieCommand.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/5/20.
//

#import "iTermRequestCookieCommand.h"

#import "iTermAPIHelper.h"
#import "iTermWebSocketCookieJar.h"

@implementation iTermRequestCookieCommand

- (id)performDefaultImplementation {
    if (![iTermAPIHelper isEnabled]) {
        [self setScriptErrorNumber:1];
        [self setScriptErrorString:@"The Python API is not enabled."];
        return nil;
    }
    return [[iTermWebSocketCookieJar sharedInstance] randomStringForCookie];
}

@end
