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

@implementation SplitSelectionView

@synthesize cancelOnly = cancelOnly_;

- (id)initAsCancelOnly:(BOOL)cancelOnly
             withFrame:(NSRect)frame
           withSession:(PTYSession *)session
              delegate:(id<SplitSelectionViewDelegate>)delegate {
    self = [super initWithFrame:frame];
    if (self) {
      cancelOnly_ = cancelOnly;
      half_ = kNoHalf;
      session_ = session;
      delegate_ = delegate;
      [self _createTrackingArea];
      [self setAlphaValue:0.9];
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
    [self removeTrackingArea:trackingArea_];
    [trackingArea_ release];
    [self _createTrackingArea];
}

- (void)_showMessage:(NSString *)message inRect:(NSRect)frame
{
    [[NSColor whiteColor] set];
    NSMutableParagraphStyle *pStyle = [[NSMutableParagraphStyle alloc] init];
    [pStyle setParagraphStyle:[NSParagraphStyle defaultParagraphStyle]];
    [pStyle setAlignment:NSCenterTextAlignment];
    
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
    if (cancelOnly_) {
        [[NSColor colorWithCalibratedRed:0 green:0.5 blue:0 alpha:1] set];
        NSRectFill(dirtyRect);
        
        [self _showMessage:@"Select a destination pane" inRect:self.frame];
    } else {
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
        }
        
        [[NSColor colorWithCalibratedRed:0.5 green:0 blue:0 alpha:1] set];
        NSRectFill(highlightRect);

        [[NSColor whiteColor] set];
        NSFrameRect(highlightRect);
        
        highlightRect = NSInsetRect(highlightRect, 1, 1);
        [[NSColor blackColor] set];
        NSFrameRect(highlightRect);

        if (half_ != kNoHalf) {
            [self _showMessage:@"Click to split this pane and move source pane here" inRect:highlightRect];
        }
    }
}

- (void)mouseDown:(NSEvent *)theEvent
{
    [delegate_ didSelectDestinationSession:session_ half:half_];
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
    NSPoint point = [self convertPoint: locationInWindow fromView: nil];

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
    
    if (half_ != possibilities[bestIndex] && minScore < 0.25) {
      half_ = possibilities[bestIndex];
      [self setNeedsDisplay:YES];
    }
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    return YES;
}

@end
