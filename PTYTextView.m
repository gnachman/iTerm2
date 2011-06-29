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
static const int MAX_WORKING_DIR_COUNT = 50;
//#define DEBUG_DRAWING

// Constants for converting RGB to luma.
#define RED_COEFFICIENT    0.30
#define GREEN_COEFFICIENT  0.59
#define BLUE_COEFFICIENT   0.11

#define SWAPINT(a, b) { int temp; temp = a; a = b; b = temp; }

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
#import "PasteboardHistory.h"
#import "PTYTab.h"
#import "iTermExpose.h"
#import "RegexKitLite/RegexKitLite.h"
#import "iTerm/NSStringITerm.h"

#include <sys/time.h>
#include <math.h>

// Minimum distance that the mouse must move before a cmd+drag will be
// recognized as a drag.
static const int kDragThreshold = 3;

// When drawing lines, we use this structure to represent a run of cells  of
// the same font, color, and attributes.
typedef enum {
  SINGLE_CODE_POINT_RUN,    // A run of cells with one code point each.
  MULTIPLE_CODE_POINT_RUN   // A single cell with multiple code points.
} RunType;

typedef struct {
    RunType runType;
    PTYFontInfo* fontInfo;
    NSColor* color;

    // Should bold text be rendered by drawing text twice with a 1px shift?
    BOOL fakeBold;

    // Pointer to code point(s) for this char.
    unichar* codes;

    // Number of codes that 'codes' points to.
    int numCodes;

    // Advances for each code.
    CGSize* advances;

    // Number of advances.
    int numAdvances;

    // x pixel coordinate for this cell.
    CGFloat x;

    // Pointer to glyphs for these chars (single code point only)
    CGGlyph* glyphs;

    // Number of glyphs.
    int numGlyphs;

    // Should this run be anti-aliased.
    BOOL antiAlias;
} CharRun;

// FIXME: Looks like this is leaked.
static NSCursor* textViewCursor =  nil;
static NSImage* bellImage = nil;
static NSImage* wrapToTopImage = nil;
static NSImage* wrapToBottomImage = nil;

@interface Coord : NSObject
{
@public
    int x, y;
}
+ (Coord*)coordWithX:(int)x y:(int)y;
@end

@implementation Coord

+ (Coord*)coordWithX:(int)x y:(int)y
{
    Coord* c = [[[Coord alloc] init] autorelease];
    c->x = x;
    c->y = y;
    return c;
}

@end

@interface SmartMatch : NSObject
{
@public
    double score;
    int startX;
    long long absStartY;
    int endX;
    long long absEndY;
}
- (NSComparisonResult)compare:(SmartMatch *)aNumber;
@end

@implementation SmartMatch

- (NSComparisonResult)compare:(SmartMatch *)other
{
    return [[NSNumber numberWithDouble:score] compare:[NSNumber numberWithDouble:other->score]];
}

@end


@implementation PTYTextView

+ (void)initialize
{
    NSPoint hotspot = NSMakePoint(4, 5);

    NSBundle* bundle = [NSBundle bundleForClass:[self class]];
    NSString* ibarFile = [bundle
                          pathForResource:@"IBarCursor"
                          ofType:@"png"];
    NSImage* image = [[[NSImage alloc] initWithContentsOfFile:ibarFile] autorelease];

    textViewCursor = [[NSCursor alloc] initWithImage:image hotSpot:hotspot];

    NSString* bellFile = [bundle
                          pathForResource:@"bell"
                          ofType:@"png"];
    bellImage = [[NSImage alloc] initWithContentsOfFile:bellFile];
    [bellImage setFlipped:YES];

    NSString* wrapToTopFile = [bundle
                          pathForResource:@"wrap_to_top"
                          ofType:@"png"];
    wrapToTopImage = [[NSImage alloc] initWithContentsOfFile:wrapToTopFile];
    [wrapToTopImage setFlipped:YES];

    NSString* wrapToBottomFile = [bundle
                               pathForResource:@"wrap_to_bottom"
                               ofType:@"png"];
    wrapToBottomImage = [[NSImage alloc] initWithContentsOfFile:wrapToBottomFile];
    [wrapToBottomImage setFlipped:YES];
}

+ (NSCursor *)textViewCursor
{
    return textViewCursor;
}

- (id)initWithFrame:(NSRect)aRect
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif

    self = [super initWithFrame: aRect];
    dataSource=_delegate=markedTextAttributes=NULL;
    firstMouseEventNumber_ = -1;
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
    lastFindStartX = lastFindEndX = oldStartX = startX = -1;
    markedText = nil;
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

    advancedFontRendering = [[PreferencePanel sharedInstance] advancedFontRendering];
    strokeThickness = [[PreferencePanel sharedInstance] strokeThickness];
    imeOffset = 0;
    resultMap_ = [[NSMutableDictionary alloc] init];

    trouter = [[Trouter alloc] init];
    workingDirectoryAtLines = [[NSMutableArray alloc] init];
    return self;
}

- (BOOL)resignFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    PTYSession* mySession = [dataSource session];
    [[mySession tab] setActiveSession:mySession];
    return YES;
}

- (void)viewWillMoveToWindow:(NSWindow *)win
{
    if (!win && [self window] && trackingRectTag) {
        [self removeTrackingRect:trackingRectTag];
        trackingRectTag = 0;
    }
    [super viewWillMoveToWindow:win];
}

- (void)viewDidMoveToWindow
{
    if ([self window]) {
        trackingRectTag = [self addTrackingRect:[self frame]
                                          owner:self
                                       userData:nil
                                   assumeInside:NO];
    }
}

- (void)dealloc
{
    int i;

    if (mouseDownEvent != nil) {
        [mouseDownEvent release];
        mouseDownEvent = nil;
    }

    if (trackingRectTag) {
        [self removeTrackingRect:trackingRectTag];
    }

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (i = 0; i < 256; i++) {
        [colorTable[i] release];
    }
    [lastFlashUpdate_ release];
    [resultMap_ release];
    [findResults_ release];
    [findString_ release];
    [defaultFGColor release];
    [defaultBGColor release];
    [defaultBoldColor release];
    [selectionColor release];
    [defaultCursorColor release];

    [self releaseFontInfo:&primaryFont];
    [self releaseFontInfo:&secondaryFont];

    [markedTextAttributes release];
    [markedText release];

    [self releaseAllFallbackFonts];
    [fallbackFonts release];
    [selectionScrollTimer release];

    [workingDirectoryAtLines release];
    [trouter release];

    [super dealloc];
}

- (BOOL)shouldDrawInsertionPoint
{
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

- (void)setAntiAlias:(BOOL)asciiAA nonAscii:(BOOL)nonAsciiAA
{
    asciiAntiAlias = asciiAA;
    nonasciiAntiAlias = nonAsciiAA;
    [self setNeedsDisplay:YES];
}

- (BOOL)useBoldFont
{
    return useBoldFont;
}

- (void)setUseBoldFont:(BOOL)boldFlag
{
    useBoldFont = boldFlag;
    [self setNeedsDisplay:YES];
}

- (void)setUseBrightBold:(BOOL)flag
{
    useBrightBold = flag;
    [self setNeedsDisplay:YES];
}

- (BOOL)blinkingCursor
{
    return blinkingCursor;
}

- (void)setBlinkingCursor:(BOOL)bFlag
{
    blinkingCursor = bFlag;
}

- (void)setBlinkAllowed:(BOOL)value
{
    blinkAllowed_ = value;
}

- (void)setCursorType:(ITermCursorType)value
{
    cursorType_ = value;
}

- (NSDictionary*)markedTextAttributes
{
    return markedTextAttributes;
}

- (void)setMarkedTextAttributes:(NSDictionary *)attr
{
    [markedTextAttributes release];
    [attr retain];
    markedTextAttributes=attr;
}

- (int)selectionStartX
{
    return startX;
}

- (int)selectionStartY
{
    return startY;
}

- (int)selectionEndX
{
    return endX;
}

- (int)selectionEndY
{
    return endY;
}

- (void)setSelectionFromX:(int)fromX fromY:(int)fromY toX:(int)toX toY:(int)toY
{
    startX = fromX;
    startY = fromY;
    endX = toX;
    endY = toY;
}

- (void)setFGColor:(NSColor*)color
{
    [defaultFGColor release];
    [color retain];
    defaultFGColor = color;
    [self setNeedsDisplay:YES];
}

- (void)setBGColor:(NSColor*)color
{
    [defaultBGColor release];
    [color retain];
    defaultBGColor = color;
    [self setNeedsDisplay:YES];
}

- (void)setBoldColor:(NSColor*)color
{
    [defaultBoldColor release];
    [color retain];
    defaultBoldColor = color;
    [self setNeedsDisplay:YES];
}

- (void)setCursorColor:(NSColor*)color
{
    [defaultCursorColor release];
    [color retain];
    defaultCursorColor = color;
    [self setNeedsDisplay:YES];
}

- (void)setSelectedTextColor:(NSColor *)aColor
{
    [selectedTextColor release];
    [aColor retain];
    selectedTextColor = aColor;
    [self setNeedsDisplay:YES];
}

- (void)setCursorTextColor:(NSColor*)aColor
{
    [cursorTextColor release];
    [aColor retain];
    cursorTextColor = aColor;
    [self setNeedsDisplay:YES];
}

- (NSColor*)cursorTextColor
{
    return cursorTextColor;
}

- (NSColor*)selectedTextColor
{
    return selectedTextColor;
}

- (NSColor*)defaultFGColor
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

- (void)setColorTable:(int)theIndex color:(NSColor*)origColor
{
    NSColor* theColor = [origColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    [colorTable[theIndex] release];
    [theColor retain];
    colorTable[theIndex] = theColor;
    [self setNeedsDisplay:YES];
}

- (NSColor*)_colorForCode:(int)theIndex alternateSemantics:(BOOL)alt bold:(BOOL)isBold
{
    NSColor* color;

    if (alt) {
        switch (theIndex) {
            case ALTSEM_SELECTED:
                color = selectedTextColor;
                break;
            case ALTSEM_CURSOR:
                color = cursorTextColor;
                break;
            case ALTSEM_BG_DEFAULT:
                color = defaultBGColor;
                break;
            default:
                if (isBold && useBrightBold) {
                    if (theIndex == ALTSEM_BG_DEFAULT) {
                        color = defaultBGColor;
                    } else {
                        color = [self defaultBoldColor];
                    }
                } else {
                    color = defaultFGColor;
                }
        }
    } else {
        // Render bold text as bright. The spec (ECMA-48) describes the intense
        // display setting (esc[1m) as "bold or bright". We make it a
        // preference.
        if (isBold &&
            useBrightBold &&
            (theIndex < 8)) { // Only colors 0-7 can be made "bright".
            theIndex |= 8;  // set "bright" bit.
        }
        color = colorTable[theIndex];
    }

    return color;
}

- (NSColor*)_dimmedColorFrom:(NSColor*)orig
{
    if (dimmingAmount_ == 0) {
        return orig;
    }
    double r = [orig redComponent];
    double g = [orig greenComponent];
    double b = [orig blueComponent];

    // This algorithm limits the dynamic range of colors as well as brightening
    // them. Both attributes change in proportion to the dimmingAmount_.

    // Find a linear interpolation between kCenter and the requested color component
    // in proportion to 1- dimmingAmount_.
    const double kCenter = 0.5;

    return [NSColor colorWithCalibratedRed:(1 - dimmingAmount_) * r + dimmingAmount_ * kCenter
                                     green:(1 - dimmingAmount_) * g + dimmingAmount_ * kCenter
                                      blue:(1 - dimmingAmount_) * b + dimmingAmount_ * kCenter
                                     alpha:[orig alphaComponent]];
}

- (NSColor*)colorForCode:(int)theIndex alternateSemantics:(BOOL)alt bold:(BOOL)isBold
{
    return [self _dimmedColorFrom:[self _colorForCode:theIndex alternateSemantics:alt bold:isBold]];
}

- (NSColor *)selectionColor
{
    return selectionColor;
}

- (void)setSelectionColor:(NSColor *)aColor
{
    [selectionColor release];
    [aColor retain];
    selectionColor = aColor;
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

+ (NSSize)charSizeForFont:(NSFont*)aFont horizontalSpacing:(double)hspace verticalSpacing:(double)vspace
{
    NSMutableDictionary *dic = [NSMutableDictionary dictionary];

    [dic setObject:aFont forKey:NSFontAttributeName];
    NSSize size = [@"W" sizeWithAttributes:dic];

    size.width = ceil(size.width * hspace);
    size.height = ceil(vspace * ceil([aFont ascender] - [aFont descender] + [aFont leading]));
    return size;
}

- (double)horizontalSpacing
{
    return horizontalSpacing_;
}

- (double)verticalSpacing
{
    return verticalSpacing_;
}

- (void)setFont:(NSFont*)aFont
         nafont:(NSFont *)naFont
    horizontalSpacing:(double)horizontalSpacing
    verticalSpacing:(double)verticalSpacing
{
    NSSize sz = [PTYTextView charSizeForFont:aFont
                           horizontalSpacing:1.0
                             verticalSpacing:1.0];

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
    if (secondaryFont.boldVersion) {
        if (primaryFont.boldVersion) {
            secondaryFont.boldVersion->baselineOffset = primaryFont.boldVersion->baselineOffset;
        } else {
            secondaryFont.boldVersion->baselineOffset = secondaryFont.baselineOffset;
        }
    }

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
    [scrollview setPageScroll:2 * [self lineHeight]];
}

- (void)changeFont:(id)fontManager
{
    if ([[PreferencePanel sharedInstance] onScreen]) {
        [[PreferencePanel sharedInstance] changeFont:fontManager];
    } else if ([[PreferencePanel sessionsInstance] onScreen]) {
        [[PreferencePanel sessionsInstance] changeFont:fontManager];
    }
}

- (id)dataSource
{
    return dataSource;
}

- (void)setDataSource:(id)aDataSource
{
    dataSource = aDataSource;
}

- (id)delegate
{
    return _delegate;
}

- (void)setDelegate:(id)aDelegate
{
    _delegate = aDelegate;
}

- (double)lineHeight
{
    return ceil(lineHeight);
}

- (void)setLineHeight:(double)aLineHeight
{
    lineHeight = aLineHeight;
}

- (double)charWidth
{
    return ceil(charWidth);
}

- (void)setCharWidth:(double)width
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

- (double)excess
{
    NSRect visible = [self scrollViewContentSize];
    visible.size.height -= VMARGIN * 2;  // Height without top and bottom margins.
    int rows = visible.size.height / lineHeight;
    double usablePixels = rows * lineHeight;
    return MAX(visible.size.height - usablePixels + VMARGIN, VMARGIN);  // Never have less than VMARGIN excess, but it can be more (if another tab has a bigger font)
}

// We override this method since both refresh and window resize can conflict
// resulting in this happening twice So we do not allow the size to be set
// larger than what the data source can fill
- (void)setFrameSize:(NSSize)frameSize
{
    // Force the height to always be correct
    frameSize.height = [dataSource numberOfLines] * lineHeight + [self excess] + imeOffset * lineHeight;
    [super setFrameSize:frameSize];

    frameSize.height += VMARGIN;  // This causes a margin to be left at the top
    [[self superview] setFrameSize:frameSize];
}

static BOOL RectsEqual(NSRect* a, NSRect* b) {
        return a->origin.x == b->origin.x &&
               a->origin.y == b->origin.y &&
               a->size.width == b->size.width &&
               a->size.height == b->size.height;
}

- (void)scheduleSelectionScroll
{
    if (selectionScrollTimer) {
        [selectionScrollTimer release];
        if (prevScrollDelay > 0.001) {
            // Maximum speed hasn't been reached so accelerate scrolling speed by 5%.
            prevScrollDelay *= 0.95;
        }
    } else {
        // Set a slow initial scrolling speed.
        prevScrollDelay = 0.1;
    }

    lastSelectionScroll = [[NSDate date] timeIntervalSince1970];
    selectionScrollTimer = [[NSTimer scheduledTimerWithTimeInterval:prevScrollDelay
                                                             target:self
                                                           selector:@selector(updateSelectionScroll)
                                                           userInfo:nil
                                                            repeats:NO] retain];
}

// Scroll the screen up or down a line for a selection drag scroll.
- (void)updateSelectionScroll
{
    double actualDelay = [[NSDate date] timeIntervalSince1970] - lastSelectionScroll;
    const int kMaxLines = 100;
    int numLines = MIN(kMaxLines, MAX(1, actualDelay / prevScrollDelay));
    NSRect visibleRect = [self visibleRect];

    int y = 0;
    if (!selectionScrollDirection) {
        [selectionScrollTimer release];
        selectionScrollTimer = nil;
        return;
    } else if (selectionScrollDirection < 0) {
        visibleRect.origin.y -= [self lineHeight] * numLines;
        // Allow the origin to go as far as y=-VMARGIN so the top border is shown when the first line is
        // on screen.
        if (visibleRect.origin.y >= -VMARGIN) {
            [self scrollRectToVisible:visibleRect];
        }
        y = visibleRect.origin.y / lineHeight;
    } else if (selectionScrollDirection > 0) {
        visibleRect.origin.y += lineHeight * numLines;
        if (visibleRect.origin.y + visibleRect.size.height > [self frame].size.height) {
            visibleRect.origin.y = [self frame].size.height - visibleRect.size.height;
        }
        [self scrollRectToVisible:visibleRect];
        y = (visibleRect.origin.y + visibleRect.size.height - [self excess]) / lineHeight;
    }

    [self moveSelectionEndpointToX:scrollingX
                                 Y:y
                locationInTextView:scrollingLocation];

    [[[self dataSource] session] refreshAndStartTimerIfNeeded];
    [self scheduleSelectionScroll];
}

- (BOOL)accessibilityIsIgnored
{
    return NO;
}

- (NSArray*)accessibilityAttributeNames
{
    return [NSArray arrayWithObjects:
            NSAccessibilityRoleAttribute,
            NSAccessibilityRoleDescriptionAttribute,
            NSAccessibilityHelpAttribute,
            NSAccessibilityFocusedAttribute,
            NSAccessibilityParentAttribute,
            NSAccessibilityChildrenAttribute,
            NSAccessibilityWindowAttribute,
            NSAccessibilityTopLevelUIElementAttribute,
            NSAccessibilityPositionAttribute,
            NSAccessibilitySizeAttribute,
            NSAccessibilityDescriptionAttribute,
            NSAccessibilityValueAttribute,
            NSAccessibilityNumberOfCharactersAttribute,
            NSAccessibilitySelectedTextAttribute,
            NSAccessibilitySelectedTextRangeAttribute,
            NSAccessibilitySelectedTextRangesAttribute,
            NSAccessibilityInsertionPointLineNumberAttribute,
            NSAccessibilityVisibleCharacterRangeAttribute,
            nil];
}

- (NSArray *)accessibilityParameterizedAttributeNames
{
    return [NSArray arrayWithObjects:
            NSAccessibilityLineForIndexParameterizedAttribute,
            NSAccessibilityRangeForLineParameterizedAttribute,
            NSAccessibilityStringForRangeParameterizedAttribute,
            NSAccessibilityRangeForPositionParameterizedAttribute,
            NSAccessibilityRangeForIndexParameterizedAttribute,
            NSAccessibilityBoundsForRangeParameterizedAttribute,
            nil];
}

// Range in allText_ of the given line.
- (NSRange)_rangeOfLine:(NSUInteger)lineNumber
{
    NSRange range;
    if (lineNumber == 0) {
        range.location = 0;
    } else {
        range.location = [[lineBreakCharOffsets_ objectAtIndex:lineNumber-1] unsignedLongValue];
    }
    if (lineNumber >= [lineBreakCharOffsets_ count]) {
        range.length = [allText_ length] - range.location;
    } else {
        range.length = [[lineBreakCharOffsets_ objectAtIndex:lineNumber] unsignedLongValue] - range.location;
    }
    return range;
}

// Range in allText_ of the given index.
- (NSUInteger)_lineNumberOfIndex:(NSUInteger)theIndex
{
    NSUInteger lineNum = 0;
    for (NSNumber* n in lineBreakIndexOffsets_) {
        NSUInteger offset = [n unsignedLongValue];
        if (offset > theIndex) {
            break;
        }
        lineNum++;
    }
    return lineNum;
}

// Line number of a location (respecting compositing chars) in allText_.
- (NSUInteger)_lineNumberOfChar:(NSUInteger)location
{
    NSUInteger lineNum = 0;
    for (NSNumber* n in lineBreakCharOffsets_) {
        NSUInteger offset = [n unsignedLongValue];
        if (offset > location) {
            break;
        }
        lineNum++;
    }
    return lineNum;
}

// Number of unichar a character uses (normally 1 in English).
- (int)_lengthOfChar:(screen_char_t)sct
{
    return [ScreenCharToStr(&sct) length];
}

// Position, respecting compositing chars, in allText_ of a line.
- (NSUInteger)_offsetOfLine:(NSUInteger)lineNum
{
    if (lineNum == 0) {
        return 0;
    }
    assert(lineNum < [lineBreakCharOffsets_ count] + 1);
    return [[lineBreakCharOffsets_ objectAtIndex:lineNum - 1] unsignedLongValue];
}

// Onscreen X-position of a location (respecting compositing chars) in allText_.
- (NSUInteger)_columnOfChar:(NSUInteger)location inLine:(NSUInteger)lineNum
{
    NSUInteger lineStart = [self _offsetOfLine:lineNum];
    screen_char_t* theLine = [dataSource getLineAtIndex:lineNum];
    assert(location >= lineStart);
    int remaining = location - lineStart;
    int i = 0;
    while (remaining > 0 && i < [dataSource width]) {
        remaining -= [self _lengthOfChar:theLine[i++]];
    }
    return i;
}

// Index (ignoring compositing chars) of a line in allText_.
- (NSUInteger)_startingIndexOfLineNumber:(NSUInteger)lineNumber
{
    if (lineNumber < [lineBreakIndexOffsets_ count]) {
        return [[lineBreakCharOffsets_ objectAtIndex:lineNumber] unsignedLongValue];
    } else if ([lineBreakIndexOffsets_ count] > 0) {
        return [[lineBreakIndexOffsets_ lastObject] unsignedLongValue];
    } else {
        return 0;
    }
}

// Range in allText_ of an index (ignoring compositing chars).
- (NSRange)_rangeOfIndex:(NSUInteger)theIndex
{
    NSUInteger lineNumber = [self _lineNumberOfIndex:theIndex];
    screen_char_t* theLine = [dataSource getLineAtIndex:lineNumber];
    NSUInteger startingIndexOfLine = [self _startingIndexOfLineNumber:lineNumber];
    assert(theIndex >= startingIndexOfLine);
    int x = theIndex - startingIndexOfLine;
    NSRange rangeOfLine = [self _rangeOfLine:lineNumber];
    NSRange range;
    range.location = rangeOfLine.location;
    for (int i = 0; i < x; i++) {
        range.location += [self _lengthOfChar:theLine[i]];
    }
    range.length = [self _lengthOfChar:theLine[x]];
    return range;
}

// Range, respecting compositing chars, of a character at an x,y position where 0,0 is the
// first char of the first line in the scrollback buffer.
- (NSRange)_rangeOfCharAtX:(int)x y:(int)y
{
    screen_char_t* theLine = [dataSource getLineAtIndex:y];
    NSRange lineRange = [self _rangeOfLine:y];
    NSRange result = lineRange;
    for (int i = 0; i < x; i++) {
        result.location += [self _lengthOfChar:theLine[i]];
    }
    result.length = [self _lengthOfChar:theLine[x]];
    return result;
}

/*
 * The concepts used here are not defined, so I'm going to give it my best guess.
 *
 * Suppose we have a terminal window like this:
 *
 * Line  On-Screen Contents
 * 0     [x]
 * 1     [ba'r]  (the ' is a combining accent)
 * 2     [y]
 *
 * Index  Location (as in a range)  Character
 * 0      0                         f
 * 1      1                         b
 * 2      2-3                       b + [']
 * 3      4                         r
 * 4      5                         y
 *
 * Index                   012 34
 * Char                    012345
 * allText_              = xba«ry
 * lineBreakCharOffests_ = [1, 4]
 * lineBreakInexOffsets_ = [1, 3]
 */
- (id)_accessibilityAttributeValue:(NSString *)attribute forParameter:(id)parameter
{
    if ([attribute isEqualToString:NSAccessibilityLineForIndexParameterizedAttribute]) {
        //(NSNumber *) - line# for char index; param:(NSNumber *)
        NSUInteger theIndex = [(NSNumber*)parameter unsignedLongValue];
        return [NSNumber numberWithUnsignedLong:[self _lineNumberOfIndex:theIndex]];
    } else if ([attribute isEqualToString:NSAccessibilityRangeForLineParameterizedAttribute]) {
        //(NSValue *)  - (rangeValue) range of line; param:(NSNumber *)
        NSUInteger lineNumber = [(NSNumber*)parameter unsignedLongValue];
        if (lineNumber >= [lineBreakIndexOffsets_ count]) {
            return [NSValue valueWithRange:NSMakeRange(NSNotFound, 0)];
        } else {
            return [NSValue valueWithRange:[self _rangeOfLine:lineNumber]];
        }
    } else if ([attribute isEqualToString:NSAccessibilityStringForRangeParameterizedAttribute]) {
        //(NSString *) - substring; param:(NSValue * - rangeValue)
        NSRange range = [(NSValue*)parameter rangeValue];
        return [allText_ substringWithRange:range];
    } else if ([attribute isEqualToString:NSAccessibilityRangeForPositionParameterizedAttribute]) {
        //(NSValue *)  - (rangeValue) composed char range; param:(NSValue * - pointValue)
        NSPoint position = [(NSValue*)parameter pointValue];
        int x = position.x / charWidth;
        NSRect myFrame = [self frame];
        myFrame.size.height = 0;
        int y = (myFrame.size.height - position.y) / lineHeight;
        return [NSValue valueWithRange:[self _rangeOfCharAtX:x y:y]];
    } else if ([attribute isEqualToString:NSAccessibilityRangeForIndexParameterizedAttribute]) {
        //(NSValue *)  - (rangeValue) composed char range; param:(NSNumber *)
        NSUInteger theIndex = [(NSNumber*)parameter unsignedLongValue];
        return [NSValue valueWithRange:[self _rangeOfIndex:theIndex]];
    } else if ([attribute isEqualToString:NSAccessibilityBoundsForRangeParameterizedAttribute]) {
        //(NSValue *)  - (rectValue) bounds of text; param:(NSValue * - rangeValue)
        NSRange range = [(NSValue*)parameter rangeValue];
        int yStart = [self _lineNumberOfChar:range.location];
        int y2 = [self _lineNumberOfChar:range.location + range.length - 1];
        int xStart = [self _columnOfChar:range.location inLine:yStart];
        int x2 = [self _columnOfChar:range.location + range.length - 1 inLine:y2];
        ++x2;
        if (x2 == [dataSource width]) {
            x2 = 0;
            ++y2;
        }
        int yMin = MIN(yStart, y2);
        int yMax = MAX(yStart, y2);
        int xMin = MIN(xStart, x2);
        int xMax = MAX(xStart, x2);
        NSRect myFrame = [self frame];
        myFrame.size.height = 0;
        NSRect result = NSMakeRect(xMin * charWidth,
                                   myFrame.size.height - yMin * lineHeight,
                                   (xMax - xMin + 1) * charWidth,
                                   (yMax - yMin + 1) * lineHeight);
        return [NSValue valueWithRect:result];
    } else {
        return [super accessibilityAttributeValue:attribute forParameter:parameter];
    }
}

- (id)accessibilityAttributeValue:(NSString *)attribute forParameter:(id)parameter
{
    id result = [self _accessibilityAttributeValue:attribute forParameter:parameter];
    return result;
}

// TODO(georgen): Speed this up! This code is dreadfully slow but it's only used
// when accessibility is on, and it might be faster than voiceover for reasonable
// amounts of text.
- (NSString*)_allText
{
    [allText_ release];
    [lineBreakCharOffsets_ release];
    [lineBreakIndexOffsets_ release];

    allText_ = [[NSMutableString alloc] init];
    lineBreakCharOffsets_ = [[NSMutableArray alloc] init];
    lineBreakIndexOffsets_ = [[NSMutableArray alloc] init];

    int width = [dataSource width];
    unichar chars[width * kMaxParts];
    int offset = 0;
    for (int i = 0; i < [dataSource numberOfLines]; i++) {
        screen_char_t* line = [dataSource getLineAtIndex:i];
        int k;
        // Get line width, store it in k
        for (k = width - 1; k >= 0; k--) {
            if (line[k].code) {
                break;
            }
        }
        int o = 0;
        // Add first width-k chars to the 'chars' array, expanding complex chars.
        for (int j = 0; j <= k; j++) {
            if (line[j].complexChar) {
                NSString* cs = ComplexCharToStr(line[j].code);
                for (int l = 0; l < [cs length]; ++l) {
                    chars[o++] = [cs characterAtIndex:l];
                }
            } else {
                chars[o++] = line[j].code;
            }
        }
        // Append this line to allText_.
        offset += o;
        if (k > 0) {
            [allText_ appendString:[NSString stringWithCharacters:chars length:o]];
        }
        if (line[width].code == EOL_HARD) {
            // Add a newline and update offsets arrays that track line break locations.
            [allText_ appendString:@"\n"];
            ++offset;
            [lineBreakCharOffsets_ addObject:[NSNumber numberWithUnsignedLong:[allText_ length]]];
            [lineBreakIndexOffsets_ addObject:[NSNumber numberWithUnsignedLong:offset]];
        }
    }

    return allText_;
}

- (id)accessibilityAttributeValue:(NSString *)attribute
{
    if ([attribute isEqualToString:NSAccessibilityRoleAttribute]) {
        return NSAccessibilityTextAreaRole;
    } else if ([attribute isEqualToString:NSAccessibilityRoleDescriptionAttribute]) {
        return NSAccessibilityRoleDescriptionForUIElement(NSAccessibilityTextAreaRole);
    } else if ([attribute isEqualToString:NSAccessibilityHelpAttribute]) {
        return nil;
    } else if ([attribute isEqualToString:NSAccessibilityFocusedAttribute]) {
        return [NSNumber numberWithBool:YES];
    } else if ([attribute isEqualToString:NSAccessibilityDescriptionAttribute]) {
        return @"shell";
    } else if ([attribute isEqualToString:NSAccessibilityValueAttribute]) {
        return [self _allText];
    } else if ([attribute isEqualToString:NSAccessibilityNumberOfCharactersAttribute]) {
        return [NSNumber numberWithInt:[[self _allText] length]];
    } else if ([attribute isEqualToString:NSAccessibilitySelectedTextAttribute]) {
        return @"";
    } else if ([attribute isEqualToString:NSAccessibilitySelectedTextRangeAttribute]) {
        int x = [dataSource cursorX] - 1;
        int y = [dataSource numberOfLines] - [dataSource height] + [dataSource cursorY] - 1;
        NSRange range = [self _rangeOfCharAtX:x y:y];
        range.length--;
        return [NSValue valueWithRange:range];
    } else if ([attribute isEqualToString:NSAccessibilitySelectedTextRangesAttribute]) {
        int x = [dataSource cursorX] - 1;
        int y = [dataSource numberOfLines] - [dataSource height] + [dataSource cursorY] - 1;
        NSRange range = [self _rangeOfCharAtX:x y:y];
        range.length--;
        return [NSArray arrayWithObject:
                [NSValue valueWithRange:range]];
    } else if ([attribute isEqualToString:NSAccessibilityInsertionPointLineNumberAttribute]) {
        return [NSNumber numberWithInt:[dataSource cursorY]-1 + [dataSource numberOfScrollbackLines]];
    } else if ([attribute isEqualToString:NSAccessibilityVisibleCharacterRangeAttribute]) {
        return [NSValue valueWithRange:NSMakeRange(0, [[self _allText] length])];
    } else {
        return [super accessibilityAttributeValue:attribute];
    }
}

- (BOOL)_isCursorBlinking
{
    if ([self blinkingCursor] &&
        [[self window] isKeyWindow] &&
        [[[dataSource session] tab] activeSession] == [dataSource session]) {
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)_charBlinks:(screen_char_t)sct
{
    return blinkAllowed_ && sct.blink;
}

- (BOOL)_isTextBlinking
{
    int width = [dataSource width];
    int lineStart = ([self visibleRect].origin.y + VMARGIN) / lineHeight;  // add VMARGIN because stuff under top margin isn't visible.
    int lineEnd = ceil(([self visibleRect].origin.y + [self visibleRect].size.height - [self excess]) / lineHeight);
    if (lineStart < 0) {
        lineStart = 0;
    }
    if (lineEnd > [dataSource numberOfLines]) {
        lineEnd = [dataSource numberOfLines];
    }
    for (int y = lineStart; y < lineEnd; y++) {
        screen_char_t* theLine = [dataSource getLineAtIndex:y];
        for (int x = 0; x < width; x++) {
            if (theLine[x].blink) {
                return YES;
            }
        }
    }

    return NO;
}

- (BOOL)_isAnythingBlinking
{
    return [self _isCursorBlinking] || (blinkAllowed_ && [self _isTextBlinking]);
}

- (BOOL)refresh
{
    DebugLog(@"PTYTextView refresh called");
    if (dataSource == nil) {
        return YES;
    }

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

    double excess = [self excess];

    if ((int)(height + excess + imeOffset * lineHeight) != frame.size.height) {
        // The old iTerm code had a comment about a hack at this location
        // that worked around an (alleged) bug in NSClipView not respecting
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
        // Add VMARGIN to include top margin.
        frame.size.height = height + excess + imeOffset * lineHeight + VMARGIN;
        [[self superview] setFrame:frame];
        frame.size.height -= VMARGIN;
        NSAccessibilityPostNotification(self, NSAccessibilityRowCountChangedNotification);
    } else if (scrollbackOverflow > 0) {
        // Some number of lines were lost from the head of the buffer.

        NSScrollView* scrollView = [self enclosingScrollView];
        double amount = [scrollView verticalLineScroll] * scrollbackOverflow;
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
                return [self _isAnythingBlinking];
            }
        }

        // Shift the old content upwards
        if (scrollbackOverflow < [dataSource height] && !userScroll) {
            [self scrollRect:[self visibleRect] by:NSMakeSize(0, -amount)];
            NSRect topMargin = [self visibleRect];
            topMargin.size.height = VMARGIN;
            [self setNeedsDisplayInRect:topMargin];

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
        NSAccessibilityPostNotification(self, NSAccessibilityRowCountChangedNotification);
    }

    // Scroll to the bottom if needed.
    BOOL userScroll = [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) userScroll];
    if (!userScroll) {
        [self scrollEnd];
    }
    NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
    long long absCursorY = [dataSource cursorY] + [dataSource numberOfLines] + [dataSource totalScrollbackOverflow] - [dataSource height];
    if ([dataSource cursorX] != accX ||
        absCursorY != accY) {
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedTextChangedNotification);
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedRowsChangedNotification);
        NSAccessibilityPostNotification(self, NSAccessibilitySelectedColumnsChangedNotification);
        accX = [dataSource cursorX];
        accY = absCursorY;
    }

    return [self updateDirtyRects] || [self _isCursorBlinking];
}

