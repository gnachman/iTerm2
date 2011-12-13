//
//  EventMonitorView.m
//  iTerm
//
//  Created by George Nachman on 11/9/11.
//  Copyright (c) 2011 George Nachman. All rights reserved.
//

#import "EventMonitorView.h"
#import "PointerPrefsController.h"
#import "FutureMethods.h"

@implementation EventMonitorView

- (void)awakeFromNib
{
    [self futureSetAcceptsTouchEvents:YES];
    [self futureSetWantsRestingTouches:YES];
}

- (void)touchesBeganWithEvent:(NSEvent *)ev
{
    numTouches_ = [[ev futureTouchesMatchingPhase:1 | (1 << 2)/*NSTouchPhasesBegan | NSTouchPhasesStationary*/
                                           inView:self] count];
}

- (void)touchesEndedWithEvent:(NSEvent *)ev
{
    numTouches_ = [[ev futureTouchesMatchingPhase:(1 << 2)/*NSTouchPhasesStationary*/
                                           inView:self] count];
}

- (void)showNotSupported
{
    [label_ setStringValue:@"You can't customize that button"];
    [label_ performSelector:@selector(setStringValue:) withObject:@"Click or Tap Here to Set Input Fields" afterDelay:1];
}

- (void)mouseUp:(NSEvent *)theEvent
{
    if (numTouches_ == 3) {
        [pointerPrefs_ setGesture:kThreeFingerClickGesture
                        modifiers:[theEvent modifierFlags]];
    } else {
        [self showNotSupported];
    }
}

- (void)rightMouseUp:(NSEvent *)theEvent
{
    int buttonNumber = 1;
    int clickCount = [theEvent clickCount];
    int modMask = [theEvent modifierFlags];
    [pointerPrefs_ setButtonNumber:buttonNumber clickCount:clickCount modifiers:modMask];
    [super mouseDown:theEvent];
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
