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
    NSMutableString *d = [NSMutableString stringWithString:@"<PTYSplitView "];
    [d appendFormat:@"<PTYSplitView frame:%@ splitter:%@ [", [NSValue valueWithRect:[self frame]], [self isVertical] ? @"|" : @"--"];
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
    NSPoint locationInView = [self convertPoint:locationInWindow toView:self];
    int x, y;
    int bestDistance = -1;
    if ([self isVertical]) {
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
        for (int i = subviews.count - 1; i >= 0; i--) {
            float subviewHeight = [[subviews objectAtIndex:i] frame].size.height;
            y += subviewHeight;
            if (bestDistance < 0 || abs(y - mouseY) < bestDistance) {
                bestDistance = abs(y - mouseY);
                clickedOnSplitterIndex = i - 1;
                bestY = y;
            }
            y += [self dividerThickness];
        }
        y = self.frame.size.height - bestY;
    }

    [[self delegate] splitView:self draggingWillBeginOfSplit:clickedOnSplitterIndex];

    // mouseDown blocks and lets the user drag things around.
    if (clickedOnSplitterIndex < 0) {
        // You don't seem to have clicked on a splitter.
        NSLog(@"Click in PTYSplitView was not on splitter");
        return;
    }
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

#if 0
// Don't need this unless the background behind the split view is a color other
// than windowBackgroundColor.
- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];

	// Draw splitters since the base class actually doesn't do that (it just
	// lets the background show through).
	BOOL isVertical = [self isVertical];
	double offset = 0;
	NSRect myFrame = self.frame;
	double dividerThickness = [self dividerThickness];
	[[NSColor windowBackgroundColor] set];
	for (NSView *v in [self subviews]) {
		NSRect rect;
		if (isVertical) {
			offset += v.frame.size.width;
		} else {
			offset += v.frame.size.height;
		}
		if (isVertical) {
			rect.origin.y = 0;
			rect.origin.x = offset;
			rect.size.width = dividerThickness;
			rect.size.height = myFrame.size.height;
		} else {
			rect.origin.x = 0;
			rect.origin.y = offset;
			rect.size.height = dividerThickness;
			rect.size.width = myFrame.size.width;
		}
		NSRectFill(rect);
		offset += dividerThickness;
	}
}
#endif

@end


