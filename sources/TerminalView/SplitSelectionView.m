//
//  SplitSelectionView.m
//  iTerm2
//
//  Created by George Nachman on 8/26/11.
//

#import "SplitSelectionView.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSColor+iTerm.h"

static CGFloat SplitHalfDistanceFromEdge(SplitSessionHalf half, NSSize size, NSPoint point) {
    switch (half) {
        case kWestHalf:
            return point.x;
        case kEastHalf:
            return size.width - point.x;
        case kSouthHalf:
            return point.y;
        case kNorthHalf:
            return size.height - point.y;
        case kNoHalf:
        case kFullPane:
        case kTabTopEdge:
        case kTabBottomEdge:
        case kTabLeftEdge:
        case kTabRightEdge:
            return INFINITY;
    }
    return INFINITY;
}

BOOL SplitSessionHalfIsTabEdge(SplitSessionHalf half) {
    switch (half) {
        case kTabTopEdge:
        case kTabBottomEdge:
        case kTabLeftEdge:
        case kTabRightEdge:
            return YES;
        case kNoHalf:
        case kNorthHalf:
        case kSouthHalf:
        case kEastHalf:
        case kWestHalf:
        case kFullPane:
            return NO;
    }
    return NO;
}

BOOL SplitSessionHalfTabEdgeIsVertical(SplitSessionHalf half) {
    return (half == kTabLeftEdge || half == kTabRightEdge);
}

BOOL SplitSessionHalfTabEdgeIsBefore(SplitSessionHalf half) {
    return (half == kTabTopEdge || half == kTabLeftEdge);
}

@interface SplitSelectionView ()

- (void)_createTrackingArea;

@end

@implementation SplitSelectionView {
    SplitSessionHalf half_;
    NSTrackingArea *trackingArea_;
    id<SplitSelectionViewDelegate> delegate_;  // weak
    __weak PTYSession *session_;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        half_ = kNoHalf;
        _mode = SplitSelectionViewModeTargetMove;
        [self setAlphaValue:0.9];
    }
    return self;
}

- (instancetype)initWithMode:(SplitSelectionViewMode)mode
                   withFrame:(NSRect)frame
                     session:(PTYSession *)session
                    delegate:(id<SplitSelectionViewDelegate>)delegate {
    self = [self initWithFrame:frame];
    if (self) {
        _mode = mode;
        session_ = session;
        delegate_ = delegate;
        [self _createTrackingArea];
    }
    return self;
}

- (void)_createTrackingArea
{
    NSRect frame = self.frame;
    trackingArea_ = [[NSTrackingArea alloc] initWithRect:NSMakeRect(0, 0, frame.size.width, frame.size.height)
                                                 options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInActiveApp
                                                  owner:self
                                                   userInfo:nil];
    [self addTrackingArea:trackingArea_];
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    if (trackingArea_) {
        [self removeTrackingArea:trackingArea_];
        trackingArea_ = nil;
        [self _createTrackingArea];
    }
}

- (void)_showMessage:(NSString *)message inRect:(NSRect)frame
{
    [[NSColor whiteColor] set];
    NSMutableParagraphStyle *pStyle = [[NSMutableParagraphStyle alloc] init];
    [pStyle setParagraphStyle:[NSParagraphStyle defaultParagraphStyle]];
    [pStyle setAlignment:NSTextAlignmentCenter];

    CGFloat fontSize = 25;
    NSMutableAttributedString* attributedString;
    NSRect rect;
    do {
        fontSize--;
        NSDictionary* attrs =
            [NSDictionary dictionaryWithObjectsAndKeys:
                [NSFont systemFontOfSize:fontSize], NSFontAttributeName,
                [NSColor whiteColor], NSForegroundColorAttributeName,
                pStyle, NSParagraphStyleAttributeName,
                nil];
        attributedString = [[NSMutableAttributedString alloc] initWithString:message
                                                                  attributes:attrs];
        rect = NSMakeRect(frame.origin.x,
                          frame.origin.y + frame.size.height * 2.0 / 3.0,
                          frame.size.width,
                          attributedString.size.height);
        if (fontSize < 8) {
            break;
        }
    } while ([attributedString size].width > frame.size.width ||
             [attributedString size].height > frame.size.height ||
             rect.size.height + rect.origin.y > frame.origin.y + frame.size.height);


    NSShadow *theShadow = [[NSShadow  alloc] init];
    [theShadow setShadowOffset:NSMakeSize(0, 0)];
    [theShadow setShadowBlurRadius:4.0];
    [theShadow setShadowColor:[NSColor blackColor]];
    [theShadow set];
    [attributedString drawWithRect:rect
                           options:0];
}

