//
//  PTYSplitView.m
//  iTerm
//
//  Created by George Nachman on 12/10/11.
//

#import "PTYSplitView.h"
#import "DebugLogging.h"
#import "iTermPreferences.h"

@implementation PTYSplitView

@dynamic delegate;

- (NSColor *)dividerColor {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    switch (preferredStyle) {
        case TAB_STYLE_LIGHT:
        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            return [NSColor lightGrayColor];
            break;
        case TAB_STYLE_DARK:
        case TAB_STYLE_DARK_HIGH_CONTRAST:
            return [NSColor darkGrayColor];
            break;
    }
}

- (NSString *)description
{
    NSMutableString *d = [NSMutableString stringWithString:@"<PTYSplitView "];
    [d appendFormat:@"<%@:%p frame:%@ splitter:%@ [",
        [self class],
        self,
        [NSValue valueWithRect:[self frame]],
        [self isVertical] ? @"|" : @"--"];
    for (NSView *view in [self subviews]) {
        [d appendFormat:@" (%@)", [view description]];
    }
    [d appendFormat:@">"];
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
    NSPoint locationInView = [self convertPoint:locationInWindow fromView:nil];
    int x = 0;
    int y = 0;
    int bestDistance = -1;
    const BOOL isVertical = [self isVertical];
    if (isVertical) {
        int mouseX = locationInView.x;
        x = 0;
        int bestX = 0;
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
        int bestY = 0;
        y = 0;
        for (int i = 0; i < subviews.count - 1; i++) {
            float subviewHeight = [[subviews objectAtIndex:i] frame].size.height;
            y += subviewHeight;
            if (bestDistance < 0 || abs(y - mouseY) < bestDistance) {
                bestDistance = abs(y - mouseY);
                clickedOnSplitterIndex = i;
                bestY = y;
            }
            y += [self dividerThickness];
        }
        y = bestY;
    }

    [[self delegate] splitView:self draggingWillBeginOfSplit:clickedOnSplitterIndex];

    // mouseDown blocks and lets the user drag things around.
    if (clickedOnSplitterIndex < 0) {
        // You don't seem to have clicked on a splitter.
        DLog(@"Click in PTYSplitView was not on splitter");
        return;
    }
    [super mouseDown:theEvent];

    // See how much the view after the splitter moved
    NSSize changePx = NSZeroSize;
    NSRect frame = [[subviews objectAtIndex:clickedOnSplitterIndex] frame];
    if (isVertical) {
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


