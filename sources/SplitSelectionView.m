//
//  SplitSelectionView.m
//  iTerm2
//
//  Created by George Nachman on 8/26/11.
//

#import "SplitSelectionView.h"

@interface SplitSelectionView ()

- (void)_createTrackingArea;

@end

@implementation SplitSelectionView {
    SplitSessionHalf half_;
    NSTrackingArea *trackingArea_;
    id<SplitSelectionViewDelegate> delegate_;  // weak
    __unsafe_unretained PTYSession *session_;
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

- (void)dealloc
{
    [trackingArea_ release];
    [super dealloc];
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
        [trackingArea_ release];
        [self _createTrackingArea];
    }
}

- (void)_showMessage:(NSString *)message inRect:(NSRect)frame
{
    [[NSColor whiteColor] set];
    NSMutableParagraphStyle *pStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
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
        attributedString = [[[NSMutableAttributedString alloc] initWithString:message
                                                                   attributes:attrs] autorelease];
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


    NSShadow *theShadow = [[[NSShadow  alloc] init] autorelease];
    [theShadow setShadowOffset:NSMakeSize(0, 0)];
    [theShadow setShadowBlurRadius:4.0];
    [theShadow setShadowColor:[NSColor blackColor]];
    [theShadow set];
    [attributedString drawWithRect:rect
                           options:0];
}

- (void)drawRect:(NSRect)dirtyRect {
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
    }
}

- (void)drawSourceWithMessage:(NSString *)message rect:(NSRect)dirtyRect {
    [[NSColor colorWithCalibratedRed:0 green:0.5 blue:0 alpha:1] set];
    NSRectFill(dirtyRect);
    [self _showMessage:message inRect:self.frame];
}

- (void)drawTargetWithMessage:(NSString *)theMessage {
    NSRect highlightRect;
    NSRect clearRect;
    NSRect rect = [self frame];
    switch (half_) {
        case kNoHalf:
            highlightRect = NSZeroRect;
            clearRect = rect;
            break;

        case kSouthHalf:
            NSDivideRect([self frame], &highlightRect, &clearRect, rect.size.height / 2, NSMinYEdge);
            break;

        case kNorthHalf:
            NSDivideRect([self frame], &highlightRect, &clearRect, rect.size.height / 2, NSMaxYEdge);
            break;

        case kWestHalf:
            NSDivideRect([self frame], &highlightRect, &clearRect, rect.size.width / 2, NSMinXEdge);
            break;

        case kEastHalf:
            NSDivideRect([self frame], &highlightRect, &clearRect, rect.size.width / 2, NSMaxXEdge);
            break;

        case kFullPane:
            highlightRect = [self frame];
            clearRect = NSZeroRect;
            break;
    }

    [[NSColor colorWithCalibratedRed:0.5 green:0 blue:0 alpha:1] set];
    NSRectFill(highlightRect);

    [[NSColor whiteColor] set];
    NSFrameRect(highlightRect);

    highlightRect = NSInsetRect(highlightRect, 1, 1);
    [[NSColor blackColor] set];
    NSFrameRect(highlightRect);

    if (delegate_ && half_ != kNoHalf) {
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
    half_ = kNoHalf;
    [self setNeedsDisplay:YES];
}

- (void)mouseMoved:(NSEvent *)theEvent
{
    NSPoint locationInWindow = [theEvent locationInWindow];
    NSPoint point = [self convertPoint:locationInWindow fromView:nil];
    [self updateAtPoint:point];
}

- (void)updateAtPoint:(NSPoint)point
{
    switch (_mode) {
        case SplitSelectionViewModeTargetSwap:
        case SplitSelectionViewModeSourceSwap:
        case SplitSelectionViewModeInspect:
            half_ = kFullPane;
            [self setNeedsDisplay:YES];
            return;

        case SplitSelectionViewModeTargetMove:
        case SplitSelectionViewModeSourceMove:
            break;
    }
    SplitSessionHalf possibilities[4];
    CGFloat scores[4];
    int numPossibilities = 0;
    if (point.x < self.frame.size.width / 2) {
        scores[numPossibilities] = point.x / self.frame.size.width;
        possibilities[numPossibilities++] = kWestHalf;
    } else {
        scores[numPossibilities] = (self.frame.size.width - point.x) / self.frame.size.width;
        possibilities[numPossibilities++] = kEastHalf;
    }
    if (point.y < self.frame.size.height / 2) {
        scores[numPossibilities] = point.y / self.frame.size.height;
        possibilities[numPossibilities++] = kSouthHalf;
    } else {
        scores[numPossibilities] = (self.frame.size.height - point.y) / self.frame.size.height;
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

    if (half_ != possibilities[bestIndex] && minScore < 0.4) {
      half_ = possibilities[bestIndex];
      [self setNeedsDisplay:YES];
    }
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return YES;
}

- (SplitSessionHalf)half
{
    return half_;
}

@end