- (void)drawRect:(NSRect)dirtyRect {
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
    switch (_mode) {
        case SplitSelectionViewModeSourceMove:
            [self drawSourceWithMessage:@"Select a destination pane" rect:dirtyRect];
            return;
        case SplitSelectionViewModeSourceSwap:
            [self drawSourceWithMessage:@"Select pane to swap with" rect:dirtyRect];
            return;
        case SplitSelectionViewModeTargetMove:
            [self drawTargetWithMessage:@"Click to move source pane to this split"];
            return;
        case SplitSelectionViewModeTargetSwap:
            [self drawTargetWithMessage:@"Click to swap source pane with this one"];
            return;
        case SplitSelectionViewModeInspect:
            [self drawInspectWithMessage:@"Click to inspect" rect:dirtyRect];
            return;
        case SplitSelectionViewModeSelect:
            [self drawInspectWithMessage:@"Click to select" rect:dirtyRect];
            return;
    }
}

- (void)drawSourceWithMessage:(NSString *)message rect:(NSRect)dirtyRect {
    NSString *hexColor = [iTermAdvancedSettingsModel splitPaneSourceFillColor];
    NSColor *color = [NSColor colorFromHexString:hexColor];
    [color ?: [NSColor colorWithCalibratedRed:0 green:0.5 blue:0 alpha:1] set];
    NSRectFill(dirtyRect);
    
    NSRect highlightRect = self.frame;
    hexColor = [iTermAdvancedSettingsModel splitPaneSourceBorderColor];
    color = [NSColor colorFromHexString:hexColor];
    [color ?: [NSColor whiteColor] set];
    NSFrameRect(highlightRect);
    
    highlightRect = NSInsetRect(highlightRect, 1, 1);
    hexColor = [iTermAdvancedSettingsModel splitPaneSourceInnerBorderColor];
    color = [NSColor colorFromHexString:hexColor];
    [color ?: [NSColor blackColor] set];
    NSFrameRect(highlightRect);
    
    [self _showMessage:message inRect:self.frame];
}

- (void)drawTargetWithMessage:(NSString *)theMessage {
    NSRect highlightRect;
    NSRect clearRect;
    // Drawing happens in bounds coordinates. The tab-spanning drop target has a
    // non-zero origin; panes are at (0, 0), where bounds and frame agree.
    NSRect rect = self.bounds;
    switch (half_) {
        case kNoHalf:
        // A whole-tab drop target spans more than this pane so the tab draws it.
        case kTabTopEdge:
        case kTabBottomEdge:
        case kTabLeftEdge:
        case kTabRightEdge:
            highlightRect = NSZeroRect;
            clearRect = rect;
            break;

        case kSouthHalf:
            NSDivideRect(rect, &highlightRect, &clearRect, rect.size.height / 2, NSMinYEdge);
            break;

        case kNorthHalf:
            NSDivideRect(rect, &highlightRect, &clearRect, rect.size.height / 2, NSMaxYEdge);
            break;

        case kWestHalf:
            NSDivideRect(rect, &highlightRect, &clearRect, rect.size.width / 2, NSMinXEdge);
            break;

        case kEastHalf:
            NSDivideRect(rect, &highlightRect, &clearRect, rect.size.width / 2, NSMaxXEdge);
            break;

        case kFullPane:
            highlightRect = rect;
            clearRect = NSZeroRect;
            break;
    }

    NSString *hexColor = [iTermAdvancedSettingsModel splitPaneTargetDropFillColor];
    NSColor *color = [NSColor colorFromHexString:hexColor];
    [color ?: [NSColor colorWithCalibratedRed:0.5 green:0 blue:0 alpha:1] set];
    NSRectFill(highlightRect);

    hexColor = [iTermAdvancedSettingsModel splitPaneTargetDropBorderColor];
    color = [NSColor colorFromHexString:hexColor];
    [color ?: [NSColor whiteColor] set];
    NSFrameRect(highlightRect);

    highlightRect = NSInsetRect(highlightRect, 1, 1);
    hexColor = [iTermAdvancedSettingsModel splitPaneTargetDropInnerBorderColor];
    color = [NSColor colorFromHexString:hexColor];
    [color ?: [NSColor blackColor] set];
    NSFrameRect(highlightRect);

    if (delegate_ && !NSIsEmptyRect(highlightRect)) {
        [self _showMessage:theMessage inRect:highlightRect];
    }
}

