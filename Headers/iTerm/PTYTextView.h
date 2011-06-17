// -*- mode:objc -*-
/*
 **  PTYTextView.h
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

#import <Cocoa/Cocoa.h>
#import <iTerm/iTerm.h>
#import "ScreenChar.h"
#import "PreferencePanel.h"
#import "Trouter.h"

#include <sys/time.h>
#define PRETTY_BOLD

#define MARGIN  5
#define VMARGIN 2
#define COLOR_KEY_SIZE 4

@class VT100Screen;

enum { SELECT_CHAR, SELECT_WORD, SELECT_LINE, SELECT_SMART, SELECT_BOX };

// A collection of data about a font.
struct PTYFontInfo {
    NSFont* font;  // Toll-free bridged to CTFontRef

    // Metrics
    double baselineOffset;

    struct PTYFontInfo* boldVersion;  // may be NULL
};
typedef struct PTYFontInfo PTYFontInfo;

@interface PTYTextView : NSView <NSTextInput>
{
    // This is a flag to let us know whether we are handling this
    // particular drag and drop operation. We are using it because
    // the prepareDragOperation and performDragOperation of the
    // parent NSTextView class return "YES" even if the parent
    // cannot handle the drag type. To make matters worse, the
    // concludeDragOperation does not have any return value.
    // This all results in the inability to test whether the
    // parent could handle the drag type properly. Is this a Cocoa
    // implementation bug?
    // Fortunately, the draggingEntered and draggingUpdated methods
    // seem to return a real status, based on which we can set this flag.
    BOOL extendedDragNDrop;

    // anti-alias flags
    BOOL asciiAntiAlias;
    BOOL nonasciiAntiAlias;

    // option to not render in bold
    BOOL useBoldFont;
    
    // Option to draw bold text as brighter colors.
    BOOL useBrightBold;
    
    // NSTextInput support
    BOOL IM_INPUT_INSERT;
    NSRange IM_INPUT_SELRANGE;
    NSRange IM_INPUT_MARKEDRANGE;
    NSDictionary *markedTextAttributes;
    NSAttributedString *markedText;

    BOOL CURSOR;
    BOOL colorInvertedCursor;

    // geometry
    double lineHeight;
    double lineWidth;
    double charWidth;
    double charWidthWithoutSpacing, charHeightWithoutSpacing;
    double horizontalSpacing_;
    double  verticalSpacing_;

    PTYFontInfo primaryFont;
    PTYFontInfo secondaryFont;

    NSColor* colorTable[256];
    NSColor* defaultFGColor;
    NSColor* defaultBGColor;
    NSColor* defaultBoldColor;
    NSColor* defaultCursorColor;
    NSColor* selectionColor;
    NSColor* selectedTextColor;
    NSColor* cursorTextColor;

    // transparency
    double transparency;

    // data source
    VT100Screen *dataSource;
    id _delegate;

    //selection
    int startX, startY, endX, endY;
    int oldStartX, oldStartY, oldEndX, oldEndY;
    char oldSelectMode;
    BOOL mouseDown;
    BOOL mouseDragged;
    char selectMode;
    BOOL mouseDownOnSelection;
    NSEvent *mouseDownEvent;

    //find support
    int lastFindStartX, lastFindEndX;
    // this includes all the lines since the beginning of time. It is stable.
    long long absLastFindStartY, absLastFindEndY;

    BOOL reportingMouseDown;

    // blinking cursor
    BOOL blinkingCursor;
    BOOL showCursor;
    BOOL blinkShow;
    struct timeval lastBlink;
    int oldCursorX, oldCursorY;

    BOOL blinkAllowed_;

    // trackingRect tab
    NSTrackingRectTag trackingRectTag;

    BOOL keyIsARepeat;

    // Is a find currently executing?
    BOOL _findInProgress;

    // Previous tracking rect to avoid expensive calls to addTrackingRect.
    NSRect _trackingRect;

    NSMutableDictionary* fallbackFonts;

    // Indicates if a selection that scrolls the window is in progress.
    // Negative value: scroll up.
    // Positive value: scroll down.
    // Zero: don't scroll.
    int selectionScrollDirection;
    NSTimeInterval lastSelectionScroll;

    // Scrolls view when you drag a selection to top or bottom of view.
    NSTimer* selectionScrollTimer;
    double prevScrollDelay;
    int scrollingX;
    int scrollingY;
    NSPoint scrollingLocation;

    // This gives the number of lines added to the bottom of the frame that do
    // not correspond to a line in the dataSource. They are used solely for
    // IME text.
    int imeOffset;

    // Last position that accessibility was read up to.
    int accX;
    int accY;

    BOOL advancedFontRendering;
    double strokeThickness;
    double minimumContrast_;

    BOOL changedSinceLastExpose_;

    double dimmingAmount_;

    // The string last searched for.
    NSString* findString_;

    // The set of SearchResult objects for which matches have been found.
    NSMutableArray* findResults_;

    // The next offset into findResults_ where values from findResults_ should
    // be added to the map.
    int nextOffset_;

    // True if a result has been highlighted & scrolled to.
    BOOL foundResult_;

    // Maps an absolute line number (NSNumber longlong) to an NSData bit array
    // with one bit per cell indicating whether that cell is a match.
    NSMutableDictionary* resultMap_;

    // True if the last search was forward, flase if backward.
    BOOL searchingForward_;

    // Offset value for last search.
    int findOffset_;

    // True if trying to find a result before/after current selection to
    // highlight.
    BOOL searchingForNextResult_;

    // True if the last search was case insensitive.
    BOOL findIgnoreCase_;

    // True if the last search was for a regex.
    BOOL findRegex_;

    // Time that the flashing bell's alpha value was last adjusted.
    NSDate* lastFlashUpdate_;

    // Alpha value of flashing bell graphic.
    double flashing_;

    enum {
        FlashBell, FlashWrapToTop, FlashWrapToBottom
    } flashImage_;

    ITermCursorType cursorType_;

    // Works around an apparent OS bug where we get drag events without a mousedown.
    BOOL dragOk_;

    // Semantic history controller
    Trouter* trouter;

    // Array of (line number, pwd) arrays, sorted by line number. Line numbers are absolute.
    NSMutableArray *workingDirectoryAtLines;

    // Saves the monotonically increasing event number of a first-mouse click, which disallows
    // selection.
    int firstMouseEventNumber_;

    // For accessibility. This is a giant string with the entire scrollback buffer plus screen concatenated with newlines for hard eol's.
    NSMutableString* allText_;
    // For accessibility. This is the indices at which newlines occur in allText_, ignoring multi-char compositing characters.
    NSMutableArray* lineBreakIndexOffsets_;
    // For accessibility. This is the actual indices at which newlines occcur in allText_.
    NSMutableArray* lineBreakCharOffsets_;
}

+ (NSCursor *)textViewCursor;
+ (NSSize)charSizeForFont:(NSFont*)aFont horizontalSpacing:(double)hspace verticalSpacing:(double)vspace;
- (id)initWithFrame:(NSRect)aRect;
- (void)dealloc;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;
- (BOOL)isFlipped;
- (BOOL)isOpaque;
- (BOOL)getAndResetChangedSinceLastExpose;
- (BOOL)shouldDrawInsertionPoint;
- (void)drawRect:(NSRect)rect;
- (void)drawRect:(NSRect)rect to:(NSPoint*)toOrigin;
- (void)keyDown:(NSEvent *)event;
- (BOOL)keyIsARepeat;
- (void)mouseExited:(NSEvent *)event;
- (void)mouseEntered:(NSEvent *)event;
- (void)mouseDown:(NSEvent *)event;
- (BOOL)mouseDownImpl:(NSEvent*)event;
- (void)mouseUp:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;
- (void)otherMouseDown: (NSEvent *) event;
- (void)otherMouseUp:(NSEvent *)event;
- (void)otherMouseDragged:(NSEvent *)event;
- (void)rightMouseDown:(NSEvent *)event;
- (void)rightMouseUp:(NSEvent *)event;
- (void)rightMouseDragged:(NSEvent *)event;
- (void)scrollWheel:(NSEvent *)event;
- (NSString *)contentFromX:(int)startx Y:(int)starty ToX:(int)endx Y:(int)endy pad: (BOOL) pad;
- (NSString*)contentInBoxFromX:(int)startx Y:(int)starty ToX:(int)nonInclusiveEndx Y:(int)endy pad: (BOOL) pad;
- (NSString *)selectedText;
- (NSString *)selectedTextWithPad: (BOOL) pad;
- (NSString *)content;
- (void)copy:(id)sender;
- (void)paste:(id)sender;
- (void)pasteSelection:(id)sender;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)changeFont:(id)sender;
- (NSMenu *)menuForEvent:(NSEvent *)theEvent;
- (void)browse:(id)sender;
- (void)searchInBrowser:(id)sender;
- (void)mail:(id)sender;
// Cause the next find to start at the top/bottom of the buffer
- (void)resetFindCursor;

- (BOOL)growSelectionLeft;
- (void)growSelectionRight;

//get/set methods
- (NSFont *)font;
- (NSFont *)nafont;
- (void)setFont:(NSFont*)aFont nafont:(NSFont *)naFont horizontalSpacing:(double)horizontalSpacing verticalSpacing:(double)verticalSpacing;
- (NSRect)scrollViewContentSize;
- (void)setAntiAlias:(BOOL)asciiAA nonAscii:(BOOL)nonAsciiAA;
- (BOOL)useBoldFont;
- (void)setUseBoldFont:(BOOL)boldFlag;
- (void)setUseBrightBold:(BOOL)flag;
- (BOOL)blinkingCursor;
- (void)setBlinkingCursor:(BOOL)bFlag;
- (void)setBlinkAllowed:(BOOL)value;
- (void)setCursorType:(ITermCursorType)value;

//color stuff
- (NSColor*)defaultFGColor;
- (NSColor*)defaultBGColor;
- (NSColor*)defaultBoldColor;
- (NSColor*)colorForCode:(int)theIndex alternateSemantics:(BOOL)alt bold:(BOOL)isBold;
- (NSColor*)selectionColor;
- (NSColor*)defaultCursorColor;
- (NSColor*)selectedTextColor;
- (NSColor*)cursorTextColor;
- (void)setFGColor:(NSColor*)color;
- (void)setBGColor:(NSColor*)color;
- (void)setBoldColor:(NSColor*)color;
- (void)setColorTable:(int) theIndex color:(NSColor *) c;
- (void)setSelectionColor:(NSColor *)aColor;
- (void)setCursorColor:(NSColor*)color;
- (void)setSelectedTextColor:(NSColor *)aColor;
- (void)setCursorTextColor:(NSColor*)color;

- (int)selectionStartX;
- (int)selectionStartY;
- (int)selectionEndX;
- (int)selectionEndY;
- (void)setSelectionFromX:(int)fromX fromY:(int)fromY toX:(int)toX toY:(int)toY;

- (double)excess;


- (NSDictionary*)markedTextAttributes;
- (void)setMarkedTextAttributes:(NSDictionary*)attr;

- (id)dataSource;
- (void)setDataSource:(id)aDataSource;
- (id)delegate;
- (void)setDelegate:(id)delegate;
- (double)lineHeight;
- (void)setLineHeight:(double)aLineHeight;
- (double)charWidth;
- (void)setCharWidth:(double)width;

// Update the scroll position and schedule a redraw. Returns true if anything
// onscreen is blinking.
- (BOOL)refresh;
- (void)setFrameSize:(NSSize)aSize;
- (void)showCursor;
- (void)hideCursor;

// selection
- (IBAction)selectAll:(id)sender;
- (void)deselect;

// transparency
- (double)transparency;
- (void)setTransparency:(double)fVal;
- (BOOL)useTransparency;

- (void)setSmartCursorColor:(BOOL)value;
- (void)setMinimumContrast:(double)value;

// Dim all colors towards gray
- (void)setDimmingAmount:(double)value;

//
// Drag and Drop methods for our text view
//
- (unsigned int)draggingEntered: (id<NSDraggingInfo>) sender;
- (unsigned int)draggingUpdated: (id<NSDraggingInfo>) sender;
- (void)draggingExited: (id<NSDraggingInfo>) sender;
- (BOOL)prepareForDragOperation: (id<NSDraggingInfo>) sender;
- (BOOL)performDragOperation: (id<NSDraggingInfo>) sender;
- (void)concludeDragOperation: (id<NSDraggingInfo>) sender;

// Cursor control
- (void)resetCursorRects;

// Scrolling control
- (NSRect)adjustScroll:(NSRect)proposedVisibleRect;
- (void)scrollLineUp:(id)sender;
- (void)scrollLineDown:(id)sender;
- (void)scrollPageUp:(id)sender;
- (void)scrollPageDown:(id)sender;
- (void)scrollHome;
- (void)scrollEnd;
- (void)scrollToAbsoluteOffset:(long long)absOff height:(int)height;
- (void)scrollToSelection;


    // Save method
- (void)saveDocumentAs:(id)sender;
- (void)print:(id)sender;
- (void)printContent:(NSString *)aString;

// Find method
- (BOOL)findString:(NSString*)aString
  forwardDirection:(BOOL)direction
      ignoringCase:(BOOL)ignoreCase
             regex:(BOOL)regex
        withOffset:(int)offset;

// Remove highlighted terms from previous search.
- (void)clearHighlights;

// NSTextInput
- (void)insertText:(id)aString;
- (void)setMarkedText:(id)aString selectedRange:(NSRange)selRange;
- (void)unmarkText;
- (BOOL)hasMarkedText;
- (NSRange)markedRange;
- (NSRange)selectedRange;
- (NSArray *)validAttributesForMarkedText;
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)theRange;
- (void)doCommandBySelector:(SEL)aSelector;
- (unsigned int)characterIndexForPoint:(NSPoint)thePoint;
- (long)conversationIdentifier;
- (NSRect)firstRectForCharacterRange:(NSRange)theRange;

    // service stuff
- (id)validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType;
- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard types:(NSArray *)types;
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard;
- (BOOL)findInProgress;
- (BOOL)continueFind;
- (double)horizontalSpacing;
- (double)verticalSpacing;

// This textview is about to become invisible because another tab is selected.
- (void)aboutToHide;

// Flash a graphic. See the enum for flashImage_.
- (void)beginFlash:(int)image;

- (void)drawFlippedBackground:(NSRect)bgRect toPoint:(NSPoint)dest;
- (void)drawBackground:(NSRect)bgRect;
- (void)drawBackground:(NSRect)bgRect toPoint:(NSPoint)dest;

- (long long)absoluteScrollPosition;

// Returns true if any character in the buffer is selected.
- (BOOL)isAnyCharSelected;

- (void)clearMatches;

// Clear working directories for when buffer is cleared
- (void)clearWorkingDirectories;
- (NSString *)getWordForX:(int)x
                        y:(int)y
                   startX:(int *)startx
                   startY:(int *)starty
                     endX:(int *)endx
                     endY:(int *)endy;

@end

//
// private methods
//
@interface PTYTextView (Private)

// Types of characters. Used when classifying characters for word selection.
typedef enum {
    CHARTYPE_WHITESPACE,  // whitespace chars or NUL
    CHARTYPE_WORDCHAR,    // Any character considered part of a word, including user-defined chars.
    CHARTYPE_DW_FILLER,   // Double-width character effluvia.
    CHARTYPE_OTHER,       // Symbols, etc. Anything that doesn't fall into the other categories.
} PTYCharType;

- (void)modifyFont:(NSFont*)font info:(PTYFontInfo*)fontInfo;
- (void)releaseFontInfo:(PTYFontInfo*)fontInfo;

- (unsigned int) _checkForSupportedDragTypes:(id <NSDraggingInfo>) sender;

- (void) _scrollToLine:(int)line;
- (void)_scrollToCenterLine:(int)line;
- (BOOL)shouldSelectCharForWord:(unichar)ch
                      isComplex:(BOOL)compled
                selectWordChars:(BOOL)selectWordChars;

- (PTYCharType)classifyChar:(unichar)ch
                  isComplex:(BOOL)complex;

- (NSString *)_getURLForX:(int)x y:(int)y;
// Returns true if any char in the line is blinking.
- (BOOL)_drawLine:(int)line AtY:(double)curY toPoint:(NSPoint*)toPoint;
- (void)_drawCursor;
- (void)_drawCursorTo:(NSPoint*)toOrigin;
- (void)_drawCharacter:(screen_char_t)screenChar
               fgColor:(int)fgColor
    alternateSemantics:(BOOL)fgAlt
                fgBold:(BOOL)fgBold
                   AtX:(double)X
                     Y:(double)Y
           doubleWidth:(BOOL)double_width
         overrideColor:(NSColor*)overrideColor;

- (BOOL)_isBlankLine:(int)y;
- (void)_openURL:(NSString *)aURLString;
- (void)_openURL:(NSString *)aURLString atLine:(long long)line;

// Snapshot working directory for Trouter
- (void)logWorkingDirectoryAtLine:(long long)line;
- (NSString *)getWorkingDirectoryAtLine:(long long)line;

// Trouter change directory
- (void)_changeDirectory:(NSString *)path;

- (BOOL)_findMatchingParenthesis:(NSString *)parenthesis withX:(int)X Y:(int)Y;
- (void)_dragText:(NSString *)aString forEvent:(NSEvent *)theEvent;
- (BOOL)_isCharSelectedInRow:(int)row col:(int)col checkOld:(BOOL)old;
- (void)_settingsChanged:(NSNotification *)notification;
- (void)_modifyFont:(NSFont*)font into:(PTYFontInfo*)fontInfo;
- (PTYFontInfo*)getFontForChar:(UniChar)ch
                     isComplex:(BOOL)complex
                       fgColor:(int)fgColor
                    renderBold:(BOOL*)renderBold;

- (PTYFontInfo*)getOrAddFallbackFont:(NSFont*)font;
- (void)releaseAllFallbackFonts;
// Returns true if any onscreen text is blinking
- (BOOL)updateDirtyRects;
- (BOOL)isFutureTabSelectedAfterX:(int)x Y:(int)y;
- (BOOL)isTabFillerOrphanAtX:(int)x Y:(int)y;
- (void)moveSelectionEndpointToX:(int)x Y:(int)y locationInTextView:(NSPoint)locationInTextView;

// Compute the number of single-wdith character spans that the input method
// text takes up.
- (int)inputMethodEditorLength;

// Mark the entire input method editor text area as needing a redraw.
- (void)invalidateInputMethodEditorRect;

// Return the number of pixels tall to draw the cursor.
- (double)cursorHeight;

// Draw the contents of the input method editor beginning at some location, 
// usually the cursor position.
// xStart, yStart: cell coordinates
// width, height: cell width, height of screen
// cursorHeight: cursor height in pixels
- (BOOL)drawInputMethodEditorTextAt:(int)xStart y:(int)yStart width:(int)width height:(int)height cursorHeight:(double)cursorHeight;

- (BOOL)_wasAnyCharSelected;

- (void)_deselectDirtySelectedText;
- (BOOL) _updateBlink;
// Returns true if any onscreen char is blinking.
- (BOOL)_markChangedSelectionAndBlinkDirty:(BOOL)redrawBlink width:(int)width;

@end

