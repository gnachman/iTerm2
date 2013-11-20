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
#import "iTerm.h"
#import "ScreenChar.h"
#import "PreferencePanel.h"
#import "Trouter.h"
#import "LineBuffer.h"
#import "PointerController.h"
#import "PTYFontInfo.h"
#import "CharacterRun.h"

#include <sys/time.h>
#define PRETTY_BOLD

#define MARGIN  5
#define VMARGIN 2
#define COLOR_KEY_SIZE 4

@class MovingAverage;
@class PTYScrollView;
@class PTYSession;  // TODO: Remove this after PTYTextView doesn't depend directly on PTYSession
@class PTYTask;
@class SearchResult;
@class ThreeFingerTapGestureRecognizer;
@class VT100Screen;
@class VT100Terminal;
@protocol TrouterDelegate;

@protocol PTYTextViewDelegate <NSObject>

- (BOOL)xtermMouseReporting;
- (BOOL)isPasting;
- (void)queueKeyDown:(NSEvent *)event;
- (void)keyDown:(NSEvent *)event;
- (BOOL)hasActionableKeyMappingForEvent:(NSEvent *)event;
- (int)optionKey;
- (int)rightOptionKey;
// Contextual menu
- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu;
- (void)pasteString:(NSString *)aString;
- (void)paste:(id)sender;
- (void)textViewFontDidChange;
- (PTYScrollView *)SCROLLVIEW;
- (void)sendEscapeSequence:(NSString *)text;
- (void)sendHexCode:(NSString *)codes;
- (void)sendText:(NSString *)text;
- (void)launchCoprocessWithCommand:(NSString *)command;
- (void)insertText:(NSString *)string;
- (PTYTask *)SHELL;

@end

// Amount of time to highlight the cursor after beginFindCursor:YES
static const double kFindCursorHoldTime = 1;
enum {
    SELECT_CHAR,
    SELECT_WORD,
    SELECT_LINE,
    SELECT_SMART,
    SELECT_BOX,
    SELECT_WHOLE_LINE
};

@interface FindCursorView : NSView {
    NSPoint cursor;
}

@property (nonatomic, assign) NSPoint cursor;

@end

@class CRunStorage;

