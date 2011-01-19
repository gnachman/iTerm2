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

static const float THUMB_MARGIN = 25;

// This subclass of NSWindow is used for the fullscreen borderless window.
@interface iTermExposeWindow : NSWindow
{
}

- (BOOL)canBecomeKeyWindow;
- (void)keyDown:(NSEvent *)event;

@end

@implementation iTermExposeWindow

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    NSString *unmodkeystr = [event charactersIgnoringModifiers];
    unichar unmodunicode = [unmodkeystr length] > 0 ? [unmodkeystr characterAtIndex:0] : 0;
    if (unmodunicode == 27) {
        [iTermExpose toggle];
    }
}

@end

@class iTermExposeTabView;
@protocol iTermExposeTabViewDelegate

- (void)onSelection:(iTermExposeTabView*)theView;

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
}

+ (NSString*)labelForTab:(PTYTab*)aTab windowNumber:(int)i;
- (id)initWithImage:(NSImage*)image label:(NSString*)label tab:(PTYTab*)tab frame:(NSRect)frame fullSizeFrame:(NSRect)fullSizeFrame normalFrame:(NSRect)normalFrame delegate:(id<iTermExposeTabViewDelegate>)delegate;
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
- (id)tabObject;
- (void)clear;
- (void)setDirty:(BOOL)dirty;
- (BOOL)dirty;
- (void)setWindowIndex:(int)windowIndex tabIndex:(int)tabIndex;

@end

@implementation iTermExposeTabView

+ (NSString*)labelForTab:(PTYTab*)aTab windowNumber:(int)i
{
    if (i == 0) {
        return @"Defunct Tab";
    }
    NSString* jobName = [[aTab activeSession] jobName];
    if (jobName) {
        return [NSString stringWithFormat:@"%d. %@ (%@)", i, [[aTab activeSession] rawName], [[aTab activeSession] jobName]];
    } else {
        return [NSString stringWithFormat:@"%d. %@", i, [[aTab activeSession] rawName]];
    }
}

