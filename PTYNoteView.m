//
//  PTYNoteView.m
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import "PTYNoteView.h"

@implementation PTYNoteView

@synthesize delegate = delegate_;

- (NSColor *)backgroundColor {
    return [NSColor colorWithCalibratedRed:252.0/255.0
                                     green:250.0/255.0
                                      blue:198.0/255.0
                                     alpha:0.95];
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];

    NSBezierPath* path = [[[NSBezierPath alloc] init] autorelease];
    NSSize size = self.frame.size;
    size.width -= 5;
    size.height -= 5;
    CGFloat radius = 5;
    CGFloat arrowWidth = 10;
    CGFloat arrowHeight = 7;
    CGFloat offset = 0.5;
    CGFloat yoffset = 4.5;

    [path moveToPoint:NSMakePoint(offset + 0, yoffset + size.height)];
    [path lineToPoint:NSMakePoint(offset + size.width - radius, yoffset + size.height)];
    [path curveToPoint:NSMakePoint(offset + size.width, yoffset + size.height - radius)
         controlPoint1:NSMakePoint(offset + size.width, yoffset + size.height)
         controlPoint2:NSMakePoint(offset + size.width, yoffset + size.height)];
    [path lineToPoint:NSMakePoint(offset + size.width, yoffset + radius)];
    [path curveToPoint:NSMakePoint(offset + size.width - radius, yoffset + 0)
         controlPoint1:NSMakePoint(offset + size.width, yoffset + 0)
         controlPoint2:NSMakePoint(offset + size.width, yoffset + 0)];
    [path lineToPoint:NSMakePoint(offset + arrowWidth + radius, yoffset + 0)];
    [path curveToPoint:NSMakePoint(offset + arrowWidth, yoffset + radius)
         controlPoint1:NSMakePoint(offset + arrowWidth, yoffset + 0)
         controlPoint2:NSMakePoint(offset + arrowWidth, yoffset + 0)];
    [path lineToPoint:NSMakePoint(offset + arrowWidth, yoffset + size.height - arrowHeight)];
    [path lineToPoint:NSMakePoint(offset + 0, yoffset + size.height)];
    
	[[self backgroundColor] set];
    [path fill];

	[[NSColor colorWithCalibratedRed:255.0/255.0 green:229.0/255.0 blue:114.0/255.0 alpha:0.95] set];
    [path setLineWidth:1];
    [path stroke];
}

@end