@interface PTYTextView : NSView <NSTextInput, PointerControllerDelegate, TrouterDelegate>
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

    // option to not render in italic
    BOOL useItalicFont;

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

    PTYFontInfo *primaryFont;
    PTYFontInfo *secondaryFont;

    NSColor* colorTable[256];
    NSColor* defaultFGColor;
    NSColor* defaultBGColor;
    NSColor* defaultBoldColor;
    NSColor* defaultCursorColor;
    NSColor* selectionColor;
    NSColor* unfocusedSelectionColor;
    NSColor* selectedTextColor;
    NSColor* cursorTextColor;

    // transparency
    double transparency;
    double blend;

    // data source
    id<PTYTextViewDataSource> dataSource;
    id<PTYTextViewDelegate> _delegate;

    // selection goes from startX,startY to endX,endY. The end may be before or after the start.
    // While the selection is being made (the mouse was clicked and is being dragged) the end
    // position moves with the cursor.
    int startX, startY, endX, endY;
    int oldStartX, oldStartY, oldEndX, oldEndY;

    // Underlined selection range (inclusive of all values), indicating clickable url.
    int _underlineStartX, _underlineStartY, _underlineEndX, _underlineEndY;
    char oldSelectMode;
    BOOL mouseDown;
    BOOL mouseDragged;
    char selectMode;
    BOOL mouseDownOnSelection;
    NSEvent *mouseDownEvent;
    int lastReportedX_, lastReportedY_;

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
    NSTrackingArea *trackingArea;

    BOOL keyIsARepeat;

    // Is a find currently executing?
    BOOL _findInProgress;

    // Previous tracking rect to avoid expensive calls to addTrackingRect.
    NSRect _trackingRect;

    // Maps a NSNumber int consisting of color index, alternate fg semantics
    // flag, bold flag, and background flag to NSColor*s.
    NSMutableDictionary* dimmedColorCache_;

    // Dimmed background color with alpha.
    NSColor *cachedBackgroundColor_;
    double cachedBackgroundColorAlpha_;  // cached alpha value (comparable to another double)

    // Previuos contrasting color returned
    NSColor *memoizedContrastingColor_;
    double memoizedMainRGB_[4];  // rgba for "main" color memoized.
    double memoizedOtherRGB_[3];  // rgb for "other" color memoized.

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

    // Image currently flashing.
    FlashImage flashImage_;

    ITermCursorType cursorType_;

    // Works around an apparent OS bug where we get drag events without a mousedown.
    BOOL dragOk_;

    // Semantic history controller
    Trouter* trouter;

    // Flag to make sure a Trouter drag check is only one once per drag
    BOOL trouterDragged;

    // Array of (line number, pwd) arrays, sorted by line number. Line numbers are absolute.
    NSMutableArray *workingDirectoryAtLines;

    // Saves the monotonically increasing event number of a first-mouse click, which disallows
    // selection.
    int firstMouseEventNumber_;

    // For accessibility. This is a giant string with the entire scrollback buffer plus screen concatenated with newlines for hard eol's.
    NSMutableString* allText_;
    // For accessibility. This is the indices at which soft newlines occur in allText_, ignoring multi-char compositing characters.
    NSMutableArray* lineBreakIndexOffsets_;
    // For accessibility. This is the actual indices at which soft newlines occcur in allText_.
    NSMutableArray* lineBreakCharOffsets_;

    // Brightness of background color
    double backgroundBrightness_;

    // Dim everything but the default background color.
    BOOL dimOnlyText_;

    // For find-cursor animation
    NSWindow *findCursorWindow_;
    FindCursorView *findCursorView_;
    NSTimer *findCursorTeardownTimer_;
    NSTimer *findCursorBlinkTimer_;
    BOOL autoHideFindCursor_;
    NSPoint imeCursorLastPos_;

    // Number of fingers currently down (only valid if three finger click
    // emulates middle button)
    int numTouches_;

    // If true, ignore the next mouse up because it's due to a three finger
    // mouseDown.
    BOOL mouseDownIsThreeFingerClick_;

    // Is the mouse inside our view?
    BOOL mouseInRect_;

    // Time the selection last changed at or 0 if there's no selection.
    NSTimeInterval selectionTime_;

    // Dictionaries with a regex and a priority.
    NSArray *smartSelectionRules_;

    // Show a background indicator when in broadcast input mode
    BOOL useBackgroundIndicator_;

    // Find context just after initialization.
    FindContext *initialFindContext_;

    PointerController *pointer_;
	NSCursor *cursor_;

    // True while the context menu is being opened.
    BOOL openingContextMenu_;

	// Experimental feature gated by ThreeFingerTapEmulatesThreeFingerClick bool pref.
    ThreeFingerTapGestureRecognizer *threeFingerTapGestureRecognizer_;

    // Position of cursor last time we looked. Since the cursor might move around a lot between
    // calls to -updateDirtyRects without making any changes, we only redraw the old and new cursor
    // positions.
    int prevCursorX, prevCursorY;

    MovingAverage *drawRectDuration_, *drawRectInterval_;
	// Current font. Only valid for the duration of a single drawing context.
    NSFont *selectedFont_;

    // Used by _drawCursorTo: to remember the last time the cursor moved to avoid drawing a blinked-out
    // cursor while it's moving.
    NSTimeInterval lastTimeCursorMoved_;

    // If set, the last-modified time of each line on the screen is shown on the right side of the display.
    BOOL showTimestamps_;
    float _antiAliasedShift;  // Amount to shift anti-aliased text by horizontally to simulate bold
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
- (void)updateCursor:(NSEvent *)event;
- (void)swipeWithEvent:(NSEvent *)event;
- (void)mouseExited:(NSEvent *)event;
- (void)mouseEntered:(NSEvent *)event;
- (void)mouseDown:(NSEvent *)event;
- (BOOL)mouseDownImpl:(NSEvent*)event;
- (void)mouseUp:(NSEvent *)event;
- (void)mouseMoved:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;
- (void)otherMouseDown: (NSEvent *) event;
- (void)otherMouseUp:(NSEvent *)event;
- (void)otherMouseDragged:(NSEvent *)event;
- (void)rightMouseDown:(NSEvent *)event;
- (void)rightMouseUp:(NSEvent *)event;
- (void)rightMouseDragged:(NSEvent *)event;
- (void)scrollWheel:(NSEvent *)event;

