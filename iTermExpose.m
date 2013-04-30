// -*- mode:objc -*-
/*
 **  iTermExpose.m
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Implements an Exposé-like UI for iTerm2 tabs.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "iTermExpose.h"
#import "iTermController.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "GlobalSearch.h"
#import "FutureMethods.h"

static const float THUMB_MARGIN = 25;
/*
static NSString* FormatRect(NSRect r) {
    return [NSString stringWithFormat:@"%lf,%lf %lfx%lf", r.origin.x, r.origin.y,
            r.size.width, r.size.height];
}*/

// This subclass of NSWindow is used for the fullscreen borderless window.
@interface iTermExposeWindow : NSWindow
{
}

- (BOOL)canBecomeKeyWindow;
- (void)keyDown:(NSEvent *)event;
- (BOOL)disableFocusFollowsMouse;

@end

@class iTermExposeTabView;
@protocol iTermExposeTabViewDelegate

- (void)onSelection:(iTermExposeTabView*)theView session:(PTYSession*)theSession;

@end

// This is the content view of the exposé window. It shows a gradient in its
// background and may have a bunch of iTermExposeTabViews as children.
@interface iTermExposeGridView : NSView <iTermExposeTabViewDelegate>
{
    iTermExposeTabView* focused_;
    NSRect* frames_;
    NSImage* cache_;  // background image
}

- (id)initWithFrame:(NSRect)frame
             images:(NSArray*)images
             labels:(NSArray*)labels
               tabs:(NSArray*)tabs
             frames:(NSRect*)frames
       wasMaximized:(NSArray*)wasMaximized
           putOnTop:(int)topIndex;
- (void)dealloc;
- (void)updateTab:(PTYTab*)theTab;
- (void)drawRect:(NSRect)rect;
- (NSRect)tabOrigin:(PTYTab *)theTab visibleScreenFrame:(NSRect)visibleScreenFrame screenFrame:(NSRect)screenFrame;
- (NSSize)zoomedSize:(NSSize)origin thumbSize:(NSSize)thumbSize screenFrame:(NSRect)screenFrame;
- (NSRect)zoomedFrame:(NSRect)dest size:(NSSize)origSize visibleScreenFrame:(NSRect)visibleScreenFrame;
- (iTermExposeTabView*)addTab:(PTYTab *)theTab
                        label:(NSString *)theLabel
                        image:(NSImage *)theImage
                  screenFrame:(NSRect)screenFrame
           visibleScreenFrame:(NSRect)visibleScreenFrame
                        frame:(NSRect)frame
                        index:(int)theIndex
                 wasMaximized:(BOOL)wasMaximized;
// Delegate methods
- (void)onSelection:(iTermExposeTabView*)theView session:(PTYSession*)theSession;
- (BOOL)recomputeIndices;
- (void)setFrames:(NSRect*)frames screenFrame:(NSRect)visibleScreenFrame;
- (void)updateTrackingRectForView:(iTermExposeTabView*)aView;

@end

// This view holds one tab's image and label.
@interface iTermExposeTabView : NSView
{
    NSImage* image_;
    NSString* label_;
    NSInteger tabIndex_;
    NSInteger windowIndex_;
    BOOL showLabel_;
    NSRect originalFrame_;
    NSRect fullSizeFrame_;
    NSRect normalFrame_;
    NSTrackingRectTag trackingRectTag_;
    BOOL highlight_;
    id tabObject_;
    id<iTermExposeTabViewDelegate> delegate_;
    BOOL dirty_;
    BOOL hasResult_;
    NSSize origSize_;
    int index_;
    BOOL wasMaximized_;
}

- (id)initWithImage:(NSImage*)image
              label:(NSString*)label
                tab:(PTYTab*)tab
              frame:(NSRect)frame
      fullSizeFrame:(NSRect)fullSizeFrame
        normalFrame:(NSRect)normalFrame
           delegate:(id<iTermExposeTabViewDelegate>)delegate
              index:(int)theIndex
       wasMaximized:(BOOL)wasMaximized;

- (void)dealloc;
- (NSRect)imageFrame:(NSSize)thumbSize;
- (NSRect)originalFrame;
- (void)drawRect:(NSRect)rect;
- (void)showLabel;
- (NSTrackingRectTag)trackingRectTag;
- (void)setTrackingRectTag:(NSTrackingRectTag)tag;
- (void)moveToTop;
- (void)bringTabToFore;
- (NSInteger)tabIndex;
- (NSInteger)windowIndex;
- (void)setImage:(NSImage*)newImage;
- (void)setLabel:(NSString*)newLabel;
- (NSString*)label;
- (void)setTabObject:(id)tab;
- (id)tabObject;
- (void)clear;
- (void)setDirty:(BOOL)dirty;
- (BOOL)dirty;
- (void)setWindowIndex:(int)windowIndex tabIndex:(int)tabIndex;
- (void)setHasResult:(BOOL)hasResult;
- (NSImage*)image;
- (void)setNormalFrame:(NSRect)normalFrame;
- (void)setFullSizeFrame:(NSRect)fullSizeFrame;
- (NSSize)origSize;
- (int)index;
- (PTYTab*)tab;
- (BOOL)wasMaximized;

@end

@interface iTermExpose (Private) <NSWindowDelegate>
- (void)_toggleOn;
- (void)_toggleOff;
- (int)_populateArrays:(NSMutableArray *)images
                labels:(NSMutableArray *)labels
                  tabs:(NSMutableArray *)tabs
          wasMaximized:(NSMutableArray *)wasMaximized
            controller:(iTermController *)controller;
- (void)_squareThumbGridSize:(float)aspectRatio n:(float)n cols_p:(int *)cols_p rows_p:(int *)rows_p;
- (void)_optimalGridSize:(int *)cols_p rows_p:(int *)rows_p frames:(NSRect*)frames screenFrame:(NSRect)screenFrame images:(NSMutableArray *)images n:(float)n maxWindowsToOptimize:(const int)maxWindowsToOptimize;
- (float)_layoutImages:(NSArray*)images
                  size:(NSSize)size
           screenFrame:(NSRect)screenFrame
                frames:(NSRect*)frames;

@end


