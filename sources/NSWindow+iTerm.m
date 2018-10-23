//
//  NSWindow+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 7/10/16.
//
//

#import "NSWindow+iTerm.h"
#import "PTYWindow.h"

NSString *const iTermWindowAppearanceDidChange = @"iTermWindowAppearanceDidChange";

@implementation NSWindow(iTerm)

- (BOOL)isFullScreen {
    return ((self.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen);
}

- (BOOL)isTerminalWindow {
    return [self conformsToProtocol:@protocol(PTYWindow)];
}

- (NSArray<NSTitlebarAccessoryViewController *> *)it_titlebarAccessoryViewControllers {
    if (self.styleMask & NSWindowStyleMaskTitled) {
        return self.titlebarAccessoryViewControllers;
    } else {
        return @[];
    }
}
@end
