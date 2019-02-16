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

- (NSString *)it_styleMaskDescription {
    NSDictionary *map = @{ @(NSWindowStyleMaskClosable): @"closable",
                           @(NSWindowStyleMaskMiniaturizable): @"miniaturizable",
                           @(NSWindowStyleMaskResizable): @"resizable",
                           @(NSWindowStyleMaskTexturedBackground): @"textured-background",
                           @(NSWindowStyleMaskUnifiedTitleAndToolbar): @"unified",
                           @(NSWindowStyleMaskFullScreen): @"fullscreen",
                           @(NSWindowStyleMaskFullSizeContentView): @"full-size-content-view",
                           @(NSWindowStyleMaskUtilityWindow): @"utility",
                           @(NSWindowStyleMaskDocModalWindow): @"doc-modal",
                           @(NSWindowStyleMaskNonactivatingPanel): @"non-activating-panel",
                           @(NSWindowStyleMaskHUDWindow): @"hud-window" };

    NSUInteger i = 1;
    NSMutableArray *array = [NSMutableArray array];
    const NSUInteger styleMask = self.styleMask;
    while (i) {
        if (styleMask & i) {
            NSString *name = map[@(i)];
            if (name) {
                [array addObject:name];
            } else {
                [array addObject:[@(i) stringValue]];
            }
        }
        i <<= 1;
    }
    return [array componentsJoinedByString:@" "];
}

@end