@interface iTermExposeView : NSView <GlobalSearchDelegate>
{
    // Not explicitly retained, but a subview.
    iTermExposeGridView* grid_;
    GlobalSearch* search_;
    iTermExposeTabView* resultView_;
    PTYSession* resultSession_;
    double prevSearchHeight_;
}

- (id)initWithFrame:(NSRect)frameRect;
- (void)dealloc;
- (void)setGrid:(iTermExposeGridView*)grid;
- (iTermExposeGridView*)grid;
- (NSRect)searchFrame;
- (iTermExposeTabView*)resultView;
- (PTYSession*)resultSession;

#pragma mark GlobalSearchDelegate
- (void)globalSearchSelectionChangedToSession:(PTYSession*)theSession;
- (void)globalSearchOpenSelection;
- (void)globalSearchViewDidResize:(NSRect)origSize;
- (void)globalSearchCanceled;

@end



@implementation iTermExposeWindow

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)keyDown:(NSEvent*)event
{
    NSString *unmodkeystr = [event charactersIgnoringModifiers];
    unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    if (unmodunicode == 27) {
        [iTermExpose toggle];
    }
}

- (BOOL)disableFocusFollowsMouse
{
    return YES;
}

@end

@implementation iTermExposeTabView

- (id)initWithImage:(NSImage*)image
              label:(NSString*)label
                tab:(PTYTab*)tab
              frame:(NSRect)frame
      fullSizeFrame:(NSRect)fullSizeFrame
        normalFrame:(NSRect)normalFrame
           delegate:(id<iTermExposeTabViewDelegate>)delegate
              index:(int)theIndex
       wasMaximized:(BOOL)wasMaximized
{
    self = [super initWithFrame:frame];
    if (self) {
        wasMaximized_ = wasMaximized;
        image_ = [image retain];
        label_ = [label retain];
        tabIndex_ = [[tab realParentWindow] indexOfTab:tab];
        assert(tabIndex_ != NSNotFound);
        windowIndex_ = [[[iTermController sharedInstance] terminals] indexOfObjectIdenticalTo:[tab realParentWindow]];
        fullSizeFrame_ = fullSizeFrame;
        normalFrame_ = normalFrame;
        showLabel_ = NO;
        originalFrame_ = frame;
        delegate_ = delegate;
        tabObject_ = tab;
        origSize_ = frame.size;
        index_ = theIndex;
        //NSLog(@"Label %@ has index %d", label_, index_);
    }
    return self;
}

- (void)dealloc
{
    [label_ release];
    [image_ release];

    [super dealloc];
}

- (id)tabObject
{
    return tabObject_;
}

- (void)setTabObject:(id)tab
{
    tabObject_ = tab;
}

- (void)setDirty:(BOOL)dirty
{
    dirty_ = dirty;
}

