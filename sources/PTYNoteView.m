//
//  PTYNoteView.m
//  iTerm
//
//  Created by George Nachman on 11/18/13.
//
//

#import "PTYNoteView.h"
#import "iTermMouseCursor.h"

static const CGFloat kMinWidth = 50;
static const CGFloat kMinHeight = 33;

static const CGFloat kLeftMargin = 5;
static const CGFloat kRightMargin = 14;
static const CGFloat kTopMargin = 4;
static const CGFloat kBottomMargin = 0;
static const CGFloat kKillButtonTopMargin = 2;

static const CGFloat kInset = 5;
static const CGFloat kRadius = 5;
static const CGFloat kPointerBase = 7;
static const CGFloat kPointerLength = 7;

static const CGFloat kButtonSize = 17;

const CGFloat kDragAreaSize = 5;

@implementation PTYNoteView

@synthesize point = point_;
@synthesize contentView = contentView_;
@synthesize tipEdge = tipEdge_;
@synthesize delegate = delegate_;
@synthesize backgroundColor = backgroundColor_;

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        backgroundColor_ = [[self defaultBackgroundColor] retain];
        NSImage *closeImage = [NSImage imageNamed:@"closebutton"];
        killButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, kButtonSize, kButtonSize)];
        [killButton_ setButtonType:NSMomentaryPushInButton];
        [killButton_ setImage:closeImage];
        [killButton_ setTarget:self];
        [killButton_ setAction:@selector(kill:)];
        [killButton_ setBordered:NO];
        [[killButton_ cell] setHighlightsBy:NSContentsCellMask];
        [killButton_ setTitle:@""];
        [self addSubview:killButton_];
        [killButton_ release];
    }
    return self;
}

- (void)dealloc {
    [contentView_ release];
    [backgroundColor_ release];
    [super dealloc];
}

- (NSColor *)defaultBackgroundColor {
    return [NSColor colorWithCalibratedRed:252.0/255.0
                                     green:250.0/255.0
                                      blue:198.0/255.0
                                     alpha:1];
}

- (NSColor *)borderColor {
    return [NSColor colorWithCalibratedRed:255.0/255.0
                                     green:229.0/255.0
                                      blue:114.0/255.0
                                     alpha:0.95];
}

static NSPoint FlipPoint(NSPoint p, CGFloat height) {
    return NSMakePoint(p.x, height - p.y);
}

static NSRect FlipRect(NSRect rect, CGFloat height) {
    return NSMakeRect(rect.origin.x, height - NSMaxY(rect), rect.size.width, rect.size.height);
}

- (NSPoint)leadingCornerOfRoundedRect:(NSRect)frame
                               radius:(CGFloat)radius
                                   dx:(int)dx
                                   dy:(int)dy {
    assert(dx == 0 || dy == 0);
    assert((dx == 0) ^ (dy == 0));
    NSPoint p = frame.origin;
    if (dx > 0) {
        p.x = NSMaxX(frame) - radius;
        p.y = NSMinY(frame);
    } else if (dx < 0) {
        p.x = NSMinX(frame) + radius;
        p.y = NSMaxY(frame);
    } else if (dy > 0) {
        p.x = NSMaxX(frame);
        p.y = NSMaxY(frame) - radius;
    } else if (dy < 0) {
        p.x = NSMinX(frame);
        p.y = NSMinY(frame) + radius;
    }

    return p;
}

- (NSPoint)trailingCornerOfRoundedRect:(NSRect)frame
                                radius:(CGFloat)radius
                                    dx:(int)dx
                                    dy:(int)dy {
    assert(dx == 0 || dy == 0);
    assert((dx == 0) ^ (dy == 0));

    NSPoint p = frame.origin;
    if (dx > 0) {
        p.x = NSMaxX(frame);
        p.y = NSMinY(frame) + radius;
    } else if (dx < 0) {
        p.x = NSMinX(frame);
        p.y = NSMaxY(frame) - radius;
    } else if (dy > 0) {
        p.x = NSMaxX(frame) - radius;
        p.y = NSMaxY(frame);
    } else if (dy < 0) {
        p.x = NSMinX(frame) + radius;
        p.y = NSMinY(frame);
    }
    return p;
}