- (void)pasteFromClipboardWithEvent:(NSEvent *)event;
- (void)pasteFromSelectionWithEvent:(NSEvent *)event;
- (void)openTargetWithEvent:(NSEvent *)event;
- (void)openTargetInBackgroundWithEvent:(NSEvent *)event;
- (void)smartSelectWithEvent:(NSEvent *)event;
- (void)smartSelectIgnoringNewlinesWithEvent:(NSEvent *)event;
- (void)openContextMenuWithEvent:(NSEvent *)event;
- (void)nextTabWithEvent:(NSEvent *)event;
- (void)previousTabWithEvent:(NSEvent *)event;
- (void)nextWindowWithEvent:(NSEvent *)event;
- (void)previousWindowWithEvent:(NSEvent *)event;
- (void)movePaneWithEvent:(NSEvent *)event;
- (void)sendEscapeSequence:(NSString *)text withEvent:(NSEvent *)event;
- (void)sendHexCode:(NSString *)codes withEvent:(NSEvent *)event;
- (void)sendText:(NSString *)text withEvent:(NSEvent *)event;
- (void)selectPaneLeftWithEvent:(NSEvent *)event;
- (void)selectPaneRightWithEvent:(NSEvent *)event;
- (void)selectPaneAboveWithEvent:(NSEvent *)event;
- (void)selectPaneBelowWithEvent:(NSEvent *)event;
- (void)newWindowWithProfile:(NSString *)guid withEvent:(NSEvent *)event;
- (void)newTabWithProfile:(NSString *)guid withEvent:(NSEvent *)event;
- (void)newVerticalSplitWithProfile:(NSString *)guid withEvent:(NSEvent *)event;
- (void)newHorizontalSplitWithProfile:(NSString *)guid withEvent:(NSEvent *)event;
- (void)selectNextPaneWithEvent:(NSEvent *)event;
- (void)selectPreviousPaneWithEvent:(NSEvent *)event;
- (void)placeCursorOnCurrentLineWithEvent:(NSEvent *)event;


- (NSString *)contentFromX:(int)startx
                         Y:(int)starty
                       ToX:(int)nonInclusiveEndx
                         Y:(int)endy
                       pad:(BOOL)pad
        includeLastNewline:(BOOL)includeLastNewline
    trimTrailingWhitespace:(BOOL)trimSelectionTrailingSpaces;

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
- (NSTimeInterval)selectionTime;
// Cause the next find to start at the top/bottom of the buffer
- (void)resetFindCursor;

- (BOOL)growSelectionLeft;
- (void)growSelectionRight;

- (void)setTrouterPrefs:(NSDictionary *)prefs;
- (void)setSmartSelectionRules:(NSArray *)rules;

//get/set methods
- (NSFont *)font;
- (NSFont *)nafont;
- (void)setFont:(NSFont*)aFont nafont:(NSFont *)naFont horizontalSpacing:(double)horizontalSpacing verticalSpacing:(double)verticalSpacing;
- (NSRect)scrollViewContentSize;
- (void)setAntiAlias:(BOOL)asciiAA nonAscii:(BOOL)nonAsciiAA;
- (BOOL)useBoldFont;
- (void)setUseBoldFont:(BOOL)boldFlag;
- (void)setUseBrightBold:(BOOL)flag;
- (BOOL)useItalicFont;
- (void)setUseItalicFont:(BOOL)italicFlag;
- (BOOL)blinkingCursor;
- (void)setBlinkingCursor:(BOOL)bFlag;
- (void)setBlinkAllowed:(BOOL)value;
- (void)setCursorType:(ITermCursorType)value;
- (void)setDimOnlyText:(BOOL)value;

//color stuff
- (NSColor*)defaultFGColor;
- (NSColor*)defaultBGColor;
- (NSColor*)defaultBoldColor;
- (NSColor*)colorForCode:(int)theIndex green:(int)green blue:(int)blue colorMode:(ColorMode)theMode bold:(BOOL)isBold isBackground:(BOOL)isBackground;
- (NSColor*)colorFromRed:(int)red green:(int)green blue:(int)blue;
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

// Update the scroller color for light or dark backgrounds.
- (void)updateScrollerForBackgroundColor;

- (int)selectionStartX;
- (int)selectionStartY;
- (int)selectionEndX;
- (int)selectionEndY;
- (void)setSelectionFromX:(int)fromX fromY:(int)fromY toX:(int)toX toY:(int)toY;
- (void)setRectangularSelection:(BOOL)isBox;

// Remove underline indicating clickable URL.
- (void)removeUnderline;

- (double)excess;


- (NSDictionary*)markedTextAttributes;
- (void)setMarkedTextAttributes:(NSDictionary*)attr;

- (id<PTYTextViewDataSource>)dataSource;
- (void)setDataSource:(id<PTYTextViewDataSource>)aDataSource;
- (id)delegate;
- (void)setDelegate:(id)delegate;
- (double)lineHeight;
- (void)setLineHeight:(double)aLineHeight;
- (double)charWidth;
- (void)setCharWidth:(double)width;

// Toggles whether line timestamps are displayed.
- (void)toggleShowTimestamps;

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
- (double)blend;
- (void)setTransparency:(double)fVal;
- (void)setBlend:(double)blend;
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

