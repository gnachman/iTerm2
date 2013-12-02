//
//  PTYNoteView.m
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import "PTYNoteView.h"

static const CGFloat kMinWidth = 50;
static const CGFloat kMinHeight = 30;

@implementation PTYNoteView

@synthesize noteViewController = noteViewController_;
@synthesize point = point_;

- (NSColor *)backgroundColor {
    return [NSColor colorWithCalibratedRed:252.0/255.0
                                     green:250.0/255.0
                                      blue:198.0/255.0
                                     alpha:0.95];
}

static NSPoint MakeNotePoint(NSSize maxSize, CGFloat x, CGFloat y)
{
    return NSMakePoint(0.5 + x, maxSize.height + 4.5 - y);
}

static NSPoint ModifyNotePoint(NSPoint p, CGFloat dx, CGFloat dy)
{
    return NSMakePoint(p.x + dx, p.y - dy);
}

- (NSRect)visibleFrame {
    NSRect frame = self.frame;
    frame.size.width -= 5;
    frame.size.height -= 5;
    return frame;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];

    NSBezierPath* path = [[[NSBezierPath alloc] init] autorelease];
    NSSize size = [self visibleFrame].size;
    CGFloat radius = 5;
    CGFloat arrowWidth = 10;
    CGFloat arrowHeight = 7;
    CGFloat topOffset = arrowHeight;
    CGFloat bottomOffset = 0;
    
    CGFloat height = self.frame.size.height;

    [path appendBezierPathWithRoundedRect:NSMakeRect(0,
                                                     bottomOffset + 5,
                                                     size.width,
                                                     size.height - (topOffset + bottomOffset))
                                  xRadius:radius
                                  yRadius:radius];
    [[self backgroundColor] set];
    [path fill];
    
    [[NSColor colorWithCalibratedRed:255.0/255.0 green:229.0/255.0 blue:114.0/255.0 alpha:0.95] set];
    [path setLineWidth:1];
    [path stroke];

    NSPoint base1;
    NSPoint base2;
    NSPoint tip;
    
    base1 = NSMakePoint(point_.x - arrowWidth / 2, height - arrowHeight - 1);
    base2 = NSMakePoint(point_.x + arrowWidth / 2, height - arrowHeight - 1);
    if (base2.x > size.width - radius) {
        CGFloat overage = base2.x - (size.width - radius);
        base1.x -= overage;
        base2.x -= overage;
    }
    if (base1.x < radius) {
        base1.x += radius;
        base2.x += radius;
    }
    tip = NSMakePoint(point_.x, height - point_.y);
    
    path = [[[NSBezierPath alloc] init] autorelease];
    [path moveToPoint:base1];
    [path lineToPoint:tip];
    [path lineToPoint:base2];
    [path lineToPoint:base1];
    [[self backgroundColor] set];
    [path fill];

    path = [[[NSBezierPath alloc] init] autorelease];
    [path moveToPoint:base1];
    [path lineToPoint:tip];
    [path lineToPoint:base2];
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
                                MAX(kMinWidth, ceil(originalSize_.width + dw)),
                                MAX(kMinHeight, ceil(originalSize_.height + dh)));
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

- (void)setPoint:(NSPoint)point {
    point_ = point;
    [self setNeedsDisplay:YES];
}

@end
