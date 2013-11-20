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

- (void)mouseDown:(NSEvent *)theEvent {
    const CGFloat horizontalRegionWidth = self.bounds.size.width - 10;
    NSRect rightDragRegion = NSMakeRect(horizontalRegionWidth, 5, 10, self.bounds.size.height - 10);
    NSRect bottomRightDragRegion = NSMakeRect(horizontalRegionWidth, 0, 10, 5);
    NSRect bottomDragRegion = NSMakeRect(0, 0, horizontalRegionWidth, 5);
    struct {
        NSRect rect;
        BOOL horizontal;
        BOOL bottom;
    } regions[] = {
        { rightDragRegion, YES, NO },
        { bottomRightDragRegion, YES, YES },
        { bottomDragRegion, NO, YES }
    };
    NSPoint pointInView = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    for (int i = 0; i < sizeof(regions) / sizeof(*regions); i++) {
        if (NSPointInRect(pointInView, regions[i].rect)) {
            NSLog(@"Ok to drag.");
            dragRight_ = regions[i].horizontal;
            dragBottom_ = regions[i].bottom;
            dragOrigin_ = [theEvent locationInWindow];
            originalSize_ = self.frame.size;
            break;
        }
    }
}

- (void)mouseDragged:(NSEvent *)theEvent {
    if (dragRight_ || dragBottom_) {
        NSPoint point = [theEvent locationInWindow];
        CGFloat dw = dragRight_ ? point.x - dragOrigin_.x : 0;
        CGFloat dh = 0;
        if (dragBottom_) {
            dh = dragOrigin_.y - point.y;
        }
        self.frame = NSMakeRect(self.frame.origin.x,
                                self.frame.origin.y,
                                ceil(originalSize_.width + dw),
                                ceil(originalSize_.height + dh));
    }
}

- (void)resetCursorRects {
    const CGFloat horizontalRegionWidth = self.bounds.size.width - 10;
    NSRect rightDragRegion = NSMakeRect(horizontalRegionWidth, 5, 10, self.bounds.size.height - 10);
    NSRect bottomRightDragRegion = NSMakeRect(horizontalRegionWidth, 0, 10, 5);
    NSRect bottomDragRegion = NSMakeRect(0, 0, horizontalRegionWidth, 5);

    NSImage* image = [NSImage imageNamed:@"nw_se_resize_cursor"];
    static NSCursor *topRightDragCursor;
    if (!topRightDragCursor) {
        topRightDragCursor = [[NSCursor alloc] initWithImage:image hotSpot:NSMakePoint(8, 8)];
    }

    [self addCursorRect:bottomDragRegion cursor:[NSCursor resizeUpDownCursor]];
    [self addCursorRect:bottomRightDragRegion cursor:topRightDragCursor];
    [self addCursorRect:rightDragRegion cursor:[NSCursor resizeLeftRightCursor]];
}

@end