- (void)placeFindCursorOnAutoHide;
- (BOOL)isFindingCursor;
- (void)beginFindCursor:(BOOL)hold;
- (void)endFindCursor;

- (void)movePane:(id)sender;

// Clear working directories for when buffer is cleared
- (void)clearWorkingDirectories;
- (NSString *)getWordForX:(int)x
                        y:(int)y
                   startX:(int *)startx
                   startY:(int *)starty
                     endX:(int *)endx
                     endY:(int *)endy;

- (double)perceivedBrightness:(NSColor*)c;
- (void)drawOutlineInRect:(NSRect)rect topOnly:(BOOL)topOnly;

// Add a search result for highlighting in yellow.
- (void)addResultFromX:(int)resStartX absY:(long long)absStartY toX:(int)resEndX toAbsY:(long long)absEndY;

- (FindContext *)initialFindContext;

- (NSString*)_allText;

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

- (unsigned int) _checkForSupportedDragTypes:(id <NSDraggingInfo>) sender;

- (void) _scrollToLine:(int)line;
- (void)_useBackgroundIndicatorChanged:(NSNotification *)notification;
- (void)_scrollToCenterLine:(int)line;
- (BOOL)shouldSelectCharForWord:(unichar)ch
                      isComplex:(BOOL)compled
                selectWordChars:(BOOL)selectWordChars;

- (PTYCharType)classifyChar:(unichar)ch
                  isComplex:(BOOL)complex;

- (NSString *)_getURLForX:(int)x
                        y:(int)y
     charsTakenFromPrefix:(int *)charsTakenFromPrefixPtr;
// Returns true if any char in the line is blinking.
- (BOOL)_drawLine:(int)line
              AtY:(double)curY
          toPoint:(NSPoint*)toPoint
        charRange:(NSRange)charRange
          context:(CGContextRef)ctx;

- (void)_drawCursor;
- (void)_drawCursorTo:(NSPoint*)toOrigin;
- (void)_drawCharacter:(screen_char_t)screenChar
               fgColor:(int)fgColor
               fgGreen:(int)fgGreen
                fgBlue:(int)fgBlue
           fgColorMode:(ColorMode)fgColorMode
                fgBold:(BOOL)fgBold
                   AtX:(double)X
                     Y:(double)Y
           doubleWidth:(BOOL)double_width
         overrideColor:(NSColor*)overrideColor
               context:(CGContextRef)ctx;

- (void)_drawRunsAt:(NSPoint)initialPoint
                run:(CRun *)run
            storage:(CRunStorage *)storage
            context:(CGContextRef)ctx;

- (BOOL)_isBlankLine:(int)y;
- (void)_findUrlInString:(NSString *)aURLString andOpenInBackground:(BOOL)background;
- (void)_openSemanticHistoryForUrl:(NSString *)aURLString
                            atLine:(long long)line
                      inBackground:(BOOL)background
                            prefix:(NSString *)prefix
                            suffix:(NSString *)suffix;
- (NSString *)wrappedStringAtX:(int)xi
                             y:(int)yi
                           dir:(int)dir
           respectHardNewlines:(BOOL)respectHardNewlines;

// Snapshot working directory for Trouter
- (void)logWorkingDirectoryAtLine:(long long)line;
- (void)logWorkingDirectoryAtLine:(long long)line withDirectory:(NSString *)workingDirectory;
- (NSString *)getWorkingDirectoryAtLine:(long long)line;

- (BOOL)_findMatchingParenthesis:(NSString *)parenthesis withX:(int)X Y:(int)Y;
- (void)_dragText:(NSString *)aString forEvent:(NSEvent *)theEvent;
- (BOOL)_isCharSelectedInRow:(int)row col:(int)col checkOld:(BOOL)old;
- (void)_settingsChanged:(NSNotification *)notification;
- (PTYFontInfo*)getFontForChar:(UniChar)ch
                     isComplex:(BOOL)complex
                    renderBold:(BOOL*)renderBold
                  renderItalic:(BOOL)renderItalic;

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
- (BOOL)drawInputMethodEditorTextAt:(int)xStart
                                  y:(int)yStart
                              width:(int)width
                             height:(int)height
                       cursorHeight:(double)cursorHeight
                                ctx:(CGContextRef)ctx;

- (BOOL)_wasAnyCharSelected;

- (void)_deselectDirtySelectedText;
- (BOOL) _updateBlink;
// Returns true if any onscreen char is blinking.
- (BOOL)_markChangedSelectionAndBlinkDirty:(BOOL)redrawBlink width:(int)width;

@end

