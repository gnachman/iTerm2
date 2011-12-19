//
//  PTYSplitView.m
//  iTerm
//
//  Created by George Nachman on 12/10/11.
//

#import "PTYSplitView.h"

@implementation PTYSplitView

- (NSObject<PTYSplitViewDelegate> *)delegate
{
    return (NSObject<PTYSplitViewDelegate> *) [super delegate];
}

- (void)setDelegate:(NSObject<PTYSplitViewDelegate> *)delegate
{
    [super setDelegate:delegate];
}

- (NSString *)description
{
    NSMutableString *d = [NSMutableString string];
    [d appendFormat:@"%@ %@ [", [NSValue valueWithRect:[self frame]], [self isVertical] ? @"|" : @"--"];
    for (NSView *view in [self subviews]) {
        [d appendFormat:@" (%@)", [view description]];
    }
    [d appendFormat:@"]"];
    return d;
}

- (void)mouseDown:(NSEvent *)theEvent
{
    // First, find the splitter that was clicked on. It will be the one closest
    // to the mouse. The OS seems to give a bit of wiggle room so it's not
    // necessary exactly under the mouse.
    int clickedOnSplitterIndex = -1;
    NSArray *subviews = [self subviews];
    NSPoint locationInWindow = [theEvent locationInWindow];
    locationInWindow.y--;
    NSPoint locationInView = [self convertPointFromBase:locationInWindow];
    int x, y;
    int bestDistance = -1;
    if ([self isVertical]) {
        int mouseX = locationInView.x;
        x = 0;
        int bestX;
        for (int i = 0; i < subviews.count; i++) {
            x += [[subviews objectAtIndex:i] frame].size.width;
            if (bestDistance < 0 || abs(x - mouseX) < bestDistance) {
                bestDistance = abs(x - mouseX);
                clickedOnSplitterIndex = i;
                bestX = x;
            }
            x += [self dividerThickness];
        }
        x = bestX;
    } else {
        int mouseY = locationInView.y;
        int bestY;
        y = 0;
        for (int i = 0; i < subviews.count; i++) {
            y += [[subviews objectAtIndex:i] frame].size.height;
            if (bestDistance < 0 || abs(y - mouseY) < bestDistance) {
                bestDistance = abs(y - mouseY);
                clickedOnSplitterIndex = i;
                bestY = y;
            }
            y += [self dividerThickness];
        }
        y = bestY;
    }

    // mouseDown blocks and lets the user drag things around.
    assert(clickedOnSplitterIndex >= 0);
    [super mouseDown:theEvent];

    // See how much the view after the splitter moved
    NSSize changePx = NSZeroSize;
    NSRect frame = [[subviews objectAtIndex:clickedOnSplitterIndex] frame];
    if ([self isVertical]) {
        changePx.width = (frame.origin.x + frame.size.width) - x;
    } else {
        changePx.height = (frame.origin.y + frame.size.height) - y;
    }

    // Run our delegate method.
    [[self delegate] splitView:self
         draggingDidEndOfSplit:clickedOnSplitterIndex
                        pixels:changePx];
}

@end


