//
//  iTermExposeTabView.m
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import "iTermExposeTabView.h"
#import "iTermController.h"
#import "iTermHotKeyController.h"
#import "iTermExpose.h"
#import "iTermExposeView.h"
#import "PseudoTerminal.h"

@implementation iTermExposeTabView {
    NSInteger tabIndex_;
    NSInteger windowIndex_;
    BOOL showLabel_;
    BOOL highlight_;
    id<iTermExposeTabViewDelegate> delegate_;
    BOOL hasResult_;
    NSSize origSize_;
}

@synthesize tabObject = tabObject_;
@synthesize dirty = dirty_;
@synthesize originalFrame = originalFrame_;
@synthesize normalFrame = normalFrame_;
@synthesize fullSizeFrame = fullSizeFrame_;
@synthesize image = image_;
@synthesize index = index_;
@synthesize label = label_;
@synthesize wasMaximized = wasMaximized_;
@synthesize trackingRectTag = trackingRectTag_;

- (instancetype)initWithImage:(NSImage*)image
              label:(NSString*)label
                tab:(PTYTab*)tab
              frame:(NSRect)frame
      fullSizeFrame:(NSRect)fullSizeFrame
        normalFrame:(NSRect)normalFrame
           delegate:(id<iTermExposeTabViewDelegate>)delegate
              index:(int)theIndex
       wasMaximized:(BOOL)wasMaximized {
    self = [super initWithFrame:frame];
    if (self) {
        wasMaximized_ = wasMaximized;
        image_ = [image retain];
        label_ = [label retain];
        tabIndex_ = [[tab realParentWindow] indexOfTab:tab];
        assert(tabIndex_ != NSNotFound);
        windowIndex_ = [[[iTermController sharedInstance] terminals] indexOfObjectIdenticalTo:(PseudoTerminal *)[tab realParentWindow]];
        fullSizeFrame_ = fullSizeFrame;
        normalFrame_ = normalFrame;
        showLabel_ = NO;
        originalFrame_ = frame;
        delegate_ = delegate;
        tabObject_ = tab;
        origSize_ = frame.size;
        index_ = theIndex;
    }
    return self;
}

- (void)dealloc
{
    [label_ release];
    [image_ release];

    [super dealloc];
}

- (void)setWindowIndex:(int)windowIndex tabIndex:(int)tabIndex
{
    windowIndex_ = windowIndex;
    tabIndex_ = tabIndex;
}

- (void)setHasResult:(BOOL)hasResult
{
    hasResult_ = hasResult;
}

- (void)clear
{
    windowIndex_ = -1;
    tabIndex_ = -1;
    NSSize size = [image_ size];
    [image_ release];
    image_ = [[NSImage alloc] initWithSize:size];
    [image_ lockFocus];
    [[[NSColor whiteColor] colorWithAlphaComponent:0] set];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    [image_ unlockFocus];
}

static BOOL RectsApproxEqual(NSRect a, NSRect b)
{
    return fabs(a.origin.x - b.origin.x) < 1 &&
    fabs(a.origin.y - b.origin.y) < 1 &&
    fabs(a.size.width - b.size.width) < 1 &&
    fabs(a.size.height - b.size.height) < 1;
}

- (void)onMouseExit
{
    highlight_ = NO;
    [[self animator] setFrame:normalFrame_];
    [self setNeedsDisplay:YES];
}

- (void)moveToTop
{
    [self retain];
    NSView* superView = [self superview];
    [self removeFromSuperview];
    [superView addSubview:self];
    [self release];

    [self setNeedsDisplay:YES];
}

- (void)onMouseEnter
{
    if (windowIndex_ >= 0 && tabIndex_ >= 0) {
        highlight_ = YES;
        if (!RectsApproxEqual([self frame], fullSizeFrame_)) {
            [[self animator] setFrame:fullSizeFrame_];
        }

        [self moveToTop];
    }
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint locInWin = [event locationInWindow];
    NSPoint loc = [self convertPoint:locInWin fromView:nil];
    if ([self tabObject] && NSPointInRect(loc, [self imageFrame:[self frame].size])) {
        if (windowIndex_ >= 0 && tabIndex_ >= 0) {
            // TODO: pick the session under the mouse
            [delegate_ onSelection:self session:[[self tabObject] activeSession]];
        }
    } else {
        [[self superview] mouseDown:event];
    }
}