- (NSPoint)controlPointOfRect:(NSRect)rect forDx:(int)dx dy:(int)dy {
    if (dx == 0 && dy == -1) {
        return rect.origin;
    } else if (dx == 1 && dy == 0) {
        return NSMakePoint(NSMaxX(rect), NSMinY(rect));
    } else if (dx == 0 && dy == 1) {
        return NSMakePoint(NSMaxX(rect), NSMaxY(rect));
    } else if (dx == -1 && dy == 0) {
        return NSMakePoint(NSMinX(rect), NSMaxY(rect));
    } else {
        assert(false);
    }
}

- (NSPoint)projectionOfPoint:(NSPoint)p
                    ontoEdge:(PTYNoteViewTipEdge)edge
                     ofFrame:(NSRect)frame {
    switch (edge) {
        case kPTYNoteViewTipEdgeTop:
            return NSMakePoint(p.x, NSMinY(frame));

        case kPTYNoteViewTipEdgeLeft:
            return NSMakePoint(NSMinX(frame), p.y);

        case kPTYNoteViewTipEdgeBottom:
            return NSMakePoint(p.x, NSMaxY(frame));

        case kPTYNoteViewTipEdgeRight:
            return NSMakePoint(NSMaxX(frame), p.y);

        default:
            assert(false);
    }
}

- (NSRect)bubbleFrameInRect:(NSRect)frame
                      inset:(CGFloat)inset
              pointerLength:(CGFloat)pointerLength
                  tipOnEdge:(PTYNoteViewTipEdge)tipEdge {
    CGFloat left = frame.origin.x + 0.5;
    CGFloat top = frame.origin.y + 0.5;
    CGFloat right = NSMaxX(frame) - inset - 0.5;
    CGFloat bottom = NSMaxY(frame) - inset - 0.5;

    switch (tipEdge) {
        case kPTYNoteViewTipEdgeRight:
            right -= pointerLength;
            break;

        case kPTYNoteViewTipEdgeLeft:
            left += pointerLength;
            break;

        case kPTYNoteViewTipEdgeBottom:
            bottom -= pointerLength;
            break;

        case kPTYNoteViewTipEdgeTop:
            top += pointerLength;
            break;
    }
    NSRect bubbleFrame = NSMakeRect(left, top, right - left, bottom - top);
    return bubbleFrame;
}

