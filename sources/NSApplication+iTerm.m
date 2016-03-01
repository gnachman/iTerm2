//
//  NSApplication+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 7/4/15.
//
//

#import <Cocoa/Cocoa.h>

@implementation NSApplication (iTerm)

- (BOOL)isRunningUnitTests {
    static BOOL testing = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        testing = ([[[NSProcessInfo processInfo] environment] objectForKey:@"XCInjectBundle"] != nil);
    });
    return testing;
}

@end