- (void)bringTabToFore {
    if (windowIndex_ >= 0 && tabIndex_ >= 0) {
        iTermController *controller = [iTermController sharedInstance];
        PseudoTerminal *terminal = [[controller terminals] objectAtIndex:windowIndex_];
        if ([terminal isHotKeyWindow]) {
            iTermProfileHotKey *hotKey =
                [[iTermHotKeyController sharedInstance] profileHotKeyForWindowController:terminal];
            [[iTermHotKeyController sharedInstance] showWindowForProfileHotKey:hotKey url:nil];
        } else {
            [controller setCurrentTerminal:terminal];
            [[terminal window] makeKeyAndOrderFront:self];
            [[terminal tabView] selectTabViewItemAtIndex:tabIndex_];
        }
    } else {
        NSBeep();
    }
}

- (NSInteger)tabIndex
{
    return tabIndex_;
}

- (NSInteger)windowIndex
{
    return windowIndex_;
}

- (void)setImage:(NSImage*)newImage
{
    [image_ autorelease];
    image_ = [newImage retain];
    [self setNeedsDisplay:YES];
}

- (void)setLabel:(NSString*)newLabel
{
    [label_ autorelease];
    label_ = [newLabel retain];
    [self setNeedsDisplay:YES];
}

- (NSRect)imageFrame:(NSSize)thumbSize
{
    NSSize newSize = [image_ size];
    float scale = 1;
    if (newSize.width > thumbSize.width - 2 * kItermExposeThumbMargin) {
        scale = (thumbSize.width - 2 * kItermExposeThumbMargin) / newSize.width;
    }
    if (newSize.height * scale > thumbSize.height - 2 * kItermExposeThumbMargin) {
        scale = (thumbSize.height - 2 * kItermExposeThumbMargin) / newSize.height;
    }
    if (scale < 1) {
        newSize.width *= scale;
        newSize.height *= scale;
    }
    // Center image in its thumbnail region.
    NSPoint imgOrigin;
    imgOrigin.x = (thumbSize.width - newSize.width) / 2;
    imgOrigin.y = kItermExposeThumbMargin;
    return NSMakeRect(imgOrigin.x, imgOrigin.y, newSize.width, newSize.height);
}

- (void)_drawFocusRing:(NSRect)frame
{
    // Draw a focus ring around a frame.
    [NSGraphicsContext saveGraphicsState];
    [[NSColor keyboardFocusIndicatorColor] set];
    NSSetFocusRingStyle(NSFocusRingOnly);
    [[NSBezierPath bezierPathWithRect:NSMakeRect(frame.origin.x,
                                                 frame.origin.y,
                                                 frame.size.width,
                                                 frame.size.height)] stroke];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)_drawLabel
{
    // Draw a label in a rounded rectangle at the bottom of the frame.
    NSMutableParagraphStyle* paragraph = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [paragraph setAlignment:NSCenterTextAlignment];
    NSDictionary* attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           hasResult_ ? [NSColor yellowColor] : [NSColor whiteColor], NSForegroundColorAttributeName,
                           [NSFont systemFontOfSize:12], NSFontAttributeName,
                           paragraph, NSParagraphStyleAttributeName,
                           NULL];
    NSAttributedString* str = [[[NSMutableAttributedString alloc] initWithString:label_
                                                                      attributes:attrs] autorelease];

    const NSSize thumbSize = [self frame].size;
    NSRect strRect = [str boundingRectWithSize:thumbSize options:0];
    strRect.size.width = MIN(strRect.size.width,
                             thumbSize.width - kItermExposeThumbMargin * 2 - (strRect.size.height + 5));
    NSRect textRect = NSMakeRect((thumbSize.width - strRect.size.width) / 2,
                                 6,
                                 strRect.size.width,
                                 strRect.size.height);

    [[[NSColor blackColor] colorWithAlphaComponent:0.5] set];
    NSBezierPath* thePath = [NSBezierPath bezierPath];
    [thePath appendBezierPathWithRoundedRect:NSMakeRect(textRect.origin.x + textRect.size.width / 2 - strRect.size.width / 2 - 10,
                                                        textRect.origin.y - 5,
                                                        strRect.size.width + 20,
                                                        strRect.size.height + 5)
                                     xRadius:(strRect.size.height + 5) / 2
                                     yRadius:(strRect.size.height + 5)];
    [thePath fill];
    if (hasResult_) {
        [[NSColor yellowColor] set];
    } else {
        [[NSColor darkGrayColor] set];
    }
    [thePath stroke];

    [str drawWithRect:textRect
              options:NSStringDrawingTruncatesLastVisibleLine];
}

