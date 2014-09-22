//
//  FindCursorView.m
//  iTerm
//
//  Created by George Nachman on 12/26/13.
//
//

#import "FindCursorView.h"

// When performing the "find cursor" action, a gray window is shown with a
// transparent "hole" around the cursor. This is the radius of that hole in
// pixels.
const double kFindCursorHoleRadius = 30;

@implementation FindCursorView

@synthesize cursor;

- (void)drawRect:(NSRect)dirtyRect
{
    const double initialAlpha = 0.7;
    NSGradient *grad = [[NSGradient alloc] initWithStartingColor:[NSColor whiteColor]
                                                     endingColor:[NSColor blackColor]];
    NSPoint relativeCursorPosition = NSMakePoint(2 * (cursor.x / self.frame.size.width - 0.5),
                                                 2 * (cursor.y / self.frame.size.height - 0.5));
    [grad drawInRect:NSMakeRect(0, 0, self.frame.size.width, self.frame.size.height)
        relativeCenterPosition:relativeCursorPosition];
    [grad release];
    
    double x = cursor.x;
    double y = cursor.y;
    
    const double numSteps = 1;
    const double stepSize = 1;
    const double initialRadius = kFindCursorHoleRadius + numSteps * stepSize;
    double a = initialAlpha;
    for (double focusRadius = initialRadius;
         a > 0 && focusRadius >= initialRadius - numSteps * stepSize;
         focusRadius -= stepSize) {
        [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeCopy];
        NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - focusRadius,
                                                                                 y - focusRadius,
                                                                                 focusRadius * 2,
                                                                                 focusRadius * 2)];
        a -= initialAlpha / numSteps;
        a = MAX(0, a);
        [[NSColor colorWithDeviceWhite:0.5 alpha:a] set];
        [circle fill];
    }
}
@end
