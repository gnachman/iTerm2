//
//  EventMonitorView.m
//  iTerm
//
//  Created by George Nachman on 11/9/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "EventMonitorView.h"
#import "PointerPrefsController.h"

@implementation EventMonitorView

- (void)showNotSupported
{
    [label_ setStringValue:@"You can't customize that button"];
    [label_ performSelector:@selector(setStringValue:) withObject:@"Click Here to Set Input Fields" afterDelay:1];
}

- (void)mouseDown:(NSEvent *)theEvent
{
    [self showNotSupported];
}

- (void)rightMouseDown:(NSEvent *)theEvent
{
    [self showNotSupported];
}

- (void)otherMouseDown:(NSEvent *)theEvent
{
    int buttonNumber = [theEvent buttonNumber];
    int clickCount = [theEvent clickCount];
    int modMask = [theEvent modifierFlags];
    [pointerPrefs_ setButtonNumber:buttonNumber clickCount:clickCount modifiers:modMask];
    [super mouseDown:theEvent];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor whiteColor] set];
    NSRectFill(dirtyRect);
    [[NSColor blackColor] set];
    NSFrameRect(NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height));

    [super drawRect:dirtyRect];
}
@end
