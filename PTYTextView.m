// -*- mode:objc -*-
// $Id: PTYTextView.m,v 1.325 2009-02-06 14:33:17 delx Exp $
/*
 **  PTYTextView.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **         Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: NSTextView subclass. The view object for the VT100 screen.
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

#define DEBUG_ALLOC           0
#define DEBUG_METHOD_TRACE    0
#define GREED_KEYDOWN         1
//#define DEBUG_DRAWING

#import <iTerm/iTerm.h>
#import <iTerm/PTYTextView.h>
#import <iTerm/PseudoTerminal.h>
#import <iTerm/PTYSession.h>
#import <iTerm/VT100Screen.h>
#import <iTerm/FindCommandHandler.h>
#import <iTerm/PreferencePanel.h>
#import <iTerm/PTYScrollView.h>
#import <iTerm/PTYTask.h>
#import <iTerm/iTermController.h>
#import <iTerm/NSStringITerm.h>
#import "iTermApplicationDelegate.h"
#import "PreferencePanel.h"

#include <sys/time.h>
#include <math.h>

static NSCursor* textViewCursor =  nil;

@implementation PTYTextView

+ (void) initialize
{
    NSImage *ibeamImage = [[NSCursor IBeamCursor] image];
    NSPoint hotspot = [[NSCursor IBeamCursor] hotSpot];
    NSImage *aCursorImage = [ibeamImage copy];
    NSImage *reverseCursorImage = [ibeamImage copy];
    [reverseCursorImage lockFocus];
    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(0,0,[reverseCursorImage size].width,[reverseCursorImage size].height));
    [ibeamImage compositeToPoint:NSMakePoint(0,0) operation:NSCompositeDestinationIn];
    [reverseCursorImage unlockFocus];
    [aCursorImage lockFocus];
    [reverseCursorImage compositeToPoint:NSMakePoint(2,0) operation:NSCompositePlusLighter];
    [aCursorImage unlockFocus];
    [reverseCursorImage release];
    textViewCursor = [[NSCursor alloc] initWithImage:aCursorImage hotSpot:hotspot];
    [aCursorImage release];
}

+ (NSCursor *) textViewCursor
{
    return textViewCursor;
}

- (id)initWithFrame: (NSRect) aRect
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif

    self = [super initWithFrame: aRect];
    dataSource=_delegate=markedTextAttributes=NULL;

    layoutManager = [[NSLayoutManager alloc] init];
    fallbackFonts = [[NSMutableDictionary alloc] init];

    [self setMarkedTextAttributes:
        [NSDictionary dictionaryWithObjectsAndKeys:
            defaultBGColor, NSBackgroundColorAttributeName,
            defaultFGColor, NSForegroundColorAttributeName,
            secondaryFont.font, NSFontAttributeName,
            [NSNumber numberWithInt:(NSUnderlineStyleSingle|NSUnderlineByWordMask)],
                NSUnderlineStyleAttributeName,
            NULL]];
    CURSOR=YES;
    lastFindX = oldStartX = startX = -1;
    markedText=nil;
    gettimeofday(&lastBlink, NULL);
    [[self window] useOptimizedDrawing:YES];

    // register for drag and drop
    [self registerForDraggedTypes: [NSArray arrayWithObjects:
        NSFilenamesPboardType,
        NSStringPboardType,
        nil]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_settingsChanged:)
                                                 name:@"iTermRefreshTerminal"
                                               object:nil];

    colorInvertedCursor = [[PreferencePanel sharedInstance] colorInvertedCursor];

    return (self);
}

- (BOOL) resignFirstResponder
{

    //NSLog(@"0x%x: %s", self, __PRETTY_FUNCTION__);

    return (YES);
}

- (BOOL) becomeFirstResponder
{

    //NSLog(@"0x%x: %s", self, __PRETTY_FUNCTION__);

    return (YES);
}

- (void)viewWillMoveToWindow:(NSWindow *)win
{

    //NSLog(@"0x%x: %s, will move view from %@ to %@", self, __PRETTY_FUNCTION__, [self window], win);
    if (!win && [self window] && trackingRectTag) {
        //NSLog(@"remove tracking");
        [self removeTrackingRect:trackingRectTag];
        trackingRectTag = 0;
    }
    [super viewWillMoveToWindow:win];
}

- (void)viewDidMoveToWindow
{
    //NSLog(@"0x%x: %s, moved view to %@", self, __PRETTY_FUNCTION__, [self window]);
    if ([self window]) {
        //NSLog(@"add tracking");
        trackingRectTag = [self addTrackingRect:[self frame] owner: self userData: nil assumeInside: NO];
    }

}

- (void)dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    int i;

    if (mouseDownEvent != nil) {
        [mouseDownEvent release];
        mouseDownEvent = nil;
    }

    //NSLog(@"remove tracking");
    if (trackingRectTag) {
        [self removeTrackingRect:trackingRectTag];
    }

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (i = 0; i < 256; i++) {
        [colorTable[i] release];
    }
    [defaultFGColor release];
    [defaultBGColor release];
    [defaultBoldColor release];
    [selectionColor release];
    [defaultCursorColor release];
    [layoutManager release];

    [self releaseFontInfo:&primaryFont];
    [self releaseFontInfo:&secondaryFont];

    [markedTextAttributes release];
    [markedText release];

    [self releaseAllFallbackFonts];
    [fallbackFonts release];

    [super dealloc];

#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x, done", __PRETTY_FUNCTION__, self);
#endif
}

- (BOOL)shouldDrawInsertionPoint
{
#if 0 // DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView shouldDrawInsertionPoint]",
          __FILE__, __LINE__);
#endif
    return NO;
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)isOpaque
{
    return YES;
}


- (BOOL) antiAlias
{
    return (antiAlias);
}

- (void) setAntiAlias: (BOOL) antiAliasFlag
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView setAntiAlias: %d]",
          __FILE__, __LINE__, antiAliasFlag);
#endif
    antiAlias = antiAliasFlag;
    [self setNeedsDisplay:YES];
}

- (BOOL) disableBold
{
    return (disableBold);
}

- (void) setDisableBold: (BOOL) boldFlag
{
    disableBold = boldFlag;
    [self setNeedsDisplay:YES];
}


- (BOOL) blinkingCursor
{
    return (blinkingCursor);
}

- (void) setBlinkingCursor: (BOOL) bFlag
{
    blinkingCursor = bFlag;
}

- (NSDictionary*) markedTextAttributes
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView selectedTextAttributes]",
          __FILE__, __LINE__);
#endif
    return markedTextAttributes;
}

- (void) setMarkedTextAttributes: (NSDictionary *) attr
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView setSelectedTextAttributes:%@]",
          __FILE__, __LINE__,attr);
#endif
    [markedTextAttributes release];
    [attr retain];
    markedTextAttributes=attr;
}

- (void) setFGColor:(NSColor*)color
{
    [defaultFGColor release];
    [color retain];
    defaultFGColor=color;
    [self setNeedsDisplay:YES];
    // reset our default character attributes
}

- (void) setBGColor:(NSColor*)color
{
    [defaultBGColor release];
    [color retain];
    defaultBGColor=color;
    //    bg = [bg colorWithAlphaComponent: [[SESSION backgroundColor] alphaComponent]];
    //    fg = [fg colorWithAlphaComponent: [[SESSION foregroundColor] alphaComponent]];
    [self setNeedsDisplay:YES];
}

- (void) setBoldColor: (NSColor*)color
{
    [defaultBoldColor release];
    [color retain];
    defaultBoldColor=color;
    [self setNeedsDisplay:YES];
}

- (void) setCursorColor: (NSColor*)color
{
    [defaultCursorColor release];
    [color retain];
    defaultCursorColor=color;
    [self setNeedsDisplay:YES];
}

- (void) setSelectedTextColor: (NSColor *) aColor
{
    [selectedTextColor release];
    [aColor retain];
    selectedTextColor = aColor;
    [self setNeedsDisplay:YES];
}

- (void) setCursorTextColor:(NSColor*) aColor
{
    [cursorTextColor release];
    [aColor retain];
    cursorTextColor = aColor;
    [self setNeedsDisplay:YES];
}

- (NSColor *) cursorTextColor
{
    return (cursorTextColor);
}

- (NSColor *) selectedTextColor
{
    return (selectedTextColor);
}

- (NSColor *) defaultFGColor
{
    return defaultFGColor;
}

- (NSColor *) defaultBGColor
{
    return defaultBGColor;
}

- (NSColor *) defaultBoldColor
{
    return defaultBoldColor;
}

- (NSColor *) defaultCursorColor
{
    return defaultCursorColor;
}

- (void) setColorTable:(int) theIndex color:(NSColor *)theColor
{
    [colorTable[theIndex] release];
    [theColor retain];
    colorTable[theIndex] = theColor;
    [self setNeedsDisplay:YES];
}

- (NSColor *)colorForCode:(int)theIndex
{
    NSColor *color;

    if (theIndex & DEFAULT_FG_COLOR_CODE) {
        // special colors?
        switch (theIndex) {
            case SELECTED_TEXT:
                color = selectedTextColor;
                break;
            case CURSOR_TEXT:
                color = cursorTextColor;
                break;
            case DEFAULT_BG_COLOR_CODE:
                color = defaultBGColor;
                break;
            default:
                if(theIndex & BOLD_MASK) {
                    color = theIndex-BOLD_MASK == DEFAULT_BG_COLOR_CODE ? defaultBGColor : [self defaultBoldColor];
                }
                else {
                    color = defaultFGColor;
                }
        }
    }
    else {
        // Render bold text as bright. The spec (ECMA-48) describes the intense
        // display setting (esc[1m) as "bold or bright". One user complained that
        // bold black on black bg didn't show up. Let's try making all bold text
        // also bright and see how that works.
        // If this is unpopular, make it bright iff the foreground=background.
        if ((theIndex & BOLD_MASK) &&
            (theIndex % 256 < 8)) {
            theIndex = (theIndex & ~BOLD_MASK) + 8;
        }
        color = colorTable[theIndex & 0xff];
    }

    return color;
}

- (NSColor *) selectionColor
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView selectionColor]",
          __FILE__, __LINE__);
#endif

    return selectionColor;
}

- (void) setSelectionColor: (NSColor *) aColor
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView setSelectionColor:%@]",
          __FILE__, __LINE__,aColor);
#endif
    [selectionColor release];
    [aColor retain];
    selectionColor=aColor;
    [self setNeedsDisplay:YES];
}

- (NSFont *)font
{
    return primaryFont.font;
}

- (NSFont *)nafont
{
    return secondaryFont.font;
}

+ (NSSize)charSizeForFont:(NSFont*)aFont horizontalSpacing:(float)hspace verticalSpacing:(float)vspace
{
    NSMutableDictionary *dic = [NSMutableDictionary dictionary];

    [dic setObject:aFont forKey:NSFontAttributeName];
    NSSize size = [@"W" sizeWithAttributes:dic];

    size.width = ceil(size.width * hspace);
    size.height = ceil(vspace * ceil([aFont ascender] - [aFont descender] + [aFont leading]));
    return size;
}

- (float)horizontalSpacing
{
    return horizontalSpacing_;
}

- (float)verticalSpacing
{
    return verticalSpacing_;
}

- (void)setFont:(NSFont*)aFont nafont:(NSFont *)naFont horizontalSpacing:(float)horizontalSpacing verticalSpacing:(float)verticalSpacing
{
    NSSize sz = [PTYTextView charSizeForFont:aFont horizontalSpacing:1.0 verticalSpacing:1.0];

    charWidthWithoutSpacing = sz.width;
    charHeightWithoutSpacing = sz.height;
    horizontalSpacing_ = horizontalSpacing;
    verticalSpacing_ = verticalSpacing;
    charWidth = ceil(charWidthWithoutSpacing * horizontalSpacing);
    lineHeight = ceil(charHeightWithoutSpacing * verticalSpacing);
    [self modifyFont:aFont info:&primaryFont];
    [self modifyFont:naFont info:&secondaryFont];

    // Cannot keep fallback fonts if the primary font changes because their
    // baseline offsets are set by the primary font. It's simplest to remove
    // them and then re-add them as needed.
    [self releaseAllFallbackFonts];

    // Force the secondary font to use the same baseline as the primary font.
    secondaryFont.baselineOffset = primaryFont.baselineOffset;

    [self setMarkedTextAttributes:
        [NSDictionary dictionaryWithObjectsAndKeys:
            defaultBGColor, NSBackgroundColorAttributeName,
            defaultFGColor, NSForegroundColorAttributeName,
            secondaryFont.font, NSFontAttributeName,
            [NSNumber numberWithInt:(NSUnderlineStyleSingle|NSUnderlineByWordMask)],
                NSUnderlineStyleAttributeName,
            NULL]];
    [self setNeedsDisplay:YES];

    NSScrollView* scrollview = [self enclosingScrollView];
    [scrollview setLineScroll:[self lineHeight]];
    [scrollview setPageScroll:2*[self lineHeight]];
}

- (void)changeFont:(id)fontManager
{
    if ([[PreferencePanel sharedInstance] onScreen]) {
        [[PreferencePanel sharedInstance] changeFont:fontManager];
    } else if ([[PreferencePanel sessionsInstance] onScreen]) {
        [[PreferencePanel sessionsInstance] changeFont:fontManager];
    }
}

- (id) dataSource
{
    return (dataSource);
}

- (void) setDataSource: (id) aDataSource
{
    dataSource = aDataSource;
}

- (id) delegate
{
    return _delegate;
}

- (void) setDelegate: (id) aDelegate
{
    _delegate = aDelegate;
}

- (float)lineHeight
{
    return ceil(lineHeight);
}

- (void) setLineHeight: (float) aLineHeight
{
    lineHeight = aLineHeight;
}

- (float) charWidth
{
    return ceil(charWidth);
}

- (void) setCharWidth: (float) width
{
    charWidth = width;
}

#ifdef DEBUG_DRAWING
NSMutableArray* screens=0;
- (void)appendDebug:(NSString*)str
{
    if (!screens) {
        screens = [[NSMutableArray alloc] init];
    }
    [screens addObject:str];
    if ([screens count] > 100) {
        [screens removeObjectAtIndex:0];
    }
}
#endif

- (NSRect)scrollViewContentSize
{
    NSRect r = NSMakeRect(0, 0, 0, 0);
    r.size = [[self enclosingScrollView] contentSize];
    return r;
}

- (float)excess
{
    NSRect visible = [self scrollViewContentSize];
    int rows = visible.size.height / lineHeight;
    float usablePixels = rows * lineHeight;
    return visible.size.height - usablePixels;
}

// We override this method since both refresh and window resize can conflict
// resulting in this happening twice So we do not allow the size to be set
// larger than what the data source can fill
- (void)setFrameSize:(NSSize)frameSize
{
    // Force the height to always be correct
    frameSize.height = [dataSource numberOfLines] * lineHeight + [self excess];
    [super setFrameSize:frameSize];
}

static BOOL RectsEqual(NSRect* a, NSRect* b) {
        return a->origin.x == b->origin.x &&
                   a->origin.y == b->origin.y &&
               a->size.width == b->size.width &&
           a->size.height == b->size.height;
}

- (void)refresh
{
    if(dataSource == nil) return;

    // reset tracking rect
    NSRect visibleRect = [self visibleRect];
    if (!trackingRectTag || !RectsEqual(&visibleRect, &_trackingRect)) {
        if (trackingRectTag) {
            [self removeTrackingRect:trackingRectTag];
        }
        // This call is very slow.
        trackingRectTag = [self addTrackingRect:visibleRect owner:self userData:nil assumeInside:NO];
        _trackingRect = visibleRect;
    }

    // number of lines that have disappeared if circular buffer is full
    int scrollbackOverflow = [dataSource scrollbackOverflow];
    [dataSource resetScrollbackOverflow];

    // frame size changed?
    int height = [dataSource numberOfLines] * lineHeight;
    NSRect frame = [self frame];

    NSRect visible = [self scrollViewContentSize];
    int rows = visible.size.height / lineHeight;
    float usablePixels = rows * lineHeight;
    float excess = visible.size.height - usablePixels;

    if ((int)(height + excess) != frame.size.height) {
        // The old iTerm code had a comment about a hack at this location
        // that worked around an (alleged) but in NSClipView not respecting
        // setCopiesOnScroll:YES and a gross workaround. The workaround caused
        // drawing bugs on Snow Leopard. It was a performance optimization, but
        // the penalty was too great.
        //
        // I believe the redraw errors occurred because they disabled drawing
        // for the duration of the call. [drawRects] was called (in another thread?)
        // and didn't redraw some invalid rects. Those rects never got another shot
        // at being drawn. They had originally been invalidated because they had
        // new content. The bug only happened when drawRect was called twice for
        // the same screen (I guess because the timer fired while the screen was
        // being updated).

        // Resize the frame
        frame.size.height = height;
        [self setFrame:frame];
    } else if (scrollbackOverflow > 0) {
        // Some number of lines were lost from the head of the buffer.

        NSScrollView* scrollView = [self enclosingScrollView];
        float amount = [scrollView verticalLineScroll] * scrollbackOverflow;
        BOOL userScroll = [(PTYScroller*)([scrollView verticalScroller]) userScroll];

        // Keep correct selection highlighted
        startY -= scrollbackOverflow;
        if (startY < 0) {
            startX = -1;
        }
        endY -= scrollbackOverflow;
        oldStartY -= scrollbackOverflow;
        if (oldStartY < 0) {
            oldStartX = -1;
        }
        oldEndY -= scrollbackOverflow;

        // Keep the user's current scroll position, nothing to redraw.
        if (userScroll) {
            BOOL redrawAll = NO;
            NSRect scrollRect = [self visibleRect];
            scrollRect.origin.y -= amount;
            if (scrollRect.origin.y < 0) {
                scrollRect.origin.y = 0;
                redrawAll = YES;
                [self setNeedsDisplay:YES];
            }
            [self scrollRectToVisible:scrollRect];
            if (!redrawAll) {
                return;
            }
        }

        // Shift the old content upwards
        if (scrollbackOverflow < [dataSource height] && !userScroll) {
            [self scrollRect:[self visibleRect] by:NSMakeSize(0, -amount)];

#ifdef DEBUG_DRAWING
            [self appendDebug:[NSString stringWithFormat:@"refresh: Scroll by %d", (int)amount]];
#endif
            if ([self needsDisplay]) {
                // If any part of the view needed to be drawn prior to
                // scrolling, mark the whole thing as needing to be redrawn.
                // This avoids some race conditions between scrolling and
                // drawing.  For example, if there was a region that needed to
                // be displayed because the underlying data changed, but before
                // drawRect is called we scroll with [self scrollRect], then
                // the wrong region will be drawn. This could be optimized by
                // storing the regions that need to be drawn and re-invaliding
                // them in their new positions, but it should be somewhat rare
                // that this branch of the if statement is taken.
                [self setNeedsDisplay:YES];
            } else {
                // Invalidate the bottom of the screen that was revealed by
                // scrolling.
                NSRect dr = NSMakeRect(0, frame.size.height - amount, frame.size.width, amount);
#ifdef DEBUG_DRAWING
                [self appendDebug:[NSString stringWithFormat:@"refresh: setNeedsDisplayInRect:%d,%d %dx%d", (int)dr.origin.x, (int)dr.origin.y, (int)dr.size.width, (int)dr.size.height]];
#endif
                [self setNeedsDisplayInRect:dr];
            }
        }
    }

    [self updateDirtyRects];
}


- (NSRect)adjustScroll:(NSRect)proposedVisibleRect
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView adjustScroll]", __FILE__, __LINE__ );
#endif
    proposedVisibleRect.origin.y=(int)(proposedVisibleRect.origin.y/lineHeight+0.5)*lineHeight;
    return proposedVisibleRect;
}

-(void) scrollLineUp: (id) sender
{
    NSRect scrollRect;

    scrollRect= [self visibleRect];
    scrollRect.origin.y-=[[self enclosingScrollView] verticalLineScroll];
    if (scrollRect.origin.y<0) scrollRect.origin.y=0;
    //NSLog(@"%f/%f",[[self enclosingScrollView] verticalLineScroll],[[self enclosingScrollView] verticalPageScroll]);
    [self scrollRectToVisible: scrollRect];
}

-(void) scrollLineDown: (id) sender
{
    NSRect scrollRect;

    scrollRect= [self visibleRect];
    scrollRect.origin.y+=[[self enclosingScrollView] verticalLineScroll];
    [self scrollRectToVisible: scrollRect];
}

-(void) scrollPageUp: (id) sender
{
    NSRect scrollRect;

    scrollRect= [self visibleRect];
    scrollRect.origin.y-= scrollRect.size.height - [[self enclosingScrollView] verticalPageScroll];
    [self scrollRectToVisible: scrollRect];
}

-(void) scrollPageDown: (id) sender
{
    NSRect scrollRect;

    scrollRect= [self visibleRect];
    scrollRect.origin.y+= scrollRect.size.height - [[self enclosingScrollView] verticalPageScroll];
    [self scrollRectToVisible: scrollRect];
}

-(void) scrollHome
{
    NSRect scrollRect;

    scrollRect= [self visibleRect];
    scrollRect.origin.y = 0;
    [self scrollRectToVisible: scrollRect];
}

- (void)scrollEnd
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView scrollEnd]", __FILE__, __LINE__ );
#endif

    if ([dataSource numberOfLines] <= 0) {
      return;
    }
    NSRect lastLine = [self visibleRect];
    lastLine.origin.y = ([dataSource numberOfLines] - 1) * lineHeight + [self excess];
    lastLine.size.height = lineHeight;
    [self scrollRectToVisible:lastLine];
}

- (void)scrollToSelection
{
    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = startY * lineHeight;
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = (endY - startY + 1) *lineHeight;
    [self scrollRectToVisible: aFrame];
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
}

-(void) hideCursor
{
    CURSOR=NO;
}

-(void) showCursor
{
    CURSOR=YES;
}

-(void)_debugLogScreenContents
{
    NSRect rect = [self visibleRect];
    [self lockFocus];
    int x,y;
    DebugLog([NSString stringWithFormat:@"visible rect is %d,%d %dx%d", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]);
    for (y=rect.origin.y; y < rect.origin.y + rect.size.height; ++y) {
        NSMutableString* line = [[NSMutableString alloc] init];
        [line autorelease];
        int i = 0;
        int count = 0;
        int prev = -1;
        for (x=rect.origin.x; x <= rect.origin.x + rect.size.width; ++x, ++i) {
            NSColor *theColor;
            int b;
            if (x < rect.origin.x + rect.size.width) {
                theColor = NSReadPixel(NSMakePoint(x, y));
                b = (int)(10*[theColor brightnessComponent]);
            } else {
                // last pix on the line, force output.
                b = -1;
            }
            if (prev == -1) {
                // first pixel on the line
                prev = b;
                count = 1;
            } else if (b == prev) {
                // repeated value
                ++count;
            } else {
                // value changed, output previous value
                [line appendFormat:@"%c%d", 'a'+prev, count];
                prev = b;
                count = 1;
            }
        }

        DebugLog(line);
    }
    [self unlockFocus];
}

- (void)drawRect:(NSRect)rect
{
#ifdef DEBUG_DRAWING
    static int iteration=0;
    static BOOL prevBad=NO;
    ++iteration;
    if (prevBad) {
        NSLog(@"Last was bad.");
        prevBad = NO;
    }
#endif
    DebugLog([NSString stringWithFormat:@"%s(0x%x):-[PTYTextView drawRect:(%f,%f,%f,%f) frameRect: (%f,%f,%f,%f)]",
          __PRETTY_FUNCTION__, self,
          rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
          [self frame].origin.x, [self frame].origin.y, [self frame].size.width, [self frame].size.height]);
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(0x%x):-[PTYTextView drawRect:(%f,%f,%f,%f) frameRect: (%f,%f,%f,%f)]",
        __PRETTY_FUNCTION__, self,
        rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
        [self frame].origin.x, [self frame].origin.y, [self frame].size.width, [self frame].size.height);
#endif

    float curLineWidth = [dataSource width] * charWidth;
    if (lineHeight <= 0 || curLineWidth <= 0) {
        DebugLog(@"height or width too small");
        return;
    }

    // Configure graphics
    [[NSGraphicsContext currentContext] setShouldAntialias: antiAlias];
    [[NSGraphicsContext currentContext] setCompositingOperation: NSCompositeCopy];

    // Where to start drawing?
    int lineStart = rect.origin.y / lineHeight;
    int lineEnd = lineStart + ceil(rect.size.height / lineHeight);

    // Ensure valid line ranges
    if(lineStart < 0) {
        lineStart = 0;
    }
    if (lineEnd > [dataSource numberOfLines]) {
        lineEnd = [dataSource numberOfLines];
    }
    NSRect visible = [self scrollViewContentSize];
    int vh = visible.size.height;
    int lh = lineHeight;
    int visibleRows = vh/lh;
    int firstVisibleRow = [[[dataSource session] SCROLLVIEW] documentVisibleRect].origin.y / lh;
    if (lineEnd > firstVisibleRow + visibleRows) {
        lineEnd = firstVisibleRow + visibleRows;
    }

    DebugLog([NSString stringWithFormat:@"Draw lines in [%d, %d)", lineStart, lineEnd]);
    // Draw each line
#ifdef DEBUG_DRAWING
    NSMutableDictionary* dct =
    [NSDictionary dictionaryWithObjectsAndKeys:
     [NSColor textBackgroundColor], NSBackgroundColorAttributeName,
     [NSColor textColor], NSForegroundColorAttributeName,
     [NSFont userFixedPitchFontOfSize: 0], NSFontAttributeName, NULL];
#endif
    int overflow = [dataSource scrollbackOverflow];
#ifdef DEBUG_DRAWING
    NSMutableString* lineDebug = [NSMutableString stringWithFormat:@"drawRect:%d,%d %dx%d drawing these lines with scrollback overflow of %d, iteration=%d:\n", (int)rect.origin.x, (int)rect.origin.y, (int)rect.size.width, (int)rect.size.height, (int)[dataSource scrollbackOverflow], iteration];
#endif
    for(int line = lineStart; line < lineEnd; line++) {
        NSRect lineRect = [self visibleRect];
        lineRect.origin.y = line*lineHeight;
        lineRect.size.height = lineHeight;
        if([self needsToDrawRect:lineRect]) {
///            NSLog(@"drawing %d", line);
            if (overflow <= line) {
                // If overflow > 0 then the lines in the dataSource are not
                // lined up in the normal way with the view. This happens when
                // the datasource has scrolled its contents up but -[refresh]
                // has not been called yet, so the view's contents haven't been
                // scrolled up yet. When that's the case, the first line of the
                // view is what the first line of the datasource was before
                // it overflowed. Continue to draw text in this out-of-alignment
                // manner until refresh is called and gets things in sync again.
                [self _drawLine:line-overflow AtY:line*lineHeight];
            }
            // if overflow > line then the requested line cannot be drawn
            // because it has been lost to the sands of time.
#ifdef DEBUG_DRAWING
            screen_char_t* theLine = [dataSource getLineAtIndex:line-overflow];
            for (int i = 0; i < [dataSource width]; ++i) {
                [lineDebug appendFormat:@"%c", theLine[i].ch];
            }
            [lineDebug appendString:@"\n"];
            [[NSString stringWithFormat:@"Iter %d, line %d", iteration, line] drawInRect:NSMakeRect(rect.size.width-200, line*lineHeight, 200, lineHeight) withAttributes:dct];
#endif
        }
    }
#ifdef DEBUG_DRAWING
    [self appendDebug:lineDebug];
#endif
    NSRect excessRect;
    excessRect.origin.x = 0;
    excessRect.origin.y = lineEnd*lineHeight; //lineEnd * lineHeight;
    excessRect.size.width = [[self enclosingScrollView] contentSize].width;
    excessRect.size.height = 15; //[self excess];
#if 0
    // Draws the excess bar in a different color each time
    static int i;
    i++;
    float r = ((float)((i + 0) % 100)) / 100;
    float g = ((float)((i + 33) % 100)) / 100;
    float b = ((float)((i + 66) % 100)) / 100;
    [[NSColor colorWithDeviceRed:r green:g blue:b alpha:1] set];
#else
    [defaultBGColor set];
#endif
    NSRectFill(excessRect);

#ifdef DEBUG_DRAWING
    // Draws a different-colored rectangle around each drawn area. Useful for
    // seeing which groups of lines were drawn in a batch.
    static float it;
    it += 3.14/4;
    float red = sin(it);
    float green = sin(it + 1*2*3.14/3);
    float blue = sin(it + 2*2*3.14/3);
    NSColor* c = [NSColor colorWithDeviceRed:red green:green blue:blue alpha:1];
    [c set];
    NSRect r = rect;
    r.origin.y++;
    r.size.height -= 2;
    NSFrameRect(rect);
    if (overflow != 0) {
        // Draw a diagonal line through blocks that were drawn when there
        // [dataSource scrollbackOverflow] > 0.
        [NSBezierPath strokeLineFromPoint:NSMakePoint(r.origin.x, r.origin.y)
                                  toPoint:NSMakePoint(r.origin.x + r.size.width, r.origin.y + r.size.height)];
    }
    NSString* debug;
    if (overflow == 0) {
        debug = [NSString stringWithFormat:@"origin=%d", (int)rect.origin.y];
    } else {
        debug = [NSString stringWithFormat:@"origin=%d, overflow=%d", (int)rect.origin.y, (int)overflow];
    }
    [debug drawInRect:rect withAttributes:dct];
#endif
    // Draw cursor
    [self _drawCursor];

    if (gDebugLogging) {
        [self _debugLogScreenContents];
    }
#ifdef DEBUG_DRAWING
    if (overflow) {
        // It's useful to put a breakpoint at the top of this function
        // when prevBad == YES because then you can see the results of this
        // draw function.
        prevBad=YES;
    }
#endif
}

- (void)keyDown:(NSEvent*)event
{
    id delegate = [self delegate];
    unsigned int modflag = [event modifierFlags];
    BOOL prev = [self hasMarkedText];

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView keyDown:%@]", __FILE__, __LINE__, event );
#endif

    keyIsARepeat = [event isARepeat];

    // Hide the cursor
    [NSCursor setHiddenUntilMouseMoves:YES];

    // Should we process the event immediately in the delegate?
    if ((!prev) &&
        ([delegate hasKeyMappingForEvent:event highPriority:YES] ||
         (modflag & (NSNumericPadKeyMask | NSFunctionKeyMask)) ||
         ((modflag & NSAlternateKeyMask) && [delegate optionKey] != OPT_NORMAL)))
    {
        [delegate keyDown:event];
        return;
    }

    // Let the IME process key events
    IM_INPUT_INSERT = NO;
    [self interpretKeyEvents:[NSArray arrayWithObject:event]];

    // If the IME didn't want it, pass it on to the delegate
    if (!prev &&
        !IM_INPUT_INSERT &&
        ![self hasMarkedText]) {
        [delegate keyDown:event];
    }
}

- (BOOL) keyIsARepeat
{
    return (keyIsARepeat);
}

- (void) otherMouseDown: (NSEvent *) event
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s: %@]", __PRETTY_FUNCTION__, event);
#endif

    NSPoint locationInWindow, locationInTextView;
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    if (([[self delegate] xtermMouseReporting])
        && (locationInTextView.y > visibleRect.origin.y) && !([event modifierFlags] & NSAlternateKeyMask))
        //        && ([event modifierFlags] & NSCommandKeyMask == 0))
    {
        int rx, ry;
        rx = (locationInTextView.x-MARGIN - visibleRect.origin.x)/charWidth;
        ry = (locationInTextView.y - visibleRect.origin.y)/lineHeight;
        if (rx < 0) rx = -1;
        if (ry < 0) ry = -1;
        VT100Terminal *terminal = [dataSource terminal];
        PTYSession* session = [dataSource session];

        int bnum = [event buttonNumber];
        if (bnum == 2) bnum = 1;

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_NORMAL:
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                reportingMouseDown = YES;
                [session writeTask:[terminal mousePress:bnum withModifiers:[event modifierFlags] atX:rx Y:ry]];
                return;
                break;
            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }

    if([[PreferencePanel sharedInstance] pasteFromClipboard])
        [self paste: nil];
    else
        [self pasteSelection: nil];
}

- (void)otherMouseUp:(NSEvent *)event
{
    NSPoint locationInWindow, locationInTextView;
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    if (([[self delegate] xtermMouseReporting])
        && reportingMouseDown && !([event modifierFlags] & NSAlternateKeyMask))
    {
        reportingMouseDown = NO;
        int rx, ry;
        rx = (locationInTextView.x-MARGIN - visibleRect.origin.x)/charWidth;
        ry = (locationInTextView.y - visibleRect.origin.y)/lineHeight;
        if (rx < 0) rx = -1;
        if (ry < 0) ry = -1;
        VT100Terminal *terminal = [dataSource terminal];
        PTYSession* session = [dataSource session];

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_NORMAL:
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                [session writeTask:[terminal mouseReleaseAtX:rx Y:ry]];
                return;
                break;
            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }
    [super otherMouseUp:event];
}

- (void)otherMouseDragged:(NSEvent *)event
{
    NSPoint locationInWindow, locationInTextView;
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    if (([[self delegate] xtermMouseReporting])
        && (locationInTextView.y > visibleRect.origin.y)
        && reportingMouseDown && !([event modifierFlags] & NSAlternateKeyMask))
    {
        int rx, ry;
        rx = (locationInTextView.x-MARGIN - visibleRect.origin.x)/charWidth;
        ry = (locationInTextView.y - visibleRect.origin.y)/lineHeight;
        if (rx < 0) rx = -1;
        if (ry < 0) ry = -1;
        VT100Terminal *terminal = [dataSource terminal];
        PTYSession* session = [dataSource session];

        int bnum = [event buttonNumber];
        if (bnum == 2) bnum = 1;

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_NORMAL:
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                [session writeTask:[terminal mouseMotion:bnum withModifiers:[event modifierFlags] atX:rx Y:ry]];
                return;
                break;
            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }
    [super otherMouseDragged:event];
}

- (void) rightMouseDown: (NSEvent *) event
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s: %@]", __PRETTY_FUNCTION__, event);
#endif

    NSPoint locationInWindow, locationInTextView;
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    if (([[self delegate] xtermMouseReporting])
        && (locationInTextView.y > visibleRect.origin.y) && !([event modifierFlags] & NSAlternateKeyMask))
        //        && ([event modifierFlags] & NSCommandKeyMask == 0))
    {
        int rx, ry;
        rx = (locationInTextView.x-MARGIN - visibleRect.origin.x)/charWidth;
        ry = (locationInTextView.y - visibleRect.origin.y)/lineHeight;
        if (rx < 0) rx = -1;
        if (ry < 0) ry = -1;
        VT100Terminal *terminal = [dataSource terminal];
        PTYSession* session = [dataSource session];

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_NORMAL:
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                reportingMouseDown = YES;
                [session writeTask:[terminal mousePress:2 withModifiers:[event modifierFlags] atX:rx Y:ry]];
                return;
                break;
            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }
    [super rightMouseDown:event];
}

- (void)rightMouseUp:(NSEvent *)event
{
    NSPoint locationInWindow, locationInTextView;
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    if (([[self delegate] xtermMouseReporting])
        && reportingMouseDown && !([event modifierFlags] & NSAlternateKeyMask))
    {
        reportingMouseDown = NO;
        int rx, ry;
        rx = (locationInTextView.x-MARGIN - visibleRect.origin.x)/charWidth;
        ry = (locationInTextView.y - visibleRect.origin.y)/lineHeight;
        if (rx < 0) rx = -1;
        if (ry < 0) ry = -1;
        VT100Terminal *terminal = [dataSource terminal];
        PTYSession* session = [dataSource session];

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_NORMAL:
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                [session writeTask:[terminal mouseReleaseAtX:rx Y:ry]];
                return;
                break;
            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }
    [super rightMouseUp:event];
}

- (void)rightMouseDragged:(NSEvent *)event
{
    NSPoint locationInWindow, locationInTextView;
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    if (([[self delegate] xtermMouseReporting])
        && (locationInTextView.y > visibleRect.origin.y)
        && reportingMouseDown && !([event modifierFlags] & NSAlternateKeyMask))
    {
        int rx, ry;
        rx = (locationInTextView.x-MARGIN - visibleRect.origin.x)/charWidth;
        ry = (locationInTextView.y - visibleRect.origin.y)/lineHeight;
        if (rx < 0) rx = -1;
        if (ry < 0) ry = -1;
        VT100Terminal *terminal = [dataSource terminal];
        PTYSession* session = [dataSource session];

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_NORMAL:
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                [session writeTask:[terminal mouseMotion:2 withModifiers:[event modifierFlags] atX:rx Y:ry]];
                return;
                break;
            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }
    [super rightMouseDragged:event];
}

- (void)scrollWheel:(NSEvent *)event
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s: %@]", __PRETTY_FUNCTION__, event);
#endif

    NSPoint locationInWindow, locationInTextView;
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    if (([[self delegate] xtermMouseReporting])
        && (locationInTextView.y > visibleRect.origin.y) && !([event modifierFlags] & NSAlternateKeyMask))
        //        && ([event modifierFlags] & NSCommandKeyMask == 0))
    {
        int rx, ry;
        rx = (locationInTextView.x-MARGIN - visibleRect.origin.x)/charWidth;
        ry = (locationInTextView.y - visibleRect.origin.y)/lineHeight;
        if (rx < 0) rx = -1;
        if (ry < 0) ry = -1;
        VT100Terminal *terminal = [dataSource terminal];
        PTYSession* session = [dataSource session];

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_NORMAL:
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                if([event deltaY] != 0) {
                    [session writeTask:[terminal mousePress:([event deltaY] > 0 ? 4:5) withModifiers:[event modifierFlags] atX:rx Y:ry]];
                    return;
                }
                break;
            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }

    [super scrollWheel:event];
}

- (void)mouseExited:(NSEvent *)event
{
    //NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
    // no-op
}

- (void)mouseEntered:(NSEvent *)event
{
    //NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);

    if ([[PreferencePanel sharedInstance] focusFollowsMouse]) {
        [[self window] makeKeyWindow];
    }
}

- (void)mouseDown:(NSEvent *)event
{

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView mouseDown:%@]",
          __FILE__, __LINE__, event );
#endif

    NSPoint locationInWindow, locationInTextView;
    int x, y;
    int width = [dataSource width];

    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    x = (locationInTextView.x - MARGIN + charWidth/2)/charWidth;
    //NSLog(@"Down on to pixel %d -> x=%d (charWidth=%d)", (int) locationInTextView.x-MARGIN, x, (int)charWidth);
    if (x < 0) {
        x = 0;
    }
    y = locationInTextView.y/lineHeight;

    if (x >= width) {
        x = width  - 1;
    }

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    if (([[self delegate] xtermMouseReporting]) &&
        (locationInTextView.y > visibleRect.origin.y) &&
        !([event modifierFlags] & NSAlternateKeyMask)) {

        int rx, ry;
        rx = (locationInTextView.x-MARGIN - visibleRect.origin.x)/charWidth;
        ry = (locationInTextView.y - visibleRect.origin.y)/lineHeight;
        if (rx < 0) rx = -1;
        if (ry < 0) ry = -1;
        VT100Terminal *terminal = [dataSource terminal];
        PTYSession* session = [dataSource session];

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_NORMAL:
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                reportingMouseDown = YES;
                [session writeTask:[terminal mousePress:0 withModifiers:[event modifierFlags] atX:rx Y:ry]];
                return;
                break;
            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }

    // Lock auto scrolling while the user is selecting text
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];

    if(mouseDownEvent != nil) {
        [mouseDownEvent release];
        mouseDownEvent = nil;
    }
    [event retain];
    mouseDownEvent = event;


    mouseDragged = NO;
    mouseDown = YES;
    mouseDownOnSelection = NO;

    if ([event clickCount] < 2) {
        // single click
        if (([event modifierFlags] & NSAlternateKeyMask) ||
            (selectMode == SELECT_BOX && ([event modifierFlags] & NSCommandKeyMask))) {
            selectMode = SELECT_BOX;
        } else {
            selectMode = SELECT_CHAR;
        }

        if (startX > -1 && ([event modifierFlags] & NSShiftKeyMask)) {
            // holding down shfit key and there is an existing selection ->
            // extend the selection.
            // If you click before the start then flip start and end and extend end to click location. (effectively extends left)
            // If you click after the start then move the end to the click location. (extends right)
            // This means that if you click inside the selection it truncates it by moving the end (whichever that is)
            if (x + y * width < startX + startY * width) {
                // Clicked before the start. Move the start to the old end.
                startX = endX;
                startY = endY;
            }
            // Move the end to the click location.
            endX = x;
            endY = y;
            // startX and endX may be reversed, but mouseUp fixes it.
        } else if (startX > -1 &&
                   [self _isCharSelectedInRow:y col:x checkOld:NO]) {
            // not holding down shift key but there is an existing selection.
            // Possibly a drag coming up.
            mouseDownOnSelection = YES;
            [super mouseDown: event];
            return;
        } else if (!([event modifierFlags] & NSCommandKeyMask)) {
            // start a new selection
            endX = startX = x;
            endY = startY = y;
        }
    } else if ([event clickCount] == 2) {
        int tmpX1, tmpY1, tmpX2, tmpY2;

        // double-click; select word
        selectMode = SELECT_WORD;
        NSString *selectedWord = [self _getWordForX: x y: y startX: &tmpX1 startY: &tmpY1 endX: &tmpX2 endY: &tmpY2];
        if ([self _findMatchingParenthesis:selectedWord withX:tmpX1 Y:tmpY1]) {
            // Found a matching paren
            ;
        } else if (startX > -1 && ([event modifierFlags] & NSShiftKeyMask)) {
            // no matching paren, but holding shift and extending selection
            if (startX + startY * width < tmpX1 + tmpY1 * width) {
                // extend end of selection
                endX = tmpX2;
                endY = tmpY2;
            } else {
                // extend start of selection
                startX = endX;
                startY = endY;
                endX = tmpX1;
                endY = tmpY1;
            }
        } else  {
            // no matching paren and not holding shift. Set selection to word boundary.
            startX = tmpX1;
            startY = tmpY1;
            endX = tmpX2;
            endY = tmpY2;
        }
    } else if ([event clickCount] >= 3) {
        // triple-click; select line
        selectMode = SELECT_LINE;
        if (startX > -1 && ([event modifierFlags] & NSShiftKeyMask)) {
            // extend existing selection
            if (startY < y) {
                // extend start
                endX = width;
                endY = y;
            } else {
                // extend end
                if (startX + startY * width < endX + endY * width) {
                    // advance start to end
                    startX = endX;
                    startY = endY;
                }
                endX = 0;
                endY = y;
            }
        } else {
            // not holding shift
            startX = 0;
            endX = width;
            startY = endY = y;
        }
    }

    DebugLog([NSString stringWithFormat:@"Mouse down. startx=%d starty=%d, endx=%d, endy=%d", startX, startY, endX, endY]);
    if([_delegate respondsToSelector: @selector(willHandleEvent:)] && [_delegate willHandleEvent: event])
        [_delegate handleEvent: event];
    [self refresh];

}

- (void)mouseUp:(NSEvent *)event
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView mouseUp:%@]",
          __FILE__, __LINE__, event );
#endif
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint locationInTextView = [self convertPoint: locationInWindow fromView: nil];
    int x, y;
    int width = [dataSource width];

    x = (locationInTextView.x - MARGIN) / charWidth;
    if (x < 0) {
        x = 0;
    }
    if (x>=width) {
        x = width - 1;
    }

    y = locationInTextView.y / lineHeight;

    // Send mouse up event to host if xterm mouse reporting is on
    if ([[self delegate] xtermMouseReporting]
        && reportingMouseDown && !([event modifierFlags] & NSAlternateKeyMask)) {
        reportingMouseDown = NO;
        int rx, ry;
        NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
        rx = (locationInTextView.x - MARGIN - visibleRect.origin.x) / charWidth;
        ry = (locationInTextView.y - visibleRect.origin.y) / lineHeight;
        if (rx < 0) {
            rx = -1;
        }
        if (ry < 0) {
            ry = -1;
        }
        VT100Terminal *terminal = [dataSource terminal];
        PTYSession* session = [dataSource session];

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_NORMAL:
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                [session writeTask:[terminal mouseReleaseAtX:rx Y:ry]];
                return;
                break;
            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }

    // Unlock auto scrolling as the user as finished selecting text
    if(([self visibleRect].origin.y + [self visibleRect].size.height) / lineHeight == [dataSource numberOfLines]) {
        [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:NO];
    }

    if (mouseDown == NO) {
        DebugLog([NSString stringWithFormat:@"Mouse up. startx=%d starty=%d, endx=%d, endy=%d", startX, startY, endX, endY]);
        return;
    }
    mouseDown = NO;

    // make sure we have key focus
    [[self window] makeFirstResponder: self];

    if (startY > endY ||
        (startY == endY && startX > endX)) {
        // Make sure the start is before the end.
        int t;
        t = startY; startY = endY; endY = t;
        t = startX; startX = endX; endX = t;
    } else if ([mouseDownEvent locationInWindow].x == [event locationInWindow].x &&
               [mouseDownEvent locationInWindow].y == [event locationInWindow].y &&
               !([event modifierFlags] & NSShiftKeyMask) &&
               [event clickCount] < 2 &&
               !mouseDragged) {
        // Just a click in the window.
        startX=-1;
        if (([event modifierFlags] & NSCommandKeyMask) &&
            [[PreferencePanel sharedInstance] cmdSelection] &&
            [mouseDownEvent locationInWindow].x == [event locationInWindow].x &&
            [mouseDownEvent locationInWindow].y == [event locationInWindow].y) {
            // Command click in place.
            //[self _openURL: [self selectedText]];
            NSString *url = [self _getURLForX:x y:y];
            if (url != nil) {
                [self _openURL:url];
            }
        } else {
            lastFindX = endX;
            absLastFindY = endY + [dataSource totalScrollbackOverflow];
            NSLog(@"Reset find position to %d,%d", lastFindX, absLastFindY);
        }
    }

    // if we are on an empty line, we select the current line to the end
    //if([self _isBlankLine: y] && y >= 0)
    //  endX = [dataSource width] - 1;

    if (startX > -1 && _delegate) {
        // if we want to copy our selection, do so
        if ([[PreferencePanel sharedInstance] copySelection]) {
            [self copy: self];
        }
    }

    if (selectMode != SELECT_BOX) {
        selectMode = SELECT_CHAR;
    }
    DebugLog([NSString stringWithFormat:@"Mouse up. startx=%d starty=%d, endx=%d, endy=%d", startX, startY, endX, endY]);

    [self refresh];
}

- (void)mouseDragged:(NSEvent *)event
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView mouseDragged:%@; modifier flags = 0x%x]",
          __FILE__, __LINE__, event, [event modifierFlags] );
#endif
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint locationInTextView = [self convertPoint: locationInWindow fromView: nil];
    NSRect  rectInTextView = [self visibleRect];
    int x, y, tmpX1, tmpX2, tmpY1, tmpY2;
    int width = [dataSource width];
    NSString *theSelectedText;

    float logicalX = locationInTextView.x - MARGIN - charWidth/2;
    if (logicalX >= 0) {
        x = logicalX / charWidth;
    } else {
        x = -1;
    }
    //NSLog(@"Drag to pixel %d -> x=%d (charWidth=%d) logical=%f", (int) locationInTextView.x-MARGIN, x, (int)charWidth, logicalX);
    if (x < -1) x = -1;
    if (x >= width) x = width - 1;


    y = locationInTextView.y/lineHeight;

    if (([[self delegate] xtermMouseReporting])
        && reportingMouseDown&& !([event modifierFlags] & NSAlternateKeyMask)) {
        int rx, ry;
        NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
        rx = (locationInTextView.x-MARGIN - visibleRect.origin.x)/charWidth;
        ry = (locationInTextView.y - visibleRect.origin.y)/lineHeight;
        if (rx < 0) rx = -1;
        if (ry < 0) ry = -1;
        VT100Terminal *terminal = [dataSource terminal];
        PTYSession* session = [dataSource session];

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                [session writeTask:[terminal mouseMotion:0 withModifiers:[event modifierFlags] atX:rx Y:ry]];
            case MOUSE_REPORTING_NORMAL:
                DebugLog([NSString stringWithFormat:@"Mouse drag. startx=%d starty=%d, endx=%d, endy=%d", startX, startY, endX, endY]);
                return;
                break;
            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }

    mouseDragged = YES;

    if (mouseDownOnSelection == YES &&
        ([event modifierFlags] & NSCommandKeyMask)) {
        // Drag and drop a selection
        if (selectMode == SELECT_BOX) {
            theSelectedText = [self contentInBoxFromX: startX Y: startY ToX: endX Y: endY pad: NO];
        } else {
            theSelectedText = [self contentFromX: startX Y: startY ToX: endX Y: endY pad: NO];
        }
        if ([theSelectedText length] > 0) {
            [self _dragText: theSelectedText forEvent: event];
            DebugLog([NSString stringWithFormat:@"Mouse drag. startx=%d starty=%d, endx=%d, endy=%d", startX, startY, endX, endY]);
            return;
        }
    }

    // NSLog(@"(%f,%f)->(%f,%f)",locationInWindow.x,locationInWindow.y,locationInTextView.x,locationInTextView.y);
    if (locationInTextView.y < rectInTextView.origin.y) {
        // Scroll window up to show selection
        rectInTextView.origin.y = locationInTextView.y;
        [self scrollRectToVisible:rectInTextView];
    } else if (locationInTextView.y > rectInTextView.origin.y + rectInTextView.size.height) {
        // Scroll window down to show selection
        rectInTextView.origin.y += locationInTextView.y - rectInTextView.origin.y - rectInTextView.size.height;
        [self scrollRectToVisible:rectInTextView];
    }

    // if we are on an empty line, we select the current line to the end
    if (y >= 0 && [self _isBlankLine: y]) {
        x = width;
    }

    if (locationInTextView.x < MARGIN && startY < y) {
        // complete selection of previous line
        x = width;
        y--;
    }
    if (y < 0) {
        y = 0;
    }
    if (y >= [dataSource numberOfLines]) {
        y=[dataSource numberOfLines] - 1;
    }

    switch (selectMode) {
        case SELECT_CHAR:
        case SELECT_BOX:
            endX = x + 1;
            endY = y;
            break;
        case SELECT_WORD:
            [self _getWordForX:x y:y startX:&tmpX1 startY:&tmpY1 endX:&tmpX2 endY:&tmpY2];
            if ((startX + (startY * width)) < (tmpX2 + (tmpY2 * width))) {
                // We go forwards in our selection session... and...
                if ((startX + (startY * width)) > (endX + (endY * width))) {
                    // This will always be called, if the selection direction is changed from backwards to forwards,
                    // that is the user changed his mind and now wants to select text AFTER the initial starting
                    // word, AND we come back to the initial starting word.
                    // In this case, our X starting and ending values will be SWAPPED, as swapping the values is
                    // necessary for backwards selection (forward selection: start|(several) word(s)|end---->,
                    //                                    backward selection: <----|end|(several) word(s)|start)
                    // _getWordForX will report a word range with a half open interval (a <= x < b). b-1 will thus be
                    // the LAST character of the current word. If we call the function again with new_a = b, it will
                    // report the boundaries for the next word in line (which by definition will always be a white
                    // space, iff we're in SELECT_WORD mode.)
                    // Thus calling the function with b-1 will report the correct values for the CURRENT (read as in
                    // NOT next word).
                    // Afterwards, selecting will continue normally.
                    int tx1, tx2, ty1, ty2;
                    [self _getWordForX:startX-1 y:startY startX:&tx1 startY:&ty1 endX:&tx2 endY:&ty2];
                    startX = tx1;
                    startY = ty1;
                }
                // This will update the ending coordinates to the new selected word's end boundaries.
                // If we had to swap the starting and ending value (see above), the ending value is set
                // to the new value gathered from above (initial double-clicked word).
                // Else, just extend the selection.
                endX = tmpX2;
                endY = tmpY2;
            } else {
                // This time, the user wants to go backwards in his selection session.
                if ((startX + (startY * width)) < (endX + (endY * width))) {
                    // This branch will re-select the current word with both start and end values swapped,
                    // whenever the initial double clicked word is reached again (that is, we were already
                    // selecting backwards.)
                    // For an explanation why, read the long comment above.
                    int tx1, tx2, ty1, ty2;
                    [self _getWordForX:startX y:startY startX:&tx1 startY:&ty1 endX:&tx2 endY:&ty2];
                    startX = tx2;
                    startY = ty2;
                }
                // Continue selecting text backwards. For a complete explanation see above, but read
                // it upside-down. :p
                endX = tmpX1;
                endY = tmpY1;
            }
            break;
        case SELECT_LINE:
            if (startY <= y) {
                startX = 0;
                endX = [dataSource width];
                endY = y;
            } else {
                endX = 0;
                endY = y;
                startX = [dataSource width];
            }
            break;
    }

    DebugLog([NSString stringWithFormat:@"Mouse drag. startx=%d starty=%d, endx=%d, endy=%d", startX, startY, endX, endY]);
    [self refresh];
    //NSLog(@"(%d,%d)-(%d,%d)",startX,startY,endX,endY);
}

- (NSString*)contentInBoxFromX:(int)startx Y:(int)starty ToX:(int)nonInclusiveEndx Y:(int)endy pad: (BOOL) pad
{
    int i;
    int estimated_size = abs((endy-startx) * [dataSource width]) + abs(nonInclusiveEndx - startx);
    NSMutableString* result = [NSMutableString stringWithCapacity:estimated_size];
    for (i = starty; i < endy; ++i) {
        NSString* line = [self contentFromX:startx Y:i ToX:nonInclusiveEndx Y:i pad:pad];
        [result appendString:line];
        if (i < endy-1) {
            [result appendString:@"\n"];
        }
    }
    return result;
}

- (NSString *)contentFromX:(int)startx
                         Y:(int)starty
                       ToX:(int)nonInclusiveEndx
                         Y:(int)endy
                       pad:(BOOL) pad
{
    int endx = nonInclusiveEndx-1;
    unichar *temp;
    int j;
    int width, y, x1, x2;
    NSString *str;
    screen_char_t *theLine;
    BOOL endOfLine;
    int i;

    width = [dataSource width];
    temp = (unichar *) malloc(((endy-starty+1)*(width+1)+(endx-startx+1))*sizeof(unichar));
    j = 0;
    for (y = starty; y <= endy; y++) {
        theLine = [dataSource getLineAtIndex:y];

        x1 = y == starty ? startx : 0;
        x2 = y == endy ? endx : width-1;
        for ( ; x1 <= x2; x1++) {
            if (theLine[x1].ch != 0xffff && theLine[x1].ch != DWC_SKIP) {
                temp[j] = theLine[x1].ch;
                if (theLine[x1].ch == 0) { // end of line?
                    // If there is no text after this, insert a hard line break.
                    endOfLine = YES;
                    for (i = x1 + 1; i <= x2 && endOfLine; i++) {
                        if (theLine[i].ch != 0) {
                            endOfLine = NO;
                        }
                    }
                    if (endOfLine) {
                        if (pad) {
                            for (i = x1; i <= x2; i++) {
                              temp[j++] = ' ';
                            }
                        }
                        if (y < endy && theLine[width].ch == EOL_HARD) {
                            temp[j] = '\n'; // hard break
                            j++;
                            break; // continue to next line
                        }
                        break;
                    } else {
                        temp[j] = ' '; // represent blank with space
                    }
                } else if (x1 == x2 &&
                           y < endy &&
                           theLine[width].ch == EOL_HARD) {
                    // definitely end of line
                    temp[++j] = '\n'; // hard break
                }
                j++;
            }
        }
    }

    str = [NSString stringWithCharacters:temp length:j];
    free(temp);

    return str;
}

- (IBAction) selectAll: (id) sender
{
    // set the selection region for the whole text
    startX = startY = 0;
    endX = [dataSource width];
    endY = [dataSource numberOfLines] - 1;
    [self refresh];
}

- (void) deselect
{
    if (startX > -1) {
        startX = -1;
        [self refresh];
    }
}

- (NSString *) selectedText
{
    return [self selectedTextWithPad: NO];
}


- (NSString *) selectedTextWithPad: (BOOL) pad
{

#if DEBUG_METHOD_TRACE
    NSLog(@"%s]", __PRETTY_FUNCTION__);
#endif

    if (startX <= -1) return nil;
    if (selectMode == SELECT_BOX) {
        return [self contentInBoxFromX: startX Y: startY ToX: endX Y: endY pad: pad];
    } else {
        return ([self contentFromX: startX Y: startY ToX: endX Y: endY pad: pad]);
    }
}

- (NSString *) content
{

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView content]", __FILE__, __LINE__);
#endif

    return [self contentFromX:0 Y:0 ToX:[dataSource width] Y:[dataSource numberOfLines]-1 pad: NO];
}

- (void) copy: (id) sender
{
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    NSString *copyString;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView copy:%@]", __FILE__, __LINE__, sender );
#endif

    copyString=[self selectedText];

    if (copyString && [copyString length]>0) {
        [pboard declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
        [pboard setString: copyString forType: NSStringPboardType];
    }
}

- (void)paste:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView paste:%@]", __FILE__, __LINE__, sender );
#endif

    if ([_delegate respondsToSelector:@selector(paste:)])
        [_delegate paste:sender];
}

- (void) pasteSelection: (id) sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s: %@]", __PRETTY_FUNCTION__, sender );
#endif

    if (startX > -1 && [_delegate respondsToSelector:@selector(pasteString:)])
        [_delegate pasteString:[self selectedText]];

}


- (BOOL)validateMenuItem:(NSMenuItem *)item
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView validateMenuItem:%@; supermenu = %@]", __FILE__, __LINE__, item, [[item menu] supermenu] );
#endif

    if ([item action] == @selector(paste:))
    {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];

        // Check if there is a string type on the pasteboard
        return ([pboard stringForType:NSStringPboardType] != nil);
    }
    else if ([item action ] == @selector(cut:))
        return NO;
    else if ([item action]==@selector(saveDocumentAs:) ||
             [item action] == @selector(selectAll:) ||
             ([item action] == @selector(print:) && [item tag] != 1))
    {
        // We always validate the above commands
        return (YES);
    }
    else if ([item action]==@selector(mail:) ||
             [item action]==@selector(browse:) ||
             [item action]==@selector(searchInBrowser:) ||
             [item action]==@selector(copy:) ||
             [item action]==@selector(pasteSelection:) ||
             ([item action]==@selector(print:) && [item tag] == 1)) // print selection
    {
        //        NSLog(@"selected range:%d",[self selectedRange].length);
        return (startX > -1);
    }
    else
        return NO;
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    NSMenu *theMenu;

    // Allocate a menu
    theMenu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];

    // Menu items for acting on text selections
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"-> Browser",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(browse:) keyEquivalent:@""];
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"-> Google",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(searchInBrowser:) keyEquivalent:@""];
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"-> Mail",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(mail:) keyEquivalent:@""];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Copy,  paste, and save
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Copy",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(copy:) keyEquivalent:@""];
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Paste",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(paste:) keyEquivalent:@""];
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Save",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(saveDocumentAs:) keyEquivalent:@""];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Select all
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Select All",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(selectAll:) keyEquivalent:@""];


    // Ask the delegae if there is anything to be added
    if ([[self delegate] respondsToSelector:@selector(menuForEvent: menu:)])
        [[self delegate] menuForEvent:theEvent menu: theMenu];

    return [theMenu autorelease];
}

- (void) mail:(id)sender
{
    [self _openURL: [self selectedText]];
}

- (void) browse:(id)sender
{
    [self _openURL: [self selectedText]];
}

- (void) searchInBrowser:(id)sender
{
    [self _openURL: [[NSString stringWithFormat:[[PreferencePanel sharedInstance] searchCommand], [self selectedText]] stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding]];
}

//
// Drag and Drop methods for our text view
//

//
// Called when our drop area is entered
//
- (unsigned int) draggingEntered:(id <NSDraggingInfo>)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView draggingEntered:%@]", __FILE__, __LINE__, sender );
#endif

    // Always say YES; handle failure later.
    bExtendedDragNDrop = YES;

    return bExtendedDragNDrop;
}

//
// Called when the dragged object is moved within our drop area
//
- (unsigned int) draggingUpdated:(id <NSDraggingInfo>)sender
{
    unsigned int iResult;
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView draggingUpdated:%@]", __FILE__, __LINE__, sender );
#endif

    // Let's see if our parent NSTextView knows what to do
    iResult = [super draggingUpdated: sender];

    // If parent class does not know how to deal with this drag type, check if we do.
    if (iResult == NSDragOperationNone) // Parent NSTextView does not support this drag type.
        return [self _checkForSupportedDragTypes: sender];

    return iResult;
}

//
// Called when the dragged object leaves our drop area
//
- (void) draggingExited:(id <NSDraggingInfo>)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView draggingExited:%@]", __FILE__, __LINE__, sender );
#endif

    // We don't do anything special, so let the parent NSTextView handle this.
    [super draggingExited: sender];

    // Reset our handler flag
    bExtendedDragNDrop = NO;
}

//
// Called when the dragged item is about to be released in our drop area.
//
- (BOOL) prepareForDragOperation:(id <NSDraggingInfo>)sender
{
    BOOL bResult;
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView prepareForDragOperation:%@]", __FILE__, __LINE__, sender );
#endif

    // Check if parent NSTextView knows how to handle this.
    bResult = [super prepareForDragOperation: sender];

    // If parent class does not know how to deal with this drag type, check if we do.
    if ( bResult != YES && [self _checkForSupportedDragTypes: sender] != NSDragOperationNone )
        bResult = YES;

    return bResult;
}

//
// Called when the dragged item is released in our drop area.
//
- (BOOL) performDragOperation:(id <NSDraggingInfo>)sender
{
    unsigned int dragOperation;
    BOOL bResult = NO;
    PTYSession *delegate = [self delegate];

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView performDragOperation:%@]", __FILE__, __LINE__, sender );
#endif

    // If parent class does not know how to deal with this drag type, check if we do.
    if (bExtendedDragNDrop)
    {
        NSPasteboard *pb = [sender draggingPasteboard];
        NSArray *propertyList;
        NSString *aString;
        int i;

        dragOperation = [self _checkForSupportedDragTypes: sender];

        switch (dragOperation)
        {
            case NSDragOperationCopy:
                // Check for simple strings first
                aString = [pb stringForType:NSStringPboardType];
                if (aString != nil)
                {
                    if ([delegate respondsToSelector:@selector(pasteString:)])
                        [delegate pasteString: aString];
                }

                    // Check for file names
                    propertyList = [pb propertyListForType: NSFilenamesPboardType];
                for (i = 0; i < (int)[propertyList count]; i++) {

                    // Ignore text clippings
                    NSString *filename = (NSString*)[propertyList objectAtIndex: i]; // this contains the POSIX path to a file
                    NSDictionary *filenamesAttributes = [[NSFileManager defaultManager] fileAttributesAtPath:filename traverseLink:YES];
                    if (([filenamesAttributes fileHFSTypeCode] == 'clpt' &&
                         [filenamesAttributes fileHFSCreatorCode] == 'MACS') ||
                        [[filename pathExtension] isEqualToString:@"textClipping"] == YES)
                    {
                        continue;
                    }

                    // Just paste the file names into the shell after escaping special characters.
                    if ([delegate respondsToSelector:@selector(pasteString:)])
                    {
                        NSMutableString *aMutableString;

                        aMutableString = [[NSMutableString alloc] initWithString: (NSString*)[propertyList objectAtIndex: i]];
                        // get rid of special characters
                        [aMutableString replaceOccurrencesOfString: @"\\" withString: @"\\\\" options: 0 range: NSMakeRange(0, [aMutableString length])];
                        [aMutableString replaceOccurrencesOfString: @" " withString: @"\\ " options: 0 range: NSMakeRange(0, [aMutableString length])];
                        [aMutableString replaceOccurrencesOfString: @"(" withString: @"\\(" options: 0 range: NSMakeRange(0, [aMutableString length])];
                        [aMutableString replaceOccurrencesOfString: @")" withString: @"\\)" options: 0 range: NSMakeRange(0, [aMutableString length])];
                        [aMutableString replaceOccurrencesOfString: @"\"" withString: @"\\\"" options: 0 range: NSMakeRange(0, [aMutableString length])];
                        [aMutableString replaceOccurrencesOfString: @"&" withString: @"\\&" options: 0 range: NSMakeRange(0, [aMutableString length])];
                        [aMutableString replaceOccurrencesOfString: @"'" withString: @"\\'" options: 0 range: NSMakeRange(0, [aMutableString length])];

                        [delegate pasteString: aMutableString];
                        [delegate pasteString: @" "];
                        [aMutableString release];
                    }

                }
                bResult = YES;
                break;
        }

    }

    return bResult;
}

//
//
//
- (void) concludeDragOperation:(id <NSDraggingInfo>)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView concludeDragOperation:%@]", __FILE__, __LINE__, sender );
#endif

    // If we did no handle the drag'n'drop, ask our parent to clean up
    // I really wish the concludeDragOperation would have a useful exit value.
    if (!bExtendedDragNDrop)
        [super concludeDragOperation: sender];

    bExtendedDragNDrop = NO;
}

- (void)resetCursorRects
{
    [self addCursorRect:[self visibleRect] cursor:textViewCursor];
    [textViewCursor setOnMouseEntered:YES];
}

// Save method
- (void) saveDocumentAs: (id) sender
{

    NSData *aData;
    NSSavePanel *aSavePanel;
    NSString *aString;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView saveDocumentAs:%@]", __FILE__, __LINE__, sender );
#endif

    // We get our content of the textview or selection, if any
    aString = [self selectedText];
    if (!aString) aString = [self content];
    aData = [aString
            dataUsingEncoding: NSASCIIStringEncoding
         allowLossyConversion: YES];
    // retain here so that is does not go away...
    [aData retain];

    // initialize a save panel
    aSavePanel = [NSSavePanel savePanel];
    [aSavePanel setAccessoryView: nil];
    [aSavePanel setRequiredFileType: @""];

    // Run the save panel as a sheet
    [aSavePanel beginSheetForDirectory: @""
                                  file: @"Unknown"
                        modalForWindow: [self window]
                         modalDelegate: self
                        didEndSelector: @selector(_savePanelDidEnd: returnCode: contextInfo:)
                           contextInfo: aData];
}

// Print
- (void) print: (id) sender
{
    NSRect visibleRect;
    int lineOffset, numLines;
    int type = sender ? [sender tag] : 0;

    switch (type)
    {
        case 0: // visible range
            visibleRect = [[self enclosingScrollView] documentVisibleRect];
            // Starting from which line?
            lineOffset = visibleRect.origin.y/lineHeight;
            // How many lines do we need to draw?
            numLines = visibleRect.size.height/lineHeight;
            [self printContent: [self contentFromX: 0 Y: lineOffset
                                               ToX: [dataSource width] Y: lineOffset + numLines - 1
                                        pad: NO]];
            break;
        case 1: // text selection
            [self printContent: [self selectedTextWithPad: NO]];
            break;
        case 2: // entire buffer
            [self printContent: [self content]];
            break;
    }
}

- (void) printContent: (NSString *) aString
{
    NSPrintInfo *aPrintInfo;

    aPrintInfo = [NSPrintInfo sharedPrintInfo];
    [aPrintInfo setHorizontalPagination: NSFitPagination];
    [aPrintInfo setVerticalPagination: NSAutoPagination];
    [aPrintInfo setVerticallyCentered: NO];

    // create a temporary view with the contents, change to black on white, and print it
    NSTextView *tempView;
    NSMutableAttributedString *theContents;

    tempView = [[NSTextView alloc] initWithFrame: [[self enclosingScrollView] documentVisibleRect]];
    theContents = [[NSMutableAttributedString alloc] initWithString: aString];
    [theContents addAttributes: [NSDictionary dictionaryWithObjectsAndKeys:
        [NSColor textBackgroundColor], NSBackgroundColorAttributeName,
        [NSColor textColor], NSForegroundColorAttributeName,
        [NSFont userFixedPitchFontOfSize: 0], NSFontAttributeName, NULL]
                         range: NSMakeRange(0, [theContents length])];
    [[tempView textStorage] setAttributedString: theContents];
    [theContents release];

    // now print the temporary view
    [[NSPrintOperation printOperationWithView: tempView  printInfo: aPrintInfo] runOperation];
    [tempView release];
}

/// NSTextInput stuff
- (void)doCommandBySelector:(SEL)aSelector
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView doCommandBySelector:...]",
          __FILE__, __LINE__);
#endif

#if GREED_KEYDOWN == 0
    id delegate = [self delegate];

    if ([delegate respondsToSelector:aSelector]) {
        [delegate performSelector:aSelector withObject:nil];
    }
#endif
}

- (void)insertText:(id)aString
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView insertText:%@]",
          __FILE__, __LINE__, aString);
#endif

    if ([self hasMarkedText]) {
        IM_INPUT_MARKEDRANGE = NSMakeRange(0, 0);
        [markedText release];
        markedText=nil;
    }
    if (startX == -1) {
        [self resetFindCursor];
    }

    if ([(NSString*)aString length]>0) {
        if ([_delegate respondsToSelector:@selector(insertText:)])
            [_delegate insertText:aString];
        else
            [super insertText:aString];

        IM_INPUT_INSERT = YES;
    }

}

- (void)setMarkedText:(id)aString selectedRange:(NSRange)selRange
{

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView setMarkedText:%@ selectedRange:(%d,%d)]",
          __FILE__, __LINE__, aString, selRange.location, selRange.length);
#endif
    [markedText release];
    if ([aString isKindOfClass:[NSAttributedString class]]) {
        markedText=[[NSAttributedString alloc] initWithString:[aString string] attributes:[self markedTextAttributes]];
    }
    else {
        markedText=[[NSAttributedString alloc] initWithString:aString attributes:[self markedTextAttributes]];
    }
    IM_INPUT_MARKEDRANGE = NSMakeRange(0,[markedText length]);
    IM_INPUT_SELRANGE = selRange;
    [self refresh];
}

- (void)unmarkText
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView unmarkText]", __FILE__, __LINE__ );
#endif
    IM_INPUT_MARKEDRANGE = NSMakeRange(0, 0);
}

- (BOOL)hasMarkedText
{
    BOOL result;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView hasMarkedText]", __FILE__, __LINE__ );
#endif
    if (IM_INPUT_MARKEDRANGE.length > 0)
        result = YES;
    else
        result = NO;

    return result;
}

- (NSRange)markedRange
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView markedRange]", __FILE__, __LINE__);
#endif

    //return IM_INPUT_MARKEDRANGE;
    if (IM_INPUT_MARKEDRANGE.length > 0) {
        return NSMakeRange([dataSource cursorX]-1, IM_INPUT_MARKEDRANGE.length);
    }
    else
        return NSMakeRange([dataSource cursorX]-1, 0);
}

- (NSRange)selectedRange
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView selectedRange]", __FILE__, __LINE__);
#endif
    return NSMakeRange(NSNotFound, 0);
}

- (NSArray *)validAttributesForMarkedText
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView validAttributesForMarkedText]", __FILE__, __LINE__);
#endif
    return [NSArray arrayWithObjects:NSForegroundColorAttributeName,
        NSBackgroundColorAttributeName,
        NSUnderlineStyleAttributeName,
        NSFontAttributeName,
        nil];
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)theRange
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView attributedSubstringFromRange:(%d,%d)]", __FILE__, __LINE__, theRange.location, theRange.length);
#endif

    return [markedText attributedSubstringFromRange:NSMakeRange(0,theRange.length)];
}

- (unsigned int)characterIndexForPoint:(NSPoint)thePoint
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView characterIndexForPoint:(%f,%f)]", __FILE__, __LINE__, thePoint.x, thePoint.y);
#endif

    return thePoint.x/charWidth;
}

- (long)conversationIdentifier
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView conversationIdentifier]", __FILE__, __LINE__);
#endif
    return (long)self; //not sure about this
}

- (NSRect)firstRectForCharacterRange:(NSRange)theRange
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView firstRectForCharacterRange:(%d,%d)]", __FILE__, __LINE__, theRange.location, theRange.length);
#endif
    int y=[dataSource cursorY]-1;
    int x=[dataSource cursorX]-1;

    NSRect rect=NSMakeRect(x*charWidth+MARGIN,(y+[dataSource numberOfLines] - [dataSource height]+1)*lineHeight,charWidth*theRange.length,lineHeight);
    //NSLog(@"(%f,%f)",rect.origin.x,rect.origin.y);
    rect.origin=[[self window] convertBaseToScreen:[self convertPoint:rect.origin toView:nil]];
    //NSLog(@"(%f,%f)",rect.origin.x,rect.origin.y);

    return rect;
}

- (BOOL)findInProgress
{
    return _findInProgress;
}

- (BOOL) continueFind
{
    BOOL more;
    BOOL found;
    // NSLog(@"PTYTextView continueFind");
    more = [dataSource continueFindResultAtStartX:&startX
                                         atStartY:&startY
                                           atEndX:&endX
                                           atEndY:&endY
                                            found:&found];

        if (found) {
            // Lock scrolling after finding text
            ++endX; // make it half-open
            [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];

            [self _scrollToLine:endY];
            [self setNeedsDisplay:YES];
            lastFindX = startX;
            absLastFindY = (long long)startY + [dataSource totalScrollbackOverflow];
        }
    if (!more) {
        // NSLog(@"PTYTextView: done");
        _findInProgress = NO;
        if (!found) {
        // Clear the selection.
            startX = startY = endX = endY = -1;
            absLastFindY = -1;
            [self setNeedsDisplay:YES];
        }
    }
    return more;
}

- (void)resetFindCursor
{
    lastFindX = absLastFindY = -1;
}

- (BOOL)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
      ignoringCase:(BOOL)ignoreCase
        withOffset:(int)offset
{
    if (_findInProgress) {
        [dataSource cancelFind];
    }

    if (lastFindX == -1) {
        lastFindX = 0;
        absLastFindY = (long long)([dataSource numberOfLines] + 1) + [dataSource totalScrollbackOverflow];
    }

    [dataSource initFindString:aString
              forwardDirection:direction
                  ignoringCase:ignoreCase
                   startingAtX:lastFindX
                   startingAtY:absLastFindY - [dataSource totalScrollbackOverflow]
                    withOffset:offset];
    _findInProgress = YES;

    return [self continueFind];
}

// transparency
- (float) transparency
{
    return (transparency);
}

- (void) setTransparency: (float) fVal
{
    transparency = fVal;
    [self setNeedsDisplay:YES];
}

- (BOOL) useTransparency
{
    return useTransparency;
}

- (void) setUseTransparency: (BOOL) flag
{
    useTransparency = flag;
    [self setNeedsDisplay:YES];
}

// service stuff
- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
    //NSLog(@"%s: %@, %@", __PRETTY_FUNCTION__, sendType, returnType);

    if(sendType != nil && [sendType isEqualToString: NSStringPboardType])
        return (self);

    return ([super validRequestorForSendType: sendType returnType: returnType]);
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types
{
    //NSLog(@"%s", __PRETTY_FUNCTION__);
    NSString *copyString;

    copyString=[self selectedText];

    if (copyString && [copyString length]>0) {
        [pboard declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
        [pboard setString: copyString forType: NSStringPboardType];
        return (YES);
    }

    return (NO);
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard
{
    //NSLog(@"%s", __PRETTY_FUNCTION__);
    return (NO);
}

@end

//
// private methods
//
@implementation PTYTextView (Private)

- (PTYFontInfo*)getFontForChar:(UniChar)ch
                       fgColor:(int)fgColor
                    renderBold:(BOOL*)renderBold
{
    BOOL isBold = (fgColor & BOLD_MASK) && !disableBold;
    *renderBold = NO;
    PTYFontInfo* theFont;
    BOOL usePrimary = (ch < 128);
    if (!usePrimary) {
        // Try to use the primary font for non-ascii characters, but only
        // if it has the glyph.
        CGGlyph glyph;
        if (CTFontGetGlyphsForCharacters((CTFontRef)primaryFont.font,
                                         &ch,
                                         &glyph,
                                         1)) {
            usePrimary = YES;
        } else {
            usePrimary = NO;
        }
    }

    if (usePrimary) {
        if (isBold) {
            theFont = primaryFont.boldVersion;
            if (!theFont) {
                theFont = &primaryFont;
                *renderBold = YES;
            }
        } else {
            theFont = &primaryFont;
        }
    } else {
        if (isBold) {
            theFont = secondaryFont.boldVersion;
            if (!theFont) {
                theFont = &secondaryFont;
                *renderBold = YES;
            }
        } else {
            theFont = &secondaryFont;
        }

        // Make sure the secondary font has the glyph. If not, ask core text
        // to pick one for us.
        CGGlyph glyph;
        if (!CTFontGetGlyphsForCharacters((CTFontRef)theFont->font,
                                          &ch,
                                          &glyph,
                                          1)) {
            CFStringRef tempString = CFStringCreateWithCharactersNoCopy(0, &ch, 1, kCFAllocatorNull);
            CTFontRef substituteFont = CTFontCreateForString((CTFontRef)theFont->font, tempString, CFRangeMake(0, 1));
            CFRelease(tempString);
            if (substituteFont) {
                return [self getOrAddFallbackFont:(NSFont*)substituteFont];
            }
        }
    }

    return theFont;
}


- (void)_drawLine:(int)line AtY:(float)curY
{
    int screenstartline = [self frame].origin.y / lineHeight;
    DebugLog([NSString stringWithFormat:@"Draw line %d (%d on screen)", line, (line - screenstartline)]);

    int WIDTH = [dataSource width];
    screen_char_t* theLine = [dataSource getLineAtIndex:line];
    PTYScrollView* scrollView = (PTYScrollView*)[self enclosingScrollView];
    BOOL hasBGImage = [scrollView backgroundImage] != nil;
    float alpha = useTransparency ? 1.0 - transparency : 1.0;
    BOOL reversed = [[dataSource terminal] screenMode];
    NSColor *aColor = nil;

    // Redraw margins
    NSRect leftMargin = NSMakeRect(0, curY, MARGIN, lineHeight);
    NSRect rightMargin;
    NSRect visibleRect = [self visibleRect];
    rightMargin.origin.x = charWidth * WIDTH;
    rightMargin.origin.y = curY;
    rightMargin.size.width = visibleRect.size.width - rightMargin.origin.x;
    rightMargin.size.height = lineHeight;

    aColor = [self colorForCode:DEFAULT_BG_COLOR_CODE];
    aColor = [aColor colorWithAlphaComponent:alpha];
    [aColor set];
    if(hasBGImage) {
        [scrollView drawBackgroundImageRect:leftMargin];
        [scrollView drawBackgroundImageRect:rightMargin];
    } else {
        NSRectFill(leftMargin);
        NSRectFill(rightMargin);
    }
    [aColor set];

    // Contiguous sections of background with the same colour
    // are combined into runs and draw as one operation
    int bgstart = -1;
    int j = 0;
    unsigned int bgcode = 0, fgcode = 0;
    BOOL bgselected = NO;

    // Build up runs of characters.
    UniChar codes[WIDTH];
    CGSize advances[WIDTH];
    NSColor* colors[WIDTH];  // TODO(georgen): should be 1:1 with runs.
    PTYFontInfo* fonts[WIDTH];  // TODO(georgen): should be 1:1 with runs.
    BOOL renderBold[WIDTH];  // TODO(georgen): should be 1:1 with runs.
    int runs[WIDTH];
    int runX[WIDTH];
    int runLength = 0;
    int numRuns = 0;
    int numGlyphs = 0;
    BOOL interruptedRun = NO;

    // Iterate over each character in the line
    while (j <= WIDTH) {
        if (theLine[j].ch == 0xffff) {
            // Do not draw the right-hand side of double-width characters.
            j++;
            continue;
        }

        BOOL selected;
        if (theLine[j].ch == DWC_SKIP) {
            selected = NO;
        } else {
            selected = [self _isCharSelectedInRow:line col:j checkOld:NO];
        }
        BOOL double_width = j < WIDTH - 1 && (theLine[j+1].ch == 0xffff);

        if (j != WIDTH && bgstart < 0) {
            // Start new run
            bgstart = j;
            bgcode = theLine[j].bg_color;
            bgselected = selected;
        }

        if (j != WIDTH &&
            bgselected == selected &&
            theLine[j].bg_color == bgcode) {
            // Continue the run
            j += (double_width ? 2 : 1);
        } else if (bgstart >= 0) {
            // This run is finished, draw it
            NSRect bgRect = NSMakeRect(floor(MARGIN+bgstart*charWidth),curY,ceil((j-bgstart)*charWidth),lineHeight);

            if (hasBGImage) {
                [(PTYScrollView *)[self enclosingScrollView] drawBackgroundImageRect: bgRect];
            }
            if (!hasBGImage || bgcode != DEFAULT_BG_COLOR_CODE || bgselected) {
                aColor = bgselected ? selectionColor : [self colorForCode: (reversed && bgcode == DEFAULT_BG_COLOR_CODE) ? DEFAULT_FG_COLOR_CODE: bgcode];
                aColor = [aColor colorWithAlphaComponent:alpha];
                [aColor set];
                NSRectFillUsingOperation(bgRect, hasBGImage?NSCompositeSourceOver:NSCompositeCopy);
            }

            // Now draw characters over the top
            float curX = MARGIN + bgstart*charWidth;

            for (int k = bgstart; k < j; k++) {
                if (theLine[k].ch == 0xffff) {
                    continue;
                }
                double_width = k < WIDTH - 1 && (theLine[k+1].ch == 0xffff);

                if (bgselected && ((theLine[k].fg_color & 0x1ff) == DEFAULT_FG_COLOR_CODE)) {
                    fgcode = SELECTED_TEXT;
                } else {
                    fgcode = (reversed && theLine[k].fg_color & DEFAULT_FG_COLOR_CODE) ?
                        (DEFAULT_BG_COLOR_CODE | (theLine[k].fg_color & BOLD_MASK)) : theLine[k].fg_color & 0x3ff;
                }

                if (blinkShow || !(theLine[k].fg_color & BLINK_MASK)) {
                    if (theLine[k].ch == 0) {
                        // Skip nulls because they should display empty (not all fonts do, either).
                        if (numGlyphs > 0) {
                            interruptedRun = YES;
                        }
                    } else {
                        codes[numGlyphs] = (theLine[k].ch == DWC_SKIP) ? ' ' : theLine[k].ch;
                        colors[numGlyphs] = [self colorForCode:fgcode];
                        advances[numGlyphs].width = double_width ? charWidth * 2 : charWidth;
                        advances[numGlyphs].height = 0;
                        fonts[numGlyphs] = [self getFontForChar:codes[numGlyphs]
                                                        fgColor:fgcode
                                                     renderBold:&renderBold[numGlyphs]];
                        if (numGlyphs > 0) {
                            if (interruptedRun ||
                                colors[numGlyphs] != colors[numGlyphs - 1] ||
                                fonts[numGlyphs] != fonts[numGlyphs - 1] ||
                                renderBold[numGlyphs] != renderBold[numGlyphs - 1]) {
                                // This is the first char of a new run.
                                // Set the length of the previous run.
                                runs[numRuns++] = runLength;
                                // Set the x position of this new run.
                                runX[numRuns] = curX;
                                runLength = 0;
                            }
                        } else {
                            // Save the x position of the first glyph
                            runX[numRuns] = curX;
                        }
                        interruptedRun = NO;
                        ++runLength;
                        ++numGlyphs;
                    }

                    // draw underline
                    if (theLine[k].fg_color & UNDER_MASK && theLine[k].ch) {
                        [[self colorForCode:fgcode] set];
                        NSRectFill(NSMakeRect(curX,
                                              curY + lineHeight - 2,
                                              double_width ? charWidth * 2 : charWidth,
                                              1));
                    }
                }
                curX += charWidth * (double_width ? 2 : 1);
            }

            bgstart = -1;
            // Return to top of loop without incrementing j so this
            // character gets the chance to start its own run
        } else {
            // Don't need to draw and not on a run, move to next char
            j += (double_width ? 2 : 1);
        }
    }
    if (runLength > 0) {
        runs[numRuns++] = runLength;
    }

    // TODO(georgen): Factor this out into drawRunOfChars().
    // Display runs of text with same font, color, boldness.
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    CGContextSetTextDrawingMode(ctx, kCGTextFill);
    CGContextSetShouldAntialias(ctx, antiAlias);
    int start = 0;
    for (int i = 0; i < numRuns; ++i) {
        CGGlyph glyphs[WIDTH];
        int length = runs[i];
        PTYFontInfo* theFont = fonts[start];

        CTFontGetGlyphsForCharacters((CTFontRef)theFont->font,
                                     codes + start,
                                     glyphs,
                                     length);
        CGContextSelectFont(ctx,
                            [[theFont->font fontName] UTF8String],
                            [theFont->font pointSize],
                            kCGEncodingMacRoman);
        NSColor* color = colors[start];
        CGContextSetFillColorSpace(ctx, [[color colorSpace] CGColorSpace]);
        int componentCount = [color numberOfComponents];
        {
            CGFloat components[componentCount];
            [color getComponents:components];
            CGContextSetFillColor(ctx, components);
        }
        int y = curY + lineHeight + theFont->baselineOffset;
        int x = runX[i];
        // Flip vertically and translate to (x, y).
        CGContextSetTextMatrix(ctx, CGAffineTransformMake(1.0,  0.0,
                                                          0.0, -1.0,
                                                          x,    y));

        CGContextShowGlyphsWithAdvances(ctx, glyphs, advances + start, length);
        if (renderBold[start]) {
            CGContextSetTextMatrix(ctx, CGAffineTransformMake(1.0,  0.0,
                                                              0.0, -1.0,
                                                              x + 1, y));

            CGContextShowGlyphsWithAdvances(ctx, glyphs, advances + start, length);
        }
        start += length;
    }
}

- (void)_drawCharacter:(unichar)c fgColor:(int)fg AtX:(float)X Y:(float)Y doubleWidth:(BOOL)dw overrideColor:(NSColor*)overrideColor
{
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    CGContextSetTextDrawingMode(ctx, kCGTextFill);
    CGContextSetShouldAntialias(ctx, antiAlias);
    CGGlyph glyph;
    BOOL renderBold;
    PTYFontInfo* theFont = [self getFontForChar:c
                                        fgColor:fg
                                     renderBold:&renderBold];

    CTFontGetGlyphsForCharacters((CTFontRef)theFont->font,
                                 &c,
                                 &glyph,
                                 1);
    CGContextSelectFont(ctx,
                        [[theFont->font fontName] UTF8String],
                        [theFont->font pointSize],
                        kCGEncodingMacRoman);
    NSColor* color = overrideColor ? overrideColor : [self colorForCode:fg];
    CGContextSetFillColorSpace(ctx, [[color colorSpace] CGColorSpace]);
    int componentCount = [color numberOfComponents];
    {
        CGFloat components[componentCount];
        [color getComponents:components];
        CGContextSetFillColor(ctx, components);
    }
    // Flip vertically and translate to (x, y).
    Y += lineHeight + theFont->baselineOffset;
    CGContextSetTextMatrix(ctx, CGAffineTransformMake(1.0,  0.0,
                                                      0.0, -1.0,
                                                      X,    Y));
    CGSize advances[1];
    advances[0].width = charWidth;
    advances[0].height = 0;
    CGContextShowGlyphsWithAdvances(ctx, &glyph, advances, 1);
    if (renderBold) {
        CGContextSetTextMatrix(ctx, CGAffineTransformMake(1.0,  0.0,
                                                          0.0, -1.0,
                                                          X + 1, Y));

        CGContextShowGlyphsWithAdvances(ctx, &glyph, advances, 1);
    }
}

- (void)_drawCursor
{
    int WIDTH, HEIGHT;
    screen_char_t* theLine;
    int yStart, x1;
    float cursorWidth, cursorHeight;
    float curX, curY;
    BOOL double_width;
    float alpha = useTransparency ? 1.0 - transparency : 1.0;

    WIDTH = [dataSource width];
    HEIGHT = [dataSource height];
    x1 = [dataSource cursorX] - 1;
    yStart = [dataSource cursorY] - 1;

    int lastVisibleLine = [[[dataSource session] SCROLLVIEW] documentVisibleRect].origin.y / [self lineHeight] + HEIGHT;
    int cursorLine = [dataSource numberOfLines] - [dataSource height] + [dataSource cursorY] - [dataSource scrollbackOverflow];
    if (cursorLine > lastVisibleLine) {
        return;
    }
    if (cursorLine < 0) {
        return;
    }

    if (charWidth < charWidthWithoutSpacing) {
        cursorWidth = charWidth;
    } else {
        cursorWidth = charWidthWithoutSpacing;
    }
    if (lineHeight < charHeightWithoutSpacing) {
        cursorHeight = lineHeight;
    } else {
        cursorHeight = charHeightWithoutSpacing;
    }

    if ([self blinkingCursor] &&
        [[self window] isKeyWindow] &&
        x1 == oldCursorX &&
        yStart == oldCursorY) {
        showCursor = blinkShow;
    } else {
        showCursor = YES;
    }

    // draw any text for NSTextInput
    if ([self hasMarkedText]) {
        // The following mod is brought to you by Zonble.
        int len = [markedText length];
        if (len > WIDTH - x1) {
          len = WIDTH - x1;
        }

        NSString* str = [markedText string];
        int offset = 0;
        int cursorOffset = 0;
        int baseX = floor(x1 * charWidth + MARGIN);
        int i;
        int y = (yStart + [dataSource numberOfLines] - HEIGHT) * lineHeight;
        int cursorY = y;
        for (i = 0; i < (int)[str length]; ++i) {
            UniChar aChar = [str characterAtIndex:i];
            int x = baseX + offset;
            if (x >= WIDTH * charWidth + MARGIN) {
                // TODO(georgen): Wrapping doesn't work. This code should be
                // moved out of drawCursor and be part of the regular window
                // drawing code. It should also scroll the screen as needed when
                // the IME text is too large to fit on screen.
                x = MARGIN;
                y += lineHeight;
            }
            BOOL doubleWidth = [NSString isDoubleWidthCharacter:aChar
                                                       encoding:NSUTF32StringEncoding
                                         ambiguousIsDoubleWidth:[[dataSource session] doubleWidth]];

            NSRect r = NSMakeRect(x, y, charWidth * (doubleWidth ? 2 : 1), lineHeight);
            [defaultBGColor set];
            NSRectFill(r);

            [defaultFGColor set];
            NSRect s = NSMakeRect(x, y + lineHeight - 1, charWidth * (doubleWidth ? 2 : 1), 1);
            NSRectFill(s);

            [self _drawCharacter:aChar
                         fgColor:0
                             AtX:x
                               Y:y
                     doubleWidth:doubleWidth
                   overrideColor:defaultFGColor];
            if (i == (int)IM_INPUT_SELRANGE.location) {
                cursorOffset = offset;
                cursorY = y;
            }
            offset += r.size.width;
        }
        if (i == (int)IM_INPUT_SELRANGE.location) {
            cursorOffset = offset;
            cursorY = y;
        }

        NSRect cursorFrame = NSMakeRect(floor(x1 * charWidth + MARGIN) + cursorOffset,
                                        cursorY,
                                        2.0,
                                        cursorHeight);
        [[NSColor yellowColor] set];
        NSRectFill(cursorFrame);

        memset([dataSource dirty] + yStart * WIDTH + x1,
               1,
               WIDTH - x1 > len*2 ? len*2 : WIDTH-x1); //len*2 is an over-estimation, but safe
        return;
    }


    if (CURSOR) {
        if (showCursor && x1 < WIDTH && x1 >= 0 && yStart >= 0 && yStart < HEIGHT) {
            // get the cursor line
            theLine = [dataSource getLineAtScreenIndex:yStart];
            double_width = 0;
            unichar aChar = theLine[x1].ch;
            if (aChar) {
                if (aChar == 0xffff && x1 > 0) {
                    x1--;
                    aChar = theLine[x1].ch;
                }
                double_width = (x1 < WIDTH-1) && (theLine[x1+1].ch == 0xffff);
            }
            curX = floor(x1 * charWidth + MARGIN);
            curY = (yStart + [dataSource numberOfLines] - HEIGHT + 1) * lineHeight - cursorHeight;

            NSColor *bgColor;
            if (colorInvertedCursor) {
                bgColor = [self colorForCode: (theLine[x1].fg_color)];
                bgColor = [bgColor colorWithAlphaComponent:alpha];
                [bgColor set];
            } else {
                bgColor = [self defaultCursorColor];
                [[bgColor colorWithAlphaComponent: alpha] set];
            }

            switch ([[PreferencePanel sharedInstance] cursorType]) {
                case CURSOR_BOX:
                    // draw the box
                    if([[self window] isKeyWindow]) {
                        NSRectFill(NSMakeRect(curX,
                                              curY,
                                              ceil(cursorWidth * (double_width ? 2 : 1)),
                                              cursorHeight));
                    } else {
                        NSFrameRect(NSMakeRect(curX,
                                               curY,
                                               ceil(cursorWidth * (double_width ? 2 : 1)),
                                               cursorHeight));
                    }
                    // draw any character on cursor if we need to
                    if (aChar) {
                        // Have a char at the cursor position.
                        if (colorInvertedCursor) {
                            unsigned int fgColor;
                            if ([[self window] isKeyWindow]) {
                                // Draw a solid rectangle in the bg color
                                fgColor = theLine[x1].bg_color;
                            } else {
                                // Draw an outline in the foreground color
                                fgColor = theLine[x1].fg_color;
                            }
                            NSColor* proposedForeground = [[self colorForCode:fgColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
                            CGFloat fgBrightness = [proposedForeground brightnessComponent];
                            CGFloat bgBrightness = [[bgColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace] brightnessComponent];
                            NSColor* overrideColor = nil;
                            if (fabs(fgBrightness - bgBrightness) < 0.2) {
                                // foreground and background are very similar. Just use black and
                                // white.
                                if (bgBrightness < 0.5) {
                                    overrideColor = [NSColor whiteColor];
                                } else {
                                    overrideColor = [NSColor blackColor];
                                }
                            }
                            [self _drawCharacter:aChar
                                         fgColor:[[self window] isKeyWindow] ? theLine[x1].bg_color : theLine[x1].fg_color
                                             AtX:x1 * charWidth + MARGIN
                                               Y:(yStart + [dataSource numberOfLines] - HEIGHT) * lineHeight
                                     doubleWidth:double_width
                                   overrideColor:overrideColor];
                        } else {
                            // Non-inverted cursor
                            [self _drawCharacter:aChar
                                         fgColor:[[self window] isKeyWindow]?CURSOR_TEXT:theLine[x1].fg_color
                                             AtX:x1 * charWidth + MARGIN
                                               Y:(yStart + [dataSource numberOfLines] - HEIGHT) * lineHeight
                                     doubleWidth:double_width
                                   overrideColor:nil];
                        }
                    }

                    break;

                case CURSOR_VERTICAL:
                    NSRectFill(NSMakeRect(curX, curY, 1, cursorHeight));
                    break;

                case CURSOR_UNDERLINE:
                    NSRectFill(NSMakeRect(curX,
                                          curY + lineHeight - 2,
                                          ceil(cursorWidth * (double_width ? 2 : 1)),
                                          2));
                    break;
            }
        }

        ([dataSource dirty] + yStart * WIDTH)[x1] = 1; //cursor loc is dirty
    }

    oldCursorX = x1;
    oldCursorY = yStart;
}


- (void) _scrollToLine:(int)line
{
    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = line * lineHeight;
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = lineHeight;
    [self scrollRectToVisible: aFrame];
}


- (unichar) _getCharacterAtX:(int) x Y:(int) y
{
    screen_char_t *theLine;
    theLine = [dataSource getLineAtIndex:y];

    return theLine[x].ch;
}

- (NSString *)_getWordForX:(int) x
                         y:(int) y
                    startX:(int *) startx
                    startY:(int *) starty
                      endX:(int *) endx
                      endY:(int *) endy
{
    NSString *wordChars;
    int tmpX;
    int tmpY;
    int x1;
    int yStart;
    int x2;
    int y2;
    int width = [dataSource width];

    // Grab the preference for extra characters to be included in a word.
    wordChars = [[PreferencePanel sharedInstance] wordChars];
    if (wordChars == nil) {
        wordChars = @"";
    }

    // Search backward from (x, y) to find the beginning of the word.
    tmpX = x;
    tmpY = y;
    while (tmpX >= 0) {
        screen_char_t* theLine = [dataSource getLineAtIndex:tmpY];
        NSString* aString = [NSString stringWithCharacters:&theLine[tmpX].ch length:1];
        if ([aString characterAtIndex:0] != 0xffff &&
            ([aString rangeOfCharacterFromSet:[NSCharacterSet alphanumericCharacterSet]].length == 0) &&
            [wordChars rangeOfString:aString].length == 0) {
            // Found whitespace at this position.
            break;
        }
        tmpX--;
        if (tmpX < 0 && tmpY > 0) {
            // Wrap tmpX, tmpY to the end of the previous line.
            theLine = [dataSource getLineAtIndex:tmpY-1];
            if (theLine[width].ch != EOL_HARD) {
                // check if there's a hard line break
                tmpY--;
                tmpX = width - 1;
            }
        }
    }
    if (tmpX != x) {
        // Advance back to the right of the whitespace that caused us to break.
        tmpX++;
    }

    // Ensure the values are sane, although I think none of these cases will
    // ever occur.
    if (tmpX < 0) {
        tmpX = 0;
    }
    if (tmpY < 0) {
        tmpY = 0;
    }
    if (tmpX >= width) {
        tmpX = 0;
        tmpY++;
    }

    if (tmpY >= [dataSource numberOfLines]) {
        tmpY = [dataSource numberOfLines] - 1;
    }

    // Save to startx, starty.
    if (startx) {
        *startx = tmpX;
    }
    if (starty) {
        *starty = tmpY;
    }
    x1 = tmpX;
    yStart = tmpY;


    // Search forward from x to find the end of the word.
    tmpX = x;
    tmpY = y;
    while (tmpX < width) {
        screen_char_t* theLine = [dataSource getLineAtIndex:tmpY];
        NSString* aString = [NSString stringWithCharacters:&theLine[tmpX].ch length:1];
        if ([aString characterAtIndex:0] != 0xffff &&
            ([aString rangeOfCharacterFromSet:[NSCharacterSet alphanumericCharacterSet]].length == 0) &&
            [wordChars rangeOfString:aString].length == 0) {
            // Found whitespace at this position.
            break;
        }
        tmpX++;
        if (tmpX >= width && tmpY < [dataSource numberOfLines]) {
            if (theLine[width].ch == EOL_HARD) {
                // check if there's a hard line break
                tmpY++;
                tmpX = 0;
            }
        }
    }

    // Back off from trailing whitespace
    if (tmpX != x) {
        tmpX--;
    }

    // Sanity checks.
    if (tmpX < 0) {
        tmpX = width - 1;
        tmpY--;
    }
    if (tmpY < 0) {
        tmpY = 0;
    }
    if (tmpX >= width) {
        tmpX = width - 1;
    }
    if (tmpY >= [dataSource numberOfLines]) {
        tmpY = [dataSource numberOfLines] - 1;
    }

    // Save to endx, endy.
    if (endx) {
        *endx = tmpX+1;
    }
    if (endy) {
        *endy = tmpY;
    }

    // Grab the contents to return.
    x2 = tmpX+1;
    y2 = tmpY;

    return ([self contentFromX:x1 Y:yStart ToX:x2 Y:y2 pad: YES]);
}

- (NSString *) _getURLForX: (int) x
                    y: (int) y
{
    static char *urlSet = ".?/:;%=&_-,+~#@!*'()";
    int w = [dataSource width];
    int h = [dataSource numberOfLines];
    NSMutableString *url = [NSMutableString string];
    unichar theChar = [self _getCharacterAtX:x Y:y];

    if (theChar == '\0' || !(isalnum(theChar) || strchr(urlSet, theChar)))
        return url;

    // Look for a left and right edge bracketed by | characters
    // Look for a left edge
    int leftx = 0;
    for (int xi = x-1, yi = y; 0 <= xi; xi--) {
        unichar curChar = [self _getCharacterAtX:xi Y:yi];
        if (curChar == '|' &&
            ((yi > 0 && [self _getCharacterAtX:xi Y:yi-1] == '|') ||
             (yi < h-1 && [self _getCharacterAtX:xi Y:yi+1] == '|'))) {
            leftx = xi+1;
            break;
        }
    }
    //NSLog(@"%s: leftx: %d", __PRETTY_FUNCTION__, leftx);

    // Look for a right edge
    int rightx = w-1;
    for (int xi = x+1, yi = y; xi < w; xi++) {
        unichar c = [self _getCharacterAtX:xi Y:yi];
        if (c == '|' &&
            ((yi > 0 && [self _getCharacterAtX:xi Y:yi-1] == '|') ||
             (yi < h-1 && [self _getCharacterAtX:xi Y:yi+1] == '|'))) {
            rightx = xi-1;
            break;
        }
    }
    //NSLog(@"%s: width: %d", __PRETTY_FUNCTION__, w);
    //NSLog(@"%s: rightx: %d", __PRETTY_FUNCTION__, rightx);

    // Move to the left
    {
        int endx = x-1;
        for (int xi = endx, yi = y; xi >= leftx && 0 <= yi; xi--) {
            unichar curChar = [self _getCharacterAtX:xi Y:yi];
            if (curChar == '\0' || !(isalnum(curChar) || strchr(urlSet, curChar))) {
                // Found a non-url character so append the left part of the URL.
                [url insertString:[self contentFromX:xi+1 Y:yi ToX:endx+1 Y:yi pad: YES]
                     atIndex:0];
                break;
            }
            if (xi == leftx) {
                // hit the start of the line
                [url insertString:[self contentFromX:xi Y:yi ToX:endx+1 Y:yi pad: YES]
                     atIndex:0];
                // Try to wrap around to the previous line
                if (yi == 0) {
                    break;
                }
                yi--;
                if (rightx < w-1 && [self _getCharacterAtX:rightx+1 Y:yi] != '|') {
                    // Was bracketed by |s but the previous line lacks them.
                    break;
                }
                // skip backslashes at the end of the line indicating wrapping.
                xi = rightx;
                while (xi >= leftx && [self _getCharacterAtX:xi Y:yi] == '\\') {
                    xi--;
                }
                endx = xi;
            }
        }
    }
    //NSLog(@"%s: url-at-the-left: %@", __PRETTY_FUNCTION__, url);

    // Move to the right
    {
        int startx = x;
        for (int xi = startx+1, yi = y; xi <= rightx && yi < h; xi++) {
            unichar curChar = [self _getCharacterAtX:xi Y:yi];
            if (curChar == '\0' || !(isalnum(curChar) || strchr(urlSet, curChar))) {
                // Found something non-urly. Append what we have so far.
                [url appendString:[self contentFromX:startx Y:yi ToX:xi Y:yi pad: YES]];
                // skip backslahes that indicate wrapping
                while (x <= rightx && [self _getCharacterAtX:xi Y:yi] == '\\') {
                    xi++;
                }
                if (xi <= rightx) {
                    // before rightx there was something besides \s
                    break;
                }
                // xi is left at rightx+1
            } else if (xi == rightx) {
                // Made it to rightx.
                [url appendString:[self contentFromX:startx Y:yi ToX:xi+1 Y:yi pad: YES]];
            } else {
                // Char is valid and xi < rightx.
                continue;
            }
            // Wrap to the next line
            if (yi == h-1) {
                // got to the end of the screen.
                break;
            }
            yi++;
            if (leftx > 0 && [self _getCharacterAtX:leftx-1 Y:yi] != '|') {
                // Tried to wrap but there was no |, so stop.
                break;
            }
            xi = startx = leftx;
        }
    }
    //NSLog(@"%s: url-whole: %@", __PRETTY_FUNCTION__, url);

    // Grab the addressbook command
    [url replaceOccurrencesOfString:@"\n" withString:@"" options:NSLiteralSearch range:NSMakeRange(0, [url length])];

    return (url);

}

- (BOOL) _findMatchingParenthesis: (NSString *) parenthesis withX:(int)X Y:(int)Y
{
    unichar matchingParenthesis, sameParenthesis, c;
    int level = 0, direction;
    int x1, yStart;
    int w = [dataSource width];
    int h = [dataSource numberOfLines];

    if (!parenthesis || [parenthesis length]<1)
        return NO;

    [parenthesis getCharacters:&sameParenthesis range:NSMakeRange(0,1)];
    switch (sameParenthesis) {
        case '(':
            matchingParenthesis = ')';
            direction = 0;
            break;
        case ')':
            matchingParenthesis = '(';
            direction = 1;
            break;
        case '[':
            matchingParenthesis = ']';
            direction = 0;
            break;
        case ']':
            matchingParenthesis = '[';
            direction = 1;
            break;
        case '{':
            matchingParenthesis = '}';
            direction = 0;
            break;
        case '}':
            matchingParenthesis = '{';
            direction = 1;
            break;
        default:
            return NO;
    }

    if (direction) {
        x1 = X -1;
        yStart = Y;
        if (x1<0) yStart--, x1=w-1;
        for (; x1 >= 0 && yStart >= 0; ) {
            c = [self _getCharacterAtX:x1 Y:yStart];
            if (c == sameParenthesis) level++;
            else if (c == matchingParenthesis) {
                level--;
                if (level<0) break;
            }
            x1--;
            if (x1<0) yStart--, x1=w-1;
        }
        if (level<0) {
            startX = x1;
            startY = yStart;
            endX = X+1;
            endY = Y;

            return YES;
        }
        else
            return NO;
    }
    else {
        x1 = X +1;
        yStart = Y;
        if (x1>=w) yStart++, x1=0;

        for (; x1 < w && yStart < h; ) {
            c = [self _getCharacterAtX:x1 Y:yStart];
            if (c == sameParenthesis) level++;
            else if (c == matchingParenthesis) {
                level--;
                if (level<0) break;
            }
            x1++;
            if (x1>=w) yStart++, x1=0;
        }
        if (level<0) {
            startX = X;
            startY = Y;
            endX = x1+1;
            endY = yStart;

            return YES;
        }
        else
            return NO;
    }

}

- (unsigned int) _checkForSupportedDragTypes:(id <NSDraggingInfo>) sender
{
    NSString *sourceType;
    BOOL iResult;

    iResult = NSDragOperationNone;

    // We support the FileName drag type for attching files
    sourceType = [[sender draggingPasteboard] availableTypeFromArray: [NSArray arrayWithObjects:
        NSFilenamesPboardType,
        NSStringPboardType,
        nil]];

    if (sourceType)
        iResult = NSDragOperationCopy;

    return iResult;
}

- (void) _savePanelDidEnd: (NSSavePanel *) theSavePanel
               returnCode: (int) theReturnCode
              contextInfo: (void *) theContextInfo
{
    // If successful, save file under designated name
    if (theReturnCode == NSOKButton)
    {
        if ( ![(NSData *)theContextInfo writeToFile: [theSavePanel filename] atomically: YES] )
            NSBeep();
    }
    // release our hold on the data
    [(NSData *)theContextInfo release];
}

- (BOOL) _isBlankLine: (int) y
{
    NSString *lineContents, *blankLine;
    char blankString[1024];


    lineContents = [self contentFromX: 0 Y: y ToX: [dataSource width] Y: y pad: YES];
    memset(blankString, ' ', 1024);
    blankString[[dataSource width]] = 0;
    blankLine = [NSString stringWithUTF8String: (const char*)blankString];

    return ([lineContents isEqualToString: blankLine]);

}

- (void) _openURL: (NSString *) aURLString
{
    NSURL *url;
    NSString* trimmedURLString;

    trimmedURLString = [aURLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // length returns an unsigned value, so couldn't this just be ==? [TRE]
    if([trimmedURLString length] <= 0)
        return;

    // Check for common types of URLs

    NSRange range = [trimmedURLString rangeOfString:@"://"];
    if (range.location == NSNotFound) {
        trimmedURLString = [@"http://" stringByAppendingString:trimmedURLString];
    } else {
        // Search backwards for the start of the scheme.
        for (int i = range.location - 1; 0 <= i; i--) {
            unichar c = [trimmedURLString characterAtIndex:i];
            if (!isalnum(c)) {
                // Remove garbage before the scheme part
                trimmedURLString = [trimmedURLString substringFromIndex:i + 1];
                switch (c) {
                case '(':
                    // If an open parenthesis is right before the
                    // scheme part, remove the closing parenthesis
                    {
                        NSRange closer = [trimmedURLString rangeOfString:@")"];
                        if (closer.location != NSNotFound) {
                            trimmedURLString = [trimmedURLString substringToIndex:closer.location];
                        }
                    }
                    break;
                }
                // Chomp a dot at the end
                int last = [trimmedURLString length] - 1;
                if (0 <= last && [trimmedURLString characterAtIndex:last] == '.') {
                    trimmedURLString = [trimmedURLString substringToIndex:last];
                }
                break;
            }
        }
    }

    url = [NSURL URLWithString:trimmedURLString];

    Bookmark *bm = [[PreferencePanel sharedInstance] handlerBookmarkForURL:[url scheme]];

    //NSLog(@"Got the URL:%@\n%@", [url scheme], bm);
    if (bm != nil)  {
        [[iTermController sharedInstance] launchBookmark:bm
                                              inTerminal:[[iTermController sharedInstance] currentTerminal]
                                                 withURL:trimmedURLString];
    } else {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }

}

- (void) _dragText: (NSString *) aString forEvent: (NSEvent *) theEvent
{
    NSImage *anImage;
    int length;
    NSString *tmpString;
    NSPasteboard *pboard;
    NSArray *pbtypes;
    NSSize imageSize;
    NSPoint dragPoint;
    NSSize dragOffset = NSMakeSize(0.0, 0.0);

    //NSLog(@"%s: %@", __PRETTY_FUNCTION__, aString);


    length = [aString length];
    if([aString length] > 15)
        length = 15;

    imageSize = NSMakeSize(charWidth*length, lineHeight);
    anImage = [[NSImage alloc] initWithSize: imageSize];
    [anImage lockFocus];
    if([aString length] > 15)
        tmpString = [NSString stringWithFormat: @"%@...", [aString substringWithRange: NSMakeRange(0, 12)]];
    else
        tmpString = [aString substringWithRange: NSMakeRange(0, length)];

    [tmpString drawInRect: NSMakeRect(0, 0, charWidth*length, lineHeight) withAttributes: nil];
    [anImage unlockFocus];
    [anImage autorelease];

    // get the pasteboard
    pboard = [NSPasteboard pasteboardWithName:NSDragPboard];

    // Declare the types and put our tabViewItem on the pasteboard
    pbtypes = [NSArray arrayWithObjects: NSStringPboardType, nil];
    [pboard declareTypes: pbtypes owner: self];
    [pboard setString: aString forType: NSStringPboardType];

    // tell our app not switch windows (currently not working)
    [NSApp preventWindowOrdering];

    // drag from center of the image
    dragPoint = [self convertPoint: [theEvent locationInWindow] fromView: nil];
    dragPoint.x -= imageSize.width/2;

    // start the drag
    [self dragImage:anImage at: dragPoint offset:dragOffset
              event: mouseDownEvent pasteboard:pboard source:self slideBack:YES];

}

- (BOOL) _isCharSelectedInRow:(int)row col:(int)col checkOld:(BOOL)old
{
    int tempStartX;
    int tempStartY;
    int tempEndX;
    int tempEndY;
    char tempSelectMode;

    if (!old) {
        tempStartY = startY;
        tempStartX = startX;
        tempEndY = endY;
        tempEndX = endX;
        tempSelectMode = selectMode;
    } else {
        tempStartY = oldStartY;
        tempStartX = oldStartX;
        tempEndY = oldEndY;
        tempEndX = oldEndX;
        tempSelectMode = oldSelectMode;
    }

    if (tempStartX <= -1 || (tempStartY == tempEndY && tempStartX == tempEndX)) {
        return NO;
    }
    if (tempStartY > tempEndY || (tempStartY == tempEndY && tempStartX > tempEndX)) {
        int t;
        // swap start and end.
        t = tempStartY;
        tempStartY = tempEndY;
        tempEndY = t;

        t = tempStartX;
        tempStartX = tempEndX;
        tempEndX = t;
    }
    if (tempSelectMode == SELECT_BOX) {
        return (row >= tempStartY && row < tempEndY) && (col >= tempStartX && col < tempEndX);
    }
    if (row == tempStartY && tempStartY == tempEndY) {
        return (col >= tempStartX && col < tempEndX);
    } else if (row == tempStartY && col >= tempStartX) {
        return YES;
    } else if (row == tempEndY && col < tempEndX) {
        return YES;
    } else if (row > tempStartY && row < tempEndY) {
        return YES;
    } else {
        return NO;
    }
}

- (void) _settingsChanged:(NSNotification *)notification
{
    colorInvertedCursor = [[PreferencePanel sharedInstance] colorInvertedCursor];
    [self setNeedsDisplay:YES];
}

- (void)_modifyFont:(NSFont*)font into:(PTYFontInfo*)fontInfo
{
    if (fontInfo->font) {
        [self releaseFontInfo:fontInfo];
    }

    fontInfo->font = font;
    [fontInfo->font retain];
    fontInfo->baselineOffset = -floor([font leading] - [font descender]);
    fontInfo->boldVersion = NULL;
}

- (void)modifyFont:(NSFont*)font info:(PTYFontInfo*)fontInfo
{
    [self _modifyFont:font into:fontInfo];
    NSFontManager* fontManager = [NSFontManager sharedFontManager];
    NSFont* boldFont = [fontManager convertFont:font toHaveTrait:NSBoldFontMask];
    if (boldFont && ([fontManager traitsOfFont:boldFont] & NSBoldFontMask)) {
        fontInfo->boldVersion = (PTYFontInfo*)malloc(sizeof(PTYFontInfo));
        fontInfo->boldVersion->font = NULL;
        [self _modifyFont:boldFont into:fontInfo->boldVersion];
    }
}

- (PTYFontInfo*)getOrAddFallbackFont:(NSFont*)font
{
    NSString* name = [font fontName];
    NSValue* entry = [fallbackFonts objectForKey:name];
    if (entry) {
        return [entry pointerValue];
    } else {
        PTYFontInfo* info = (PTYFontInfo*) malloc(sizeof(PTYFontInfo));
        info->font = NULL;
        [self _modifyFont:font into:info];

        // Force this font to line up with the primary font's baseline.
        info->baselineOffset = primaryFont.baselineOffset;
        if (info->boldVersion) {
            info->boldVersion->baselineOffset = primaryFont.baselineOffset;
        }

        [fallbackFonts setObject:[NSValue valueWithPointer:info] forKey:name];
        return info;
    }
}

- (void)releaseAllFallbackFonts
{
    NSEnumerator* enumerator = [fallbackFonts keyEnumerator];
    id key;
    while ((key = [enumerator nextObject])) {
        PTYFontInfo* info = [[fallbackFonts objectForKey:key] pointerValue];
        [self releaseFontInfo:info];
        free(info);
    }
    [fallbackFonts removeAllObjects];
}

- (void)releaseFontInfo:(PTYFontInfo*)fontInfo
{
    [fontInfo->font release];
    if (fontInfo->boldVersion) {
        [self releaseFontInfo:fontInfo->boldVersion];
    }
}

// WARNING: Do not call this function directly. Call
// -[refresh] instead, as it ensures scrollback overflow
// is dealt with so that this function can dereference
// [dataSource dirty] correctly.
- (void)updateDirtyRects
{
    if ([dataSource scrollbackOverflow] != 0) {
        NSAssert([dataSource scrollbackOverflow] == 0, @"updateDirtyRects called with nonzero overflow");
    }
#ifdef DEBUG_DRAWING
    [self appendDebug:[NSString stringWithFormat:@"updateDirtyRects called. Scrollback overflow is %d. Screen is: %@", [dataSource scrollbackOverflow], [dataSource debugString]]];
#endif
    DebugLog(@"updateDirtyRects called");
    int WIDTH = [dataSource width];
    char* dirty;
    int lineStart;
    int lineEnd;

    // Check each line for dirty selected text
    // If any is found then deselect everything
    dirty = [dataSource dirty];
    lineStart = [dataSource numberOfLines] - [dataSource height];
    lineEnd = [dataSource numberOfLines];
    for (int y = lineStart; y < lineEnd && startX > -1; y++) {
        for (int x = 0; x < WIDTH; x++) {
            BOOL isSelected = [self _isCharSelectedInRow:y col:x checkOld:NO];
            int cursorX = [dataSource cursorX] - 1;
            int cursorY = [dataSource cursorY] + [dataSource numberOfLines] - [dataSource height] - 1;
            BOOL isCursor = (x == cursorX && y == cursorY);
            if (dirty[x] && isSelected && !isCursor) {
                // Don't call [self deselect] as it would recurse back here
                startX = -1;
                DebugLog(@"found selected dirty noncursor");
                break;
            }
        }
        dirty += WIDTH;
    }

    // Time to redraw blinking text?
    struct timeval now;
    BOOL redrawBlink = NO;
    gettimeofday(&now, NULL);
    if(now.tv_sec*10+now.tv_usec/100000 >= lastBlink.tv_sec*10+lastBlink.tv_usec/100000+7) {
        blinkShow = !blinkShow;
        lastBlink = now;
        redrawBlink = YES;
        DebugLog(@"time to redraw blinking text");
    }

    // Visible chars that have changed selection status are dirty
    // Also mark blinking text as dirty if needed
    lineStart = [self visibleRect].origin.y / lineHeight;
    lineEnd = lineStart + ceil([self visibleRect].size.height / lineHeight);
    if(lineStart < 0) lineStart = 0;
    if(lineEnd > [dataSource numberOfLines]) lineEnd = [dataSource numberOfLines];
    for(int y = lineStart; y < lineEnd; y++) {
        screen_char_t* theLine = [dataSource getLineAtIndex:y];
        for(int x = 0; x < WIDTH; x++) {
            BOOL isSelected = [self _isCharSelectedInRow:y col:x checkOld:NO];
            BOOL wasSelected = [self _isCharSelectedInRow:y col:x checkOld:YES];
            BOOL blinked = redrawBlink && (theLine[x].fg_color & BLINK_MASK);
            if (isSelected != wasSelected || blinked) {
                NSRect dirtyRect = [self visibleRect];
                dirtyRect.origin.y = y*lineHeight;
                dirtyRect.size.height = lineHeight;
                DebugLog([NSString stringWithFormat:@"found selection change/blink at %d,%d", x, y]);
                [self setNeedsDisplayInRect:dirtyRect];
                break;
            }
        }
    }
    oldStartX=startX; oldStartY=startY; oldEndX=endX; oldEndY=endY; oldSelectMode = selectMode;

    // Redraw lines with dirty characters
    dirty = [dataSource dirty];
    lineStart = [dataSource numberOfLines] - [dataSource height];
    // lineStart = number of scrollback lines
    lineEnd = [dataSource numberOfLines];
    // lineEnd = number of scrollback lines + screen height
    DebugLog([NSString stringWithFormat:@"Search lines [%d, %d) for dirty", lineStart, lineEnd]);
#ifdef DEBUG_DRAWING
    NSMutableString* dirtyDebug = [NSMutableString stringWithString:@"updateDirtyRects found these dirty lines:\n"];
    int screenindex=0;
#endif
    for(int y = lineStart; y < lineEnd; y++) {
        for(int x = 0; x < WIDTH; x++) {
            if(dirty[x]) {
                NSRect dirtyRect = [self visibleRect];
                dirtyRect.origin.y = y*lineHeight;
                dirtyRect.size.height = lineHeight;
                DebugLog([NSString stringWithFormat:@"%d is dirty", y]);
                [self setNeedsDisplayInRect:dirtyRect];
#ifdef DEBUG_DRAWING
                char temp[100];
                screen_char_t* p = [dataSource getLineAtScreenIndex:screenindex];
                for (int i = 0; i < WIDTH; ++i) {
                    temp[i] = p[i].ch;
                }
                temp[WIDTH] = 0;
                [dirtyDebug appendFormat:@"set rect %d,%d %dx%d (line %d=%s) dirty\n",
                 (int)dirtyRect.origin.x,
                 (int)dirtyRect.origin.y,
                 (int)dirtyRect.size.width,
                 (int)dirtyRect.size.height,
                 y, temp];
#endif
                break;
            }
        }
#ifdef DEBUG_DRAWING
        ++screenindex;
#endif
        dirty += WIDTH;
    }
    DebugLog(@"updateDirtyRects resetDirty");
#ifdef DEBUG_DRAWING
    [self appendDebug:dirtyDebug];
#endif
    [dataSource resetDirty];
}

@end
