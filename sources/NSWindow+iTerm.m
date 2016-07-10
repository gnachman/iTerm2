//
//  NSWindow+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 7/10/16.
//
//

#import "NSWindow+iTerm.h"

@implementation NSWindow(iTerm)

- (BOOL)isFullScreen {
    return ((self.styleMask & NSFullScreenWindowMask) == NSFullScreenWindowMask);
}

@end
