//
//  iTermCursorBlinkFadeCurveIcon.m
//  iTerm2
//

#import "iTermCursorBlinkFadeCurveIcon.h"

@implementation iTermCursorBlinkFadeCurveIcon

+ (NSImage *)imageForCurve:(iTermCursorBlinkFadeCurve)curve fadeOut:(BOOL)fadeOut {
    const NSSize size = NSMakeSize(26, 16);
    NSImage *image = [NSImage imageWithSize:size
                                    flipped:NO
                             drawingHandler:^BOOL(NSRect dstRect) {
        const CGFloat inset = 2.0;
        const CGFloat left = NSMinX(dstRect) + inset;
        const CGFloat bottom = NSMinY(dstRect) + inset;
        const CGFloat plotWidth = NSWidth(dstRect) - inset * 2.0;
        const CGFloat plotHeight = NSHeight(dstRect) - inset * 2.0;

        NSBezierPath *path = [NSBezierPath bezierPath];
        const NSInteger samples = 32;
        for (NSInteger i = 0; i <= samples; i++) {
            const CGFloat t = (CGFloat)i / (CGFloat)samples;
            CGFloat y = [iTermCursorBlinkFadeAnimator easedProgressForCurve:curve atProgress:t];
            if (fadeOut) {
                // x axis is time, y axis is opacity. Fade-out falls from 1 to 0,
                // which is the fade-in shape flipped vertically.
                y = 1.0 - y;
            }
            const NSPoint point = NSMakePoint(left + t * plotWidth,
                                              bottom + y * plotHeight);
            if (i == 0) {
                [path moveToPoint:point];
            } else {
                [path lineToPoint:point];
            }
        }
        path.lineWidth = 1.25;
        path.lineCapStyle = NSLineCapStyleRound;
        path.lineJoinStyle = NSLineJoinStyleRound;
        // Color is irrelevant for a template image; the menu tints it to match
        // the text color and selection state.
        [[NSColor blackColor] set];
        [path stroke];
        return YES;
    }];
    image.template = YES;
    return image;
}

@end