- (NSRect)adjustScroll:(NSRect)proposedVisibleRect
{
    proposedVisibleRect.origin.y=(int)(proposedVisibleRect.origin.y/lineHeight+0.5)*lineHeight;
    return proposedVisibleRect;
}

- (void)scrollLineUp:(id)sender
{
    NSRect scrollRect;

    scrollRect= [self visibleRect];
    scrollRect.origin.y-=[[self enclosingScrollView] verticalLineScroll];
    if (scrollRect.origin.y<0) scrollRect.origin.y=0;
    [self scrollRectToVisible: scrollRect];
}

- (void)scrollLineDown:(id)sender
{
    NSRect scrollRect;

    scrollRect= [self visibleRect];
    scrollRect.origin.y+=[[self enclosingScrollView] verticalLineScroll];
    [self scrollRectToVisible: scrollRect];
}

- (void)scrollPageUp:(id)sender
{
    NSRect scrollRect;

    scrollRect= [self visibleRect];
    scrollRect.origin.y-= scrollRect.size.height - [[self enclosingScrollView] verticalPageScroll];
    [self scrollRectToVisible: scrollRect];
}

- (void)scrollPageDown:(id)sender
{
    NSRect scrollRect;

    scrollRect = [self visibleRect];
    scrollRect.origin.y+= scrollRect.size.height - [[self enclosingScrollView] verticalPageScroll];
    [self scrollRectToVisible: scrollRect];
}

- (void)scrollHome
{
    NSRect scrollRect;

    scrollRect = [self visibleRect];
    scrollRect.origin.y = 0;
    [self scrollRectToVisible: scrollRect];
}

- (void)scrollEnd
{
    if ([dataSource numberOfLines] <= 0) {
      return;
    }
    NSRect lastLine = [self visibleRect];
    lastLine.origin.y = ([dataSource numberOfLines] - 1) * lineHeight + [self excess] + imeOffset * lineHeight;
    lastLine.size.height = lineHeight;
    [self scrollRectToVisible:lastLine];
}

- (long long)absoluteScrollPosition
{
    NSRect visibleRect = [self visibleRect];
    long long localOffset = (visibleRect.origin.y + VMARGIN) / [self lineHeight];
    return localOffset + [dataSource totalScrollbackOverflow];
}

- (void)scrollToAbsoluteOffset:(long long)absOff height:(int)height
{
    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = (absOff - [dataSource totalScrollbackOverflow]) * lineHeight - VMARGIN;
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = lineHeight * height;
    [self scrollRectToVisible: aFrame];
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
}

- (void)scrollToSelection
{
    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = startY * lineHeight - VMARGIN;  // allow for top margin
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = (endY - startY + 1) *lineHeight;
    [self scrollRectToVisible: aFrame];
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];
}

- (void)hideCursor
{
    CURSOR=NO;
}

- (void)showCursor
{
    CURSOR=YES;
}

- (void)drawRect:(NSRect)rect
{
    [self drawRect:rect to:nil];

    if (flashing_ > 0) {
        NSRect frame = [self visibleRect];
        NSImage* image = nil;
        switch (flashImage_) {
            case FlashBell:
                image = bellImage;
                break;

            case FlashWrapToTop:
                image = wrapToTopImage;
                break;

            case FlashWrapToBottom:
                image = wrapToBottomImage;
                break;
        }

        NSSize size = [image size];
        [image drawAtPoint:NSMakePoint(frame.origin.x + frame.size.width/2 - size.width/2,
                                       frame.origin.y + frame.size.height/2 - size.height/2)
                  fromRect:NSMakeRect(0, 0, size.width, size.height)
                 operation:NSCompositeSourceOver
                  fraction:flashing_];
    }
}

- (void)drawRect:(NSRect)rect to:(NSPoint*)toOrigin
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
    DebugLog([NSString stringWithFormat:@"%s(0x%x): rect=(%f,%f,%f,%f) frameRect=(%f,%f,%f,%f)]",
          __PRETTY_FUNCTION__, self,
          rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
          [self frame].origin.x, [self frame].origin.y, [self frame].size.width, [self frame].size.height]);

    double curLineWidth = [dataSource width] * charWidth;
    if (lineHeight <= 0 || curLineWidth <= 0) {
        DebugLog(@"height or width too small");
        return;
    }

    // Configure graphics
    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeCopy];

    // Where to start drawing?
    int lineStart = rect.origin.y / lineHeight;
    int lineEnd = ceil((rect.origin.y + rect.size.height) / lineHeight);

    // Ensure valid line ranges
    if (lineStart < 0) {
        lineStart = 0;
    }
    if (lineEnd > [dataSource numberOfLines]) {
        lineEnd = [dataSource numberOfLines];
    }
    NSRect visible = [self scrollViewContentSize];
    int vh = visible.size.height;
    int lh = lineHeight;
    int visibleRows = vh / lh;
    NSRect docVisibleRect = [[[dataSource session] SCROLLVIEW] documentVisibleRect];
    double hiddenAbove = docVisibleRect.origin.y + [self frame].origin.y;
    int firstVisibleRow = hiddenAbove / lh;
    if (lineEnd > firstVisibleRow + visibleRows) {
        lineEnd = firstVisibleRow + visibleRows;
    }

    DebugLog([NSString stringWithFormat:@"drawRect: Draw lines in range [%d, %d)", lineStart, lineEnd]);
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
    double y = lineStart * lineHeight;
    const double initialY = y;
    BOOL anyBlinking = NO;
    for (int line = lineStart; line < lineEnd; line++) {
        NSRect lineRect = [self visibleRect];
        lineRect.origin.y = line*lineHeight;
        lineRect.size.height = lineHeight;
        if ([self needsToDrawRect:lineRect]) {
            if (overflow <= line) {
                // If overflow > 0 then the lines in the dataSource are not
                // lined up in the normal way with the view. This happens when
                // the datasource has scrolled its contents up but -[refresh]
                // has not been called yet, so the view's contents haven't been
                // scrolled up yet. When that's the case, the first line of the
                // view is what the first line of the datasource was before
                // it overflowed. Continue to draw text in this out-of-alignment
                // manner until refresh is called and gets things in sync again.
                NSPoint temp;
                if (toOrigin) {
                    const CGFloat offsetFromTopOfScreen = y - initialY;
                    temp = NSMakePoint(toOrigin->x, toOrigin->y + offsetFromTopOfScreen);
                }
                anyBlinking |= [self _drawLine:line-overflow AtY:y toPoint:toOrigin ? &temp : nil];
            }
            // if overflow > line then the requested line cannot be drawn
            // because it has been lost to the sands of time.
            if (gDebugLogging) {
                screen_char_t* theLine = [dataSource getLineAtIndex:line-overflow];
                int w = [dataSource width];
                char dl[w+1];
                for (int i = 0; i < [dataSource width]; ++i) {
                    if (theLine[i].complexChar) {
                        dl[i] = '#';
                    } else {
                        dl[i] = theLine[i].code;
                    }
                }
                DebugLog([NSString stringWithCString:dl]);
            }

#ifdef DEBUG_DRAWING
            screen_char_t* theLine = [dataSource getLineAtIndex:line-overflow];
            for (int i = 0; i < [dataSource width]; ++i) {
                [lineDebug appendFormat:@"%@", ScreenCharToStr(&theLine[i])];
            }
            [lineDebug appendString:@"\n"];
            [[NSString stringWithFormat:@"Iter %d, line %d, y=%d",
              iteration, line, (int)(y)] drawInRect:NSMakeRect(rect.size.width-200,
                                                               y,
                                                               200,
                                                               lineHeight)
             withAttributes:dct];
#endif
        }
        y += lineHeight;
    }
#ifdef DEBUG_DRAWING
    [self appendDebug:lineDebug];
#endif
    NSRect excessRect;
    if (imeOffset) {
        // Draw a default-color rectangle from below the last line of text to
        // the bottom of the frame to make sure that IME offset lines are
        // cleared when the screen is scrolled up.
        excessRect.origin.x = 0;
        excessRect.origin.y = lineEnd * lineHeight;
        excessRect.size.width = [[self enclosingScrollView] contentSize].width;
        excessRect.size.height = [self frame].size.height - excessRect.origin.y;
    } else  {
        // Draw the excess bar at the bottom of the visible rect the in case
        // that some other tab has a larger font and these lines don't fit
        // evenly in the available space.
        NSRect visibleRect = [self visibleRect];
        excessRect.origin.x = 0;
        excessRect.origin.y = visibleRect.origin.y + visibleRect.size.height - [self excess];
        excessRect.size.width = [[self enclosingScrollView] contentSize].width;
        excessRect.size.height = [self excess];
    }
#ifdef DEBUG_DRAWING
    // Draws the excess bar in a different color each time
    static int i;
    i++;
    double rc = ((double)((i + 0) % 100)) / 100;
    double gc = ((double)((i + 33) % 100)) / 100;
    double bc = ((double)((i + 66) % 100)) / 100;
    [[NSColor colorWithCalibratedRed:rc green:gc blue:bc alpha:1] set];
    NSRectFill(excessRect);
#else
    if (toOrigin) {
        [self drawBackground:excessRect toPoint:*toOrigin];
    } else {
        [self drawBackground:excessRect];
    }
#endif

    // Draw a margin at the top of the visible area.
    NSRect topMarginRect = [self visibleRect];
    if (topMarginRect.origin.y > 0) {
        topMarginRect.size.height = VMARGIN;
        if (toOrigin) {
            [self drawBackground:topMarginRect toPoint:*toOrigin];
        } else {
            [self drawBackground:topMarginRect];
        }
    }

#ifdef DEBUG_DRAWING
    // Draws a different-colored rectangle around each drawn area. Useful for
    // seeing which groups of lines were drawn in a batch.
    static double it;
    it += 3.14/4;
    double red = sin(it);
    double green = sin(it + 1*2*3.14/3);
    double blue = sin(it + 2*2*3.14/3);
    NSColor* c = [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1];
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
    // If the IME is in use, draw its contents over top of the "real" screen
    // contents.
    [self drawInputMethodEditorTextAt:[dataSource cursorX] - 1
                                    y:[dataSource cursorY] - 1
                                width:[dataSource width]
                               height:[dataSource height]
                         cursorHeight:[self cursorHeight]];
    [self _drawCursorTo:toOrigin];
    anyBlinking |= [self _isCursorBlinking];

#ifdef DEBUG_DRAWING
    if (overflow) {
        // It's useful to put a breakpoint at the top of this function
        // when prevBad == YES because then you can see the results of this
        // draw function.
        prevBad=YES;
    }
#endif
    if (anyBlinking) {
        // The user might have used the scroll wheel to cause blinking text to become
        // visible. Make sure the timer is running if anything onscreen is
        // blinking.
        [[dataSource session] scheduleUpdateIn:kBlinkTimerIntervalSec];
    }
}

- (NSString*)_getTextInWindowAroundX:(int)x
                                   y:(int)y
                            numLines:(int)numLines
                        targetOffset:(int*)targetOffset
                              coords:(NSMutableArray*)coords
{
    const int width = [dataSource width];
    NSMutableString* joinedLines = [NSMutableString stringWithCapacity:numLines * width];

    *targetOffset = -1;

    BOOL rejectAtHardEol = YES;
    int xMin, xMax;
    xMin = 0;
    xMax = width;

    int j = 0;

    for (int i = y - numLines; i <= y + numLines; i++) {
        if (i < 0 || i >= [dataSource numberOfLines]) {
            continue;
        }
        screen_char_t* theLine = [dataSource getLineAtIndex:i];
        if (i < y && rejectAtHardEol && theLine[width].code == EOL_HARD) {
            continue;
        }
        unichar* backingStore;
        int* deltas;
        NSString* string = ScreenCharArrayToString(theLine,
                                                   xMin,
                                                   MIN(EffectiveLineLength(theLine, width), xMax),
                                                   &backingStore,
                                                   &deltas);
        int o = 0;
        for (int k = 0; k < [string length]; k++, o++) {
            o += deltas[k];
            if (*targetOffset == -1 && i == y && o >= x) {
                *targetOffset = k + [joinedLines length];
            }
            [coords addObject:[Coord coordWithX:o
                                              y:i]];
        }
        [joinedLines appendString:string];
        free(deltas);
        free(backingStore);

        j++;
        if (i >= y && rejectAtHardEol && theLine[width].code == EOL_HARD) {
            [coords addObject:[Coord coordWithX:o
                                              y:i]];
            break;
        }
    }
    // TODO: What if it's multiple lines ending in a soft eol and the selection goes to the end?
    return joinedLines;
}