- (BOOL)dirty
{
    return dirty_;
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

- (NSImage*)image
{
    return image_;
}

- (NSRect)originalFrame
{
    return originalFrame_;
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

- (NSTrackingRectTag)trackingRectTag
{
    return trackingRectTag_;
}

- (void)setTrackingRectTag:(NSTrackingRectTag)tag
{
    trackingRectTag_ = tag;
}

- (NSRect)normalFrame
{
    return normalFrame_;
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
    //NSLog(@"onMouseExit: Set rect of tabview to %@", FormatRect(normalFrame_));
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

- (void)bringTabToFore
{
    if (windowIndex_ >= 0 && tabIndex_ >= 0) {
        iTermController* controller = [iTermController sharedInstance];
        PseudoTerminal* terminal = [[controller terminals] objectAtIndex:windowIndex_];
        if ([terminal isHotKeyWindow]) {
            [[iTermController sharedInstance] showHotKeyWindow];
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

- (NSString*)label
{
    return label_;
}

- (NSRect)imageFrame:(NSSize)thumbSize
{
    NSSize newSize = [image_ size];
    float scale = 1;
    if (newSize.width > thumbSize.width - 2 * THUMB_MARGIN) {
        scale = (thumbSize.width - 2 * THUMB_MARGIN) / newSize.width;
    }
    if (newSize.height * scale > thumbSize.height - 2 * THUMB_MARGIN) {
        scale = (thumbSize.height - 2 * THUMB_MARGIN) / newSize.height;
    }
    if (scale < 1) {
        newSize.width *= scale;
        newSize.height *= scale;
    }
    // Center image in its thumbnail region.
    NSPoint imgOrigin;
    imgOrigin.x = (thumbSize.width - newSize.width) / 2;
    imgOrigin.y = THUMB_MARGIN;
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
                             thumbSize.width - THUMB_MARGIN * 2 - (strRect.size.height + 5));
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
              options:NSLineBreakByClipping];
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

    [image setScalesWhenResized:YES];
    [image setSize:imageFrame.size];

    iTermExposeView* theView =  (iTermExposeView*)[[self superview] superview];
    if (!highlight_ && !hasResult_ && [theView resultView]) {
        [image compositeToPoint:imageFrame.origin operation:NSCompositeSourceOver fraction:0.5];
    } else {
        [image compositeToPoint:imageFrame.origin operation:NSCompositeSourceOver];
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

- (void)setNormalFrame:(NSRect)normalFrame
{
    normalFrame_ = normalFrame;
}

- (void)setFullSizeFrame:(NSRect)fullSizeFrame
{
    fullSizeFrame_ = fullSizeFrame;
}

- (NSSize)origSize
{
    return origSize_;
}

- (int)index
{
    return index_;
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

- (BOOL)wasMaximized
{
    return wasMaximized_;
}

@end

@implementation iTermExposeGridView

static BOOL SizesEqual(NSSize a, NSSize b) {
    return (int)a.width == (int)b.width && (int)a.height == (int)b.height;
}

static NSScreen *ExposeScreen() {
    return [[[NSApplication sharedApplication] keyWindow] deepestScreen];
}

- (id)initWithFrame:(NSRect)frame
             images:(NSArray*)images
             labels:(NSArray*)labels
               tabs:(NSArray*)tabs
             frames:(NSRect*)frames
       wasMaximized:(NSArray*)wasMaximized
           putOnTop:(int)topIndex
{
    self = [super initWithFrame:frame];
    if (self) {
        NSScreen* theScreen = ExposeScreen();
        NSRect screenFrame = [theScreen frame];
        screenFrame.origin = NSZeroPoint;
        NSRect visibleScreenFrame = [theScreen visibleFrame];
        //NSLog(@"Screen origin is %lf, %lf", screenFrame.origin.x, screenFrame.origin.y);
        frames_ = frames;
        [self setAlphaValue:0];
        [[self animator] setAlphaValue:1];
        const int n = [images count];

        iTermExposeTabView* selectedView = nil;
        for (int i = 0; i < n; i++) {
            PTYTab* theTab = [tabs objectAtIndex:i];
            NSString* theLabel = [labels objectAtIndex:i];
            NSImage* theImage = [images objectAtIndex:i];
            BOOL wasMax = [[wasMaximized objectAtIndex:i] boolValue];
            //NSLog(@"Place %@ at %lf,%lf", theLabel, frames_[i].origin.x, frames_[i].origin.y);
            iTermExposeTabView* newView = [self addTab:theTab
                                                 label:theLabel
                                                 image:theImage
                                           screenFrame:screenFrame
                                    visibleScreenFrame:visibleScreenFrame
                                                 frame:frames_[i]
                                                 index:i
                                          wasMaximized:wasMax];
            if (i == topIndex) {
                selectedView = newView;
            }
        }
        [selectedView moveToTop];
    }
    return self;
}

- (void)dealloc
{
    for (iTermExposeTabView* tabView in [self subviews]) {
        [self removeTrackingRect:[tabView trackingRectTag]];
    }
    [cache_ release];
    free(frames_);
    [super dealloc];
}

- (iTermExposeTabView*)_tabViewForTab:(PTYTab*)theTab
{
    for (iTermExposeTabView* tabView in [self subviews]) {
        if ([tabView tabObject] == theTab) {
            return tabView;
        }
    }
    return nil;
}

- (BOOL)recomputeIndices
{
    for (iTermExposeTabView* tabView in [self subviews]) {
        [tabView setDirty:YES];
    }

    BOOL anythingLeft = NO;
    int w = 0;
    for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
        int t = 0;
        for (PTYTab* aTab in [term tabs]) {
            iTermExposeTabView* tabView = [self _tabViewForTab:aTab];
            if (tabView) {
                [tabView setWindowIndex:w tabIndex:t];
                [tabView setDirty:NO];
                anythingLeft = YES;
            }
            ++t;
        }
        ++w;
    }
    for (iTermExposeTabView* tabView in [self subviews]) {
        if ([tabView dirty]) {
            [tabView clear];
        }
    }
    return anythingLeft;
}

- (void)setFrames:(NSRect*)frames screenFrame:(NSRect)visibleScreenFrame
{
    free(frames_);
    int i = 0;
    for (iTermExposeTabView* tabView in [self subviews]) {
        if ([tabView isKindOfClass:[iTermExposeTabView class]]) {
            [[tabView animator] setFrame:frames[i]];
            //NSLog(@"setFrames: Set rect of tabview %@ to %@", [tabView label], FormatRect(frames[i]));
            [tabView setNormalFrame:frames[i]];
            NSRect zoomedFrame = [self zoomedFrame:frames[i]
                                              size:[tabView origSize]
                                visibleScreenFrame:visibleScreenFrame];
            [tabView setFullSizeFrame:zoomedFrame];
            [self performSelector:@selector(updateTrackingRectForView:)
                       withObject:tabView
                       afterDelay:[[NSAnimationContext currentContext] duration]];
            i++;
        }
    }
    frames_ = frames;
}

- (NSRect)tabOrigin:(PTYTab *)theTab visibleScreenFrame:(NSRect)visibleScreenFrame screenFrame:(NSRect)screenFrame
{
    NSRect origin = [[[theTab realParentWindow] currentTab] absoluteFrame];
    origin.origin.y -= visibleScreenFrame.origin.y;
    origin.origin.x -= visibleScreenFrame.origin.x;

    origin.origin.y -= origin.size.height + screenFrame.origin.y + THUMB_MARGIN;
    origin.origin.x -= THUMB_MARGIN;
    origin.size.width += 2*THUMB_MARGIN;
    origin.size.height += 2*THUMB_MARGIN;
    return origin;
}

- (NSSize)zoomedSize:(NSSize)origin thumbSize:(NSSize)thumbSize screenFrame:(NSRect)screenFrame
{
    NSSize origSize = origin;
    origSize.width = MAX(thumbSize.width,
                         MIN(origSize.width,
                             screenFrame.size.width * 0.9));
    origSize.height = MAX(thumbSize.height,
                          MIN(origSize.height,
                              screenFrame.size.height * 0.9));
    return origSize;
}

- (void)drawRect:(NSRect)rect
{
    if (!cache_ || !SizesEqual([cache_ size], [self frame].size)) {
        [cache_ release];
        cache_ = [[NSImage alloc] initWithSize:[self frame].size];
        [cache_ lockFocus];
        // Can't use alpha 0 because clicks would pass through to windows below.
        NSGradient* aGradient = [[[NSGradient alloc]
                                  initWithStartingColor:[[NSColor blackColor] colorWithAlphaComponent:0.1]
                                  endingColor:[[NSColor blackColor] colorWithAlphaComponent:0.7]] autorelease];
        [aGradient drawInRect:[self frame]
       relativeCenterPosition:NSMakePoint(0, 0)];
        [cache_ unlockFocus];
    }

    [cache_ compositeToPoint:rect.origin
                    fromRect:rect
                   operation:NSCompositeSourceOver];
}

- (NSRect)zoomedFrame:(NSRect)dest size:(NSSize)origSize visibleScreenFrame:(NSRect)visibleScreenFrame
{
    NSPoint center = NSMakePoint(dest.origin.x + dest.size.width / 2,
                                 dest.origin.y + dest.size.height / 2);
    NSRect fullSizeFrame = NSMakeRect(center.x - origSize.width / 2,
                                          center.y - origSize.height / 2,
                                      origSize.width,
                                      origSize.height);

    // rewrite fullSizeFrame so it fits entirely in visibleScreenFrame and is as
    // large as possible.
    double scale = 1;
    if (fullSizeFrame.size.width > visibleScreenFrame.size.width) {
        scale = MIN(scale, visibleScreenFrame.size.width / fullSizeFrame.size.width);
    }
    if (fullSizeFrame.size.height > visibleScreenFrame.size.height) {
        scale = MIN(scale, visibleScreenFrame.size.height / fullSizeFrame.size.height);
    }
    fullSizeFrame.size.width = round(fullSizeFrame.size.width * scale);
    fullSizeFrame.size.height  = round(fullSizeFrame.size.height * scale);
    
    fullSizeFrame.origin.x = MAX(fullSizeFrame.origin.x,
                                 visibleScreenFrame.origin.x);
    fullSizeFrame.origin.y = MAX(fullSizeFrame.origin.y,
                                 visibleScreenFrame.origin.y);

    if (fullSizeFrame.origin.x + fullSizeFrame.size.width > visibleScreenFrame.origin.x + visibleScreenFrame.size.width) {
        fullSizeFrame.origin.x = (visibleScreenFrame.origin.x + visibleScreenFrame.size.width) - fullSizeFrame.size.width;
    }
    if (fullSizeFrame.origin.y + fullSizeFrame.size.height > visibleScreenFrame.origin.y + visibleScreenFrame.size.height) {
        fullSizeFrame.origin.y = (visibleScreenFrame.origin.y + visibleScreenFrame.size.height) - fullSizeFrame.size.height;
    }
    
    return fullSizeFrame;
}

- (iTermExposeTabView*)addTab:(PTYTab *)theTab
                        label:(NSString *)theLabel
                        image:(NSImage *)theImage
                  screenFrame:(NSRect)screenFrame
           visibleScreenFrame:(NSRect)visibleScreenFrame
                        frame:(NSRect)dest
                        index:(int)theIndex
                 wasMaximized:(BOOL)wasMaximized
{
    NSRect tabRect = [self tabOrigin:theTab
                        visibleScreenFrame:visibleScreenFrame
                         screenFrame:screenFrame];

    NSSize origSize = [self zoomedSize:tabRect.size
                             thumbSize:dest.size
                           screenFrame:screenFrame];

    NSRect fullSizeFrame = [self zoomedFrame:dest
                                        size:origSize
                          visibleScreenFrame:NSMakeRect(0, 0, visibleScreenFrame.size.width, visibleScreenFrame.size.height)];
    //NSLog(@"initial zoomedFrame of %@ in %@ is %@", FormatRect(dest), FormatRect(visibleScreenFrame), FormatRect(fullSizeFrame));

    iTermExposeTabView* aView = [[iTermExposeTabView alloc] initWithImage:theImage
                                                                    label:theLabel
                                                                      tab:theTab
                                                                    frame:tabRect
                                                            fullSizeFrame:fullSizeFrame
                                                              normalFrame:dest
                                                                 delegate:self
                                                                    index:theIndex
                                                             wasMaximized:wasMaximized];
    [self addSubview:aView];
    [aView release];
    [[aView animator] setFrame:dest];
    [self performSelector:@selector(viewIsReady:)
               withObject:aView
               afterDelay:[[NSAnimationContext currentContext] duration]];
    return aView;
}

- (void)updateTab:(PTYTab*)theTab
{
    NSInteger tabIndex, windowIndex;
    tabIndex = [[theTab realParentWindow] indexOfTab:theTab];
    assert(tabIndex != NSNotFound);
    windowIndex = [[[iTermController sharedInstance] terminals] indexOfObjectIdenticalTo:[theTab realParentWindow]];
    for (iTermExposeTabView* aView in [self subviews]) {
        if ([aView isKindOfClass:[iTermExposeTabView class]]) {
            if ([aView tabIndex] == tabIndex &&
                [aView windowIndex] == windowIndex) {
                [aView setImage:[theTab image:NO]];
                [aView setLabel:[iTermExpose labelForTab:theTab
                                            windowNumber:[aView windowIndex] + 1
                                               tabNumber:[aView tabIndex] + 1]];
            }
        }
    }
}

- (void)_restoreMaximizationExceptSession:(PTYSession*)theSession
{
    for (iTermExposeTabView* aView in [self subviews]) {
        if ([aView isKindOfClass:[iTermExposeTabView class]]) {
            iTermExposeTabView* tabView = (iTermExposeTabView*)aView;
            if ([aView wasMaximized] && [theSession tab] != [tabView tab]) {
                [[tabView tab] maximize];
            }
        }
    }
}

- (void)onSelection:(iTermExposeTabView*)theView session:(PTYSession*)theSession
{
    if (theView && ![theView tabObject]) {
        return;
    }
    [self _restoreMaximizationExceptSession:theSession];
    [theView moveToTop];
    for (iTermExposeTabView* aView in [self subviews]) {
        if ([aView isKindOfClass:[iTermExposeTabView class]]) {
            [[aView animator] setFrame:[aView originalFrame]];
        }
    }
    if (theView) {
        [[theView tabObject] setActiveSession:theSession];
    }
    [[self animator] setAlphaValue:0];
    [self performSelector:@selector(bringTabToFore:)
               withObject:theView
               afterDelay:[[NSAnimationContext currentContext] duration]];
}

- (void)bringTabToFore:(iTermExposeTabView*)theView
{
    [[iTermExpose sharedInstance] showWindows:NO];
    if (theView) {
        [theView bringTabToFore];
    } else {
        [[[iTermExpose sharedInstance] window] orderOut:self];
    }
}

- (void)updateTrackingRectForView:(iTermExposeTabView*)aView
{
    NSRect viewRect = [aView normalFrame];
    NSRect rect = [aView imageFrame:viewRect.size];
    rect.origin.x += viewRect.origin.x;
    rect.origin.y += viewRect.origin.y;

    NSTrackingRectTag oldTag = [aView trackingRectTag];
    if (oldTag) {
        [self removeTrackingRect:oldTag];
    }
    if ([aView tabObject]) {
        [aView setTrackingRectTag:[self addTrackingRect:rect
                                                  owner:self
                                               userData:aView
                                           assumeInside:NO]];
    }
}

- (void)viewIsReady:(iTermExposeTabView*)aView
{
    [aView showLabel];
    [self updateTrackingRectForView:aView];
}

- (void)mouseExited:(NSEvent *)event
{
    //NSLog(@"mouseExited:%p", focused_);
    [focused_ onMouseExit];
    for (iTermExposeTabView* aView in [self subviews]) {
        if (aView != focused_ &&
            [aView isKindOfClass:[iTermExposeTabView class]]) {
            [[aView animator] setAlphaValue:1];
        }
    }
    focused_ = nil;
}

- (void)mouseEntered:(NSEvent *)event
{
    if (!focused_) {
        focused_ = [event userData];
        //NSLog(@"mouseEntered:%p", focused_);
        [focused_ onMouseEnter];
        for (iTermExposeTabView* aView in [self subviews]) {
            if (aView != focused_ &&
                [aView isKindOfClass:[iTermExposeTabView class]]) {
                [[aView animator] setAlphaValue:0.8];
            }
        }
    }
}

- (void)mouseDown:(NSEvent *)event
{
    [[iTermExpose sharedInstance] _toggleOff];
}

@end

@implementation iTermExposeView

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        search_ = [[GlobalSearch alloc] initWithNibName:@"GlobalSearch" bundle:nil];
        [search_ setDelegate:self];
        const int SEARCH_MARGIN = 10;
        [[search_ view] setFrame:NSMakeRect(SEARCH_MARGIN,
                                            [self frame].size.height - [[search_ view] frame].size.height - SEARCH_MARGIN,
                                            [[search_ view] frame].size.width,
                                            [[search_ view] frame].size.height)];
        prevSearchHeight_ = [[search_ view] frame].size.height;
        [self addSubview:[search_ view]];
    }
    return self;
}

- (void)dealloc
{
    [search_ abort];
    [search_ release];
    [super dealloc];
}

- (void)setGrid:(iTermExposeGridView*)newGrid
{
    iTermExposeGridView* oldGrid = grid_;
    // retain, change, release in case newGrid==grid_.
    [oldGrid retain];
    [oldGrid removeFromSuperview];
    [self addSubview:newGrid positioned:NSWindowBelow relativeTo:[search_ view]];
    [oldGrid release];
    grid_ = newGrid;
}

- (iTermExposeGridView*)grid
{
    return grid_;
}

- (NSRect)searchFrame
{
    NSRect rect = [[search_ view] frame];
    double dh = prevSearchHeight_ - rect.size.height;
    rect.origin.y -= dh;
    rect.size.height += dh;
    //NSLog(@"Serach frame: %lf,%lf %lfx%lf", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
    return rect;
}

- (void)globalSearchSelectionChangedToSession:(PTYSession*)theSession
{
    [resultView_ setHasResult:NO];
    resultView_ = nil;
    resultSession_ = nil;
    PTYTab* changedTab = [theSession tab];
    for (iTermExposeTabView* aView in [grid_ subviews]) {
        if ([aView isKindOfClass:[iTermExposeTabView class]]) {
            PTYTab* theTab = [aView tabObject];
            if (theTab && theTab == changedTab) {
                resultView_ = aView;
                resultSession_ = theSession;
            }
            [aView setNeedsDisplay:YES];
        }
    }
    [resultView_ setHasResult:YES];
    if (resultView_) {
        [grid_ updateTab:[theSession tab]];
    }
}

- (void)globalSearchOpenSelection
{
    [grid_ onSelection:resultView_ session:resultSession_];
}

- (void)globalSearchCanceled
{
    [[iTermExpose sharedInstance] _toggleOff];
}

- (void)globalSearchViewDidResize:(NSRect)origSize;
{
    // If we were called because a window closed, make sure we're up to date (there's a race where
    // GlobalSearch's notification may be run before ours).
    [[iTermExpose sharedInstance] recomputeIndices:nil];

    if ([search_ numResults] > 0 &&
        [[search_ view] frame].size.height <= prevSearchHeight_) {
        return;
    }
    //NSLog(@"Size changed with %d results", [search_ numResults]);
    if ([search_ numResults] > 0) {
        prevSearchHeight_ = [self frame].size.height;
    } else {
        prevSearchHeight_ = [[search_ view] frame].size.height;
    }
    
    NSMutableArray* images = [NSMutableArray arrayWithCapacity:[[grid_ subviews] count]];
    // fill the array up with images in the wrong order just to make it large
    // enough.
    int i = 0;
    for (iTermExposeTabView* tabView in [grid_ subviews]) {
        if ([tabView isKindOfClass:[iTermExposeTabView class]]) {
            [images addObject:[NSNumber numberWithInt:i]];
            i++;
        }
    }
    // now make the order correct.
    NSMutableArray* permutation = [NSMutableArray arrayWithCapacity:[[grid_ subviews] count]];
    i = 0;
    for (iTermExposeTabView* tabView in [grid_ subviews]) {
        if ([tabView isKindOfClass:[iTermExposeTabView class]]) {
            [permutation addObject:[NSNumber numberWithInt:[tabView index]]];
            i++;
            if ([tabView tabObject]) {
                [images replaceObjectAtIndex:[tabView index]
                                  withObject:[[tabView tabObject] image:NO]];
            } else {
                // TODO: test this
                [images replaceObjectAtIndex:[tabView index]
                                  withObject:[tabView image]];
            }
            //NSLog(@"Place %@ at index %d", [tabView label], [tabView index]);
        }
    }

    NSRect* frames = (NSRect*)calloc([images count], sizeof(NSRect));
    NSScreen* theScreen = ExposeScreen();
    NSRect screenFrame = [theScreen visibleFrame];
    screenFrame.origin = NSZeroPoint;
    if ([search_ numResults] > 0) {
        screenFrame.origin.x = [self searchFrame].origin.x + [self searchFrame].size.width;
        screenFrame.size.width -= [self searchFrame].size.width;
    }
    [[iTermExpose sharedInstance] computeLayout:images frames:frames screenFrame:screenFrame];
    
    NSRect* permutedFrames = (NSRect*)calloc([images count], sizeof(NSRect));
    for (i = 0; i < [images count]; i++) {
        //NSLog(@"Move frame at %d to %d", [[permutation objectAtIndex:i] intValue], i);
        permutedFrames[i] = frames[[[permutation objectAtIndex:i] intValue]];
    }
    free(frames);
    [grid_ setFrames:permutedFrames screenFrame:screenFrame];
}

- (iTermExposeTabView*)resultView
{
    return resultView_;
}

- (PTYSession*)resultSession
{
    return resultSession_;
}

@end

@implementation iTermExpose

+ (NSString*)labelForTab:(PTYTab*)aTab windowNumber:(int)i tabNumber:(int)j
{
    if (i == 0) {
        return @"Defunct Tab";
    }
    NSString* jobName = [[aTab activeSession] jobName];
    if (jobName) {
        return [NSString stringWithFormat:@"%d/%d. %@", i, j, [[aTab activeSession] name]];
    } else {
        return [NSString stringWithFormat:@"%d/%d. %@", i, j, [[aTab activeSession] name]];
    }
}

+ (iTermExpose*)sharedInstance
{
    static iTermExpose* inst;
    if (!inst) {
        inst = [[iTermExpose alloc] init];
    }
    return inst;
}

+ (void)toggle
{
    if ([iTermExpose sharedInstance]->window_) {
        [[iTermExpose sharedInstance] _toggleOff];
    } else {
        [[iTermExpose sharedInstance] _toggleOn];
    }
}

+ (void)exitIfActive
{
    if ([iTermExpose sharedInstance]->window_) {
        [[iTermExpose sharedInstance] _toggleOff];
    }
}

- (id)init
{
    self = [super init];
    if (self) {
        // If anything changes, we exit because there isn't yet code to
        // rearrange thumbnails.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tabChangedSinceLastExpose)
                                                     name:@"iTermTabContentsChanged"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recomputeIndices:)
                                                     name:@"iTermNumberOfSessionsDidChange"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recomputeIndices:)
                                                     name:@"iTermWindowDidClose"
                                                   object:nil];
    }
    return self;
}

- (NSWindow*)window
{
    return window_;
}

- (BOOL)isVisible
{
    return window_ != nil;
}

- (void)updateTab:(PTYTab*)theTab
{
    if (window_) {
        [[view_ grid] updateTab:theTab];
    }
}

- (void)dealloc
{
    [window_ close];
    [view_ release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    [window_ close];
    [self showWindows:YES];
    window_ = nil;
    [view_ release];
    view_ = nil;
    SetSystemUIMode(kUIModeNormal, 0);
}

- (void)showWindows:(BOOL)fade
{
    iTermController* controller = [iTermController sharedInstance];
    for (int i = 0; i < [controller numberOfTerminals]; i++) {
        PseudoTerminal* term = [controller terminalAtIndex:i];
        if ([[term window] alphaValue] == 0) {
            if (fade) {
                [[[term window] animator] setAlphaValue:1];
            } else {
                [[term window] setAlphaValue:1];
            }
        }
    }
}

static int CompareFrames(const void* aPtr, const void* bPtr)
{
    const NSRect* a = (NSRect*)aPtr;
    const NSRect* b = (NSRect*)bPtr;
    if (b->origin.y > a->origin.y) {
        return 1;
    }
    if (b->origin.y < a->origin.y) {
        return -1;
    }
    if (b->origin.x > a->origin.x) {
        return -1;
    }
    if (b->origin.x < a->origin.x) {
        return 1;
    }
    return 0;
}

- (void)_sortFrames:(NSRect*)frames n:(int)n
{
    qsort(frames, n, sizeof(NSRect), CompareFrames);
}

- (void)computeLayout:(NSMutableArray *)images
               frames:(NSRect*)frames
          screenFrame:(NSRect)screenFrame
{
    /*NSLog(@"**computeLayout with screen frame %lf,%lf %lfx%lf", 
          screenFrame.origin.x,
          screenFrame.origin.y,
          screenFrame.size.width,
          screenFrame.size.height);
      */    
    float n = [images count];
    int rows = 1, cols = 1;
    const float aspectRatio = screenFrame.size.width / screenFrame.size.height;

    // Computing the optimal grid size is O(n^2). Limit the number of iterations
    // to 30^2=900.
    const int maxWindowsToOptimize = 100;
    if (n > maxWindowsToOptimize) {
        [self _squareThumbGridSize:aspectRatio
                                 n:n
                            cols_p:&cols
                            rows_p:&rows];
        float waste;
        do {
            waste = [self _layoutImages:images
                                   size:NSMakeSize(screenFrame.size.width / cols,
                                                   screenFrame.size.height / rows)
                            screenFrame:screenFrame
                                 frames:frames];
            if (isinf(waste)) {
                if (screenFrame.size.width / cols > screenFrame.size.height / rows) {
                    ++cols;
                } else {
                    ++rows;
                }
            }
        } while (isinf(waste));
        
    } else {
        [self _optimalGridSize:&cols
                        rows_p:&rows
                        frames:frames
                   screenFrame:screenFrame
                        images:images
                             n:n
          maxWindowsToOptimize:maxWindowsToOptimize];
    }
    
    [self _sortFrames:frames n:[images count]];
    for (int i = 0; i < n; i++) {
        //NSLog(@"After sorting frame %d is at %@", i, FormatRect(frames[i]));
    }
}

- (void)recomputeIndices:(NSNotification*)notification
{
    if (![[view_ grid] recomputeIndices] && [iTermExpose sharedInstance]->window_) {
        [self _toggleOff];
    }
    NSMutableArray* allSessions = [NSMutableArray arrayWithCapacity:100];
    NSMutableArray* allTabs = [NSMutableArray arrayWithCapacity:100];
    for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
        [allSessions addObjectsFromArray:[term allSessions]];
        [allTabs addObjectsFromArray:[term tabs]];
    }
    if ([view_ resultView] &&
        [allSessions indexOfObjectIdenticalTo:[view_ resultSession]] != NSNotFound) {
        [view_ globalSearchSelectionChangedToSession:nil];
    }
    for (iTermExposeTabView* tabView in [[view_ grid] subviews]) {
        if ([tabView isKindOfClass:[iTermExposeTabView class]]) {
            PTYTab* tab = [tabView tabObject];
            if (tab && [allTabs indexOfObjectIdenticalTo:tab] == NSNotFound) {
                [tabView setTabObject:nil];
                [[view_ grid] updateTrackingRectForView:tabView];
            }
        }
    }
}


@end

@implementation iTermExpose (Private)

- (NSSize)scaledImageSize:(NSSize)origSize thumbSize:(NSSize)size
{
    float scale = 1;
    if (origSize.width > size.width) {
        scale = size.width / origSize.width;
    }
    if (origSize.height * scale > size.height) {
        scale = size.height / origSize.height;
    }
    // Use floor here because when tiling images they can fit exactly into a row
    // but if they're over by a fraction the grid won't work.
    return NSMakeSize(floor(origSize.width * scale), floor(origSize.height * scale));
}

static BOOL AdvanceCell(float* x, float* y, NSRect screenFrame, NSSize size) {
    *x += size.width;
    if (*x + size.width > screenFrame.origin.x + screenFrame.size.width) {
        //NSLog(@"  would have advanced x to %lf which with size of %lf is more than screen width of %lf", (double)(*x+size.width), size.width, screenFrame.size.width);
        *x = screenFrame.origin.x;
        *y += size.height;
        if (*y + size.height > screenFrame.origin.y + screenFrame.size.height) {
            return NO;
        }
    }
    return YES;
}

- (float)_layoutImages:(NSArray*)images
                  size:(NSSize)size
           screenFrame:(NSRect)screenFrame
                frames:(NSRect*)frames
{
    //NSLog(@"Layout images in frame %lf,%lf %lfx%lf", screenFrame.origin.x, screenFrame.origin.y, screenFrame.size.width, screenFrame.size.height);
    // Slightly decrease the size in case the caller expects it to exactly divide
    // screenSize. We don't want floating point errors to have a huge effect.
    size.width--;
    size.height--;

    // Find the largest image when all images have been scaled down to thumbnail
    // size. Store the scaled sizes also.
    const int n = [images count];
    int i = 0;
    NSSize scaledSizes[n];
    NSSize maxThumbSize = NSMakeSize(0, 0);
    for (NSImage* anImage in images) {
        const NSSize origSize = [anImage size];
        scaledSizes[i] = [self scaledImageSize:origSize
                                     thumbSize:size];
        maxThumbSize = NSMakeSize(MAX(maxThumbSize.width, scaledSizes[i].width),
                                  MAX(maxThumbSize.height, scaledSizes[i].height));
        i++;
    }

    // Lay the frames out in a grid originating in the lower left.
    i = 0;
    float x = screenFrame.origin.x;
    float y = screenFrame.origin.y;
    BOOL isOk = YES;
    for (NSImage* anImage in images) {
        if (!isOk) {
            return INFINITY;
        }
        NSRect proposedRect = NSMakeRect(x,
                                         y,
                                         maxThumbSize.width,
                                         maxThumbSize.height);
        frames[i++] = proposedRect;
        isOk = AdvanceCell(&x, &y, screenFrame, maxThumbSize);
    }

    // Center each row horizontally and center the collection of rows
    // vertically.
    const float verticalSpan = frames[i-1].origin.y + frames[i-1].size.height;
    const float verticalShift = (screenFrame.size.height - verticalSpan) / 2;

    for (i = 0; i < n; ) {
        int j;
        for (j = i; j < n; j++) {
            // The analyzer warning here is bogus (all frames from 0 to n-1 are initialized above).
            if (frames[j].origin.y != frames[i].origin.y) {
                break;
            }
        }
        // The analyzer warning here is bogus (all frames from 0 to n-1 are initialized above).
        const float horizontalSpan = frames[j-1].origin.x + frames[j-1].size.width - frames[i].origin.x;
        const float horizontalShift = (screenFrame.size.width - horizontalSpan) / 2;
        for (int k = i; k < j; k++) {
            frames[k].origin.x += horizontalShift;
            frames[k].origin.y += verticalShift;
        }
        i = j;
    }

    // Adjust views that overlap search view by shrinking them or eliminating
    // the cell and adding to skip, the count that must be added to the end.
    NSRect searchFrame = [view_ searchFrame];
    int skip = 0;
    for (i = 0; i + skip < n; i++) {
        if (skip) {
            frames[i] = frames[i + skip];
        }
        if (NSIntersectsRect(searchFrame, frames[i])) {
            /*NSLog(@"Frame %lf,%lf %lfx%lf intersects search frame %lf,%lf %lfx%lf.",
                  frames[i].origin.x, frames[i].origin.y, frames[i].size.width, frames[i].size.height,
                  searchFrame.origin.x, searchFrame.origin.y, searchFrame.size.width, searchFrame.size.height);
             */
            NSRect intersection = NSIntersectionRect(searchFrame, frames[i]);
            if (intersection.size.height > maxThumbSize.height / 3 ||
                maxThumbSize.height < 50) {
                ++skip;
                --i;
            } else {
                // Shorten the cell a bit.
                frames[i].size.height -= intersection.size.height;
            }
        }
    }

    if (skip == n) {
        // Not enough room for any cell!
        //NSLog(@"Warning: not enough room for any cell!");
        return INFINITY;
    }

    // Add views to the end if any had to be eliminated
    // First, set x and y to the first location after the last cell.
    if (skip) {
        x = frames[i - 1].origin.x;
        y = frames[i - 1].origin.y;
        if (!AdvanceCell(&x, &y, screenFrame, maxThumbSize)) {
            return INFINITY;
        }

        // Set new x,y coordinates for the last 'skip' cells.
        while (skip) {
            NSRect proposedRect = NSMakeRect(x,
                                             y,
                                             maxThumbSize.width,
                                             maxThumbSize.height);
            if (!AdvanceCell(&x, &y, screenFrame, maxThumbSize)) {
                return INFINITY;
            }
            if (NSIntersectsRect(searchFrame, proposedRect)) {
                continue;
            }
            frames[n-skip] = proposedRect;
            --skip;
        }
    }
    // Count up wasted space
    float availableSpace = screenFrame.size.width * screenFrame.size.height - searchFrame.size.width * searchFrame.size.height;
    for (i = 0; i < n; i++) {
        const NSSize origSize = [[images objectAtIndex:i] size];
        NSSize scaledSize = [self scaledImageSize:origSize
                                        thumbSize:frames[i].size];
        availableSpace -= scaledSize.width * scaledSize.height;
    }

    return availableSpace;
}

- (void)_toggleOn
{
    iTermController* controller = [iTermController sharedInstance];
    if ([controller isHotKeyWindowOpen]) {
        [controller fastHideHotKeyWindow];
    }

    // Crete parallel arrays with info needed to create subviews.
    NSMutableArray* images = [NSMutableArray arrayWithCapacity:[controller numberOfTerminals]];
    NSMutableArray* tabs = [NSMutableArray arrayWithCapacity:[controller numberOfTerminals]];
    NSMutableArray* labels = [NSMutableArray arrayWithCapacity:[controller numberOfTerminals]];
    NSMutableArray* wasMaximized = [NSMutableArray arrayWithCapacity:[controller numberOfTerminals]];

    int selectedIndex = [self _populateArrays:images
                                       labels:labels
                                         tabs:tabs
                                 wasMaximized:wasMaximized
                                   controller:controller];

    NSRect* frames = (NSRect*)calloc([images count], sizeof(NSRect));

    // Figure out the right size for a thumbnail.
    NSScreen* theScreen = ExposeScreen();
    SetSystemUIMode(kUIModeAllHidden, 0);
    NSRect screenFrame = [theScreen frame];
    // Create the window and its view.
    window_ = [[iTermExposeWindow alloc] initWithContentRect:screenFrame
                                                   styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES
                                                      screen:theScreen];
    [window_ setDelegate:self];
    view_ = [[iTermExposeView alloc] initWithFrame:NSMakeRect(0,
                                                              0,
                                                              screenFrame.size.width,
                                                              screenFrame.size.height)];

    [self computeLayout:images
                 frames:frames
            screenFrame:NSMakeRect(0, 0, screenFrame.size.width, screenFrame.size.height)];


    // Finish setting up the view. The frames array is now owned by view_.
    [view_ setGrid:[[[iTermExposeGridView alloc] initWithFrame:NSMakeRect(0,
                                                                          0,
                                                                          screenFrame.size.width,
                                                                          screenFrame.size.height)
                                                        images:images
                                                        labels:labels
                                                          tabs:tabs
                                                        frames:frames
                                                  wasMaximized:wasMaximized
                                                      putOnTop:selectedIndex] autorelease]];
    [window_ setContentView:view_];
    [window_ setBackgroundColor:[[NSColor blackColor] colorWithAlphaComponent:0]];
    [window_ setOpaque:NO];

    PseudoTerminal* hotKeyWindow = [controller hotKeyWindow];
    BOOL isHot = NO;
    if (hotKeyWindow) {
        isHot = [hotKeyWindow isHotKeyWindow];
        [hotKeyWindow setIsHotKeyWindow:NO];
    }
    [window_ makeKeyAndOrderFront:self];
    if (hotKeyWindow) {
        [hotKeyWindow setIsHotKeyWindow:isHot];
    }
}

- (int)_populateArrays:(NSMutableArray *)images
                labels:(NSMutableArray *)labels
                  tabs:(NSMutableArray *)tabs
          wasMaximized:(NSMutableArray*)wasMaximized
            controller:(iTermController *)controller
{
    int selectedIndex = 0;
    for (int i = 0; i < [controller numberOfTerminals]; i++) {
        PseudoTerminal* term = [controller terminalAtIndex:i];
        int j = 0;
        for (PTYTab* aTab in [term tabs]) {
            if (term == [controller currentTerminal] &&
                aTab == [term currentTab]) {
                selectedIndex = [images count];
            }
            [wasMaximized addObject:[NSNumber numberWithBool:[aTab hasMaximizedPane]]];
            if ([aTab hasMaximizedPane]) {
                [aTab unmaximize];
            }
            [images addObject:[aTab image:NO]];
            [tabs addObject:aTab];
            NSString* label = [iTermExpose labelForTab:aTab windowNumber:i+1 tabNumber:j+1];
            [labels addObject:label];
            j++;
        }
        assert(selectedIndex >= 0);

        [[[term window] animator] setAlphaValue:0];
    }
    return selectedIndex;
}

- (void)tabChangedSinceLastExpose
{
    for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
        for (PTYTab* aTab in [term tabs]) {
            for (PTYSession* aSession in [aTab sessions]) {
                PTYTextView* aTextView = [aSession TEXTVIEW];
                if ([aTextView getAndResetChangedSinceLastExpose]) {
                    [self updateTab:aTab];
                    break;
                }
            }
        }
    }
}