- (void)_drawDropShadow:(NSRect)aRect
{
    // create the shadow
    NSShadow *dropShadow = [[[NSShadow alloc] init] autorelease];
    NSColor* theColor = [NSColor darkGrayColor];
    [dropShadow setShadowColor:[theColor colorWithAlphaComponent:1]];
    [dropShadow setShadowBlurRadius:5];
    [dropShadow setShadowOffset:NSMakeSize(0,-4)];

    // save graphics state
    [NSGraphicsContext saveGraphicsState];

    [dropShadow set];

    // fill the desired area
    NSRectFill(aRect);

    // restore state
    [NSGraphicsContext restoreGraphicsState];
}

- (void)_drawGlow:(NSRect)aRect
{
    // create the shadow
    NSShadow *dropShadow = [[[NSShadow alloc] init] autorelease];
    NSColor* theColor = [NSColor yellowColor];
    [dropShadow setShadowColor:[theColor colorWithAlphaComponent:1]];
    [dropShadow setShadowBlurRadius:5];
    [dropShadow setShadowOffset:NSMakeSize(0,0)];

    // save graphics state
    [NSGraphicsContext saveGraphicsState];

    [dropShadow set];

    // fill the desired area
    NSRectFill(aRect);

    // restore state
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawRect:(NSRect)rect
{
    NSImage* image = [[image_ copy] autorelease];
    NSRect imageFrame = [self imageFrame:[self frame].size];

    if (windowIndex_ >= 0 && tabIndex_ >= 0) {
        if (hasResult_) {
            [self _drawGlow:imageFrame];
        } else {
            [self _drawDropShadow:imageFrame];
        }
    }

    [image setSize:imageFrame.size];

    iTermExposeView* theView =  (iTermExposeView*)[[self superview] superview];
    if (!highlight_ && !hasResult_ && [theView resultView]) {
        [image drawAtPoint:imageFrame.origin
                  fromRect:NSZeroRect
                 operation:NSCompositeSourceOver
                  fraction:0.5];
    } else {
        [image drawAtPoint:imageFrame.origin
                  fromRect:NSZeroRect
                 operation:NSCompositeSourceOver
                  fraction:1.0];
    }

    if (windowIndex_ >= 0 && tabIndex_ >= 0) {
        if (highlight_) {
            [self _drawFocusRing:imageFrame];
        }
        if (showLabel_) {
            [self _drawLabel];
        }
    }

}

- (void)showLabel
{
    showLabel_ = YES;
}

- (NSSize)origSize
{
    return origSize_;
}

- (PTYTab*)tab
{
    NSArray* allTerms = [[iTermController sharedInstance] terminals];
    if ([allTerms count] <= windowIndex_) {
        return nil;
    }
    PseudoTerminal* window = [allTerms objectAtIndex:windowIndex_];

    if ([window numberOfTabs] <= tabIndex_) {
        return nil;
    }
    return [[window tabs] objectAtIndex:tabIndex_];
}

@end