- (id)initWithImage:(NSImage*)image label:(NSString*)label tab:(PTYTab*)tab frame:(NSRect)frame fullSizeFrame:(NSRect)fullSizeFrame normalFrame:(NSRect)normalFrame delegate:(id<iTermExposeTabViewDelegate>)delegate
{
    self = [super initWithFrame:frame];
    if (self) {
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
    NSLog(@"Set frame of %x to %lfx%lf", self, normalFrame_.size.width, normalFrame_.size.height);
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
    if (windowIndex_ >= 0 && tabIndex_ >= 0) {
        [delegate_ onSelection:self];
    }
}

- (void)bringTabToFore
{
    if (windowIndex_ >= 0 && tabIndex_ >= 0) {
        iTermController* controller = [iTermController sharedInstance];
        PseudoTerminal* terminal = [[controller terminals] objectAtIndex:windowIndex_];
        [controller setCurrentTerminal:terminal];
        [[terminal window] makeKeyAndOrderFront:self];
        [[terminal tabView] selectTabViewItemAtIndex:tabIndex_];     
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
                           [NSColor whiteColor], NSForegroundColorAttributeName,
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
    [[NSColor darkGrayColor] set];
    [thePath stroke];
    
    [str drawWithRect:textRect
              options:NSLineBreakByClipping];
}

- (void)_drawDropShadow:(NSRect)aRect
{
    // create the shadow
    NSShadow *dropShadow = [[[NSShadow alloc] init] autorelease];
    [dropShadow setShadowColor:[[NSColor blackColor] colorWithAlphaComponent:0.5]];
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

- (void)drawRect:(NSRect)rect
{
    NSImage* image = [[image_ copy] autorelease];
    NSRect imageFrame = [self imageFrame:[self frame].size];
 
    if (windowIndex_ >= 0 && tabIndex_ >= 0) {
        [self _drawDropShadow:imageFrame];
    }
    
    [image setScalesWhenResized:YES];
    [image setSize:imageFrame.size];
    [image compositeToPoint:imageFrame.origin operation:NSCompositeSourceOver];
    
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

@end

// This is the content view of the exposé window. It shows a gradient in its
// background and may have a bunch of iTermExposeTabViews as children.
@interface iTermExposeView : NSView <iTermExposeTabViewDelegate>
{
    NSSize thumbSize_;
    int rows_;
    int cols_;
    iTermExposeTabView* focused_;
    NSImage* cache_;  // background image
}

- (id)initWithFrame:(NSRect)frame images:(NSArray*)images labels:(NSArray*)labels tabs:(NSArray*)tabs thumbSize:(NSSize)thumbSize rows:(int)rows cols:(int)cols;
- (void)dealloc;
- (NSPoint)_originOfItem:(int)i numItems:(int)n;
- (void)updateTab:(PTYTab*)theTab;
- (void)drawRect:(NSRect)rect;
- (NSRect)tabOrigin:(PTYTab *)theTab visibleScreenFrame:(NSRect)visibleScreenFrame screenFrame:(NSRect)screenFrame;
- (NSSize)zoomedSize:(NSSize)origin thumbSize:(NSSize)thumbSize screenFrame:(NSRect)screenFrame;
- (NSRect)zoomedFrame:(NSRect)dest size:(NSSize)origSize visibleScreenFrame:(NSRect)visibleScreenFrame;
- (void)addTab:(PTYTab *)theTab
         label:(NSString *)theLabel
         image:(NSImage *)theImage
   screenFrame:(NSRect)screenFrame
    visibleScreenFrame:(NSRect)visibleScreenFrame
        origin:(NSPoint)origin
     thumbSize:(NSSize)thumbSize;
// Delegate methods
- (void)onSelection:(iTermExposeTabView*)theView;
- (BOOL)recomputeIndices;

@end

@implementation iTermExposeView

static BOOL SizesEqual(NSSize a, NSSize b) {
    return (int)a.width == (int)b.width && (int)a.height == (int)b.height;
}

- (id)initWithFrame:(NSRect)frame images:(NSArray*)images labels:(NSArray*)labels tabs:(NSArray*)tabs thumbSize:(NSSize)thumbSize rows:(int)rows cols:(int)cols
{
    self = [super initWithFrame:frame];
    if (self) {
        NSScreen* theScreen = [NSScreen deepestScreen];
        NSRect screenFrame = [theScreen frame];
        NSRect visibleScreenFrame = [theScreen visibleFrame];
        NSLog(@"Screen origin is %lf, %lf", screenFrame.origin.x, screenFrame.origin.y);
        thumbSize_ = thumbSize;
        rows_ = rows;
        cols_ = cols;
        [self setAlphaValue:0];
        [[self animator] setAlphaValue:1];
        const int n = [images count];
        for (int i = 0; i < n; i++) {
            PTYTab* theTab = [tabs objectAtIndex:i];
            NSString* theLabel = [labels objectAtIndex:i];
            NSImage* theImage = [images objectAtIndex:i];
            
            [self addTab:theTab
                   label:theLabel
                   image:theImage
             screenFrame:screenFrame
                visibleScreenFrame:visibleScreenFrame
                  origin:[self _originOfItem:i
                                    numItems:n]
               thumbSize:thumbSize];

        }
        
    }
    return self;
}

- (void)dealloc
{
    for (iTermExposeTabView* tabView in [self subviews]) {
        [self removeTrackingRect:[tabView trackingRectTag]];
    }
    [cache_ release];
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
                         MIN(origSize.width + THUMB_MARGIN * 2,
                             screenFrame.size.width * 0.9));
    origSize.height = MAX(thumbSize.height,
                          MIN(origSize.height + THUMB_MARGIN * 2,
                              screenFrame.size.height * 0.9));
    return origSize;
}

- (void)drawRect:(NSRect)rect
{
    if (!cache_ || !SizesEqual([cache_ size], [self frame].size)) {
        [cache_ release];
        cache_ = [[NSImage alloc] initWithSize:[self frame].size];
        [cache_ lockFocus];
        NSGradient* aGradient = [[[NSGradient alloc]
                                  initWithStartingColor:[[NSColor blackColor] colorWithAlphaComponent:0]
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
    
    float xErr = 0;
    float yErr = 0;
    if (fullSizeFrame.origin.x < 0) {
        xErr = fullSizeFrame.origin.x;
    }
    if (fullSizeFrame.origin.x + fullSizeFrame.size.width >= visibleScreenFrame.size.width) {
        xErr = (fullSizeFrame.origin.x + fullSizeFrame.size.width) - visibleScreenFrame.size.width;
    }
    if (fullSizeFrame.origin.y < 0) {
        yErr = fullSizeFrame.origin.y;
    }
    if (fullSizeFrame.origin.y + fullSizeFrame.size.height > visibleScreenFrame.size.height) {
        yErr = (fullSizeFrame.origin.y + fullSizeFrame.size.height) - visibleScreenFrame.size.height;
    }
    fullSizeFrame.origin.x -= xErr;
    fullSizeFrame.origin.y -= yErr;
    return fullSizeFrame;
}

- (void)addTab:(PTYTab *)theTab
         label:(NSString *)theLabel
         image:(NSImage *)theImage
   screenFrame:(NSRect)screenFrame
    visibleScreenFrame:(NSRect)visibleScreenFrame
        origin:(NSPoint)thumbOrigin
     thumbSize:(NSSize)thumbSize
{
    NSRect tabRect = [self tabOrigin:theTab
                        visibleScreenFrame:visibleScreenFrame
                         screenFrame:screenFrame];
    NSRect dest;
    dest.origin = thumbOrigin;
    dest.size = thumbSize;
    
    NSSize origSize = [self zoomedSize:tabRect.size
                             thumbSize:thumbSize
                           screenFrame:screenFrame];
    
    NSRect fullSizeFrame = [self zoomedFrame:dest
                                        size:origSize
                          visibleScreenFrame:visibleScreenFrame];
    
    iTermExposeTabView* aView = [[iTermExposeTabView alloc] initWithImage:theImage
                                                                    label:theLabel
                                                                      tab:theTab
                                                                    frame:tabRect
                                                            fullSizeFrame:fullSizeFrame
                                                              normalFrame:dest
                                                                 delegate:self];
    [self addSubview:aView];
    [aView release];
    [[aView animator] setFrame:dest];
    [self performSelector:@selector(viewIsReady:)
               withObject:aView
               afterDelay:[[NSAnimationContext currentContext] duration]];
    
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
                [aView setLabel:[iTermExposeTabView labelForTab:theTab windowNumber:[aView windowIndex] + 1]];
            }
        }
    }
}

- (void)onSelection:(iTermExposeTabView*)theView
{
    [theView moveToTop];
    for (iTermExposeTabView* aView in [self subviews]) {
        if ([aView isKindOfClass:[iTermExposeTabView class]]) {
            [[aView animator] setFrame:[aView originalFrame]];
        }
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

- (void)viewIsReady:(iTermExposeTabView*)aView
{
    [aView showLabel];
    NSRect viewRect = [aView normalFrame];
    NSRect rect = [aView imageFrame:viewRect.size];
    rect.origin.x += viewRect.origin.x;
    rect.origin.y += viewRect.origin.y;
    
    NSTrackingRectTag oldTag = [aView trackingRectTag];
    if (oldTag) {
        [self removeTrackingRect:oldTag];
    }
    [aView setTrackingRectTag:[self addTrackingRect:rect
                                              owner:self
                                           userData:aView
                                       assumeInside:NO]];
}

- (void)mouseExited:(NSEvent *)event
{
    NSLog(@"mouseExited:%p", focused_);
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
        NSLog(@"mouseEntered:%p", focused_);
        [focused_ onMouseEnter];
        for (iTermExposeTabView* aView in [self subviews]) {
            if (aView != focused_ &&
                [aView isKindOfClass:[iTermExposeTabView class]]) {
                [[aView animator] setAlphaValue:0.8];
            }
        }
    }
}

- (NSPoint)_originOfItem:(int)i numItems:(int)n
{
    float rowOffset;
    if (i / cols_ == n / cols_) {
        int itemsInLastRow = n % cols_;
        rowOffset = ([self frame].size.width - itemsInLastRow * thumbSize_.width) / 2;
    } else {
        rowOffset = ([self frame].size.width - cols_ * thumbSize_.width) / 2;
    }
        
    float verticalOffset = ([self frame].size.height - rows_ * thumbSize_.height) / 2;
    int row = i / cols_;
    int col = i % cols_;
    float x = rowOffset + col * thumbSize_.width;
    NSLog(@"nr=%d, ipr=%d, row=%d, i=%d, vo=%f", rows_, cols_, row, i, verticalOffset);
    float y = thumbSize_.height * row + verticalOffset;
    return NSMakePoint(x, y);
}


@end

@interface iTermExpose (Private)
- (void)_toggleOn;
- (void)_toggleOff;
- (void)_populateArrays:(NSMutableArray *)images
                 labels:(NSMutableArray *)labels
                   tabs:(NSMutableArray *)tabs
             controller:(iTermController *)controller;
- (void)_squareThumbGridSize:(float)aspectRatio n:(float)n cols_p:(int *)cols_p rows_p:(int *)rows_p;
- (void)_optimalGridSize:(int *)cols_p rows_p:(int *)rows_p screenFrame:(NSRect)screenFrame images:(NSMutableArray *)images n:(float)n maxWindowsToOptimize:(const int)maxWindowsToOptimize;
- (NSSize)_compactThumbnailSize:(int)rows
                           cols:(int)cols
                    screenFrame:(NSRect)screenFrame
                         images:(NSArray*)images;
;
@end

@implementation iTermExpose

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
        [view_ updateTab:theTab];
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
}

- (void)showWindows:(BOOL)fade
{
    iTermController* controller = [iTermController sharedInstance];
    for (int i = 0; i < [controller numberOfTerminals]; i++) {
        PseudoTerminal* term = [controller terminalAtIndex:i];
        // TODO: this 0.9999 comes from PseudoTerminal. I don't know why it doesn't use 1. I should try using 1, it might be faster.
        if ([[term window] alphaValue] == 0) {
            if (fade) {
                [[[term window] animator] setAlphaValue:0.9999];
            } else {
                [[term window] setAlphaValue:0.9999];
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
    return NSMakeSize(origSize.width * scale, origSize.height * scale);
}

- (float)_wastedSpaceWithImages:(NSArray*)images
                           size:(NSSize)size
                     screenSize:(NSSize)screenSize
{
    float availableSpace = screenSize.width * screenSize.height;
    for (NSImage* anImage in images) {
        NSSize origSize = [anImage size];
        NSSize visibleSize = [self scaledImageSize:origSize thumbSize:size];
        availableSpace -= visibleSize.width * visibleSize.height;
    }
    return availableSpace;
}

- (void)_toggleOn
{
    iTermController* controller = [iTermController sharedInstance];
    
    // Crete parallel arrays with info needed to create subviews.
    NSMutableArray* images = [NSMutableArray arrayWithCapacity:[controller numberOfTerminals]];
    NSMutableArray* tabs = [NSMutableArray arrayWithCapacity:[controller numberOfTerminals]];
    NSMutableArray* labels = [NSMutableArray arrayWithCapacity:[controller numberOfTerminals]];

    [self _populateArrays:images
                   labels:labels
                     tabs:tabs
               controller:controller];

    
    // Figure out the right size for a thumbnail.
    NSScreen* theScreen = [NSScreen deepestScreen];
    NSRect screenFrame = [theScreen visibleFrame];

    float aspectRatio = screenFrame.size.width / screenFrame.size.height;
    float n = [images count];
    int rows = 1, cols = 1;

    // Computing the optimal grid size is O(n^2). Limit the number of iterations
    // to 30^2=900.
    const int maxWindowsToOptimize = 30;
    if (n > maxWindowsToOptimize) {
        [self _squareThumbGridSize:aspectRatio
                                 n:n
                                 cols_p:&cols
                                 rows_p:&rows];
    } else {
        [self _optimalGridSize:&cols
                        rows_p:&rows
                   screenFrame:screenFrame
                        images:images
                             n:n
             maxWindowsToOptimize:maxWindowsToOptimize];
    }
    
    // Get a good thumbnail size for this grid arrangement.
    NSSize thumbSize = [self _compactThumbnailSize:rows
                                              cols:cols
                                       screenFrame:screenFrame
                                            images:images];
    
    // Create the window and its view and show it.
    window_ = [[iTermExposeWindow alloc] initWithContentRect:screenFrame
                                                   styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES
                                                      screen:theScreen];
    [window_ setDelegate:self];
    view_ = [[iTermExposeView alloc] initWithFrame:NSMakeRect(0,
                                                              0,
                                                              screenFrame.size.width,
                                                              screenFrame.size.height)
                                            images:images
                                            labels:labels
                                              tabs:tabs
                                         thumbSize:thumbSize
                                              rows:rows
                                              cols:cols];
    [window_ setContentView:view_];
    [window_ setBackgroundColor:[[NSColor blackColor] colorWithAlphaComponent:0]];
    [window_ setOpaque:NO];
    [window_ makeKeyAndOrderFront:self];
}

- (void)_populateArrays:(NSMutableArray *)images
                 labels:(NSMutableArray *)labels
                   tabs:(NSMutableArray *)tabs
             controller:(iTermController *)controller
{
    for (int i = 0; i < [controller numberOfTerminals]; i++) {
        PseudoTerminal* term = [controller terminalAtIndex:i];
        int selectedIndex = -1;
        for (PTYTab* aTab in [term tabs]) {
            if (aTab == [term currentTab]) {
                selectedIndex = [images count];
            }
            [images addObject:[aTab image:NO]];
            [tabs addObject:aTab];
            NSString* label = [iTermExposeTabView labelForTab:aTab windowNumber:i];
            [labels addObject:label];
        }
        assert(selectedIndex >= 0);
        // Move the current tab to the end so its view will be above all the other tabs' views.
        [images exchangeObjectAtIndex:[images count]-1 withObjectAtIndex:selectedIndex];
        [tabs exchangeObjectAtIndex:[images count]-1 withObjectAtIndex:selectedIndex];
        [labels exchangeObjectAtIndex:[images count]-1 withObjectAtIndex:selectedIndex];
        
        [[[term window] animator] setAlphaValue:0];
    }
}

- (void)recomputeIndices:(NSNotification*)notification
{
    if (![view_ recomputeIndices]) {
        [self _toggleOff];
    }
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
    [view_ onSelection:nil];
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

- (void)_optimalGridSize:(int *)cols_p rows_p:(int *)rows_p screenFrame:(NSRect)screenFrame images:(NSMutableArray *)images n:(float)n maxWindowsToOptimize:(const int)maxWindowsToOptimize
{
    // Try every possible combination of rows and columns and pick the one
    // that wastes the fewest pixels.
    float bestWaste = INFINITY;
    for (int i = 1; i <= maxWindowsToOptimize; i++) {
        for (int j = 1; j <= maxWindowsToOptimize && (j-1)*i < n; j++) {
            if (i * j < n) {
                continue;
            }
            float wastedSpace = [self _wastedSpaceWithImages:images
                                                        size:NSMakeSize(screenFrame.size.width / j,
                                                                        screenFrame.size.height / i)
                                                  screenSize:screenFrame.size];
            if (wastedSpace < bestWaste) {
                bestWaste = wastedSpace;
                *rows_p = i;
                *cols_p = j;
            }
        }
    }
}

- (NSSize)_compactThumbnailSize:(int)rows
                           cols:(int)cols
                    screenFrame:(NSRect)screenFrame
                         images:(NSArray*)images
{
    // Make a guess at a good thumbnail size based on rows and columns. This
    // may not pack images very tightly if they're not the same aspect ratio
    // as the thumbSize.
    NSSize maxSizeThumb;
    NSSize thumbSize = NSMakeSize(screenFrame.size.width / cols,
                                  screenFrame.size.height / rows);
    
    
    // Figure out the largest bounding box of any image once they're all scaled
    // down to fit in the thumbSize. Use that as the actual thumbSize.
    maxSizeThumb.width = maxSizeThumb.height = 0;
    NSSize innerThumbSize = NSMakeSize(thumbSize.width - THUMB_MARGIN*2,
                                       thumbSize.height - THUMB_MARGIN*2);
    for (NSImage* anImage in images) {
        NSSize visibleSize = [self scaledImageSize:[anImage size] thumbSize:innerThumbSize];
        visibleSize.width += THUMB_MARGIN*2;
        visibleSize.height += THUMB_MARGIN*2;
        maxSizeThumb.width = MAX(maxSizeThumb.width, visibleSize.width);
        maxSizeThumb.height = MAX(maxSizeThumb.height, visibleSize.height);
    }
    thumbSize = maxSizeThumb;
    return thumbSize;
}

@end