- (NSBezierPath *)roundedRectangleWithPointerInRect:(NSRect)frame
                                              inset:(CGFloat)inset
                                             radius:(CGFloat)radius
                                        pointerBase:(CGFloat)pointerBase
                                      pointerLength:(CGFloat)pointerLength
                                       pointerTipAt:(NSPoint)tipPoint
                                          tipOnEdge:(PTYNoteViewTipEdge)tipEdge {
    CGFloat height = self.frame.size.height;
    NSPoint controlPoint;
    NSRect bubbleFrame = [self bubbleFrameInRect:frame
                                           inset:inset
                                   pointerLength:pointerLength
                                       tipOnEdge:tipEdge];
    NSBezierPath *path = [[[NSBezierPath alloc] init] autorelease];

    // start on the left edge
    NSPoint p = [self trailingCornerOfRoundedRect:bubbleFrame radius:radius dx:-1 dy:0];
    [path moveToPoint:FlipPoint(p, height)];

    struct {
        int dx, dy;
    } directions[4] = {
        { 0, -1 },  // left
        { 1, 0 },   // top
        { 0, 1 },   // right
        { -1, 0 }   // bottom
    };

    // Walk each side...
    for (int i = 0; i < 4; i++) {
        PTYNoteViewTipEdge edge = (PTYNoteViewTipEdge)i;
        int dx = directions[i].dx;
        int dy = directions[i].dy;

        // Get the location of the point just before the rounded rect at the end of this edge
        p = [self leadingCornerOfRoundedRect:bubbleFrame
                                      radius:radius
                                          dx:dx
                                          dy:dy];

        if (edge == tipEdge) {
            // This edge has the arrow. Compute the points where the arrow's base intersects
            // the edge.
            NSPoint baseCenter = [self projectionOfPoint:tipPoint
                                                ontoEdge:edge
                                                 ofFrame:bubbleFrame];
            NSPoint bases[2];
            bases[0] = NSMakePoint(baseCenter.x - dx * pointerBase / 2,
                                   baseCenter.y - dy * pointerBase / 2);
            bases[1] = NSMakePoint(baseCenter.x + dx * pointerBase / 2,
                                   baseCenter.y + dy * pointerBase / 2);

            // If the base is over the radius, scoot it away from the corner.
            for (int j = 0; j < 2; j++) {
                if (edge == kPTYNoteViewTipEdgeTop || edge == kPTYNoteViewTipEdgeBottom) {
                    if (bases[j].x < NSMinX(bubbleFrame) + radius) {
                        CGFloat error = NSMinX(bubbleFrame) + radius - bases[j].x;
                        bases[0].x += error;
                        bases[1].x += error;
                    }
                    if (bases[j].x > NSMaxX(bubbleFrame) - radius) {
                        CGFloat error = bases[j].x - (NSMaxX(bubbleFrame) - radius);
                        bases[0].x -= error;
                        bases[1].x -= error;
                    }
                } else {
                    // Left or right edge
                    if (bases[j].y < NSMinY(bubbleFrame) + radius) {
                        CGFloat error = NSMinY(bubbleFrame) + radius - bases[j].y;
                        bases[0].y += error;
                        bases[1].y += error;
                    }
                    if (bases[j].y > NSMaxY(bubbleFrame) - radius) {
                        CGFloat error = bases[j].y - (NSMaxY(bubbleFrame) - radius);
                        bases[0].y -= error;
                        bases[1].y -= error;
                    }
                }
            }

            // Draw the arrow
            [path lineToPoint:FlipPoint(bases[0], height)];
            [path lineToPoint:FlipPoint(tipPoint, height)];
            [path lineToPoint:FlipPoint(bases[1], height)];
        }

        // Line to just before the arc
        [path lineToPoint:FlipPoint(p, height)];

        // The control point is the corner of the bubbleFrame near the arc.
        controlPoint = [self controlPointOfRect:bubbleFrame forDx:dx dy:dy];
        p = [self trailingCornerOfRoundedRect:bubbleFrame
                                       radius:radius
                                           dx:dx
                                           dy:dy];

        // Draw the arc in the corner
        [path curveToPoint:FlipPoint(p, height)
             controlPoint1:FlipPoint(controlPoint, height)
             controlPoint2:FlipPoint(controlPoint, height)];
    }

    return path;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];

    NSBezierPath *path = [self roundedRectangleWithPointerInRect:self.bounds
                                                           inset:kInset
                                                          radius:kRadius
                                                     pointerBase:kPointerBase
                                                   pointerLength:kPointerLength
                                                    pointerTipAt:point_
                                                       tipOnEdge:[self tipEdge]];

    [[self backgroundColor] set];
    [path fill];

    [[self borderColor] set];
    [path setLineWidth:1];
    [path stroke];
}