- (void)_toggleOff
{
    SetSystemUIMode(kUIModeNormal, 0);
    [[view_ grid] onSelection:nil session:nil];
}

- (void)_squareThumbGridSize:(float)aspectRatio n:(float)n cols_p:(int *)cols_p rows_p:(int *)rows_p
{
    /*
     We want to solve for rows, cols.

     aspectRatio * rows ~ cols
     rows * cols ~ n
     cols ~ n / rows
     aspectRatio * rows ~ n / rows
     rows^2 ~ n / aspectRatio
     rows ~ sqrt(n/aspectRatio)
     cols ~ n / rows
     */
    float rows1 = floor(n / sqrt(n / aspectRatio));
    float cols1 = ceil(n / rows1);

    float rows2 = ceil(n / sqrt(n / aspectRatio));
    float cols2 = ceil(n / rows2);

    float aspectRatio1 = cols1/rows1;
    float aspectRatio2 = cols2/rows2;

    float err1 = fabs(aspectRatio1-aspectRatio);
    float err2 = fabs(aspectRatio2-aspectRatio);
    if (err1 < err2) {
        *rows_p = rows1;
        *cols_p = cols1;
    } else {
        *rows_p = rows2;
        *cols_p = cols2;
    }
}

- (void)_optimalGridSize:(int *)cols_p rows_p:(int *)rows_p frames:(NSRect*)frames screenFrame:(NSRect)screenFrame images:(NSMutableArray *)images n:(float)n maxWindowsToOptimize:(const int)maxWindowsToOptimize
{
    const int numImages = [images count];
    NSRect tempFrames[numImages];
    // Try every possible combination of rows and columns and pick the one
    // that wastes the fewest pixels.
    float bestWaste = INFINITY;
    for (int i = 1; i <= maxWindowsToOptimize && i <= n; i++) {
        for (int j = 1; j <= maxWindowsToOptimize && (j-1)*i < n; j++) {
            if (i * j < n) {
                continue;
            }
            float wastedSpace = [self _layoutImages:images
                                               size:NSMakeSize(screenFrame.size.width / j,
                                                               screenFrame.size.height / i)
                                         screenFrame:screenFrame
                                             frames:tempFrames];
            if (wastedSpace < bestWaste) {
                bestWaste = wastedSpace;
                memcpy(frames, tempFrames, sizeof(tempFrames));
                *rows_p = i;
                *cols_p = j;
            }
        }
    }
}


@end
