//
//  iTermWelcomCardActionButtonCell.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipCardActionButtonCell.h"

@implementation iTermTipCardActionButtonCell {
    NSTimeInterval _highlightStartTime;
}

+ (NSColor *)blueColor {
    return [NSColor colorWithCalibratedRed:0.25 green:0.25 blue:0.75 alpha:1];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    static const NSTimeInterval kHoldDuration = 0.25;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (self.isHighlighted) {
        _highlightStartTime = now;
        [self.controlView performSelector:@selector(setNeedsDisplay:) withObject:@1 afterDelay:kHoldDuration];
    }
    BOOL highlighted = self.isHighlighted || (now - _highlightStartTime < kHoldDuration);
    NSColor *foregroundColor = highlighted ? [NSColor whiteColor] : [self.class blueColor];
    NSColor *backgroundColor = highlighted ? [self.class blueColor] : [NSColor whiteColor];
    [backgroundColor set];
    NSRectFill(cellFrame);

    [[NSColor colorWithCalibratedWhite:0.85 alpha:1] set];
    NSRectFill(NSMakeRect(NSMinX(cellFrame), 0, NSWidth(cellFrame), 0.5));

    NSPoint imageOrigin = NSMakePoint(11, round((cellFrame.size.height - _icon.size.height) / 2));
    NSSize size = self.icon.size;
    CGFloat imageOffset = size.width + 7;
    [self.icon drawInRect:NSMakeRect(imageOrigin.x, imageOrigin.y, size.width, size.height)
                 fromRect:NSMakeRect(0, 0, size.width, size.height)
                operation:NSCompositeSourceOver
                 fraction:1
           respectFlipped:YES
                    hints:nil];

    NSColor *textColor = foregroundColor;
    NSFont *font = [NSFont fontWithName:@"Helvetica Neue" size:14];
    NSRect textRect = cellFrame;
    textRect.origin.x += _inset.width + imageOffset;
    textRect.origin.y += _inset.height;
    [self.title drawInRect:textRect withAttributes:@{ NSFontAttributeName: font,
                                                      NSForegroundColorAttributeName: textColor }];
    
}

@end