- (void)mouseDown:(NSEvent *)theEvent {
    NSRect rightDragRegion = [self rightDragRect];
    NSRect bottomRightDragRegion = [self bottomRightDragRect];
    NSRect bottomDragRegion = [self bottomDragRect];
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

- (NSRect)rightDragRect {
    NSRect bubbleFrame = [self bubbleFrameInRect:self.bounds
                                           inset:0
                                   pointerLength:kPointerLength
                                       tipOnEdge:self.tipEdge];
    return FlipRect(NSMakeRect(NSMaxX(bubbleFrame) - kDragAreaSize,
                               NSMinY(bubbleFrame) + kDragAreaSize,
                               kDragAreaSize,
                               NSHeight(bubbleFrame) - 2 * kDragAreaSize),
                    self.frame.size.height);
}

- (NSRect)bottomRightDragRect {
    NSRect bubbleFrame = [self bubbleFrameInRect:self.bounds
                                           inset:0
                                   pointerLength:kPointerLength
                                       tipOnEdge:self.tipEdge];
    return FlipRect(NSMakeRect(NSMaxX(bubbleFrame) - kDragAreaSize,
                               NSMaxY(bubbleFrame) - kDragAreaSize,
                               kDragAreaSize,
                               kDragAreaSize),
                    self.frame.size.height);
}

- (NSRect)bottomDragRect {
    NSRect bubbleFrame = [self bubbleFrameInRect:self.bounds
                                           inset:0
                                   pointerLength:kPointerLength
                                       tipOnEdge:self.tipEdge];
    return FlipRect(NSMakeRect(NSMinX(bubbleFrame),
                               NSMaxY(bubbleFrame) - kDragAreaSize,
                               NSWidth(bubbleFrame) - kDragAreaSize,
                               kDragAreaSize),
                    self.frame.size.height);
}

- (void)resetCursorRects {
    NSRect rightDragRegion = [self rightDragRect];
    NSRect bottomRightDragRegion = [self bottomRightDragRect];
    NSRect bottomDragRegion = [self bottomDragRect];

    [self addCursorRect:bottomDragRegion cursor:[NSCursor resizeUpDownCursor]];
    [self addCursorRect:bottomRightDragRegion
                 cursor:[iTermMouseCursor mouseCursorOfType:iTermMouseCursorTypeNorthwestSoutheastArrow]];
    [self addCursorRect:rightDragRegion cursor:[NSCursor resizeLeftRightCursor]];
    [self addCursorRect:killButton_.frame cursor:[NSCursor arrowCursor]];
}

- (void)setPoint:(NSPoint)point {
    point_ = point;
    [self setNeedsDisplay:YES];
}

- (void)setContentView:(NSView *)contentView {
    [contentView_ removeFromSuperview];
    [contentView_ autorelease];
    contentView_ = [contentView retain];
    [self addSubview:contentView_];
    [self layoutSubviews];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [self layoutSubviews];
}

- (void)layoutSubviews {
    NSRect bubbleFrame = [self bubbleFrameInRect:self.bounds
                                           inset:kInset
                                   pointerLength:kPointerLength
                                       tipOnEdge:[self tipEdge]];
    bubbleFrame = NSIntegralRect(bubbleFrame);
    self.contentView.frame = FlipRect(NSMakeRect(NSMinX(bubbleFrame) + kLeftMargin,
                                                 NSMinY(bubbleFrame) + kTopMargin,
                                                 bubbleFrame.size.width - kLeftMargin - kRightMargin,
                                                 bubbleFrame.size.height - kTopMargin - kBottomMargin),
                                      self.frame.size.height);
    killButton_.frame = FlipRect(NSMakeRect(NSMaxX(bubbleFrame) - kButtonSize,
                                            NSMinY(bubbleFrame) + kKillButtonTopMargin,
                                            kButtonSize,
                                            kButtonSize),
                                 self.frame.size.height);
    [self.window invalidateCursorRectsForView:self];
}

- (NSSize)sizeThatFitsContentView {
    switch (tipEdge_) {
        case kPTYNoteViewTipEdgeBottom:
        case kPTYNoteViewTipEdgeTop:
            return NSMakeSize(contentView_.frame.size.width + kLeftMargin + kRightMargin + kInset,
                              contentView_.frame.size.height + kBottomMargin + kTopMargin + kPointerLength + kInset);

        case kPTYNoteViewTipEdgeLeft:
        case kPTYNoteViewTipEdgeRight:
            return NSMakeSize(contentView_.frame.size.width + kLeftMargin + kRightMargin + kPointerLength + kInset,
                              contentView_.frame.size.height + kBottomMargin + kTopMargin + kInset);
    }
    assert(false);
    return NSMakeSize(0, 0);
}

- (void)kill:(id)sender {
    [delegate_ killNote];
}

@end