- (BOOL)smartSelectAtX:(int)x y:(int)y toStartX:(int*)X1 toStartY:(int*)Y1 toEndX:(int*)X2 toEndY:(int*)Y2
{
    NSString* textWindow;
    int targetOffset;
    const int numLines = 2;
    const int width = [dataSource width];
    NSMutableArray* coords = [NSMutableArray arrayWithCapacity:numLines * width];
    textWindow = [self _getTextInWindowAroundX:x
                                             y:y
                                      numLines:2
                                  targetOffset:&targetOffset
                                        coords:coords];

    const double LOW_PRECISION = 0.001;
    const double NORMAL_PRECISION = 1.0;
    const double HIGH_PRECISION = 1000.0;
    const double VERY_HIGH_PRECISION = 1000000.0;

    typedef struct {
        NSString* regex;
        double precision;
    } SmartMatchRule;
    static SmartMatchRule* rules = nil;
    static int numRules = 0;
    if (!rules) {
        NSString* plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"SmartSelectionRules"
                                                                               ofType:@"plist"];
        NSDictionary* rulesDict = [NSDictionary dictionaryWithContentsOfFile:plistFile];
        NSArray* rulesArray = [rulesDict objectForKey:@"Rules"];
        rules = malloc(sizeof(SmartMatchRule) * [rulesArray count]);
        int i = 0;
        for (NSDictionary* dict in rulesArray) {
            rules[i].regex = [[dict objectForKey:@"regex"] retain];
            NSString* precision = [dict objectForKey:@"precision"];
            if ([precision isEqualToString:@"low"]) {
                rules[i].precision = LOW_PRECISION;
            } else if ([precision isEqualToString:@"normal"]) {
                rules[i].precision = NORMAL_PRECISION;
            } else if ([precision isEqualToString:@"high"]) {
                rules[i].precision = HIGH_PRECISION;
            } else if ([precision isEqualToString:@"very_high"]) {
                rules[i].precision = VERY_HIGH_PRECISION;
            }
            i++;
        }
        numRules = [rulesArray count];
        //NSLog(@"Loaded %d smart selection rules", numRules);
    }

    NSMutableDictionary* matches = [NSMutableDictionary dictionaryWithCapacity:13];
    int numCoords = [coords count];

    //NSLog(@"Searching for %@", textWindow);
    for (int j = 0; j < numRules; j++) {
        //NSLog(@"Try regex %@", rules[j].regex);
        for (int i = 0; i <= targetOffset; i++) {
            NSString* substring = [textWindow substringWithRange:NSMakeRange(i, [textWindow length] - i)];
            NSError* regexError = nil;
            NSRange temp = [substring rangeOfRegex:rules[j].regex
                                           options:0
                                           inRange:NSMakeRange(0, [substring length])
                                           capture:0
                                             error:&regexError];
            if (temp.location != NSNotFound) {
                if (i + temp.location <= targetOffset && i + temp.location + temp.length > targetOffset) {
                    NSString* result = [substring substringWithRange:temp];
                    double score = rules[j].precision * (double) temp.length;
                    SmartMatch* oldMatch = [matches objectForKey:result];
                    if (!oldMatch || score > oldMatch->score) {
                        SmartMatch* match = [[[SmartMatch alloc] init] autorelease];
                        match->score = score;
                        Coord* startCoord = [coords objectAtIndex:i + temp.location];
                        Coord* endCoord = [coords objectAtIndex:MIN(numCoords - 1, i + temp.location + temp.length)];
                        match->startX = startCoord->x;
                        match->absStartY = startCoord->y + [dataSource totalScrollbackOverflow];
                        match->endX = endCoord->x;
                        match->absEndY = endCoord->y + [dataSource totalScrollbackOverflow];
                        [matches setObject:match forKey:result];

                        //NSLog(@"Add result %@ at %d,%lld -> %d,%lld with score %lf", result, match->startX, match->absStartY, match->endX, match->absEndY, match->score);
                    }
                    i += temp.location + temp.length - 1;
                } else {
                    i += temp.location;
                }
            } else {
                break;
            }
        }
    }

    if ([matches count]) {
        NSArray* sortedMatches = [[[matches allValues] sortedArrayUsingSelector:@selector(compare:)] retain];
        SmartMatch* bestMatch = [sortedMatches lastObject];
        *X1 = bestMatch->startX;
        *Y1 = bestMatch->absStartY - [dataSource totalScrollbackOverflow];
        *X2 = bestMatch->endX;
        *Y2 = bestMatch->absEndY - [dataSource totalScrollbackOverflow];
        return YES;
    } else {
        // Fall back on word selection
        [self getWordForX:x
                        y:y
                   startX:X1
                   startY:Y1
                     endX:X2
                     endY:Y2];
        return NO;
    }
}

- (BOOL)smartSelectAtX:(int)x y:(int)y
{
    return [self smartSelectAtX:x y:y toStartX:&startX toStartY:&startY toEndX:&endX toEndY:&endY];
}


