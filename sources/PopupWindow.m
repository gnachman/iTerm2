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
    NSWindow* parentWindow_;
    BOOL shutdown_;
}

- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSUInteger)aStyle
                            backing:(NSBackingStoreType)bufferingType
                              defer:(BOOL)flag {
    self = [super initWithContentRect:contentRect
                            styleMask:NSBorderlessWindowMask
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
    [parentWindow_ release];
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

- (void)setParentWindow:(NSWindow*)parentWindow {
    [parentWindow_ autorelease];
    parentWindow_ = [parentWindow retain];
}

- (void)close
{
    if (shutdown_) {
        [super close];
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
    [parentWindow_ makeKeyAndOrderFront:self];
}

- (BOOL)autoHidesHotKeyWindow {
    return NO;
}

@end
