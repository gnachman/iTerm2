//
//  NSWindow+iTerm.m
//  iTerm2
//
//  Created by George Nachman on 7/10/16.
//
//

#import "NSWindow+iTerm.h"

#import "iTermApplication.h"
#import "NSObject+iTerm.h"
#import "PTYWindow.h"
#import <Quartz/Quartz.h>

NSString *const iTermWindowAppearanceDidChange = @"iTermWindowAppearanceDidChange";
void *const iTermDeclineFirstResponderAssociatedObjectKey = (void *)"iTermDeclineFirstResponderAssociatedObjectKey";

@implementation NSWindow(iTerm)

- (void)it_titleBarDoubleClick {
    NSString *doubleClickAction = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleActionOnDoubleClick"];
    if ([doubleClickAction isEqualToString:@"Minimize"]) {
        [self performMiniaturize:nil];
        return;
    }
    if (doubleClickAction == nil || [doubleClickAction isEqualToString:@"Maximize"]) {
        [self performZoom:nil];
        return;
    }
}

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

- (void)it_makeKeyAndOrderFront {
    [[iTermApplication sharedApplication] it_makeWindowKey:self];
}

static NSView *SearchForViewOfClass(NSView *view, NSString *className, NSView *viewToIgnore) {
    if ([NSStringFromClass(view.class) isEqual:className]) {
        return view;
    }
    for (NSView *subview in view.subviews) {
        if (subview == viewToIgnore) {
            continue;
        }
        NSView *result = SearchForViewOfClass(subview, className, viewToIgnore);
        if (result) {
            return result;
        }
    }
    return nil;
}

- (NSView *)it_titlebarViewOfClassWithName:(NSString *)className {
    NSView *current = self.contentView;
    if (!current) {
        return nil;
    }
    while (current.superview) {
        current = current.superview;
    }
    return SearchForViewOfClass(current, className, self.contentView);
}

- (void)it_shakeNo {
    const NSRect frame = self.frame;
    CAKeyframeAnimation *shakeAnimation = [CAKeyframeAnimation animation];

    CGMutablePathRef shakePath = CGPathCreateMutable();
    CGPathMoveToPoint(shakePath, NULL, NSMinX(frame), NSMinY(frame));
    for (NSInteger index = 0; index < 3; index++){
        const CGFloat radiusFraction = 0.03;
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) - NSWidth(frame) * radiusFraction, NSMinY(frame));
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) + NSWidth(frame) * radiusFraction, NSMinY(frame));
    }
    CGPathCloseSubpath(shakePath);
    shakeAnimation.path = shakePath;
    shakeAnimation.duration = 0.5;

    [self setAnimations:@{ @"frameOrigin": shakeAnimation }];
    [self.animator setFrameOrigin:self.frame.origin];

    CGPathRelease(shakePath);
}

static NSWindow *GetWindowForResponder(NSResponder *firstResponder) {
    return [NSWindow castFrom:firstResponder] ?: [NSView castFrom:firstResponder].window;
}

- (BOOL)it_makeFirstResponderIfNotDeclined:(NSResponder *)responder
                                 callSuper:(BOOL (^ NS_NOESCAPE)(NSResponder *))callSuper {
    NSView *responderAsView = [NSView castFrom:responder];
    if (!responderAsView || responderAsView == self.firstResponder) {
        return callSuper(responder);
    }

    NSWindow *existingWindow = GetWindowForResponder(self.firstResponder);
    if (!existingWindow) {
        return callSuper(responderAsView);
    }

    NSWindow *newWindow = responderAsView.window;
    if (newWindow == self) {
        return callSuper(responder);
    }
    if (newWindow == existingWindow) {
        return callSuper(responder);
    }
    if (self.currentEvent.window == newWindow) {
        return callSuper(responder);
    }

    NSView *responderView = responderAsView;
    while (responderView != nil) {
        if ([[responderView it_associatedObjectForKey:iTermDeclineFirstResponderAssociatedObjectKey] boolValue]) {
            return NO;
        }
        responderView = [responderView superview];
    }
    return callSuper(responder);
}

@end