- (void)keyDown:(NSEvent*)event
{
    DebugLog(@"PTYTextView keyDown");
    id delegate = [self delegate];
    if ([[[[[self dataSource] session] tab] realParentWindow] inInstantReplay]) {
        // Delegate has special handling for this case.
        [delegate keyDown:event];
        return;
    }
    unsigned int modflag = [event modifierFlags];
    unsigned short keyCode = [event keyCode];
    BOOL prev = [self hasMarkedText];

    keyIsARepeat = [event isARepeat];

    // Hide the cursor
    [NSCursor setHiddenUntilMouseMoves:YES];

    // Should we process the event immediately in the delegate?
    if ((!prev) &&
        ([delegate hasActionableKeyMappingForEvent:event] ||       // delegate will do something useful
         (modflag & (NSNumericPadKeyMask | NSFunctionKeyMask)) ||  // is an arrow key, f key, etc.
         ([[event charactersIgnoringModifiers] length] > 0 &&      // Will send Meta/Esc+ (length is 0 if it's a dedicated dead key)
          (((modflag & NSLeftAlternateKeyMask) == NSLeftAlternateKeyMask && [delegate optionKey] != OPT_NORMAL) ||
           ((modflag & NSRightAlternateKeyMask) == NSRightAlternateKeyMask && [delegate rightOptionKey] != OPT_NORMAL))) ||
         ((modflag & NSControlKeyMask) &&                          // a few special cases
          (keyCode == 0x2c /* slash */ || keyCode == 0x2a /* backslash */)))) {
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

- (BOOL)keyIsARepeat
{
    return (keyIsARepeat);
}

// TODO: disable other, righxt mouse for inactive panes
- (void)otherMouseDown: (NSEvent *) event
{
    NSPoint locationInWindow, locationInTextView;
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    if (([[self delegate] xtermMouseReporting])
        && (locationInTextView.y > visibleRect.origin.y)
        && !([event modifierFlags] & NSAlternateKeyMask)) {
        // Mouse reporting is on
        int rx, ry;
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

        int bnum = [event buttonNumber];
        if (bnum == 2) {
            bnum = 1;
        }

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_NORMAL:
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                reportingMouseDown = YES;
                [session writeTask:[terminal mousePress:bnum
                                          withModifiers:[event modifierFlags]
                                                    atX:rx
                                                      Y:ry]];
                return;
                break;

            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }

    if ([[PreferencePanel sharedInstance] pasteFromClipboard]) {
        [self paste: nil];
    } else {
        [self pasteSelection: nil];
    }
}

- (void)otherMouseUp:(NSEvent *)event
{
    NSPoint locationInWindow, locationInTextView;
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    if (([[self delegate] xtermMouseReporting]) &&
        reportingMouseDown &&
        !([event modifierFlags] & NSAlternateKeyMask)) {
        reportingMouseDown = NO;
        int rx, ry;
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
                [session writeTask:[terminal mouseReleaseWithModifiers:[event modifierFlags]
                                                                   atX:rx
                                                                     Y:ry]];
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
    if (([[self delegate] xtermMouseReporting]) &&
        (locationInTextView.y > visibleRect.origin.y) &&
        reportingMouseDown &&
        !([event modifierFlags] & NSAlternateKeyMask)) {
        // Mouse reporting is on.
        int rx, ry;
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

        int bnum = [event buttonNumber];
        if (bnum == 2) {
            bnum = 1;
        }

        switch ([terminal mouseMode]) {
            case MOUSE_REPORTING_NORMAL:
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                [session writeTask:[terminal mouseMotion:bnum
                                           withModifiers:[event modifierFlags]
                                                     atX:rx
                                                       Y:ry]];
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

- (void)rightMouseDown:(NSEvent*)event
{
    NSPoint locationInWindow, locationInTextView;
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

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
                [session writeTask:[terminal mousePress:2
                                          withModifiers:[event modifierFlags]
                                                    atX:rx
                                                      Y:ry]];
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
    if (([[self delegate] xtermMouseReporting]) &&
        reportingMouseDown &&
        !([event modifierFlags] & NSAlternateKeyMask)) {
        // Mouse reporting is on
        reportingMouseDown = NO;
        int rx, ry;
        rx = (locationInTextView.x-MARGIN - visibleRect.origin.x)/charWidth;
        ry = (locationInTextView.y - visibleRect.origin.y)/lineHeight;
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
                [session writeTask:[terminal mouseReleaseWithModifiers:[event modifierFlags]
                                                                   atX:rx
                                                                     Y:ry]];
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
    if (([[self delegate] xtermMouseReporting]) &&
        (locationInTextView.y > visibleRect.origin.y) &&
        reportingMouseDown &&
        !([event modifierFlags] & NSAlternateKeyMask)) {
        // Mouse reporting is on.
        int rx, ry;
        rx = (locationInTextView.x -MARGIN - visibleRect.origin.x) / charWidth;
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
                [session writeTask:[terminal mouseMotion:2
                                           withModifiers:[event modifierFlags]
                                                     atX:rx
                                                       Y:ry]];
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
    NSPoint locationInWindow, locationInTextView;
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    if (([[self delegate] xtermMouseReporting]) &&
        (locationInTextView.y > visibleRect.origin.y) &&
        !([event modifierFlags] & NSAlternateKeyMask)) {
        // Mouse reporting is on.
        int rx, ry;
        rx = (locationInTextView.x-MARGIN - visibleRect.origin.x) / charWidth;
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
                if ([event deltaY] != 0) {
                    [session writeTask:[terminal mousePress:([event deltaY] > 0 ? 4:5)
                                              withModifiers:[event modifierFlags]
                                                        atX:rx
                                                          Y:ry]];
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
    // no-op
}

- (void)mouseEntered:(NSEvent *)event
{
    if ([[PreferencePanel sharedInstance] focusFollowsMouse] &&
            [[self window] alphaValue] > 0) {
        // Some windows automatically close when they lose key status and are
        // incompatible with FFM. Check if the key window or its controller implements
        // disableFocusFollowsMouse and if it returns YES do nothing.
        id obj = nil;
        if ([[NSApp keyWindow] respondsToSelector:@selector(disableFocusFollowsMouse)]) {
            obj = [NSApp keyWindow];
        } else if ([[[NSApp keyWindow] windowController] respondsToSelector:@selector(disableFocusFollowsMouse)]) {
            obj = [[NSApp keyWindow] windowController];
        }
        if (![obj disableFocusFollowsMouse]) {
            [[self window] makeKeyWindow];
        }
        if ([[self window] isKeyWindow]) {
            [[[dataSource session] tab] setActiveSession:[dataSource session]];
        }
    }
}

- (void)mouseDown:(NSEvent *)event
{
    if ([self mouseDownImpl:event]) {
        [super mouseDown:event];
    }
}

// Returns yes if [super mouseDown:event] should be run by caller.
- (BOOL)mouseDownImpl:(NSEvent*)event
{
    const BOOL altPressed = ([event modifierFlags] & NSAlternateKeyMask) != 0;
    const BOOL cmdPressed = ([event modifierFlags] & NSCommandKeyMask) != 0;
    const BOOL shiftPressed = ([event modifierFlags] & NSShiftKeyMask) != 0;

    dragOk_ = YES;
    PTYTextView* frontTextView = [[iTermController sharedInstance] frontTextView];
    if (!cmdPressed &&
        frontTextView &&
        [[frontTextView->dataSource session] tab] != [[dataSource session] tab]) {
        // Mouse clicks in inactive tab are always handled by superclass because we don't want clicks
        // to select a split pane to be xterm-mouse-reported. We do allow cmd-clicks to go through
        // incase you're clicking on a URL.
        return YES;
    }

    NSPoint locationInWindow, locationInTextView;
    int x, y;
    int width = [dataSource width];

    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];

    x = (locationInTextView.x - MARGIN + charWidth/2)/charWidth;
    if (x < 0) {
        x = 0;
    }
    y = locationInTextView.y / lineHeight;

    if (x >= width) {
        x = width  - 1;
    }

    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    
    if ([event eventNumber] != firstMouseEventNumber_ &&   // Not first mouse in formerly non-key app
        frontTextView == self &&                           // Is active session's textview
        ([[self delegate] xtermMouseReporting]) &&         // Xterm mouse reporting is on
        (locationInTextView.y > visibleRect.origin.y) &&   // Not inside the top margin
        !([event modifierFlags] & NSAlternateKeyMask)) {   // Not holding Opt to disable mouse reporting
        // Mouse reporting is on.
        int rx, ry;
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
                reportingMouseDown = YES;
                [session writeTask:[terminal mousePress:0
                                          withModifiers:[event modifierFlags]
                                                    atX:rx
                                                      Y:ry]];
                return NO;
                break;

            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }

    // Lock auto scrolling while the user is selecting text
    [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];

    if (mouseDownEvent != nil) {
        [mouseDownEvent release];
        mouseDownEvent = nil;
    }
    [event retain];
    mouseDownEvent = event;
    mouseDragged = NO;
    mouseDown = YES;
    mouseDownOnSelection = NO;

    int clickCount = [event clickCount];
    if (clickCount < 2) {
        // single click
        if (altPressed && cmdPressed) {
            selectMode = SELECT_BOX;
        } else {
            selectMode = SELECT_CHAR;
        }

        if (startX > -1 && shiftPressed) {
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
            return YES;
        } else if (!cmdPressed || altPressed) {
            // start a new selection
            endX = startX = x;
            endY = startY = y;
        }
    } else if (clickCount == 2) {
        int tmpX1, tmpY1, tmpX2, tmpY2;

        // double-click; select word
        selectMode = SELECT_WORD;
        NSString *selectedWord = [self getWordForX:x
                                                 y:y
                                            startX:&tmpX1
                                            startY:&tmpY1
                                              endX:&tmpX2
                                              endY:&tmpY2];
        if ([self _findMatchingParenthesis:selectedWord withX:tmpX1 Y:tmpY1]) {
            // Found a matching paren
            ;
        } else if (startX > -1 && shiftPressed) {
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
    } else if (clickCount == 3) {
        // triple-click; select line
        selectMode = SELECT_LINE;
        if (startX > -1 && shiftPressed) {
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
    } else if (clickCount == 4) {
        // quad-click: smart selection
        // ignore status of shift key for smart selection because extending was messed up by
        // triple click.
        selectMode = SELECT_SMART;
        if ([self smartSelectAtX:x y:y]) {
            int tmpX1, tmpY1, tmpX2, tmpY2;
            [self getWordForX:x
                            y:y
                       startX:&tmpX1
                       startY:&tmpY1
                         endX:&tmpX2
                         endY:&tmpY2];
        }
    }

    DebugLog([NSString stringWithFormat:@"Mouse down. startx=%d starty=%d, endx=%d, endy=%d", startX, startY, endX, endY]);
    if([_delegate respondsToSelector: @selector(willHandleEvent:)] && [_delegate willHandleEvent: event])
        [_delegate handleEvent: event];
    [[[self dataSource] session] refreshAndStartTimerIfNeeded];

    return NO;
}

static double Square(double n) {
    return n * n;
}

static double EuclideanDistance(NSPoint p1, NSPoint p2) {
    return sqrt(Square(p1.x - p2.x) + Square(p1.y - p2.y));
}

- (void)mouseUp:(NSEvent *)event
{
    dragOk_ = NO;
    PTYTextView* frontTextView = [[iTermController sharedInstance] frontTextView];
    const BOOL cmdPressed = ([event modifierFlags] & NSCommandKeyMask) != 0;
    if (!cmdPressed &&
        frontTextView &&
        [[frontTextView->dataSource session] tab] != [[dataSource session] tab]) {
        // Mouse clicks in inactive tab are always handled by superclass but make it first responder.
        [[self window] makeFirstResponder: self];
        [super mouseUp:event];
        return;
    }

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
    selectionScrollDirection = 0;
    y = locationInTextView.y / lineHeight;

    // Send mouse up event to host if xterm mouse reporting is on
    if (frontTextView == self &&
        [[self delegate] xtermMouseReporting] &&
        reportingMouseDown &&
        !([event modifierFlags] & NSAlternateKeyMask)) {
        // Mouse reporting is on.
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
                [session writeTask:[terminal mouseReleaseWithModifiers:[event modifierFlags]
                                                                   atX:rx
                                                                     Y:ry]];
                return;
                break;

            case MOUSE_REPORTING_NONE:
            case MOUSE_REPORTING_HILITE:
                // fall through
                break;
        }
    }

    // Unlock auto scrolling as the user as finished selecting text
    if (([self visibleRect].origin.y + [self visibleRect].size.height - [self excess]) / lineHeight == [dataSource numberOfLines]) {
        [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:NO];
    }

    if (mouseDown == NO) {
        DebugLog([NSString stringWithFormat:@"Mouse up. startx=%d starty=%d, endx=%d, endy=%d", startX, startY, endX, endY]);
        return;
    }
    mouseDown = NO;

    // make sure we have key focus
    [[self window] makeFirstResponder:self];

    if (startY > endY ||
        (startY == endY && startX > endX)) {
        // Make sure the start is before the end.
        int t;
        t = startY; startY = endY; endY = t;
        t = startX; startX = endX; endX = t;
    } else if ([event clickCount] < 2 &&
               !mouseDragged &&
               !([event modifierFlags] & NSShiftKeyMask)) {
        // Just a click in the window.
        startX=-1;
        if (cmdPressed &&
            [[PreferencePanel sharedInstance] cmdSelection]) {
            // Command click in place.
            NSString *url = [self _getURLForX:x y:y];

            if (url && ([event modifierFlags] & NSShiftKeyMask)) {
                // Cmd-shift click executes an alternate semantic history action.
                NSString *fullPath = [trouter getFullPath:url
                                         workingDirectory:[self getWorkingDirectoryAtLine:y + 1]
                                               lineNumber:nil];
                if ([trouter isDirectory:fullPath]) {
                    [self _changeDirectory:fullPath];
                }
            } else {
                [self _openURL:url atLine:y + 1];
            }
        } else {
            lastFindStartX = endX;
            lastFindEndX = endX+1;
            absLastFindStartY = endY + [dataSource totalScrollbackOverflow];
            absLastFindEndY = absLastFindStartY+1;
        }
    }

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

    [[[self dataSource] session] refreshAndStartTimerIfNeeded];
}

- (void)mouseDragged:(NSEvent *)event
{
    if ([event eventNumber] == firstMouseEventNumber_) {
        // We accept first mouse for the purposes of focusing a split pane but not for making a
        // selection.
        return;
    }
    if (!dragOk_) {
        return;
    }
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint locationInTextView = [self convertPoint: locationInWindow fromView: nil];
    NSRect  rectInTextView = [self visibleRect];
    int x, y;
    int width = [dataSource width];
    NSString *theSelectedText;

    double logicalX = locationInTextView.x - MARGIN - charWidth/2;
    if (logicalX >= 0) {
        x = logicalX / charWidth;
    } else {
        x = -1;
    }
    if (x < -1) {
        x = -1;
    }
    if (x >= width) {
        x = width - 1;
    }

    y = locationInTextView.y / lineHeight;

    NSPoint mouseDownLocation = [mouseDownEvent locationInWindow];

    if (([[self delegate] xtermMouseReporting]) &&
        reportingMouseDown &&
        !([event modifierFlags] & NSAlternateKeyMask)) {
        // Mouse reporting is on.
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
            case MOUSE_REPORTING_BUTTON_MOTION:
            case MOUSE_REPORTING_ALL_MOTION:
                [session writeTask:[terminal mouseMotion:0
                                           withModifiers:[event modifierFlags]
                                                     atX:rx
                                                       Y:ry]];
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

    // Prevent accidental dragging while holding cmd.
    BOOL dragThresholdMet = NO;
    if (EuclideanDistance(mouseDownLocation, locationInWindow) >= kDragThreshold) {
        dragThresholdMet = YES;
    }
    BOOL pressingCmdOnly = ([event modifierFlags] & (NSAlternateKeyMask | NSCommandKeyMask)) == NSCommandKeyMask;
    if (!pressingCmdOnly || dragThresholdMet) {
      mouseDragged = YES;
    }


    if (mouseDownOnSelection == YES &&
        ([event modifierFlags] & NSCommandKeyMask) &&
        dragThresholdMet) {
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

    if (pressingCmdOnly && !dragThresholdMet) {
        // If you're holding cmd (but not opt) then you're either trying to click on a link and
        // accidentally dragged a little bit, or you're trying to drag a selection. Do nothing until
        // the threshold is met.
        return;
    }
    if (mouseDownOnSelection == YES &&
        ([event modifierFlags] & (NSAlternateKeyMask | NSCommandKeyMask)) == (NSAlternateKeyMask | NSCommandKeyMask) &&
        !dragThresholdMet) {
        // Would be a drag of a rect region but mouse hasn't moved far enough yet. Prevent the
        // selection from changing.
        return;
    }

    if (startX < 0 && pressingCmdOnly) {
        // Drag a file handle (only possible when there is no selection).
        NSString *path = [self _getURLForX:x y:y];
        path = [trouter getFullPath:path
                   workingDirectory:[self getWorkingDirectoryAtLine:y + 1]
                         lineNumber:nil];
        if (path == nil) {
            return;
        }

        NSPoint dragPosition;
        NSImage *dragImage;

        NSArray *fileList = [NSArray arrayWithObject: path];
        NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
        [pboard declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
        [pboard setPropertyList:fileList forType:NSFilenamesPboardType];

        dragImage = [[NSWorkspace sharedWorkspace] iconForFile:path];
        dragPosition = [self convertPoint:[event locationInWindow] fromView:nil];
        dragPosition.x -= [dragImage size].width / 2;

        [self dragImage:dragImage
                     at:dragPosition
                 offset:NSZeroSize
                  event:event
             pasteboard:pboard
                 source:self
              slideBack:YES];
        return;

    }

    int prevScrolling = selectionScrollDirection;
    if (locationInTextView.y <= rectInTextView.origin.y) {
        selectionScrollDirection = -1;
        scrollingX = x;
        scrollingY = y;
        scrollingLocation = locationInTextView;
    } else if (locationInTextView.y >= rectInTextView.origin.y + rectInTextView.size.height) {
        selectionScrollDirection = 1;
        scrollingX = x;
        scrollingY = y;
        scrollingLocation = locationInTextView;
    } else {
        selectionScrollDirection = 0;
    }
    if (selectionScrollDirection && !prevScrolling) {
        [self scheduleSelectionScroll];
    }

    [self moveSelectionEndpointToX:x Y:y locationInTextView:locationInTextView];
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
    int width = [dataSource width];
    const int estimatedSize = (endy - starty + 1) * (width + 1) + (endx - startx + 1);
    NSMutableString* result = [NSMutableString stringWithCapacity:estimatedSize];
    int y, x1, x2;
    screen_char_t *theLine;
    BOOL endOfLine;
    int i;

    for (y = starty; y <= endy; y++) {
        theLine = [dataSource getLineAtIndex:y];

        x1 = y == starty ? startx : 0;
        x2 = y == endy ? endx : width-1;
        for ( ; x1 <= x2; x1++) {
            if (theLine[x1].code == TAB_FILLER) {
                // Convert orphan tab fillers (those without a subsequent
                // tab character) into spaces.
                if ([self isTabFillerOrphanAtX:x1 Y:y]) {
                    [result appendString:@" "];
                }
            } else if (theLine[x1].code != DWC_RIGHT &&
                       theLine[x1].code != DWC_SKIP) {
                if (theLine[x1].code == 0) { // end of line?
                    // If there is no text after this, insert a hard line break.
                    endOfLine = YES;
                    for (i = x1 + 1; i <= x2 && endOfLine; i++) {
                        if (theLine[i].code != 0) {
                            endOfLine = NO;
                        }
                    }
                    if (endOfLine) {
                        if (pad) {
                            for (i = x1; i <= x2; i++) {
                                [result appendString:@" "];
                            }
                        }
                        if (y < endy && theLine[width].code == EOL_HARD) {
                            [result appendString:@"\n"];
                        }
                        break;
                    } else {
                        [result appendString:@" "]; // represent end-of-line blank with space
                    }
                } else if (x1 == x2 &&
                           y < endy &&
                           theLine[width].code == EOL_HARD) {
                    // Hard line break
                    [result appendString:ScreenCharToStr(&theLine[x1])];
                    [result appendString:@"\n"];  // hard break
                } else {
                    // Normal character
                    [result appendString:ScreenCharToStr(&theLine[x1])];
                }
            }
        }
    }

    return result;
}

- (IBAction)selectAll:(id)sender
{
    // set the selection region for the whole text
    startX = startY = 0;
    endX = [dataSource width];
    endY = [dataSource numberOfLines] - 1;
    [[[self dataSource] session] refreshAndStartTimerIfNeeded];
}

- (void)deselect
{
    if (startX > -1) {
        startX = -1;
        [[[self dataSource] session] refreshAndStartTimerIfNeeded];
    }
}

- (NSString *)selectedText
{
    return [self selectedTextWithPad:NO];
}

- (NSString *)selectedTextWithPad:(BOOL)pad
{
    if (startX <= -1) {
        return nil;
    }
    if (selectMode == SELECT_BOX) {
        return [self contentInBoxFromX:startX
                                     Y:startY
                                   ToX:endX
                                     Y:endY
                                   pad:pad];
    } else {
        return ([self contentFromX:startX
                                 Y:startY
                               ToX:endX
                                 Y:endY
                               pad:pad]);
    }
}

- (NSString *)content
{
    return [self contentFromX:0
                            Y:0
                          ToX:[dataSource width]
                            Y:[dataSource numberOfLines] - 1
                          pad:NO];
}

- (void)splitTextViewVertically:(id)sender
{
    [[[[dataSource session] tab] realParentWindow] splitVertically:YES
                                                      withBookmark:[[BookmarkModel sharedInstance] defaultBookmark]
                                                     targetSession:[dataSource session]];
}

- (void)splitTextViewHorizontally:(id)sender
{
    [[[[dataSource session] tab] realParentWindow] splitVertically:NO
                                                      withBookmark:[[BookmarkModel sharedInstance] defaultBookmark]
                                                     targetSession:[dataSource session]];
}

- (void)clearWorkingDirectories {
    [workingDirectoryAtLines removeAllObjects];
}

- (void)clearTextViewBuffer:(id)sender
{
    [[dataSource session] clearBuffer];
}

- (void)editTextViewSession:(id)sender
{
    [[[[dataSource session] tab] realParentWindow] editSession:[dataSource session]];
}

- (void)closeTextViewSession:(id)sender
{
    [[[[dataSource session] tab] realParentWindow] closeSessionWithConfirmation:[dataSource session]];
}

- (void)copy:(id)sender
{
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    NSString *copyString;

    copyString = [self selectedText];

    if (copyString) {
        [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
        [pboard setString:copyString forType:NSStringPboardType];
    }

    [[PasteboardHistory sharedInstance] save:copyString];
}

- (void)paste:(id)sender
{
    NSString* info = [PTYSession pasteboardString];
    if (info) {
        [[PasteboardHistory sharedInstance] save:info];
    }

    if ([_delegate respondsToSelector:@selector(paste:)]) {
        [_delegate paste:sender];
    }
}

- (void)pasteSelection:(id)sender
{
    if (startX > -1 && [_delegate respondsToSelector:@selector(pasteString:)]) {
        [_delegate pasteString:[self selectedText]];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(paste:)) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        // Check if there is a string type on the pasteboard
        return ([pboard stringForType:NSStringPboardType] != nil);
    }
    if ([item action ] == @selector(cut:)) {
        // Never allow cut.
        return NO;
    }
    if ([item action]==@selector(saveDocumentAs:)) {
        return [self isAnyCharSelected];
    } else if ([item action] == @selector(selectAll:) ||
               [item action]==@selector(splitTextViewVertically:) ||
               [item action]==@selector(splitTextViewHorizontally:) ||
               [item action]==@selector(clearTextViewBuffer:) ||
               [item action]==@selector(editTextViewSession:) ||
               [item action]==@selector(closeTextViewSession:) ||
               ([item action] == @selector(print:) && [item tag] != 1)) {
        // We always validate the above commands
        return YES;
    }
    if ([item action]==@selector(mail:) ||
        [item action]==@selector(browse:) ||
        [item action]==@selector(searchInBrowser:) ||
        [item action]==@selector(copy:) ||
        [item action]==@selector(pasteSelection:) ||
        ([item action]==@selector(print:) && [item tag] == 1)) { // print selection
        // These commands are allowed only if there is a selection.
        return startX > -1;
    }

    return NO;
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    PTYTextView* frontTextView = [[iTermController sharedInstance] frontTextView];
    NSRect visibleRect = [[self enclosingScrollView] documentVisibleRect];
    NSPoint locationInWindow = [theEvent locationInWindow];
    NSPoint locationInTextView = [self convertPoint:locationInWindow fromView:nil];
    VT100Terminal *terminal = [dataSource terminal];
    MouseMode mm = [terminal mouseMode];
    if (frontTextView == self &&
        ([[self delegate] xtermMouseReporting]) &&
        (mm == MOUSE_REPORTING_NORMAL ||
         mm == MOUSE_REPORTING_BUTTON_MOTION ||
         mm == MOUSE_REPORTING_ALL_MOTION) &&
        (locationInTextView.y > visibleRect.origin.y) &&
        !([theEvent modifierFlags] & NSAlternateKeyMask) &&
        [[frontTextView->dataSource session] tab] == [[dataSource session] tab] &&
        [theEvent type] == NSLeftMouseDown &&
        ([theEvent modifierFlags] & NSControlKeyMask) &&
        [[PreferencePanel sharedInstance] passOnControlLeftClick]) {
        // All the many conditions are met for having the click passed on via xterm mouse reporting.
        return nil;
    }
    NSMenu *theMenu;

    // Allocate a menu
    theMenu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];

    // Menu items for acting on text selections
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Open Selection as URL",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(browse:) keyEquivalent:@""];
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Search Google for Selection",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(searchInBrowser:) keyEquivalent:@""];
    [theMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Send Email to Selected Address",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(mail:) keyEquivalent:@""];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Split pane options
    [theMenu addItemWithTitle:@"Split Pane Vertically" action:@selector(splitTextViewVertically:) keyEquivalent:@""];
    [theMenu addItemWithTitle:@"Split Pane Horizontally" action:@selector(splitTextViewHorizontally:) keyEquivalent:@""];

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

    // Clear buffer
    [theMenu addItemWithTitle:@"Clear Buffer"
                       action:@selector(clearTextViewBuffer:)
                keyEquivalent:@""];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Edit Session
    [theMenu addItemWithTitle:@"Edit Session..."
                       action:@selector(editTextViewSession:)
                keyEquivalent:@""];

    // Separator
    [theMenu addItem:[NSMenuItem separatorItem]];

    // Close current pane
    [theMenu addItemWithTitle:@"Close"
                       action:@selector(closeTextViewSession:)
                keyEquivalent:@""];

    // Ask the delegae if there is anything to be added
    if ([[self delegate] respondsToSelector:@selector(menuForEvent: menu:)])
        [[self delegate] menuForEvent:theEvent menu: theMenu];

    return [theMenu autorelease];
}

- (void)mail:(id)sender
{
    NSString* mailto;

    if ([[self selectedText] hasPrefix:@"mailto:"]) {
        mailto = [NSString stringWithString:[self selectedText]];
    } else {
        mailto = [NSString stringWithFormat:@"mailto:%@", [self selectedText]];
    }

    NSString* escapedString = (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                                  (CFStringRef)mailto,
                                                                                  (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                                                                  NULL,
                                                                                  kCFStringEncodingUTF8 );

    NSURL* url = [NSURL URLWithString:escapedString];
    [escapedString release];

    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)browse:(id)sender
{
    [self _openURL: [self selectedText]];
}

- (void)searchInBrowser:(id)sender
{
    NSString* url = [NSString stringWithFormat:[[PreferencePanel sharedInstance] searchCommand],
                              [[self selectedText] stringWithPercentEscape]];
    [self _openURL:url];
}

//
// Drag and Drop methods for our text view
//

//
// Called when our drop area is entered
//
- (unsigned int)draggingEntered:(id <NSDraggingInfo>)sender
{
    extendedDragNDrop = YES;

    // Always say YES; handle failure later.
    return YES;
}

//
// Called when the dragged object is moved within our drop area
//
- (unsigned int)draggingUpdated:(id <NSDraggingInfo>)sender
{
    unsigned int iResult;

    // Let's see if our parent NSTextView knows what to do
    iResult = [super draggingUpdated:sender];

    // If parent class does not know how to deal with this drag type, check if we do.
    if (iResult == NSDragOperationNone) {  // Parent NSTextView does not support this drag type.
        return [self _checkForSupportedDragTypes:sender];
    }

    return iResult;
}

//
// Called when the dragged object leaves our drop area
//
- (void)draggingExited:(id <NSDraggingInfo>)sender
{
    // We don't do anything special, so let the parent NSTextView handle this.
    [super draggingExited:sender];

    // Reset our handler flag
    extendedDragNDrop = NO;
}

//
// Called when the dragged item is about to be released in our drop area.
//
- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
    BOOL result;

    // Check if parent NSTextView knows how to handle this.
    result = [super prepareForDragOperation: sender];

    // If parent class does not know how to deal with this drag type, check if we do.
    if (result != YES &&
        [self _checkForSupportedDragTypes:sender] != NSDragOperationNone) {
        result = YES;
    }

    return result;
}

//
// Called when the dragged item is released in our drop area.
//
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    unsigned int dragOperation;
    PTYSession *delegate = [self delegate];
    
    // If parent class does not know how to deal with this drag type, check if we do.
    if (extendedDragNDrop) {
        NSPasteboard *pb = [sender draggingPasteboard];
        NSArray *propertyList;
        NSString *aString;
        int i;
        
        dragOperation = [self _checkForSupportedDragTypes: sender];
        
        if (dragOperation == NSDragOperationCopy) {
            // Check for simple strings first
            aString = [pb stringForType:NSStringPboardType];
            if (aString != nil) {
                if ([delegate respondsToSelector:@selector(pasteString:)]) {
                    [delegate pasteString: aString];
                }
            }
            
            // Check for file names
            propertyList = [pb propertyListForType: NSFilenamesPboardType];
            for (i = 0; i < (int)[propertyList count]; i++) {
                // Ignore text clippings
                NSString *filename = (NSString*)[propertyList objectAtIndex:i];  // this contains the POSIX path to a file
                NSDictionary *filenamesAttributes = [[NSFileManager defaultManager] fileAttributesAtPath:filename
                                                                                            traverseLink:YES];
                if (([filenamesAttributes fileHFSTypeCode] == 'clpt' &&
                     [filenamesAttributes fileHFSCreatorCode] == 'MACS') ||
                    [[filename pathExtension] isEqualToString:@"textClipping"] == YES) {
                    continue;
                }
                
                // Just paste the file names into the shell after escaping special characters.
                if ([delegate respondsToSelector:@selector(pasteString:)]) {
                    NSMutableString *path;
                    
                    path = [[NSMutableString alloc] initWithString:(NSString*)[propertyList objectAtIndex:i]];
                    
                    // get rid of special characters
                    [delegate pasteString:[path stringWithEscapedShellCharacters]];
                    [delegate pasteString:@" "];
                    [path release];
                }
            }
            return YES;
        }
    }

    return NO;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
    // If we did no handle the drag'n'drop, ask our parent to clean up
    // I really wish the concludeDragOperation would have a useful exit value.
    if (!extendedDragNDrop) {
        [super concludeDragOperation:sender];
    }

    extendedDragNDrop = NO;
}

- (void)resetCursorRects
{
    [self addCursorRect:[self visibleRect] cursor:textViewCursor];
    [textViewCursor setOnMouseEntered:YES];
}

// Save method
- (void)saveDocumentAs:(id)sender
{
    NSData *aData;
    NSSavePanel *aSavePanel;
    NSString *aString;

    // We get our content of the textview or selection, if any
    aString = [self selectedText];
    if (!aString) {
        aString = [self content];
    }
    
    aData = [aString dataUsingEncoding:[[dataSource session] encoding]
                  allowLossyConversion:YES];

    // initialize a save panel
    aSavePanel = [NSSavePanel savePanel];
    [aSavePanel setAccessoryView:nil];
    [aSavePanel setRequiredFileType:@""];
    NSString *path = @"";
    NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                               NSUserDomainMask,
                                                               YES);
    if ([searchPaths count]) {
        path = [searchPaths objectAtIndex:0];
    }

    NSString* nowStr = [[NSDate date] descriptionWithCalendarFormat:@"Log at %Y-%m-%d %H.%M.%S.txt"
                                                           timeZone:nil
                                                             locale:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];

    if ([aSavePanel runModalForDirectory:path file:nowStr] == NSFileHandlingPanelOKButton) {
        if (![aData writeToFile:[aSavePanel filename] atomically:YES]) {
            NSBeep();
        }
    }
}

// Print
- (void)print:(id)sender
{
    NSRect visibleRect;
    int lineOffset, numLines;
    int type = sender ? [sender tag] : 0;

    switch (type) {
        case 0: // visible range
            visibleRect = [[self enclosingScrollView] documentVisibleRect];
            // Starting from which line?
            lineOffset = visibleRect.origin.y/lineHeight;
            // How many lines do we need to draw?
            numLines = visibleRect.size.height/lineHeight;
            [self printContent:[self contentFromX:0
                                                Y:lineOffset
                                              ToX:[dataSource width]
                                                Y:lineOffset + numLines - 1
                                       pad: NO]];
            break;
        case 1: // text selection
            [self printContent: [self selectedTextWithPad:NO]];
            break;
        case 2: // entire buffer
            [self printContent: [self content]];
            break;
    }
}

- (void)printContent:(NSString *)aString
{
    NSPrintInfo *aPrintInfo;

    aPrintInfo = [NSPrintInfo sharedPrintInfo];
    [aPrintInfo setHorizontalPagination: NSFitPagination];
    [aPrintInfo setVerticalPagination: NSAutoPagination];
    [aPrintInfo setVerticallyCentered: NO];

    // Create a temporary view with the contents, change to black on white, and
    // print it.
    NSTextView *tempView;
    NSMutableAttributedString *theContents;

    tempView = [[NSTextView alloc] initWithFrame:[[self enclosingScrollView] documentVisibleRect]];
    theContents = [[NSMutableAttributedString alloc] initWithString: aString];
    [theContents addAttributes: [NSDictionary dictionaryWithObjectsAndKeys:
        [NSColor textBackgroundColor], NSBackgroundColorAttributeName,
        [NSColor textColor], NSForegroundColorAttributeName,
        [NSFont userFixedPitchFontOfSize: 0], NSFontAttributeName, NULL]
                         range: NSMakeRange(0, [theContents length])];
    [[tempView textStorage] setAttributedString: theContents];
    [theContents release];

    // Now print the temporary view.
    [[NSPrintOperation printOperationWithView:tempView
                                    printInfo:aPrintInfo] runOperation];
    [tempView release];
}

/// NSTextInput stuff
- (void)doCommandBySelector:(SEL)aSelector
{
    //NSLog(@"doCommandBySelector:%@", NSStringFromSelector(aSelector));

#if GREED_KEYDOWN == 0
    id delegate = [self delegate];

    if ([delegate respondsToSelector:aSelector]) {
        [delegate performSelector:aSelector withObject:nil];
    }
#endif
}

- (void)insertText:(id)aString
{
    if ([self hasMarkedText]) {
        IM_INPUT_MARKEDRANGE = NSMakeRange(0, 0);
        [markedText release];
        markedText=nil;
        imeOffset = 0;
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

    // In case imeOffset changed, the frame height must adjust.
    [[[self dataSource] session] refreshAndStartTimerIfNeeded];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    firstMouseEventNumber_ = [theEvent eventNumber];
    return YES;
}

- (void)setMarkedText:(id)aString selectedRange:(NSRange)selRange
{
    [markedText release];
    if ([aString isKindOfClass:[NSAttributedString class]]) {
        markedText = [[NSAttributedString alloc] initWithString:[aString string]
                                                     attributes:[self markedTextAttributes]];
    } else {
        markedText = [[NSAttributedString alloc] initWithString:aString
                                                     attributes:[self markedTextAttributes]];
    }
    IM_INPUT_MARKEDRANGE = NSMakeRange(0,[markedText length]);
    IM_INPUT_SELRANGE = selRange;

    // Compute the proper imeOffset.
    int dirtStart;
    int dirtEnd;
    int dirtMax;
    imeOffset = 0;
    do {
        dirtStart = ([dataSource cursorY] - 1 - imeOffset) * [dataSource width] + [dataSource cursorX] - 1;
        dirtEnd = dirtStart + [self inputMethodEditorLength];
        dirtMax = [dataSource height] * [dataSource width];
        if (dirtEnd > dirtMax) {
            ++imeOffset;
        }
    } while (dirtEnd > dirtMax);

    if (![markedText length]) {
        // The call to refresh won't invalidate the IME rect because
        // there is no IME any more. If the user backspaced over the only
        // char in the IME buffer then this causes it be erased.
        [self invalidateInputMethodEditorRect];
    }
    [[[self dataSource] session] refreshAndStartTimerIfNeeded];
    [self scrollEnd];
}

- (void)unmarkText
{
    // As far as I can tell this is never called.
    IM_INPUT_MARKEDRANGE = NSMakeRange(0, 0);
    imeOffset = 0;
    [self invalidateInputMethodEditorRect];
    [[[self dataSource] session] refreshAndStartTimerIfNeeded];
    [self scrollEnd];
}

- (BOOL)hasMarkedText
{
    BOOL result;

    if (IM_INPUT_MARKEDRANGE.length > 0) {
        result = YES;
    } else {
        result = NO;
    }
    return result;
}

- (NSRange)markedRange
{
    if (IM_INPUT_MARKEDRANGE.length > 0) {
        return NSMakeRange([dataSource cursorX]-1, IM_INPUT_MARKEDRANGE.length);
    } else {
        return NSMakeRange([dataSource cursorX]-1, 0);
    }
}

- (NSRange)selectedRange
{
    return NSMakeRange(NSNotFound, 0);
}

- (NSArray *)validAttributesForMarkedText
{
    return [NSArray arrayWithObjects:NSForegroundColorAttributeName,
        NSBackgroundColorAttributeName,
        NSUnderlineStyleAttributeName,
        NSFontAttributeName,
        nil];
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)theRange
{
    return [markedText attributedSubstringFromRange:NSMakeRange(0,theRange.length)];
}

- (unsigned int)characterIndexForPoint:(NSPoint)thePoint
{
    return thePoint.x/charWidth;
}

- (long)conversationIdentifier
{
    return (long)self; //not sure about this
}

- (NSRect)firstRectForCharacterRange:(NSRange)theRange
{
    int y = [dataSource cursorY] - 1;
    int x = [dataSource cursorX] - 1;

    NSRect rect=NSMakeRect(x * charWidth + MARGIN,
                           (y + [dataSource numberOfLines] - [dataSource height] + 1) * lineHeight,
                           charWidth * theRange.length,
                           lineHeight);
    rect.origin=[[self window] convertBaseToScreen:[self convertPoint:rect.origin
                                                               toView:nil]];

    return rect;
}

- (BOOL)findInProgress
{
    return _findInProgress || searchingForNextResult_;
}

- (BOOL)growSelectionLeft
{
    if (startX == -1) {
        return NO;
    }
    int x = startX;
    int y = startY;
    --x;
    if (x < 0) {
        x = [dataSource width] - 1;
        --y;
        if (y < 0) {
            return NO;
        }
        // Stop at a hard eol
        screen_char_t* theLine = [dataSource getLineAtIndex:y];
        if (theLine[[dataSource width]].code == EOL_HARD) {
            return NO;
        }
    }

    int tmpX1;
    int tmpX2;
    int tmpY1;
    int tmpY2;

    [self getWordForX:x
                    y:y
               startX:&tmpX1
               startY:&tmpY1
                 endX:&tmpX2
                 endY:&tmpY2];

    startX = tmpX1;
    startY = tmpY1;
    [[[self dataSource] session] refreshAndStartTimerIfNeeded];
    return YES;
}

- (void)growSelectionRight
{
    if (startX == -1) {
        return;
    }
    int x = endX;
    int y = endY;
    ++x;
    if (x >= [dataSource width]) {
        // Stop at a hard eol
        screen_char_t* theLine = [dataSource getLineAtIndex:y];
        if (theLine[[dataSource width]].code == EOL_HARD) {
            return;
        }
        x = 0;
        ++y;
        if (y >= [dataSource numberOfLines]) {
            return;
        }
    }

    int tmpX1;
    int tmpX2;
    int tmpY1;
    int tmpY2;

    [self getWordForX:x
                    y:y
               startX:&tmpX1
               startY:&tmpY1
                 endX:&tmpX2
                 endY:&tmpY2];

    endX = tmpX2;
    endY = tmpY2;
    [[[self dataSource] session] refreshAndStartTimerIfNeeded];
}

// Add a match to resultMap_
- (void)_addResultFromX:(int)resStartX absY:(long long)absStartY toX:(int)resEndX toAbsY:(long long)absEndY
{
    int width = [dataSource width];
    for (long long y = absStartY; y <= absEndY; y++) {
        NSNumber* key = [NSNumber numberWithLongLong:y];
        NSMutableData* data = [resultMap_ objectForKey:key];
        BOOL set = NO;
        if (!data) {
            data = [NSMutableData dataWithLength:(width / 8 + 1)];
            char* b = [data mutableBytes];
            memset(b, 0, (width / 8) + 1);
            set = YES;
        }
        char* b = [data mutableBytes];
        for (int i = resStartX; i < MIN(resEndX+1, width); i++) {
            const int byteIndex = i/8;
            const int bit = 1 << (i & 7);
            if (byteIndex < [data length]) {
                b[byteIndex] |= bit;
            }
        }
        if (set) {
            [resultMap_ setObject:data forKey:key];
        }
    }
}

// Select the next highlighted result by searching findResults_ for a match just before/after the
// current selection.
- (BOOL)_selectNextResultForward:(BOOL)forward withOffset:(int)offset
{
    long long overflowAdustment = [dataSource totalScrollbackOverflow] - [dataSource scrollbackOverflow];
    long long width = [dataSource width];
    long long maxPos = -1;
    long long minPos = -1;
    int start;
    int stride;
    if (forward) {
        start = [findResults_ count] - 1;
        stride = -1;
        if (absLastFindStartY < 0) {
            minPos = -1;
        } else {
            minPos = lastFindStartX + (long long) absLastFindStartY * width + offset;
        }
    } else {
        start = 0;
        stride = 1;
        if (absLastFindStartY < 0) {
            maxPos = (1 + [dataSource numberOfLines] + overflowAdustment) * width;
        } else {
            maxPos = lastFindStartX + (long long) absLastFindStartY * width - offset;
        }
    }
    BOOL found = NO;
    BOOL redraw = NO;
    int i = start;
    for (int j = 0; j < [findResults_ count]; j++) {
        SearchResult* r = [findResults_ objectAtIndex:i];
        long long pos = r->startX + (long long)r->absStartY * width;
        if (!found &&
            ((maxPos >= 0 && pos <= maxPos) ||
             (minPos >= 0 && pos >= minPos))) {
                found = YES;
                redraw = YES;
                startX = r->startX;
                startY = r->absStartY - overflowAdustment;
                endX = r->endX;
                endY = r->absEndY - overflowAdustment;
        }
        i += stride;
    }

    if (!found && !foundResult_ && [findResults_ count] > 0) {
        // Wrap around
        SearchResult* r = [findResults_ objectAtIndex:start];
        found = YES;
        startX = r->startX;
        startY = r->absStartY - overflowAdustment;
        endX = r->endX;
        endY = r->absEndY - overflowAdustment;
        if (forward) {
            [self beginFlash:FlashWrapToTop];
        } else {
            [self beginFlash:FlashWrapToBottom];
        }
    }

    if (found) {
        // Lock scrolling after finding text
        ++endX; // make it half-open
        [(PTYScroller*)([[self enclosingScrollView] verticalScroller]) setUserScroll:YES];

        [self _scrollToCenterLine:endY];
        [self setNeedsDisplay:YES];
        lastFindStartX = startX;
        lastFindEndX = endX;
        absLastFindStartY = (long long)startY + overflowAdustment;
        absLastFindEndY = (long long)endY + overflowAdustment;
        foundResult_ = YES;
    }

    if (!_findInProgress && !foundResult_) {
        // Clear the selection.
        startX = startY = endX = endY = -1;
        absLastFindStartY = absLastFindEndY = -1;
        redraw = YES;
    }

    if (redraw) {
        [self setNeedsDisplay:YES];
    }

    return found;
}

// continueFind is called by a timer in the client until it returns NO. It does
// two things:
// 1. If _findInProgress is true, search for more results in the dataSource and
//   call _addResultFromX:absY:toX:toAbsY: for each.
// 2. If searchingForNextResult_ is true, highlight the next result before/after
//   the current selection and flip searchingForNextResult_ to false.
- (BOOL)continueFind
{
    BOOL more = NO;
    BOOL redraw = NO;

    assert([self findInProgress]);
    if (_findInProgress) {
        // Collect more results.
        more = [dataSource continueFindAllResults:findResults_
                                        inContext:[dataSource findContext]];
    }
    if (!more) {
        _findInProgress = NO;
    }
    // Add new results to map.
    for (int i = nextOffset_; i < [findResults_ count]; i++) {
        SearchResult* r = [findResults_ objectAtIndex:i];
        [self _addResultFromX:r->startX absY:r->absStartY toX:r->endX toAbsY:r->absEndY];
        redraw = YES;
    }
    nextOffset_ = [findResults_ count];

    // Highlight next result if needed.
    if (searchingForNextResult_) {
        if ([self _selectNextResultForward:searchingForward_
                                withOffset:findOffset_]) {
            searchingForNextResult_ = NO;
        }
    }

    if (redraw) {
        [self setNeedsDisplay:YES];
    }
    return more;
}

- (void)resetFindCursor
{
    lastFindStartX = lastFindEndX = absLastFindStartY = absLastFindEndY = -1;
}

- (BOOL)findString:(NSString *)aString
  forwardDirection:(BOOL)direction
      ignoringCase:(BOOL)ignoreCase
             regex:(BOOL)regex
        withOffset:(int)offset
{
    searchingForward_ = direction;
    findOffset_ = offset;
    if ([findString_ isEqualToString:aString] &&
        findRegex_ == regex &&
        findIgnoreCase_ == ignoreCase) {
        foundResult_ = NO;  // select the next item before/after the current selection.
        searchingForNextResult_ = YES;
        // I would like to call _selectNextResultForward:withOffset: here, but
        // it results in drawing errors (drawing is clipped to the findbar for
        // some reason). So we return YES and continueFind is run from a timer
        // and everything works fine. The 100ms delay introduced is not
        // noticable.
        return YES;
    } else {
        // Begin a brand new search.
        if (_findInProgress) {
            [dataSource cancelFindInContext:[dataSource findContext]];
        }

        lastFindStartX = lastFindEndX = 0;
        absLastFindStartY = absLastFindEndY = (long long)([dataSource numberOfLines] + 1) + [dataSource totalScrollbackOverflow];

        // Search backwards from the end. This is slower than searching
        // forwards, but most searches are reverse searches begun at the end,
        // so it will get a result sooner.
        [dataSource initFindString:aString
                  forwardDirection:NO
                      ignoringCase:ignoreCase
                             regex:regex
                       startingAtX:0
                       startingAtY:[dataSource numberOfLines] + 1 + [dataSource totalScrollbackOverflow]
                        withOffset:0
                         inContext:[dataSource findContext]
                   multipleResults:YES];
        _findInProgress = YES;

        // Reset every bit of state.
        [self clearHighlights];

        // Initialize state with new values.
        findRegex_ = regex;
        findIgnoreCase_ = ignoreCase;
        findResults_ = [[NSMutableArray alloc] init];
        searchingForNextResult_ = YES;
        findString_ = [aString copy];

        [self setNeedsDisplay:YES];
        return YES;
    }
}

- (void)clearHighlights
{
    [findString_ release];
    findString_ = nil;
    [findResults_ release];
    findResults_ = nil;
    nextOffset_ = 0;
    foundResult_ = NO;
    [resultMap_ removeAllObjects];
    searchingForNextResult_ = NO;
}

// transparency
- (double)transparency
{
    return (transparency);
}

- (void)setTransparency:(double)fVal
{
    transparency = fVal;
    [self setNeedsDisplay:YES];
}

- (void)setSmartCursorColor:(BOOL)value
{
    colorInvertedCursor = value;
}

- (void)setMinimumContrast:(double)value
{
    minimumContrast_ = value;
}

- (void)setDimmingAmount:(double)value
{
    dimmingAmount_ = value;
    [[self superview] setNeedsDisplay:YES];
}

- (BOOL)useTransparency
{
    return [[[[dataSource session] tab] realParentWindow] useTransparency];
}

// service stuff
- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
    if (sendType != nil && [sendType isEqualToString: NSStringPboardType]) {
        return self;
    }

    return ([super validRequestorForSendType: sendType returnType: returnType]);
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types
{
    NSString *copyString;

    copyString = [self selectedText];

    if (copyString && [copyString length]>0) {
        [pboard declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
        [pboard setString: copyString forType: NSStringPboardType];
        return YES;
    }

    return NO;
}

- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard
{
    return NO;
}

// This textview is about to be hidden behind another tab.
- (void)aboutToHide
{
    selectionScrollDirection = 0;
}

// Called form a timer. Update the alpha value for the graphic and request
// that the vie be redrawn.
- (void)setFlashAlpha
{
    NSDate* now = [NSDate date];
    double interval = [now timeIntervalSinceDate:lastFlashUpdate_];
    double ratio = interval / 0.016;
    // Decrement proprotionate to the time between calls (exactly 0.05 if time
    // was 0.016 sec).
    flashing_ -= 0.05 * ratio;
    if (flashing_ < 0) {
        // All done.
        flashing_ = 0;
    } else {
        // Schedule another decrementation.
        [lastFlashUpdate_ release];
        lastFlashUpdate_ = [now retain];
        [NSTimer scheduledTimerWithTimeInterval:0.016
                                         target:self
                                       selector:@selector(setFlashAlpha)
                                       userInfo:nil
                                        repeats:NO];
    }
    [self setNeedsDisplay:YES];
}

- (void)beginFlash:(int)image
{
    flashImage_ = image;
    if (flashing_ == 0) {
        // The timer is not running so start it.
        [lastFlashUpdate_ release];
        lastFlashUpdate_ = [[NSDate date] retain];
        [NSTimer scheduledTimerWithTimeInterval:0.016
                                         target:self
                                       selector:@selector(setFlashAlpha)
                                       userInfo:nil
                                        repeats:NO];
    }
    // Turn the image to opaque and ask to redraw the screen.
    flashing_ = 1;
    [self setNeedsDisplay:YES];
}

- (void)drawFlippedBackground:(NSRect)bgRect toPoint:(NSPoint)dest
{
    PTYScrollView* scrollView = (PTYScrollView*)[self enclosingScrollView];
    BOOL hasBGImage = [scrollView backgroundImage] != nil;
    double alpha = 1.0 - transparency;
    if (hasBGImage) {
        [(PTYScrollView *)[self enclosingScrollView] drawBackgroundImageRect:bgRect
                                                                     toPoint:dest
                                                             useTransparency:[self useTransparency]];
    }
    if (!hasBGImage || ![self useTransparency]) {
        // Either draw a normal bg or, if transparency is off, blend the default bg color over the bg image.
        if (!hasBGImage && ![self useTransparency]) {
            alpha = 1;
        }
        [[self _dimmedColorFrom:[[self defaultBGColor] colorWithAlphaComponent:alpha]] set];
        NSRect fillDest = bgRect;
        fillDest.origin.y += fillDest.size.height;
        NSRectFillUsingOperation(fillDest,
                                 hasBGImage ? NSCompositeSourceOver : NSCompositeCopy);
    }
}

- (void)drawBackground:(NSRect)bgRect toPoint:(NSPoint)dest
{
    PTYScrollView* scrollView = (PTYScrollView*)[self enclosingScrollView];
    BOOL hasBGImage = [scrollView backgroundImage] != nil;
    double alpha = 1.0 - transparency;
    if (hasBGImage) {
        [(PTYScrollView *)[self enclosingScrollView] drawBackgroundImageRect:bgRect
                                                                     toPoint:dest
                                                             useTransparency:[self useTransparency]];
    }
    if (!hasBGImage || ![self useTransparency]) {
        // Either draw a normal bg or, if transparency is off, blend the default bg color over the bg image.
        if (!hasBGImage && ![self useTransparency]) {
            alpha = 1;
        }
        [[self _dimmedColorFrom:[[self defaultBGColor] colorWithAlphaComponent:alpha]] set];
        NSRectFillUsingOperation(bgRect,
                                 hasBGImage ? NSCompositeSourceOver : NSCompositeCopy);
    }
}

- (void)drawBackground:(NSRect)bgRect
{
    PTYScrollView* scrollView = (PTYScrollView*)[self enclosingScrollView];
    BOOL hasBGImage = [scrollView backgroundImage] != nil;
    double alpha = 1.0 - transparency;
    if (hasBGImage) {
        [(PTYScrollView *)[self enclosingScrollView] drawBackgroundImageRect:bgRect
                                                             useTransparency:[self useTransparency]];
    }
    if (!hasBGImage || ![self useTransparency]) {
        // Either draw a normal bg or, if transparency is off, blend the default bg color over the bg image.
        if (!hasBGImage && ![self useTransparency]) {
            alpha = 1;
        }
        [[self _dimmedColorFrom:[[self defaultBGColor] colorWithAlphaComponent:alpha]] set];
        NSRectFillUsingOperation(bgRect, hasBGImage?NSCompositeSourceOver:NSCompositeCopy);
    }
}

- (BOOL)getAndResetChangedSinceLastExpose
{
    BOOL temp = changedSinceLastExpose_;
    changedSinceLastExpose_ = NO;
    return temp;
}

- (BOOL)isAnyCharSelected
{
    if (startX <= -1 || (startY == endY && startX == endX)) {
        return NO;
    } else {
        return YES;
    }
}

- (void)clearMatches
{
    [resultMap_ removeAllObjects];
}

- (NSString *)getWordForX:(int)x
                        y:(int)y
                   startX:(int *)startx
                   startY:(int *)starty
                     endX:(int *)endx
                     endY:(int *)endy
{
    int tmpX;
    int tmpY;
    int x1;
    int yStart;
    int x2;
    int y2;
    int width = [dataSource width];

    if (x < 0) {
        x = 0;
    }
    if (x >= width) {
        x = width - 1;
    }

    // Search backward from (x, y) to find the beginning of the word.
    tmpX = x;
    tmpY = y;
    // If the char at (x,y) is not whitespace, then go into a mode where
    // word characters are selected as blocks; else go into a mode where
    // whitespace is selected as a block.
    screen_char_t* initialLine = [dataSource getLineAtIndex:tmpY];
    assert(initialLine);
    screen_char_t sct = initialLine[tmpX];
    BOOL selectWordChars = [self classifyChar:sct.code isComplex:sct.complexChar] != CHARTYPE_WHITESPACE;

    while (tmpX >= 0) {
        screen_char_t* theLine = [dataSource getLineAtIndex:tmpY];

        if ([self shouldSelectCharForWord:theLine[tmpX].code isComplex:theLine[tmpX].complexChar selectWordChars:selectWordChars]) {
            tmpX--;
            if (tmpX < 0 && tmpY > 0) {
                // Wrap tmpX, tmpY to the end of the previous line.
                theLine = [dataSource getLineAtIndex:tmpY-1];
                if (theLine[width].code != EOL_HARD) {
                    // check if there's a hard line break
                    tmpY--;
                    tmpX = width - 1;
                }
            }
        } else {
            break;
        }
    }
    if (tmpX != x) {
        // Advance back to the right of the char that caused us to break.
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
        if ([self shouldSelectCharForWord:theLine[tmpX].code isComplex:theLine[tmpX].complexChar selectWordChars:selectWordChars]) {
            tmpX++;
            if (tmpX >= width && tmpY < [dataSource numberOfLines]) {
                if (theLine[width].code != EOL_HARD) {
                    // check if there's a hard line break
                    tmpY++;
                    tmpX = 0;
                }
            }
        } else {
            break;
        }
    }
    
    // Back off from trailing char.
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

    return [self contentFromX:x1 Y:yStart ToX:x2 Y:y2 pad: YES];
}

@end

//
// private methods
//
@implementation PTYTextView (Private)

- (BOOL)_font:(NSFont*)theFont hasGlyphsForCharacters:(unichar*)chars count:(int)count
{
    CGGlyph tempGlyphs[count];
    return CTFontGetGlyphsForCharacters((CTFontRef)theFont, chars, tempGlyphs,
                                        count);
}

- (PTYFontInfo*)getFontForChar:(UniChar)ch
                     isComplex:(BOOL)complex
                       fgColor:(int)fgColor
                    renderBold:(BOOL*)renderBold
{
    BOOL isBold = *renderBold && useBoldFont;
    *renderBold = NO;
    PTYFontInfo* theFont;
    BOOL usePrimary = !complex && (ch < 128);
    if (!usePrimary && !complex) {
        // Try to use the primary font for non-ascii characters, but only
        // if it has the glyph.
        usePrimary = [self _font:primaryFont.font
                        hasGlyphsForCharacters:&ch
                           count:1];
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
    }

    return theFont;
}

// Returns true if the sequence of characters starting at (x, y) is not repeated
// TAB_FILLERs followed by a tab.
- (BOOL)isTabFillerOrphanAtX:(int)x Y:(int)y
{
    const int realWidth = [dataSource width] + 1;
    screen_char_t buffer[realWidth];
    screen_char_t* theLine = [dataSource getLineAtIndex:y withBuffer:buffer];
    int maxSearch = [dataSource width];
    while (maxSearch > 0) {
        if (x == [dataSource width]) {
            x = 0;
            ++y;
            if (y == [dataSource numberOfLines]) {
                return YES;
            }
            theLine = [dataSource getLineAtIndex:y withBuffer:buffer];
        }
        if (theLine[x].code != TAB_FILLER) {
            if (theLine[x].code == '\t') {
                return NO;
            } else {
                return YES;
            }
        }
        ++x;
        --maxSearch;
    }
    return YES;
}

// Returns true iff the tab character after a run of TAB_FILLERs starting at
// (x,y) is selected.
- (BOOL)isFutureTabSelectedAfterX:(int)x Y:(int)y
{
    const int realWidth = [dataSource width] + 1;
    screen_char_t buffer[realWidth];
    screen_char_t* theLine = [dataSource getLineAtIndex:y withBuffer:buffer];
    while (x < [dataSource width] && theLine[x].code == TAB_FILLER) {
        ++x;
    }
    if ([self _isCharSelectedInRow:y col:x checkOld:NO] &&
        theLine[x].code == '\t') {
        return YES;
    } else {
        return NO;
    }
}

- (CharRun)_truncateRun:(CharRun*)run beforeIndex:(int)truncateBeforeIndex
{
    CharRun tailRun = *run;

    for (int i = 0; i < truncateBeforeIndex; ++i) {
        tailRun.x += run->advances[i].width;
    }
    tailRun.numCodes -= truncateBeforeIndex;
    tailRun.numAdvances -= truncateBeforeIndex;
    tailRun.numGlyphs -= truncateBeforeIndex;

    tailRun.codes += truncateBeforeIndex;
    tailRun.advances += truncateBeforeIndex;
    tailRun.glyphs += truncateBeforeIndex;

    run->numCodes = truncateBeforeIndex;
    run->numAdvances = truncateBeforeIndex;
    run->numGlyphs = truncateBeforeIndex;

    return tailRun;
}

- (void)_setSubstituteFontInRun:(CharRun*)charRunArray
{
    // No valid glyphs in this run. Pick a new font and update the
    // glyphs.
    CFStringRef tempString = CFStringCreateWithCharactersNoCopy(0,
                                                                charRunArray->codes,
                                                                charRunArray->numCodes,
                                                                kCFAllocatorNull);
    CTFontRef substituteFont = CTFontCreateForString((CTFontRef)charRunArray->fontInfo->font,
                                                     tempString,
                                                     CFRangeMake(0, charRunArray->numCodes));
    CFRelease(tempString);
    if (substituteFont) {
        PTYFontInfo* subFontInfo = [self getOrAddFallbackFont:(NSFont*)substituteFont];
        CFRelease(substituteFont);
        charRunArray->fontInfo = subFontInfo;
    }
}

- (int)_setGlyphsInRun:(CharRun*)charRunArray
{
    CharRun* currentRun = charRunArray;
    if (currentRun->runType == MULTIPLE_CODE_POINT_RUN) {
        // These are complicated and glyphs are figured out later.
        return 0;
    }

    int i = 0;
    int newRuns = 0;
    BOOL isOk;
    isOk = CTFontGetGlyphsForCharacters((CTFontRef)currentRun->fontInfo->font,
                                        currentRun->codes,
                                        currentRun->glyphs,
                                        currentRun->numCodes);
    while (!isOk && i < currentRun->numCodes) {
        // As long as this loop is running there are bogus glyphs in the current
        // run. We'll try to isolate the first bad glyph in its own run, fix its
        // font to something that (hopefully) can render it, and continue with
        // the remainder of the run after that bad glyph.
        //
        // A faster algorithm would be possible if the font substitution
        // algorithm were a bit smarter, but sometimes it goes down dead ends
        // so the only way to make sure that it can render the max number of
        // glyphs in a string is to substitute fonts for one glyph at a time.
        //
        // Example: given "U+239c U+23b7" in AndaleMono, the font substitution
        // algorithm suggests HiraganoKaguGothicProN, which cannot render both
        // glyphs. Ask it one at a time and you get Apple Symbols, which can
        // render both.
        for (i = 0; i < currentRun->numCodes; ++i) {
            if (!currentRun->glyphs[i]) {
                if (i > 0) {
                    // Some glyph after the first is bad. Truncate the current
                    // run to just the good glyphs. Set the currentRun to the
                    // second half.
                    CharRun suffixRun = [self _truncateRun:currentRun beforeIndex:i];
                    charRunArray[++newRuns] = suffixRun;
                    currentRun = &charRunArray[newRuns];
                    i = 0;
                    // We leave this block with currentRun having a bad first
                    // glyph.
                }

                // The first glyph is bad. Truncate the current run to 1
                // glyph and convert it to a MULTIPLE_CODE_POINT_RUN (though it's
                // obviously only one code point, it uses NSAttributedString to
                // render which is slow but can find the right font).
                CharRun suffixRun = [self _truncateRun:currentRun beforeIndex:1];
                currentRun->runType = MULTIPLE_CODE_POINT_RUN;

                if (suffixRun.numCodes > 0) {
                    // Append the remainder of the original run to the array of
                    // runs and have the outer loop begin working on the suffix.
                    charRunArray[++newRuns] = suffixRun;
                    currentRun = &charRunArray[newRuns];
                    i = 0;
                    break;
                } else {
                    return newRuns;
                }
            }
        }
        isOk = CTFontGetGlyphsForCharacters((CTFontRef)currentRun->fontInfo->font,
                                            currentRun->codes,
                                            currentRun->glyphs,
                                            currentRun->numCodes);
    }
    return newRuns;
}

static CGFloat PerceivedBrightness(CGFloat r, CGFloat g, CGFloat b) {
    return (RED_COEFFICIENT * r) + (GREEN_COEFFICIENT * g) + (BLUE_COEFFICIENT * b);
}

- (double)_perceivedBrightness:(NSColor*) c
{
    return PerceivedBrightness([c redComponent], [c greenComponent], [c blueComponent]);
}

- (NSColor*)colorWithRed:(double)r green:(double)g blue:(double)b alpha:(double)a withPerceivedBrightness:(CGFloat)t
{
    /*
     Given:
     a vector c [c1, c2, c3] (the starting color)
     a vector e [e1, e2, e3] (an extreme color we are moving to, normally black or white)
     a vector A [a1, a2, a3] (the perceived brightness transform)
     a linear function f(Y)=AY (perceived brightness for color Y)
     a constant t (target perceived brightness)
     find a vector X such that F(X)=t
     and X lies on a straight line between c and e

     Define a parametric vector x(p) = [x1(p), x2(p), x3(p)]:
     x1(p) = p*e1 + (1-p)*c1
     x2(p) = p*e2 + (1-p)*c2
     x3(p) = p*e3 + (1-p)*c3

     when p=0, x=c
     when p=1, x=e

     the line formed by x(p) from p=0 to p=1 is the line from c to e.

     Our goal: find the value of p where f(x(p))=t

     We know that:
                            [x1(p)]
     f(X) = AX = [a1 a2 a3] [x2(p)] = a1x1(p) + a2x2(p) + a3x3(p)
                            [x3(p)]
     Expand and solve for p:
        t = a1*(p*e1 + (1-p)*c1) + a2*(p*e2 + (1-p)*c2) + a3*(p*e3 + (1-p)*c3)
        t = a1*(p*e1 + c1 - p*c1) + a2*(p*e2 + c2 - p*c2) + a3*(p*e3 + c3 - p*c3)
        t = a1*p*e1 + a1*c1 - a1*p*c1 + a2*p*e2 + a2*c2 - a2*p*c2 + a3*p*e3 + a3*c3 - a3*p*c3
        t = a1*p*e1 - a1*p*c1 + a2*p*e2 - a2*p*c2 + a3*p*e3 - a3*p*c3 + a1*c1 + a2*c2 + a3*c3
        t = p*(a2*e1 - a1*c1 + a2*e2 - a2*c2 + a3*e3 - a3*c3) + a1*c1 + a2*c2 + a3*c3
        t - (a1*c1 + a2*c2 + a3*c3) = p*(a1*e1 - a1*c1 + a2*e2 - a2*c2 + a3*e3 - a3*c3)
        p = (t - (a1*c1 + a2*c2 + a3*c3)) / (a1*e1 - a1*c1 + a2*e2 - a2*c2 + a3*e3 - a3*c3)
     */
    const CGFloat c1 = r;
    const CGFloat c2 = g;
    const CGFloat c3 = b;

    CGFloat k;
    if (PerceivedBrightness(r, g, b) < t) {
        k = 1;
    } else {
        k = 0;
    }
    const CGFloat e1 = k;
    const CGFloat e2 = k;
    const CGFloat e3 = k;

    const CGFloat a1 = RED_COEFFICIENT;
    const CGFloat a2 = GREEN_COEFFICIENT;
    const CGFloat a3 = BLUE_COEFFICIENT;

    const CGFloat p = (t - (a1*c1 + a2*c2 + a3*c3)) / (a1*(e1 - c1) + a2*(e2 - c2) + a3*(e3 - c3));

    const CGFloat x1 = p * e1 + (1 - p) * c1;
    const CGFloat x2 = p * e2 + (1 - p) * c2;
    const CGFloat x3 = p * e3 + (1 - p) * c3;

    return [self _dimmedColorFrom:[NSColor colorWithCalibratedRed:x1 green:x2 blue:x3 alpha:a]];
}

- (NSColor*)color:(NSColor*)mainColor withContrastAgainst:(NSColor*)otherColor
{
    double r = [mainColor redComponent];
    double g = [mainColor greenComponent];
    double b = [mainColor blueComponent];
    double mainBrightness = PerceivedBrightness(r, g, b);
    double otherBrightness = PerceivedBrightness([otherColor redComponent],
                                                 [otherColor greenComponent],
                                                 [otherColor blueComponent]);
    CGFloat brightnessDiff = fabs(mainBrightness - otherBrightness);
    if (brightnessDiff < minimumContrast_) {
        CGFloat error = fabs(brightnessDiff - minimumContrast_);
        CGFloat targetBrightness = mainBrightness;
        if (mainBrightness < otherBrightness) {
            targetBrightness -= error;
            if (targetBrightness < 0) {
                const double alternative = otherBrightness + minimumContrast_;
                const double baseContrast = otherBrightness;
                const double altContrast = MIN(alternative, 1) - otherBrightness;
                if (altContrast > baseContrast) {
                    targetBrightness = alternative;
                }
            }
        } else {
            targetBrightness += error;
            if (targetBrightness > 1) {
                const double alternative = otherBrightness - minimumContrast_;
                const double baseContrast = 1 - otherBrightness;
                const double altContrast = otherBrightness - MAX(alternative, 0);
                if (altContrast > baseContrast) {
                    targetBrightness = alternative;
                }
            }
        }
        targetBrightness = MIN(MAX(0, targetBrightness), 1);
        return [self colorWithRed:r
                            green:g
                             blue:b
                            alpha:[mainColor alphaComponent]
                    withPerceivedBrightness:targetBrightness];
    } else {
        return mainColor;
    }
}

- (int)_constructRuns:(NSPoint)initialPoint
              theLine:(screen_char_t *)theLine
      advancesStorage:(CGSize*)advancesStorage
          codeStorage:(unichar*)codeStorage
         glyphStorage:(CGGlyph*)glyphStorage
                 runs:(CharRun*)runs
             reversed:(BOOL)reversed
           bgselected:(BOOL)bgselected
                width:(const int)width
           indexRange:(NSRange)indexRange
              bgColor:(NSColor*)bgColor
              matches:(NSData*)matches
{
    int numRuns = 0;
    CharRun* currentRun = NULL;
    int nextFreeAdvance = 0;
    int nextFreeCode = 0;
    int nextFreeGlyph = 0;
    const char* matchBytes = [matches bytes];

    NSColor* prevCharColor = NULL;
    RunType prevCharRunType = SINGLE_CODE_POINT_RUN;
    BOOL prevCharFakeBold = NO;
    PTYFontInfo* prevCharFont = nil;
    BOOL havePrevChar = NO;
    CGFloat curX = initialPoint.x;
    BOOL prevCharAntiAlias = NO;

    for (int i = indexRange.location;
         i < indexRange.location + indexRange.length;
         i++) {
        if (theLine[i].code == DWC_RIGHT) {
            continue;
        }
        BOOL doubleWidth = i < width - 1 && (theLine[i + 1].code == DWC_RIGHT);

        NSColor* thisCharColor = NULL;
        RunType thisCharRunType;
        unichar thisCharUnichar = 0;
        NSString* thisCharString = nil;
        CGFloat thisCharAdvance;
        BOOL thisCharFakeBold = NO;
        PTYFontInfo* thisCharFont = 0;
        BOOL thisCharAntiAlias;

        if (theLine[i].code < 128 && !theLine[i].complexChar) {
            thisCharAntiAlias = asciiAntiAlias;
        } else {
            thisCharAntiAlias = nonasciiAntiAlias;
        }
        BOOL isSelection = NO;

        // Figure out the color for this char.
        if (bgselected &&
            theLine[i].alternateForegroundSemantics &&
            theLine[i].foregroundColor == ALTSEM_FG_DEFAULT) {
            // Is a selection.
            isSelection = YES;
            thisCharColor = [self _dimmedColorFrom:selectedTextColor];
        } else {
            // Not a selection.
            if (reversed &&
                theLine[i].alternateForegroundSemantics &&
                theLine[i].foregroundColor == ALTSEM_FG_DEFAULT) {
                // Has default foreground color so use background color.
                thisCharColor = [self _dimmedColorFrom:defaultBGColor];
            } else {
                // Not reversed or not subject to reversing (only default
                // foreground color is drawn in reverse video).
                thisCharColor = [self colorForCode:theLine[i].foregroundColor
                                alternateSemantics:theLine[i].alternateForegroundSemantics
                                              bold:theLine[i].bold];
            }
        }

        if (matches && !isSelection) {
            // Test if this is a highlighted match from a find.
            int theIndex = i / 8;
            int mask = 1 << (i & 7);
            if (theIndex < [matches length] && matchBytes[theIndex] & mask) {
                thisCharColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1];
            }
        }

        if (minimumContrast_ > 0.001 && bgColor) {
            thisCharColor = [self color:thisCharColor withContrastAgainst:bgColor];
        }
        BOOL drawable;
        if (blinkShow || ![self _charBlinks:theLine[i]]) {
            // This char is either not blinking or during the "on" cycle of the
            // blink.

            // Set the character type and its unichar/string.
            if (theLine[i].complexChar) {
                thisCharRunType = MULTIPLE_CODE_POINT_RUN;
                thisCharString = ComplexCharToStr(theLine[i].code);
                drawable = YES;  // TODO: not all unicode is drawable
            } else {
                thisCharRunType = SINGLE_CODE_POINT_RUN;

                // TODO: There are other spaces in unicode that should be supported.
                drawable = (theLine[i].code != 0 &&
                            theLine[i].code != '\t' &&
                            !(theLine[i].code >= ITERM2_PRIVATE_BEGIN &&
                              theLine[i].code <= ITERM2_PRIVATE_END));

                if (drawable) {
                    thisCharUnichar = theLine[i].code;
                }
            }
        } else {
            thisCharRunType = SINGLE_CODE_POINT_RUN;
            drawable = NO;
        }

        // Set all other common attributes.
        if (doubleWidth) {
            thisCharAdvance = charWidth * 2;
        } else {
            thisCharAdvance = charWidth;
        }

        if (drawable) {
            thisCharFakeBold = theLine[i].bold;
            thisCharFont = [self getFontForChar:theLine[i].code
                                      isComplex:theLine[i].complexChar
                                        fgColor:theLine[i].foregroundColor
                                     renderBold:&thisCharFakeBold];

            // Create a new run if needed (this char differs from the previous
            // or is the first in this line or comes after a nondrawable.
            BOOL beginNewRun = NO;
            if (!havePrevChar ||
                prevCharRunType == MULTIPLE_CODE_POINT_RUN ||
                thisCharRunType == MULTIPLE_CODE_POINT_RUN ||
                thisCharFont != prevCharFont ||
                thisCharColor != prevCharColor ||
                thisCharFakeBold != prevCharFakeBold ||
                thisCharAntiAlias != prevCharAntiAlias) {
                beginNewRun = YES;
                havePrevChar = YES;
            }
            if (beginNewRun) {
                if (currentRun) {
                    nextFreeGlyph += currentRun->numGlyphs;
                    nextFreeCode += currentRun->numCodes;
                    nextFreeAdvance += currentRun->numAdvances;
                    numRuns += [self _setGlyphsInRun:currentRun];
                }
                currentRun = &runs[numRuns++];
                // Begin a new run.
                currentRun->runType = thisCharRunType;
                currentRun->fontInfo = thisCharFont;
                currentRun->color = thisCharColor;
                currentRun->fakeBold = thisCharFakeBold;
                currentRun->codes = codeStorage + nextFreeCode;
                currentRun->numCodes = 0;
                currentRun->advances = advancesStorage + nextFreeAdvance;
                currentRun->numAdvances = 0;
                currentRun->glyphs = glyphStorage + nextFreeGlyph;
                currentRun->numGlyphs = 0;
                currentRun->x = curX;
                currentRun->antiAlias = thisCharAntiAlias;
            }

            if (thisCharRunType == SINGLE_CODE_POINT_RUN) {
                currentRun->codes[currentRun->numCodes++] = thisCharUnichar;
                currentRun->numGlyphs++;
            } else {
                int length = [thisCharString length];
                [thisCharString getCharacters:currentRun->codes + currentRun->numCodes
                                        range:NSMakeRange(0, length)];
                currentRun->numCodes += length;
                // numGlyphs intentionally stays at 0 because we don't get glyphs
                // for multi-code point cells until drawing time.
            }
            currentRun->advances[currentRun->numAdvances].height = 0;
            currentRun->advances[currentRun->numAdvances++].width = thisCharAdvance;
        } else {
            havePrevChar = NO;
        }

        // draw underline
        if (theLine[i].underline && drawable) {
            [thisCharColor set];
            NSRectFill(NSMakeRect(curX,
                                  initialPoint.y + lineHeight - 2,
                                  doubleWidth ? charWidth * 2 : charWidth,
                                  1));
        }
        curX += thisCharAdvance;
        prevCharRunType = thisCharRunType;
        prevCharFont = thisCharFont;
        prevCharColor = thisCharColor;
        prevCharFakeBold = thisCharFakeBold;
        prevCharAntiAlias = thisCharAntiAlias;
    }

    if (currentRun) {
        numRuns += [self _setGlyphsInRun:currentRun];
    }
    return numRuns;
}

- (void)_advancedDrawChar:(unichar*)codes
                 numCodes:(int)numCodes
                 fontInfo:(PTYFontInfo*)fontInfo
                    color:(NSColor*)color
                       at:(NSPoint)pos
                    width:(CGFloat)width
                 fakeBold:(BOOL)fakeBold
                antiAlias:(BOOL)antiAlias
{
    NSString* str = [NSString stringWithCharacters:codes
                                            length:numCodes];
    NSDictionary* attrs;
    if (advancedFontRendering && antiAlias) {
        attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                               fontInfo->font, NSFontAttributeName,
                               color, NSForegroundColorAttributeName,
                               [NSNumber numberWithFloat:strokeThickness], NSStrokeWidthAttributeName,
                               nil];
    } else {
        attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                 fontInfo->font, NSFontAttributeName,
                 color, NSForegroundColorAttributeName,
                 nil];
    }
    NSMutableAttributedString* attributedString = [[[NSMutableAttributedString alloc] initWithString:str
                                                                                          attributes:attrs] autorelease];
    // Note that drawInRect doesn't use the right baseline, but drawWithRect
    // does.
    //
    // This technique was picked because it can find glyphs that aren't in the
    // selected font (e.g., tests/radical.txt). It does a fairly nice job on
    // laying out combining marks. For now, it fails in two known cases:
    // 1. Enclosing marks (q in a circle shows as a q)
    // 2. U+239d, a part of a paren for graphics drawing, doesn't quite render
    //    right (though it appears to need to render in another char's cell).
    // Other rejected approaches included using CTFontGetGlyphsForCharacters+
    // CGContextShowGlyphsWithAdvances, which doesn't render thai characters
    // correctly in UTF-8-demo.txt.
    //
    // We use width*2 so that wide characters that are not double width chars
    // render properly. These are font-dependent. See tests/suits.txt for an
    // example.
    [attributedString drawWithRect:NSMakeRect(pos.x,
                                              pos.y + fontInfo->baselineOffset + lineHeight,
                                              width*2,
                                              lineHeight)
                           options:0];  // NSStringDrawingUsesLineFragmentOrigin
    if (fakeBold) {
        // If anti-aliased, drawing twice at the same position makes the strokes thicker.
        // If not anti-alised, draw one pixel to the right.
        [attributedString drawWithRect:NSMakeRect(pos.x + (antiAlias ? 0 : 1),
                                                  pos.y + fontInfo->baselineOffset + lineHeight,
                                                  width*2,
                                                  lineHeight)
                               options:0];  // NSStringDrawingUsesLineFragmentOrigin
    }
}

- (void)_drawComplexCharRun:(CharRun *)currentRun
                        ctx:(CGContextRef)ctx
               initialPoint:(NSPoint)initialPoint
                  antiAlias:(BOOL)antiAlias
{
    [self _advancedDrawChar:currentRun->codes
                   numCodes:currentRun->numCodes
                   fontInfo:currentRun->fontInfo
                      color:currentRun->color
                         at:NSMakePoint(currentRun->x,
                                        initialPoint.y)
                      width:currentRun->advances[0].width
                   fakeBold:currentRun->fakeBold
                  antiAlias:antiAlias];
}

- (void)_drawBasicCharRunAdvanced:(CharRun *)currentRun ctx:(CGContextRef)ctx initialPoint:(NSPoint)initialPoint
{
    CGFloat x = currentRun->x;
    for (int i = 0; i < currentRun->numCodes; i++) {
        [self _advancedDrawChar:&currentRun->codes[i]
                       numCodes:1
                       fontInfo:currentRun->fontInfo
                          color:currentRun->color
                             at:NSMakePoint(x,
                                            initialPoint.y)
                          width:currentRun->advances[i].width
                       fakeBold:currentRun->fakeBold
                      antiAlias:currentRun->antiAlias];
        x += currentRun->advances[i].width;
    }
}

- (void)_drawBasicCharRun:(CharRun *)currentRun ctx:(CGContextRef)ctx initialPoint:(NSPoint)initialPoint
{
    const int width = [dataSource width];
    CGGlyph glyphs[width];

    if (!CTFontGetGlyphsForCharacters((CTFontRef)currentRun->fontInfo->font,
                                      currentRun->codes,
                                      glyphs,
                                      currentRun->numCodes)) {
        // TODO
        // One or more glyphs could not be found in this font. Try to
        // find a font that can render them.
    }
    CGContextSelectFont(ctx,
                        [[currentRun->fontInfo->font fontName] UTF8String],
                        [currentRun->fontInfo->font pointSize],
                        kCGEncodingMacRoman);
    CGContextSetFillColorSpace(ctx, [[currentRun->color colorSpace] CGColorSpace]);
    int componentCount = [currentRun->color numberOfComponents];

    CGFloat components[componentCount];
    [currentRun->color getComponents:components];
    CGContextSetFillColor(ctx, components);

    double y = initialPoint.y + lineHeight + currentRun->fontInfo->baselineOffset;
    int x = currentRun->x;
    // Flip vertically and translate to (x, y).
    CGContextSetTextMatrix(ctx, CGAffineTransformMake(1.0,  0.0,
                                                      0.0, -1.0,
                                                      x,    y));

    CGContextShowGlyphsWithAdvances(ctx, glyphs, currentRun->advances,
                                    currentRun->numCodes);

    if (currentRun->fakeBold) {
        // If anti-aliased, drawing twice at the same position makes the strokes thicker.
        // If not anti-alised, draw one pixel to the right.
        CGContextSetTextMatrix(ctx, CGAffineTransformMake(1.0,  0.0,
                                                          0.0, -1.0,
                                                          x + (currentRun->antiAlias ? 0 : 1),    y));

        CGContextShowGlyphsWithAdvances(ctx, glyphs, currentRun->advances,
                                        currentRun->numCodes);
    }
}

- (void)_drawRuns:(NSPoint)initialPoint runs:(CharRun*)runs numRuns:(int)numRuns
{
    CharRun *currentRun;
    CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    CGContextSetTextDrawingMode(ctx, kCGTextFill);

    for (int i = 0; i < numRuns; ++i) {
        currentRun = &runs[i];
        CGContextSetShouldAntialias(ctx, currentRun->antiAlias);

        if (currentRun->runType == SINGLE_CODE_POINT_RUN) {
            if (currentRun->antiAlias && advancedFontRendering) {
                [self _drawBasicCharRunAdvanced:currentRun
                                            ctx:ctx
                                   initialPoint:initialPoint];
            } else {
                [self _drawBasicCharRun:currentRun
                                    ctx:ctx
                           initialPoint:initialPoint];
            }
        } else {
            [self _drawComplexCharRun:currentRun
                                  ctx:ctx
                         initialPoint:initialPoint
                            antiAlias:currentRun->antiAlias];
        }
    }
}

- (void)_drawCharactersInLine:(screen_char_t*)theLine
                      inRange:(NSRange)indexRange
              startingAtPoint:(NSPoint)initialPoint
                   bgselected:(BOOL)bgselected
                     reversed:(BOOL)reversed
                      bgColor:(NSColor*)bgColor
                      matches:(NSData*)matches
{
    const int width = [dataSource width];
    unichar codeStorage[width * kMaxParts];
    CGSize advancesStorage[width];
    CGGlyph glyphStorage[width * kMaxParts];
    CharRun runs[width];
    int numRuns = [self _constructRuns:initialPoint
                               theLine:theLine
                       advancesStorage:advancesStorage
                           codeStorage:codeStorage
                          glyphStorage:glyphStorage
                                  runs:runs
                              reversed:reversed
                            bgselected:bgselected
                                 width:width
                            indexRange:indexRange
                               bgColor:bgColor
                               matches:matches];

    [self _drawRuns:initialPoint runs:runs numRuns:numRuns];
}

- (BOOL)_drawLine:(int)line AtY:(double)curY toPoint:(NSPoint*)toPoint
{
    BOOL anyBlinking = NO;
    int screenstartline = [self frame].origin.y / lineHeight;
    DebugLog([NSString stringWithFormat:@"Draw line %d (%d on screen)", line, (line - screenstartline)]);

    int WIDTH = [dataSource width];
    screen_char_t* theLine = [dataSource getLineAtIndex:line];
    PTYScrollView* scrollView = (PTYScrollView*)[self enclosingScrollView];
    BOOL hasBGImage = [scrollView backgroundImage] != nil;
    double selectedAlpha = 1.0 - transparency;
    double alphaIfTransparencyInUse = [self useTransparency] ? 1.0 - transparency : 1.0;
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

    aColor = [self colorForCode:ALTSEM_BG_DEFAULT
             alternateSemantics:YES
                           bold:NO];

    aColor = [aColor colorWithAlphaComponent:selectedAlpha];
    [aColor set];
    if (hasBGImage) {
        if (toPoint) {
            [scrollView drawBackgroundImageRect:leftMargin
                                        toPoint:NSMakePoint(toPoint->x + leftMargin.origin.x,
                                                            toPoint->y + leftMargin.size.height)
                                useTransparency:[self useTransparency]];
            [scrollView drawBackgroundImageRect:rightMargin
                                        toPoint:NSMakePoint(toPoint->x + rightMargin.origin.x,
                                                            toPoint->y + rightMargin.size.height)
                                useTransparency:[self useTransparency]];
        } else {
            [scrollView drawBackgroundImageRect:leftMargin
                                useTransparency:[self useTransparency]];
            [scrollView drawBackgroundImageRect:rightMargin
                                useTransparency:[self useTransparency]];
        }
    }
    if (!hasBGImage || ![self useTransparency]) {
        // Blend fg over bgimage (because transparency is off), or there is no
        // bg image and just draw the fg.
        if (toPoint) {
            NSRectFill(NSMakeRect(toPoint->x + leftMargin.origin.x,
                                  toPoint->y,
                                  leftMargin.size.width,
                                  leftMargin.size.height));
            NSRectFill(NSMakeRect(toPoint->x + rightMargin.origin.x,
                                  toPoint->y,
                                  rightMargin.size.width,
                                  rightMargin.size.height));
        } else {
            if (hasBGImage) {
                NSRectFillUsingOperation(leftMargin, NSCompositeSourceOver);
                NSRectFillUsingOperation(rightMargin, NSCompositeSourceOver);
            } else {
                aColor = [aColor colorWithAlphaComponent:alphaIfTransparencyInUse];
                [aColor set];
                NSRectFill(leftMargin);
                NSRectFill(rightMargin);
            }
        }
    }

    // Contiguous sections of background with the same colour
    // are combined into runs and draw as one operation
    int bgstart = -1;
    int j = 0;
    int bgColor = 0;
    BOOL bgAlt = NO;
    BOOL bgselected = NO;
    BOOL isMatch = NO;
    NSData* matches = [resultMap_ objectForKey:[NSNumber numberWithLongLong:line + [dataSource totalScrollbackOverflow]]];
    const char* matchBytes = [matches bytes];

    // Iterate over each character in the line
    while (j <= WIDTH) {
        if (theLine[j].code == DWC_RIGHT) {
            // Do not draw the right-hand side of double-width characters.
            j++;
            continue;
        }
        if (blinkAllowed_ && theLine[j].blink) {
            anyBlinking = YES;
        }

        BOOL selected;
        if (theLine[j].code == DWC_SKIP) {
            selected = NO;
        } else if (theLine[j].code == TAB_FILLER) {
            if ([self isTabFillerOrphanAtX:j Y:line]) {
                // Treat orphaned tab fillers like spaces.
                selected = [self _isCharSelectedInRow:line col:j checkOld:NO];
            } else {
                // Select all leading tab fillers iff the tab is selected.
                selected = [self isFutureTabSelectedAfterX:j Y:line];
            }
        } else {
            selected = [self _isCharSelectedInRow:line col:j checkOld:NO];
        }
        BOOL double_width = j < WIDTH - 1 && (theLine[j+1].code == DWC_RIGHT);
        BOOL match = NO;
        if (matchBytes) {
            // Test if this char is a highlighted match from a Find.
            const int theIndex = j / 8;
            const int bitMask = 1 << (j & 7);
            match = theIndex < [matches length] && (matchBytes[theIndex] & bitMask);
        }

        if (j != WIDTH && bgstart < 0) {
            // Start new run
            bgstart = j;
            bgColor = theLine[j].backgroundColor;
            bgAlt = theLine[j].alternateBackgroundSemantics;
            bgselected = selected;
            isMatch = match;
        }

        if (j != WIDTH &&
            bgselected == selected &&
            theLine[j].backgroundColor == bgColor &&
            match == isMatch &&
            theLine[j].alternateBackgroundSemantics == bgAlt) {
            // Continue the run
            j += (double_width ? 2 : 1);
        } else if (bgstart >= 0) {
            // This run is finished, draw it
            NSRect bgRect = NSMakeRect(floor(MARGIN + bgstart * charWidth),
                                       curY,
                                       ceil((j - bgstart) * charWidth),
                                       lineHeight);

            if (hasBGImage) {
                if (toPoint) {
                    [(PTYScrollView *)[self enclosingScrollView] drawBackgroundImageRect:bgRect
                                                                                 toPoint:NSMakePoint(toPoint->x + bgRect.origin.x,
                                                                                                     toPoint->y + bgRect.size.height)
                                                                         useTransparency:[self useTransparency]];
                } else {
                    [(PTYScrollView *)[self enclosingScrollView] drawBackgroundImageRect:bgRect
                                                                         useTransparency:[self useTransparency]];
                }
            }
            if (!hasBGImage ||
                !(bgColor == ALTSEM_BG_DEFAULT && bgAlt) ||
                bgselected) {
                // There's no bg image, or there's a nondefault bg on a bg image.
                // We are not drawing an unmolested background image. Some
                // background fill must be drawn. If there is a background image
                // it will be blended 50/50.

                if (isMatch && !bgselected) {
                    aColor = [NSColor colorWithCalibratedRed:1 green:1 blue:0 alpha:1];
                } else if (bgselected) {
                    aColor = selectionColor;
                } else {
                    if (reversed && bgColor == ALTSEM_BG_DEFAULT && bgAlt) {
                        // Reverse video is only applied to default background-
                        // color chars.
                        aColor = [self colorForCode:ALTSEM_FG_DEFAULT
                                 alternateSemantics:YES
                                               bold:NO];
                    } else {
                        // Use the regular background color.
                        aColor = [self colorForCode:bgColor
                                 alternateSemantics:bgAlt
                                               bold:NO];
                    }
                }
                aColor = [aColor colorWithAlphaComponent:alphaIfTransparencyInUse];
                [aColor set];
                if (toPoint) {
                    bgRect.origin.x += toPoint->x;
                    bgRect.origin.y = toPoint->y;
                }
                NSRectFillUsingOperation(bgRect,
                                         hasBGImage ? NSCompositeSourceOver : NSCompositeCopy);
            } else if (hasBGImage) {
                // There is a bg image and no special background on it. Blend in the
                // default background color. But don't blend in the bg color if transparency is on.
                aColor = [self colorForCode:ALTSEM_BG_DEFAULT
                         alternateSemantics:YES
                                       bold:NO];
                aColor = [aColor colorWithAlphaComponent:selectedAlpha];
                [aColor set];
                if (![self useTransparency]) {
                    NSRectFillUsingOperation(bgRect, NSCompositeSourceOver);
                }
            }

            NSPoint textOrigin;
            if (toPoint) {
                textOrigin = NSMakePoint(toPoint->x + MARGIN + bgstart * charWidth,
                                         toPoint->y);
            } else {
                textOrigin = NSMakePoint(MARGIN + bgstart*charWidth,
                                         curY);
            }
            [self _drawCharactersInLine:theLine
                                inRange:NSMakeRange(bgstart, j - bgstart)
                        startingAtPoint:textOrigin
                             bgselected:bgselected
                               reversed:reversed
                                bgColor:aColor
                                matches:matches];
            bgstart = -1;
            // Return to top of loop without incrementing j so this
            // character gets the chance to start its own run
        } else {
            // Don't need to draw and not on a run, move to next char
            j += (double_width ? 2 : 1);
        }
    }
    return anyBlinking;
}


- (void)_drawCharacter:(screen_char_t)screenChar
               fgColor:(int)fgColor
    alternateSemantics:(BOOL)fgAlt
                fgBold:(BOOL)fgBold
                   AtX:(double)X
                     Y:(double)Y
           doubleWidth:(BOOL)double_width
         overrideColor:(NSColor*)overrideColor
{
    screen_char_t temp = screenChar;
    temp.foregroundColor = fgColor;
    temp.alternateForegroundSemantics = fgAlt;
    temp.bold = fgBold;
    CGSize advances[kMaxParts];
    unichar codes[kMaxParts];
    CGGlyph glyphs[kMaxParts];
    CharRun runs[kMaxParts];

    // Draw the characters.
    int numRuns = [self _constructRuns:NSMakePoint(X, Y)
                               theLine:&temp
                       advancesStorage:advances
                           codeStorage:codes
                          glyphStorage:glyphs
                                  runs:runs
                              reversed:NO
                            bgselected:NO
                                 width:[dataSource width]
                            indexRange:NSMakeRange(0, 1)
                               bgColor:nil
                               matches:nil];
    // If an override color is given, change the runs' colors.
    if (overrideColor) {
        for (int i = 0; i < numRuns; ++i) {
            runs[i].color = overrideColor;
        }
    }
    [self _drawRuns:NSMakePoint(X, Y) runs:runs numRuns:numRuns];

    // draw underline
    if (screenChar.underline && screenChar.code) {
        if (overrideColor) {
            [overrideColor set];
        } else {
            [[self colorForCode:fgColor
               alternateSemantics:fgAlt
                           bold:fgBold] set];
        }

        NSRectFill(NSMakeRect(X,
                              Y + lineHeight - 2,
                              double_width ? charWidth * 2 : charWidth,
                              1));
    }
}

// Compute the length, in charWidth cells, of the input method text.
- (int)inputMethodEditorLength
{
    if (![self hasMarkedText]) {
        return 0;
    }
    NSString* str = [markedText string];

    const int maxLen = [str length] * kMaxParts;
    screen_char_t buf[maxLen];
    screen_char_t fg, bg;
    memset(&bg, 0, sizeof(bg));
    memset(&fg, 0, sizeof(fg));
    int len;
    StringToScreenChars(str,
                        buf,
                        fg,
                        bg,
                        &len,
                        0,
                        [[dataSource session] doubleWidth],
                        NULL);

    // Count how many additional cells are needed due to double-width chars
    // that span line breaks being wrapped to the next line.
    int x = [dataSource cursorX] - 1;  // cursorX is 1-based
    int width = [dataSource width];
    int extra = 0;
    int curX = x;
    for (int i = 0; i < len; ++i) {
        if (curX == 0 && buf[i].code == DWC_RIGHT) {
            ++extra;
            ++curX;
        }
        ++curX;
        curX %= width;
    }
    return len + extra;
}

- (BOOL)drawInputMethodEditorTextAt:(int)xStart
                                  y:(int)yStart
                              width:(int)width
                             height:(int)height
                       cursorHeight:(double)cursorHeight
{
    // draw any text for NSTextInput
    if ([self hasMarkedText]) {
        NSString* str = [markedText string];
        const int maxLen = [str length] * kMaxParts;
        screen_char_t buf[maxLen];
        screen_char_t fg = {0}, bg = {0};
        fg.foregroundColor = ALTSEM_FG_DEFAULT;
        fg.alternateForegroundSemantics = YES;
        fg.bold = NO;
        fg.blink = NO;
        fg.underline = NO;
        memset(&bg, 0, sizeof(bg));
        int len;
        int cursorIndex = (int)IM_INPUT_SELRANGE.location;
        StringToScreenChars(str,
                            buf,
                            fg,
                            bg,
                            &len,
                            0,
                            [[dataSource session] doubleWidth],
                            &cursorIndex);
        int cursorX = 0;
        int baseX = floor(xStart * charWidth + MARGIN);
        int i;
        int y = (yStart + [dataSource numberOfLines] - height) * lineHeight;
        int cursorY = y;
        int x = baseX;
        int preWrapY = 0;
        BOOL justWrapped = NO;
        BOOL foundCursor = NO;
        for (i = 0; i < len; ) {
            CGSize advances[width * kMaxParts];
            unichar codes[width * kMaxParts];
            CGGlyph glyphs[width * kMaxParts];
            CharRun runs[width * kMaxParts];
            const int remainingCharsInBuffer = len - i;
            const int remainingCharsInLine = width - xStart;
            int charsInLine = MIN(remainingCharsInLine,
                                  remainingCharsInBuffer);
            int skipped = 0;
            if (charsInLine + i < len &&
                buf[charsInLine + i].code == DWC_RIGHT) {
                // If we actually drew 'charsInLine' chars then half of a
                // double-width char would be drawn. Skip it and draw it on the
                // next line.
                skipped = 1;
                --charsInLine;
            }
            // Draw the background.
            NSRect r = NSMakeRect(x,
                                  y,
                                  charsInLine * charWidth,
                                  lineHeight);
            [[self _dimmedColorFrom:defaultBGColor] set];
            NSRectFill(r);

            // Draw the characters.
            int numRuns = [self _constructRuns:NSMakePoint(x, y)
                                       theLine:buf
                               advancesStorage:advances
                                   codeStorage:codes
                                  glyphStorage:glyphs
                                          runs:runs
                                      reversed:NO
                                    bgselected:NO
                                         width:[dataSource width]
                                    indexRange:NSMakeRange(i, charsInLine)
                                       bgColor:nil
                                       matches:nil];
            [self _drawRuns:NSMakePoint(x, y) runs:runs numRuns:numRuns];

            // Draw an underline.
            [defaultFGColor set];
            NSRect s = NSMakeRect(x,
                                  y + lineHeight - 1,
                                  charsInLine * charWidth,
                                  1);
            NSRectFill(s);

            // Save the cursor's cell coords
            if (i <= cursorIndex && i + charsInLine > cursorIndex) {
                // The char the cursor is at was drawn in this line.
                const int cellsAfterStart = cursorIndex - i;
                cursorX = x + charWidth * cellsAfterStart;
                cursorY = y;
                foundCursor = YES;
            }

            // Advance the cell and screen coords.
            xStart += charsInLine + skipped;
            if (xStart == width) {
                justWrapped = YES;
                preWrapY = y;
                xStart = 0;
                yStart++;
            } else {
                justWrapped = NO;
            }
            x = floor(xStart * charWidth + MARGIN);
            y = (yStart + [dataSource numberOfLines] - height) * lineHeight;
            i += charsInLine;
        }

        if (!foundCursor && i == cursorIndex) {
            if (justWrapped) {
                cursorX = MARGIN + width * charWidth;
                cursorY = preWrapY;
            } else {
                cursorX = x;
                cursorY = y;
            }
        }
        const double kCursorWidth = 2.0;
        double rightMargin = MARGIN + [dataSource width] * charWidth;
        if (cursorX + kCursorWidth >= rightMargin) {
            // Make sure the cursor doesn't draw in the margin. Shove it left
            // a little bit so it fits.
            cursorX = rightMargin - kCursorWidth;
        }
        NSRect cursorFrame = NSMakeRect(cursorX,
                                        cursorY,
                                        2.0,
                                        cursorHeight);
        [[self _dimmedColorFrom:[NSColor colorWithCalibratedRed:1 green:1 blue:0 alpha:1]] set];
        NSRectFill(cursorFrame);

        return TRUE;
    }
    return FALSE;
}

- (double)cursorHeight
{
    double cursorHeight;
    if (lineHeight < charHeightWithoutSpacing) {
        cursorHeight = lineHeight;
    } else {
        cursorHeight = charHeightWithoutSpacing;
    }
    return cursorHeight;
}

- (void)_drawCursor
{
    [self _drawCursorTo:nil];
}

- (NSColor*)_charBackground:(screen_char_t)c
{
    if ([[dataSource terminal] screenMode]) {
        // reversed
        return [self colorForCode:c.foregroundColor alternateSemantics:c.alternateForegroundSemantics bold:c.bold];
    } else {
        // normal
        return [self colorForCode:c.backgroundColor alternateSemantics:c.alternateBackgroundSemantics bold:false];
    }
}

- (double)_brightnessOfCharBackground:(screen_char_t)c
{
    return [self _perceivedBrightness:[[self _charBackground:c] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
}

// Return the value in 'values' closest to target.
- (CGFloat)_minimumDistanceOf:(CGFloat)target fromAnyValueIn:(NSArray*)values
{
    CGFloat md = 1;
    for (NSNumber* n in values) {
        CGFloat dist = fabs(target - [n doubleValue]);
        if (dist < md) {
            md = dist;
        }
    }
    return md;
}

// Return the value between 0 and 1 that is farthest from any value in 'constraints'.
- (CGFloat)_farthestValueFromAnyValueIn:(NSArray*)constraints
{
    if ([constraints count] == 0) {
        return 0;
    }

    NSArray* sortedConstraints = [constraints sortedArrayUsingSelector:@selector(compare:)];
    double minVal = [[sortedConstraints objectAtIndex:0] doubleValue];
    double maxVal = [[sortedConstraints lastObject] doubleValue];

    CGFloat bestDistance = 0;
    CGFloat bestValue = -1;
    CGFloat prev = [[sortedConstraints objectAtIndex:0] doubleValue];
    for (NSNumber* np in sortedConstraints) {
        CGFloat n = [np doubleValue];
        const CGFloat dist = fabs(n - prev) / 2;
        if (dist > bestDistance) {
            bestDistance = dist;
            bestValue = (n + prev) / 2;
        }
        prev = n;
    }
    if (minVal > bestDistance) {
        bestValue = 0;
        bestDistance = minVal;
    }
    if (1 - maxVal > bestDistance) {
        bestValue = 1;
        bestDistance = 1 - maxVal;
    }

    return bestValue;
}

- (void)_drawCursorTo:(NSPoint*)toOrigin
{
    int WIDTH, HEIGHT;
    screen_char_t* theLine;
    int yStart, x1;
    double cursorWidth, cursorHeight;
    double curX, curY;
    BOOL double_width;
    double alpha = [self useTransparency] ? 1.0 - transparency : 1.0;
    const BOOL reversed = [[dataSource terminal] screenMode];

    WIDTH = [dataSource width];
    HEIGHT = [dataSource height];
    x1 = [dataSource cursorX] - 1;
    yStart = [dataSource cursorY] - 1;

    NSRect docVisibleRect = [[self enclosingScrollView] documentVisibleRect];
    int lastVisibleLine = docVisibleRect.origin.y / [self lineHeight] + HEIGHT;
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
    cursorHeight = [self cursorHeight];


    if ([self blinkingCursor] &&
        [[self window] isKeyWindow] &&
        [[[dataSource session] tab] activeSession] == [dataSource session] &&
        x1 == oldCursorX &&
        yStart == oldCursorY) {
        // Allow the cursor to blink if it is configured, the window is key, this session is active
        // in the tab, and the cursor has not moved since the last draw.
        showCursor = blinkShow;
    } else {
        showCursor = YES;
    }

    // Draw the regular cursor only if there's not an IME open as it draws its
    // own cursor.
    if (![self hasMarkedText] && CURSOR) {
        if (showCursor && x1 <= WIDTH && x1 >= 0 && yStart >= 0 && yStart < HEIGHT) {
            // get the cursor line
            screen_char_t* lineAbove = nil;
            screen_char_t* lineBelow = nil;
            theLine = [dataSource getLineAtScreenIndex:yStart];
            if (yStart > 0) {
                lineAbove = [dataSource getLineAtScreenIndex:yStart - 1];
            }
            if (yStart < HEIGHT) {
                lineBelow = [dataSource getLineAtScreenIndex:yStart + 1];
            }
            double_width = 0;
            screen_char_t screenChar = theLine[x1];
            if (x1 == WIDTH) {
                screenChar = theLine[x1 - 1];
                screenChar.code = 0;
            }
            int aChar = screenChar.code;
            if (aChar) {
                if (aChar == DWC_RIGHT && x1 > 0) {
                    x1--;
                    screenChar = theLine[x1];
                    aChar = screenChar.code;
                }
                double_width = (x1 < WIDTH-1) && (theLine[x1+1].code == DWC_RIGHT);
            }
            curX = floor(x1 * charWidth + MARGIN);
            curY = toOrigin ? toOrigin->y + (yStart + 1) * lineHeight - cursorHeight :
                (yStart + [dataSource numberOfLines] - HEIGHT + 1) * lineHeight - cursorHeight;

            NSColor *bgColor;
            if (colorInvertedCursor) {
                if (reversed) {
                    bgColor = [self colorForCode:screenChar.backgroundColor
                              alternateSemantics:screenChar.alternateBackgroundSemantics
                                            bold:screenChar.bold];
                    bgColor = [bgColor colorWithAlphaComponent:alpha];
                } else {
                    bgColor = [self colorForCode:screenChar.foregroundColor
                              alternateSemantics:screenChar.alternateForegroundSemantics
                                            bold:screenChar.bold];
                    bgColor = [bgColor colorWithAlphaComponent:alpha];
                }

                NSMutableArray* constraints = [NSMutableArray arrayWithCapacity:2];
                CGFloat bgBrightness = [self _perceivedBrightness:[bgColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
                if (x1 > 0) {
                    [constraints addObject:[NSNumber numberWithDouble:[self _brightnessOfCharBackground:theLine[x1 - 1]]]];
                }
                if (x1 < WIDTH) {
                    [constraints addObject:[NSNumber numberWithDouble:[self _brightnessOfCharBackground:theLine[x1 + 1]]]];
                }
                if (lineAbove) {
                    [constraints addObject:[NSNumber numberWithDouble:[self _brightnessOfCharBackground:lineAbove[x1]]]];
                }
                if (lineBelow) {
                    [constraints addObject:[NSNumber numberWithDouble:[self _brightnessOfCharBackground:lineBelow[x1]]]];
                }
                if ([self _minimumDistanceOf:bgBrightness fromAnyValueIn:constraints] < 0.5) {
                    CGFloat b = [self _farthestValueFromAnyValueIn:constraints];
                    bgColor = [NSColor colorWithCalibratedRed:b green:b blue:b alpha:1];
                }

                [bgColor set];
            } else {
                bgColor = [self defaultCursorColor];
                [[bgColor colorWithAlphaComponent:alpha] set];
            }

            BOOL frameOnly;
            switch (cursorType_) {
                case CURSOR_BOX:
                    // draw the box
                    if ([[self window] isKeyWindow] &&
                        [[[dataSource session] tab] activeSession] == [dataSource session]) {
                        frameOnly = NO;
                        NSRectFill(NSMakeRect(curX,
                                              curY,
                                              ceil(cursorWidth * (double_width ? 2 : 1)),
                                              cursorHeight));
                    } else {
                        frameOnly = YES;
                        NSFrameRect(NSMakeRect(curX,
                                               curY,
                                               ceil(cursorWidth * (double_width ? 2 : 1)),
                                               cursorHeight));
                    }
                    // draw any character on cursor if we need to
                    if (aChar) {
                        // Have a char at the cursor position.
                        if (colorInvertedCursor && !frameOnly) {
                            int fgColor;
                            BOOL fgAlt;
                            if ([[self window] isKeyWindow]) {
                                // Draw a character in background color when
                                // window is key.
                                fgColor = screenChar.backgroundColor;
                                fgAlt = screenChar.alternateBackgroundSemantics;
                            } else {
                                // Draw character in foreground color when there
                                // is just a frame around it.
                                fgColor = screenChar.foregroundColor;
                                fgAlt = screenChar.alternateForegroundSemantics;
                            }

                            // Pick background color for text if is key window, otherwise use fg color for text.
                            int theColor;
                            BOOL alt;
                            BOOL isBold;
                            if ([[self window] isKeyWindow]) {
                                theColor = screenChar.backgroundColor;
                                alt = screenChar.alternateBackgroundSemantics;
                                isBold = screenChar.bold;
                            } else {
                                theColor = screenChar.foregroundColor;
                                alt = screenChar.alternateForegroundSemantics;
                                isBold = screenChar.bold;
                            }

                            // Ensure text has enough contrast by making it black/white if the char's color would be close to the cursor bg.
                            NSColor* proposedForeground = [[self colorForCode:fgColor
                                                           alternateSemantics:fgAlt
                                                                         bold:screenChar.bold] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
                            CGFloat fgBrightness = [self _perceivedBrightness:proposedForeground];
                            CGFloat bgBrightness = [self _perceivedBrightness:[bgColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
                            NSColor* overrideColor = nil;
                            if (!frameOnly && fabs(fgBrightness - bgBrightness) < 0.5) {
                                // foreground and background are very similar. Just use black and
                                // white.
                                if (bgBrightness < 0.5) {
                                    overrideColor = [self _dimmedColorFrom:[NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:1]];
                                } else {
                                    overrideColor = [self _dimmedColorFrom:[NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1]];
                                }
                            }
                            [self _drawCharacter:screenChar
                                         fgColor:theColor
                              alternateSemantics:alt
                                          fgBold:isBold
                                             AtX:x1 * charWidth + MARGIN
                                               Y:curY + cursorHeight - lineHeight
                                     doubleWidth:double_width
                                   overrideColor:overrideColor];
                        } else {
                            // Non-inverted cursor or cursor is frame
                            int theColor;
                            BOOL alt;
                            BOOL isBold;
                            if ([[self window] isKeyWindow]) {
                                theColor = ALTSEM_CURSOR;
                                alt = YES;
                                isBold = screenChar.bold;
                            } else {
                                theColor = screenChar.foregroundColor;
                                alt = screenChar.alternateForegroundSemantics;
                                isBold = screenChar.bold;
                            }
                            [self _drawCharacter:screenChar
                                         fgColor:theColor
                              alternateSemantics:alt
                                          fgBold:isBold
                                             AtX:x1 * charWidth + MARGIN
                                               Y:curY + cursorHeight - lineHeight
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
    }

    oldCursorX = x1;
    oldCursorY = yStart;
}

- (void)_scrollToLine:(int)line
{
    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = line * lineHeight;
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = lineHeight;
    [self scrollRectToVisible:aFrame];
}

- (void)_scrollToCenterLine:(int)line
{
    NSRect visible = [self visibleRect];
    int visibleLines = (visible.size.height - VMARGIN*2) / lineHeight;
    int lineMargin = (visibleLines - 1) / 2;
    double margin = lineMargin * lineHeight;

    NSRect aFrame;
    aFrame.origin.x = 0;
    aFrame.origin.y = MAX(0, line * lineHeight - margin);
    aFrame.size.width = [self frame].size.width;
    aFrame.size.height = margin * 2 + lineHeight;
    double end = aFrame.origin.y + aFrame.size.height;
    NSRect total = [self frame];
    if (end > total.size.height) {
        double err = end - total.size.height;
        aFrame.size.height -= err;
    }
    [self scrollRectToVisible:aFrame];
}

- (BOOL)_haveHardNewlineAtY:(int)y
{
    screen_char_t *theLine;
    theLine = [dataSource getLineAtIndex:y];
    const int w = [dataSource width];
    return !theLine[w].complexChar && theLine[w].code == EOL_HARD;
}

- (NSString*)_getCharacterAtX:(int)x Y:(int)y
{
    screen_char_t *theLine;
    theLine = [dataSource getLineAtIndex:y];

    if (theLine[x].complexChar) {
        return ComplexCharToStr(theLine[x].code);
    } else {
        return [NSString stringWithCharacters:&theLine[x].code length:1];
    }
}

- (PTYCharType)classifyChar:(unichar)ch
                  isComplex:(BOOL)complex
{
    NSString* aString = CharToStr(ch, complex);
    UTF32Char longChar = CharToLongChar(ch, complex);

    if (longChar == DWC_RIGHT || longChar == DWC_SKIP) {
        return CHARTYPE_DW_FILLER;
    } else if (!longChar ||
               [[NSCharacterSet whitespaceCharacterSet] longCharacterIsMember:longChar] ||
               ch == TAB_FILLER) {
        return CHARTYPE_WHITESPACE;
    } else if ([[NSCharacterSet alphanumericCharacterSet] longCharacterIsMember:longChar] ||
               [[[PreferencePanel sharedInstance] wordChars] rangeOfString:aString].length != 0) {
        return CHARTYPE_WORDCHAR;
    } else {
        // Non-alphanumeric, non-whitespace, non-word, not double-width filler.
        // Miscellaneous symbols, etc.
        return CHARTYPE_OTHER;
    }
}

- (BOOL)shouldSelectCharForWord:(unichar)ch
                      isComplex:(BOOL)complex
                selectWordChars:(BOOL)selectWordChars
{
    switch ([self classifyChar:ch isComplex:complex]) {
        case CHARTYPE_WHITESPACE:
            return !selectWordChars;
            break;

        case CHARTYPE_WORDCHAR:
        case CHARTYPE_DW_FILLER:
            return selectWordChars;
            break;

        case CHARTYPE_OTHER:
            return NO;
            break;
    };
    return NO;
}

static bool IsUrlChar(NSString* str)
{
    if ([str length] == 0) {
        return NO;
    }
    UTF32Char theChar;
    if ([str length] == 1) {
        theChar = [str characterAtIndex:0];
    } else {
        unichar first = [str characterAtIndex:0];
        if (IsHighSurrogate(first)) {
            theChar = DecodeSurrogatePair(first, [str characterAtIndex:1]);
        } else {
            // Use the base character; combining marks won't affect the outcome.
            theChar = first;
        }
    }
    if (!theChar) {
        return NO;
    }

    static NSCharacterSet* urlChars;
    if (!urlChars) {
        urlChars = [[NSCharacterSet characterSetWithCharactersInString:@".?/:;%=&_-,+~#@!*'()"] retain];
    }
    return ([urlChars longCharacterIsMember:theChar] ||
            [[NSCharacterSet alphanumericCharacterSet] longCharacterIsMember:theChar]);
}

- (NSString*)_getURLForX:(int)x
                       y:(int)y
    respectingHardNewlines:(BOOL)respectHardNewlines
{
    int w = [dataSource width];
    int h = [dataSource numberOfLines];
    NSMutableString *url = [NSMutableString string];
    NSString* theChar = [self _getCharacterAtX:x Y:y];

    if (!IsUrlChar(theChar)) {
        return url;
    }

    // Look for a left and right edge bracketed by | characters
    // Look for a left edge
    int leftx = 0;
    for (int xi = x-1, yi = y; 0 <= xi; xi--) {
        NSString* curChar = [self _getCharacterAtX:xi Y:yi];
        if ([curChar isEqualToString:@"|"] &&
            ((yi > 0 && [[self _getCharacterAtX:xi Y:yi-1] isEqualToString:@"|"]) ||
             (yi < h-1 && [[self _getCharacterAtX:xi Y:yi+1] isEqualToString:@"|"]))) {
            leftx = xi+1;
            break;
        }
    }

    // Look for a right edge
    int rightx = w-1;
    for (int xi = x+1, yi = y; xi < w; xi++) {
        NSString* c = [self _getCharacterAtX:xi Y:yi];
        if ([c isEqualToString:@"|"] &&
            ((yi > 0 && [[self _getCharacterAtX:xi Y:yi-1] isEqualToString:@"|"]) ||
             (yi < h-1 && [[self _getCharacterAtX:xi Y:yi+1] isEqualToString:@"|"]))) {
            rightx = xi-1;
            break;
        }
    }

    // Move to the left
    {
        int endx = x-1;
        for (int xi = endx, yi = y; xi >= leftx && 0 <= yi; xi--) {
            NSString* curChar = [self _getCharacterAtX:xi Y:yi];
            if (!IsUrlChar(curChar)) {
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
                if (respectHardNewlines && rightx == w-1 && [self _haveHardNewlineAtY:yi]) {
                    // Hard newline before url
                    break;
                }
                if (rightx < w-1 && ![[self _getCharacterAtX:rightx+1 Y:yi] isEqualToString:@"|"]) {
                    // Was bracketed by |s but the previous line lacks them.
                    break;
                }
                // skip backslashes at the end of the line indicating wrapping.
                xi = rightx;
                while (xi >= leftx && [[self _getCharacterAtX:xi Y:yi] isEqualToString:@"\\"]) {
                    xi--;
                }
                endx = xi;
            }
        }
    }

    // Move to the right
    {
        int startx = x;
        for (int xi = startx+1, yi = y; xi <= rightx && yi < h; xi++) {
            NSString* curChar = [self _getCharacterAtX:xi Y:yi];
            if (!IsUrlChar(curChar)) {
                // Found something non-urly. Append what we have so far.
                [url appendString:[self contentFromX:startx Y:yi ToX:xi Y:yi pad: YES]];
                // skip backslahes that indicate wrapping
                while (x <= rightx && [[self _getCharacterAtX:xi Y:yi] isEqualToString:@"\\"]) {
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
            if (respectHardNewlines && rightx == w-1 && [self _haveHardNewlineAtY:yi]) {
                // Don't wrap URL at hard newline
                break;
            }

            // Wrap to the next line
            if (yi == h-1) {
                // got to the end of the screen.
                break;
            }
            yi++;
            if (leftx > 0 && ![[self _getCharacterAtX:leftx-1 Y:yi] isEqualToString:@"|"]) {
                // Tried to wrap but there was no |, so stop.
                break;
            }
            xi = startx = leftx;
        }
    }

    // Grab the addressbook command
    [url replaceOccurrencesOfString:@"\n"
                         withString:@""
                            options:NSLiteralSearch
                              range:NSMakeRange(0, [url length])];

    return (url);

}

- (BOOL)_stringLooksLikeURL:(NSString*)s
{
    return [s rangeOfRegex:@"^[a-zA-Z]{1,6}:"].location == 0;
}

- (NSString *)_getURLForX:(int)x
                        y:(int)y
{
    NSString* urlIgnoringHardEOL = [self _getURLForX:x y:y respectingHardNewlines:NO];
    NSString* urlRespectingHardEOL = [self _getURLForX:x y:y respectingHardNewlines:YES];
    if (![self _stringLooksLikeURL:urlRespectingHardEOL] &&
        [self _stringLooksLikeURL:urlIgnoringHardEOL]) {
        return urlIgnoringHardEOL;
    } else {
        return urlRespectingHardEOL;
    }
}

- (BOOL) _findMatchingParenthesis: (NSString *) parenthesis withX:(int)X Y:(int)Y
{
    unichar matchingParenthesis, sameParenthesis;
    NSString* theChar;
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
        if (x1 < 0) {
            yStart--;
            x1 = w - 1;
        }
        for (; x1 >= 0 && yStart >= 0; ) {
            theChar = [self _getCharacterAtX:x1 Y:yStart];
            if ([theChar isEqualToString:[NSString stringWithCharacters:&sameParenthesis length:1]]) {
                level++;
            } else if ([theChar isEqualToString:[NSString stringWithCharacters:&matchingParenthesis length:1]]) {
                level--;
                if (level<0) break;
            }
            x1--;
            if (x1 < 0) {
                yStart--;
                x1 = w - 1;
            }
        }
        if (level < 0) {
            startX = x1;
            startY = yStart;
            endX = X+1;
            endY = Y;

            return YES;
        } else {
            return NO;
        }
    } else {
        x1 = X +1;
        yStart = Y;
        if (x1 >= w) {
            yStart++;
            x1 = 0;
        }

        for (; x1 < w && yStart < h; ) {
            theChar = [self _getCharacterAtX:x1 Y:yStart];
            if ([theChar isEqualToString:[NSString stringWithCharacters:&sameParenthesis length:1]]) {
                level++;
            } else if ([theChar isEqualToString:[NSString stringWithCharacters:&matchingParenthesis length:1]]) {
                level--;
                if (level < 0) {
                    break;
                }
            }
            x1++;
            if (x1 >= w) {
                yStart++;
                x1 = 0;
            }
        }
        if (level < 0) {
            startX = X;
            startY = Y;
            endX = x1+1;
            endY = yStart;

            return YES;
        } else {
            return NO;
        }
    }

}

- (unsigned int)_checkForSupportedDragTypes:(id <NSDraggingInfo>)sender
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

- (BOOL)_isBlankLine:(int)y
{
    NSString *lineContents;

    lineContents = [self contentFromX:0
                                    Y:y
                                  ToX:[dataSource width]
                                    Y:y
                                  pad:YES];
    const char* utf8 = [lineContents UTF8String];
    for (int i = 0; utf8[i]; ++i) {
        if (utf8[i] != ' ') {
            return NO;
        }
    }
    return YES;
}


- (void)logWorkingDirectoryAtLine:(long long)line
{
    NSString *workingDirectory = [[dataSource shellTask] getWorkingDirectory];
    [workingDirectoryAtLines addObject:[NSArray arrayWithObjects:
          [NSNumber numberWithLongLong:line],
          workingDirectory,
          nil]];
    if ([workingDirectoryAtLines count] > MAX_WORKING_DIR_COUNT) {
        [workingDirectoryAtLines removeObjectAtIndex:0];
    }
}

- (NSString *)getWorkingDirectoryAtLine:(long long)line
{
    // TODO: use a binary search if we make MAX_WORKING_DIR_COUNT large.

    // Return current directory if not able to log via XTERMCC_WINDOW_TITLE
    if ([workingDirectoryAtLines count] == 0) {
        return [[dataSource shellTask] getWorkingDirectory];
    }

    long long previousLine = [[[workingDirectoryAtLines lastObject] objectAtIndex:0] longLongValue];
    long long currentLine;

    for (int i = [workingDirectoryAtLines count] - 2; i != -1; i--) {

        currentLine = [[[workingDirectoryAtLines objectAtIndex:i] objectAtIndex: 0] longLongValue];

        if (currentLine < line && line <= previousLine) {
            return [[workingDirectoryAtLines objectAtIndex:i] lastObject];
        }

        previousLine = currentLine;
    }

    return [[workingDirectoryAtLines lastObject] lastObject];
}

- (void)_changeDirectory:(NSString *)path
{
    // TODO: Make this more efficient by calculating the shortest path to target folder
    [[dataSource shellTask] writeTask:[[NSString stringWithFormat:@"\3cd \"%@\"; ls\n", path] dataUsingEncoding:[[dataSource session] encoding]]];
}

- (void)_openURL:(NSString *)aURLString atLine:(long long)line
{
    NSString* trimmedURLString;

    trimmedURLString = [aURLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    NSString *workingDirectory = [self getWorkingDirectoryAtLine:line];
    if (![trouter openPath:trimmedURLString workingDirectory:workingDirectory]) {
        [self _openURL:aURLString];
    }

    return;
}

- (void)_openURL:(NSString *)aURLString
{
    NSURL *url;
    NSString* trimmedURLString;

    trimmedURLString = [aURLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    // length returns an unsigned value, so couldn't this just be ==? [TRE]
    if ([trimmedURLString length] <= 0) {
        return;
    }

    // Check for common types of URLs

    NSRange range = [trimmedURLString rangeOfString:@":"];
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

    NSString* escapedString =
        (NSString *)CFURLCreateStringByAddingPercentEscapes(NULL,
                                                            (CFStringRef)trimmedURLString,
                                                            (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                                            NULL,
                                                            kCFStringEncodingUTF8 );

    url = [NSURL URLWithString:escapedString];
    [escapedString release];

    Bookmark *bm = [[PreferencePanel sharedInstance] handlerBookmarkForURL:[url scheme]];

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

- (BOOL)_wasAnyCharSelected
{
    if (oldStartX <= -1 || (oldStartY == oldEndY && oldStartX == oldEndX)) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)_isCharSelectedInRow:(int)row col:(int)col checkOld:(BOOL)old
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

- (void)_settingsChanged:(NSNotification *)notification
{
    advancedFontRendering = [[PreferencePanel sharedInstance] advancedFontRendering];
    strokeThickness = [[PreferencePanel sharedInstance] strokeThickness];
    [self setNeedsDisplay:YES];
}

- (void)_modifyFont:(NSFont*)font into:(PTYFontInfo*)fontInfo
{
    if (fontInfo->font) {
        [self releaseFontInfo:fontInfo];
    }

    fontInfo->font = font;
    [fontInfo->font retain];
    fontInfo->baselineOffset = -(floorf([font leading]) - floorf([font descender]));
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
- (BOOL)updateDirtyRects
{
    BOOL anythingIsBlinking = NO;
    BOOL foundDirty = NO;
    if ([dataSource scrollbackOverflow] != 0) {
        NSAssert([dataSource scrollbackOverflow] == 0, @"updateDirtyRects called with nonzero overflow");
    }
#ifdef DEBUG_DRAWING
    [self appendDebug:[NSString stringWithFormat:@"updateDirtyRects called. Scrollback overflow is %d. Screen is: %@", [dataSource scrollbackOverflow], [dataSource debugString]]];
#endif
    DebugLog(@"updateDirtyRects called");

    // Check each line for dirty selected text
    // If any is found then deselect everything
    [self _deselectDirtySelectedText];

    // Flip blink bit if enough time has passed. Mark blinking cursor dirty
    // when it blinks.
    BOOL redrawBlink = [self _updateBlink];
    int WIDTH = [dataSource width];

    // Any characters that changed selection status since the last update or
    // are blinking should be set dirty.
    anythingIsBlinking = [self _markChangedSelectionAndBlinkDirty:redrawBlink width:WIDTH];

    // Copy selection position to detect change in selected chars next call.
    oldStartX = startX;
    oldStartY = startY;
    oldEndX = endX;
    oldEndY = endY;
    oldSelectMode = selectMode;

    // Redraw lines with dirty characters
    int lineStart = [dataSource numberOfLines] - [dataSource height];
    int lineEnd = [dataSource numberOfLines];
    // lineStart to lineEnd is the region that is the screen when the scrollbar
    // is at the bottom of the frame.
    if (gDebugLogging) {
        DebugLog([NSString stringWithFormat:@"Search lines [%d, %d) for dirty", lineStart, lineEnd]);
    }

#ifdef DEBUG_DRAWING
    NSMutableString* dirtyDebug = [NSMutableString stringWithString:@"updateDirtyRects found these dirty lines:\n"];
    int screenindex=0;
#endif
    BOOL irEnabled = [[PreferencePanel sharedInstance] instantReplay];
    long long totalScrollbackOverflow = [dataSource totalScrollbackOverflow];
    for (int y = lineStart; y < lineEnd; y++) {
        NSMutableData* matches = [resultMap_ objectForKey:[NSNumber numberWithLongLong:y + totalScrollbackOverflow]];
        for (int x = 0; x < WIDTH; x++) {
            int dirtyFlags = [dataSource dirtyAtX:x Y:y-lineStart];
            if (dirtyFlags) {
                if (irEnabled) {
                    if (dirtyFlags & 1) {
                        foundDirty = YES;
                        if (matches) {
                            // Remove highlighted search matches on this line.
                            [resultMap_ removeObjectForKey:[NSNumber numberWithLongLong:y + totalScrollbackOverflow]];
                            matches = nil;
                        }
                    } else {
                        for (int j = x+1; j < WIDTH; ++j) {
                            if ([dataSource dirtyAtX:j Y:y-lineStart] & 1) {
                                foundDirty = YES;
                            }
                        }
                    }
                }
                NSRect dirtyRect = [self visibleRect];
                dirtyRect.origin.y = y*lineHeight;
                dirtyRect.size.height = lineHeight;
                if (gDebugLogging) {
                    DebugLog([NSString stringWithFormat:@"%d is dirty", y]);
                }
                [self setNeedsDisplayInRect:dirtyRect];

#ifdef DEBUG_DRAWING
                char temp[100];
                screen_char_t* p = [dataSource getLineAtScreenIndex:screenindex];
                for (int i = 0; i < WIDTH; ++i) {
                    temp[i] = p[i].complexChar ? '#' : p[i].code;
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
    }

    // Always mark the IME as needing to be drawn to keep things simple.
    if ([self hasMarkedText]) {
        [self invalidateInputMethodEditorRect];
    }

    // Unset the dirty bit for all chars.
    DebugLog(@"updateDirtyRects resetDirty");
#ifdef DEBUG_DRAWING
    [self appendDebug:dirtyDebug];
#endif
    [dataSource resetDirty];

    if (irEnabled && foundDirty) {
        [dataSource saveToDvr];
    }


    if (foundDirty && [[iTermExpose sharedInstance] isVisible]) {
        changedSinceLastExpose_ = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"iTermTabContentsChanged"
                                                            object:nil
                                                          userInfo:nil];
    }

    return blinkAllowed_ && anythingIsBlinking;
}

- (void)invalidateInputMethodEditorRect
{
    if ([dataSource width] == 0) {
        return;
    }
    int imeLines = ([dataSource cursorX] - 1 + [self inputMethodEditorLength] + 1) / [dataSource width] + 1;

    NSRect imeRect = NSMakeRect(MARGIN,
                                ([dataSource cursorY] - 1 + [dataSource numberOfLines] - [dataSource height]) * lineHeight,
                                [dataSource width] * charWidth,
                                imeLines * lineHeight);
    [self setNeedsDisplayInRect:imeRect];
}

- (void)moveSelectionEndpointToX:(int)x Y:(int)y locationInTextView:(NSPoint)locationInTextView
{
    int width = [dataSource width];
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

    int tmpX1, tmpX2, tmpY1, tmpY2;
    switch (selectMode) {
        case SELECT_CHAR:
        case SELECT_BOX:
            endX = x + 1;
            endY = y;
            break;

        case SELECT_SMART:
        case SELECT_WORD:
            // First, put the word around x,y in tmp[XY][12].
            if (selectMode == SELECT_WORD) {
                [self getWordForX:x
                                y:y
                           startX:&tmpX1
                           startY:&tmpY1
                             endX:&tmpX2
                             endY:&tmpY2];
            } else {
                // Set start/end x/y to new word
                [self smartSelectAtX:x
                                   y:y
                            toStartX:&tmpX1
                            toStartY:&tmpY1
                              toEndX:&tmpX2
                              toEndY:&tmpY2];
            }

            // Now the complicated bit...
            if ((startX + (startY * width)) < (tmpX2 + (tmpY2 * width))) {
                // We go forwards in our selection session... and...
                if ((startX + (startY * width)) > (endX + (endY * width))) {
                    // This will always be called, if the selection direction is changed from backwards to forwards,
                    // that is the user changed his mind and now wants to select text AFTER the initial starting
                    // word, AND we come back to the initial starting word.
                    // In this case, our X starting and ending values will be SWAPPED, as swapping the values is
                    // necessary for backwards selection (forward selection: start|(several) word(s)|end---->,
                    //                                    backward selection: <----|end|(several) word(s)|start)
                    // getWordForX will report a word range with a half open interval (a <= x < b). b-1 will thus be
                    // the LAST character of the current word. If we call the function again with new_a = b, it will
                    // report the boundaries for the next word in line (which by definition will always be a white
                    // space, iff we're in SELECT_WORD mode.)
                    // Thus calling the function with b-1 will report the correct values for the CURRENT (read as in
                    // NOT next word).
                    // Afterwards, selecting will continue normally.
                    int tx1, tx2, ty1, ty2;
                    if (selectMode == SELECT_WORD) {
                        [self getWordForX:startX-1
                                        y:startY
                                   startX:&tx1
                                   startY:&ty1
                                     endX:&tx2
                                     endY:&ty2];
                    } else {
                        [self smartSelectAtX:startX-1
                                           y:startY
                                    toStartX:&tx1
                                    toStartY:&ty1
                                      toEndX:&tx2
                                      toEndY:&ty2];
                    }
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
                    if (selectMode == SELECT_WORD) {
                        [self getWordForX:startX
                                        y:startY
                                   startX:&tx1
                                   startY:&ty1
                                     endX:&tx2
                                     endY:&ty2];
                    } else {
                        [self smartSelectAtX:startX
                                           y:startY
                                    toStartX:&tx1
                                    toStartY:&ty1
                                      toEndX:&tx2
                                      toEndY:&ty2];
                    }
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
    [[[self dataSource] session] refreshAndStartTimerIfNeeded];
}

- (void)_deselectDirtySelectedText
{
    if (![self isAnyCharSelected]) {
        return;
    }

    int width = [dataSource width];
    int lineStart = [dataSource numberOfLines] - [dataSource height];
    int lineEnd = [dataSource numberOfLines];
    int cursorX = [dataSource cursorX] - 1;
    int cursorY = [dataSource cursorY] + [dataSource numberOfLines] - [dataSource height] - 1;
    for (int y = lineStart; y < lineEnd && startX > -1; y++) {
        for (int x = 0; x < width; x++) {
            BOOL isSelected = [self _isCharSelectedInRow:y col:x checkOld:NO];
            BOOL isCursor = (x == cursorX && y == cursorY);
            if ([dataSource isDirtyAtX:x Y:y-lineStart] && isSelected && !isCursor) {
                // Don't call [self deselect] as it would recurse back here
                startX = -1;
                DebugLog(@"found selected dirty noncursor");
                break;
            }
        }
    }
}

- (BOOL)_updateBlink
{
    // Time to redraw blinking text or cursor?
    struct timeval now;
    BOOL redrawBlink = NO;
    gettimeofday(&now, NULL);
    long long nowTenths = now.tv_sec * 10 + now.tv_usec / 100000;
    long long lastBlinkTenths = lastBlink.tv_sec * 10 + lastBlink.tv_usec / 100000;
    if (nowTenths >= lastBlinkTenths + 7) {
        blinkShow = !blinkShow;
        lastBlink = now;
        redrawBlink = YES;

        if ([self blinkingCursor] &&
            [[self window] isKeyWindow]) {
            // Blink flag flipped and there is a blinking cursor. Mark it dirty.
            int cursorX = [dataSource cursorX] - 1;
            int cursorY = [dataSource cursorY] - 1;
            // Set a different bit for the cursor's dirty position because we don't
            // want to save an instant replay from when only the cursor is dirty.
            [dataSource setCharDirtyAtX:cursorX Y:cursorY value:2];
        }
        DebugLog(@"time to redraw blinking text");
    }
  return redrawBlink;
}

- (BOOL)_markChangedSelectionAndBlinkDirty:(BOOL)redrawBlink width:(int)width
{
    BOOL anyBlinkers = NO;
    // Visible chars that have changed selection status are dirty
    // Also mark blinking text as dirty if needed
    int lineStart = ([self visibleRect].origin.y + VMARGIN) / lineHeight;  // add VMARGIN because stuff under top margin isn't visible.
    int lineEnd = ceil(([self visibleRect].origin.y + [self visibleRect].size.height - [self excess]) / lineHeight);
    if (lineStart < 0) {
        lineStart = 0;
    }
    if (lineEnd > [dataSource numberOfLines]) {
        lineEnd = [dataSource numberOfLines];
    }
    if ([self isAnyCharSelected] || [self _wasAnyCharSelected]) {
        // Mark blinking or selection-changed characters as dirty
        for (int y = lineStart; y < lineEnd; y++) {
            screen_char_t* theLine = [dataSource getLineAtIndex:y];
            for (int x = 0; x < width; x++) {
                BOOL isSelected = [self _isCharSelectedInRow:y col:x checkOld:NO];
                BOOL wasSelected = [self _isCharSelectedInRow:y col:x checkOld:YES];
                BOOL charBlinks = [self _charBlinks:theLine[x]];
                anyBlinkers |= charBlinks;
                BOOL blinked = redrawBlink && charBlinks;
                if (isSelected != wasSelected || blinked) {
                    NSRect dirtyRect = [self visibleRect];
                    dirtyRect.origin.y = y*lineHeight;
                    dirtyRect.size.height = lineHeight;
                    if (gDebugLogging) {
                        DebugLog([NSString stringWithFormat:@"found selection change/blink at %d,%d", x, y]);
                    }
                    [self setNeedsDisplayInRect:dirtyRect];
                    break;
                }
            }
        }
    } else {
        // Mark blinking text as dirty
        for (int y = lineStart; y < lineEnd; y++) {
            screen_char_t* theLine = [dataSource getLineAtIndex:y];
            for (int x = 0; x < width; x++) {
                BOOL charBlinks = [self _charBlinks:theLine[x]];
                anyBlinkers |= charBlinks;
                BOOL blinked = redrawBlink && charBlinks;
                if (blinked) {
                    NSRect dirtyRect = [self visibleRect];
                    dirtyRect.origin.y = y*lineHeight;
                    dirtyRect.size.height = lineHeight;
                    if (gDebugLogging) {
                        DebugLog([NSString stringWithFormat:@"found selection change/blink at %d,%d", x, y]);
                    }
                    [self setNeedsDisplayInRect:dirtyRect];
                    break;
                }
            }
        }
    }
    return anyBlinkers;
}

@end
