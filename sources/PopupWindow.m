//
//  PopupWindow.m
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import "PopupWindow.h"
#import "iTermApplicationDelegate.h"

@implementation PopupWindow {
    BOOL shutdown_;
}

- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSWindowStyleMask)aStyle
                            backing:(NSBackingStoreType)bufferingType
                              defer:(BOOL)flag {
    self = [super initWithContentRect:contentRect
                            styleMask:NSWindowStyleMaskBorderless
                              backing:bufferingType
                                defer:flag];
    if (self) {
        [self setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
        self.opaque = NO;
    }
    return self;
}

- (void)dealloc
{
    [_owningWindow release];
    [super dealloc];
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    id cont = [self windowController];
    if (cont && [cont respondsToSelector:@selector(keyDown:)]) {
        [cont keyDown:event];
    }
}

- (void)shutdown
{
    shutdown_ = YES;
}

- (void)setOwningWindow:(NSWindow *)owningWindow {
    [_owningWindow autorelease];
    _owningWindow = [owningWindow retain];
}

- (void)closeWithoutAdjustingWindowOrder {
    [super close];
}

- (void)close {
    if (shutdown_) {
        [self closeWithoutAdjustingWindowOrder];
    } else {
        // The OS will send a hotkey window to the background if it's open and in
        // all spaces. Make it key before closing. This has to be done later because if you do it
        // here the OS gets confused and two windows are key.
        //NSLog(@"Perform delayed selector with target %@", self);
        [self performSelector:@selector(twiddleKeyWindow)
                   withObject:self
                   afterDelay:0];
    }
}

- (void)twiddleKeyWindow
{
    iTermApplicationDelegate *theDelegate = [iTermApplication.sharedApplication delegate];
    [theDelegate makeHotKeyWindowKeyIfOpen];
    [super close];
    [_owningWindow makeKeyAndOrderFront:self];
}

- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

@end