- (void)drawInspectWithMessage:(NSString *)message rect:(NSRect)dirtyRect {
    [[NSColor colorWithCalibratedRed:0 green:0.5 blue:0.25 alpha:1] set];
    NSRectFill(dirtyRect);
    [self _showMessage:message inRect:self.frame];
}


- (void)mouseDown:(NSEvent *)theEvent
{
    if (delegate_) {
        [delegate_ didSelectDestinationSession:session_ half:half_];
    }
}

- (void)mouseEntered:(NSEvent *)theEvent
{
    [self mouseMoved:theEvent];
}

- (void)mouseExited:(NSEvent *)theEvent
{
    [self setHalf:kNoHalf];
}

- (void)mouseMoved:(NSEvent *)theEvent
{
    NSPoint locationInWindow = [theEvent locationInWindow];
    NSPoint point = [self convertPoint:locationInWindow fromView:nil];
    [self updateAtPoint:point];
}

// Extra distance a tab edge keeps its selection for after the pointer leaves
// its zone, so that a pointer wobbling on the boundary does not flicker between
// a whole-tab drop and a half-pane drop.
static const CGFloat kTabEdgeHysteresis = 6;

// A pane may be short or narrow, in which case an absolute zone could swallow
// the whole thing and make half-pane drops unreachable.
static const CGFloat kMaxTabEdgeZoneFraction = 0.33;

- (SplitSessionHalf)tabEdgeAtPoint:(NSPoint)point zone:(CGFloat)zone {
    const NSSize size = self.frame.size;
    const struct {
        iTermTabEdgeMask mask;
        SplitSessionHalf half;
        CGFloat distance;
        CGFloat extent;
    } candidates[] = {
        { iTermTabEdgeMaskTop, kTabTopEdge, size.height - point.y, size.height },
        { iTermTabEdgeMaskBottom, kTabBottomEdge, point.y, size.height },
        { iTermTabEdgeMaskLeft, kTabLeftEdge, point.x, size.width },
        { iTermTabEdgeMaskRight, kTabRightEdge, size.width - point.x, size.width }
    };
    SplitSessionHalf best = kNoHalf;
    CGFloat bestDistance = INFINITY;
    for (size_t i = 0; i < sizeof(candidates) / sizeof(*candidates); i++) {
        if (!(_tabEdges & candidates[i].mask)) {
            continue;
        }
        const CGFloat maximumZone = candidates[i].extent * kMaxTabEdgeZoneFraction;
        CGFloat limit = MIN(zone, maximumZone);
        if (half_ == candidates[i].half) {
            limit = MIN(zone + kTabEdgeHysteresis, maximumZone);
        }
        if (candidates[i].distance > limit) {
            continue;
        }
        if (candidates[i].distance < bestDistance) {
            bestDistance = candidates[i].distance;
            best = candidates[i].half;
        }
    }
    return best;
}

