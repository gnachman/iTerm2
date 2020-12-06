//
//  iTermRequestCookieCommand.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/5/20.
//

#import "iTermRequestCookieCommand.h"

#import "iTermAPIHelper.h"
#import "iTermAPIConnectionIdentifierController.h"
#import "iTermScriptHistory.h"
#import "iTermWebSocketCookieJar.h"

@implementation iTermRequestCookieCommand

- (id)performDefaultImplementation {
    if (![iTermAPIHelper isEnabled]) {
        [self setScriptErrorNumber:1];
        [self setScriptErrorString:@"The Python API is not enabled."];
        return nil;
    }

    NSString *cookie = [[iTermWebSocketCookieJar sharedInstance] randomStringForCookie];
    NSString *name = self.arguments[@"appName"];
    if (name) {
        NSString *key = [[NSUUID UUID] UUIDString];
        NSString *identifier = [[iTermAPIConnectionIdentifierController sharedInstance] identifierForKey:key];
        iTermScriptHistoryEntry *entry = [[iTermScriptHistoryEntry alloc] initWithName:[@"≈" stringByAppendingString:name]
                                                                              fullPath:nil
                                                                            identifier:identifier
                                                                              relaunch:nil];
        [[iTermScriptHistory sharedInstance] addHistoryEntry:entry];
        [entry addOutput:@"API permission granted by Applescript.\n" completion:^{}];
        return [NSString stringWithFormat:@"%@ %@", cookie, key];
    }
    return cookie;
}


@end