- (void)setHalf:(SplitSessionHalf)half {
    if (half == half_) {
        return;
    }
    const BOOL wasTabEdge = SplitSessionHalfIsTabEdge(half_);
    half_ = half;
    [self setNeedsDisplay:YES];
    const BOOL isTabEdge = SplitSessionHalfIsTabEdge(half_);
    if ((wasTabEdge || isTabEdge) && self.tabEdgeDidChange) {
        self.tabEdgeDidChange(isTabEdge ? half_ : kNoHalf);
    }
}

- (void)updateAtPoint:(NSPoint)point
{
    switch (_mode) {
        case SplitSelectionViewModeTargetSwap:
        case SplitSelectionViewModeSourceSwap:
        case SplitSelectionViewModeInspect:
        case SplitSelectionViewModeSelect:
            [self setHalf:kFullPane];
            return;

        case SplitSelectionViewModeTargetMove:
        case SplitSelectionViewModeSourceMove:
            break;
    }
    // Only a target offers tab edges: the source pane’s overlay ignores half_ and
    // clicking it cancels, so a whole-tab highlight there would be misleading.
    if (_mode == SplitSelectionViewModeTargetMove && _tabEdges != iTermTabEdgeMaskNone) {
        const CGFloat zone = [iTermAdvancedSettingsModel tabEdgeDropZoneSize];
        if (zone > 0) {
            const SplitSessionHalf edge = [self tabEdgeAtPoint:point zone:zone];
            if (edge != kNoHalf) {
                [self setHalf:edge];
                return;
            }
        }
        if (SplitSessionHalfIsTabEdge(half_)) {
            // Left the zone: give up the whole-tab target before choosing a half
            // below, so the tab stops drawing it.
            [self setHalf:kNoHalf];
        }
    }
    SplitSessionHalf possibilities[4];
    CGFloat scores[4];
    CGFloat distances[4];
    int numPossibilities = 0;
    if (point.x < self.frame.size.width / 2) {
        scores[numPossibilities] = point.x / self.frame.size.width;
        distances[numPossibilities] = point.x;
        possibilities[numPossibilities++] = kWestHalf;
    } else {
        scores[numPossibilities] = (self.frame.size.width - point.x) / self.frame.size.width;
        distances[numPossibilities] = self.frame.size.width - point.x;
        possibilities[numPossibilities++] = kEastHalf;
    }
    if (point.y < self.frame.size.height / 2) {
        scores[numPossibilities] = point.y / self.frame.size.height;
        distances[numPossibilities] = point.y;
        possibilities[numPossibilities++] = kSouthHalf;
    } else {
        scores[numPossibilities] = (self.frame.size.height - point.y) / self.frame.size.height;
        distances[numPossibilities] = self.frame.size.height - point.y;
        possibilities[numPossibilities++] = kNorthHalf;
    }

    CGFloat minScore = INFINITY;
    int bestIndex = 0;
    for (int i = 0; i < numPossibilities; i++) {
        if (scores[i] < minScore) {
            minScore = scores[i];
            bestIndex = i;
        }
    }

    if (half_ == possibilities[bestIndex] || minScore >= 0.4) {
        return;
    }
    // Dead zone around diagonal boundaries, with a minimum size for small panes.
    const NSSize size = self.frame.size;
    const CGFloat currentDist = SplitHalfDistanceFromEdge(half_, size, point);
    const CGFloat kHysteresisFraction = 0.05;
    const CGFloat kHysteresisMinPx = 8.0;
    const CGFloat minDim = MIN(size.width, size.height);
    const CGFloat hysteresis = MAX(kHysteresisFraction * minDim, kHysteresisMinPx);
    const BOOL switchNow = (currentDist == INFINITY || distances[bestIndex] < currentDist - hysteresis);
    if (switchNow) {
        [self setHalf:possibilities[bestIndex]];
    }
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return YES;
}

- (NSView *)hitTest:(NSPoint)point {
    if (_clickThrough) {
        return nil;
    }
    return [super hitTest:point];
}

- (SplitSessionHalf)half
{
    return half_;
}

@end
