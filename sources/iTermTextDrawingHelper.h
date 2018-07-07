//
//  iTermTextDrawingHelper.h
//  iTerm2
//
//  Created by George Nachman on 3/9/15.
//
//

#import <Foundation/Foundation.h>
#import "ITAddressBookMgr.h"
#import "iTermCursor.h"
#import "iTermTimestampDrawHelper.h"
#import "ScreenChar.h"
#import "VT100GridTypes.h"

@class iTermColorMap;
@class iTermFindOnPageHelper;
@class iTermSelection;
@class iTermTextExtractor;
@class PTYFontInfo;
@class VT100ScreenMark;

BOOL CheckFindMatchAtIndex(NSData *findMatches, int index);

@protocol iTermTextDrawingHelperDelegate <NSObject>

- (void)drawingHelperDrawBackgroundImageInRect:(NSRect)rect
                        blendDefaultBackground:(BOOL)blendDefaultBackground;

- (VT100ScreenMark *)drawingHelperMarkOnLine:(int)line;

- (screen_char_t *)drawingHelperLineAtIndex:(int)line;
- (screen_char_t *)drawingHelperLineAtScreenIndex:(int)line;

- (screen_char_t *)drawingHelperCopyLineAtIndex:(int)line toBuffer:(screen_char_t *)buffer;

- (iTermTextExtractor *)drawingHelperTextExtractor;

- (NSArray *)drawingHelperCharactersWithNotesOnLine:(int)line;

- (void)drawingHelperUpdateFindCursorView;

- (NSDate *)drawingHelperTimestampForLine:(int)line;

- (NSColor *)drawingHelperColorForCode:(int)theIndex
                                 green:(int)green
                                  blue:(int)blue
                             colorMode:(ColorMode)theMode
                                  bold:(BOOL)isBold
                                 faint:(BOOL)isFaint
                          isBackground:(BOOL)isBackground;

- (PTYFontInfo *)drawingHelperFontForChar:(UniChar)ch
                                isComplex:(BOOL)isComplex
                               renderBold:(BOOL *)renderBold
                             renderItalic:(BOOL *)renderItalic;

- (NSData *)drawingHelperMatchesOnLine:(int)line;

- (void)drawingHelperDidFindRunOfAnimatedCellsStartingAt:(VT100GridCoord)coord ofLength:(int)length;

- (NSString *)drawingHelperLabelForDropTargetOnLine:(int)line;

@end

@interface iTermTextDrawingHelper : NSObject

// Holds the current selection, if any.
@property(nonatomic, retain) iTermSelection *selection;

// Color for the cursor guide, if any.
@property(nonatomic, retain) NSColor *cursorGuideColor;

// Image to show as badge.
@property(nonatomic, retain) NSImage *badgeImage;

// Color for selection background when the view is not focused.
@property(nonatomic, retain) NSColor *unfocusedSelectionColor;

// Holds colors.
@property(nonatomic, retain) iTermColorMap *colorMap;

// Required delegate.
@property(nonatomic, assign) NSView<iTermTextDrawingHelperDelegate> *delegate;

// Size of a cell in pixels.
@property(nonatomic, assign) NSSize cellSize;

// Size of a cell in pixels excluding extra spacing requested by the user.
@property(nonatomic, assign) NSSize cellSizeWithoutSpacing;

// Should diagonal stripes be overlain between background and text?
@property(nonatomic, assign) BOOL showStripes;

// Should ASCII characters be anti-aliased?
@property(nonatomic, assign) BOOL asciiAntiAlias;

// Should non-ASCII characters be anti-aliased?
@property(nonatomic, assign) BOOL nonAsciiAntiAlias;

// Are blinking items (cursor, text) currently visible?
@property(nonatomic, assign) BOOL blinkingItemsVisible;

// The size of the grid in cells.
@property(nonatomic, assign) VT100GridSize gridSize;

// Total number of lines available (scrollback plus screen height).
@property(nonatomic, assign) int numberOfLines;

// Location of the cursor on the screen.
@property(nonatomic, assign) VT100GridCoord cursorCoord;

// Is the cursor configured to blink?
@property(nonatomic, assign) BOOL cursorBlinking;

// Are we in copy mode?
@property(nonatomic, assign) BOOL copyMode;
@property(nonatomic, assign) BOOL copyModeSelecting;

// Location of the copy-mode cursor
@property(nonatomic, assign) VT100GridCoord copyModeCursorCoord;

// Height of the "excess" region between the last line and the bottom of the view.
@property(nonatomic, assign) double excess;

// Total number of lines ever scrolled out of history.
@property(nonatomic, assign) long long totalScrollbackOverflow;

// Should ambiguous-width characters be treated as double-width?
@property(nonatomic, assign) BOOL ambiguousIsDoubleWidth;

// Unicode normalization form to use. In practice, I can't find a way that this is used. We
// don't normalize IME text on input unless there's a combining mark, but I don't know a case where
// adding a combining mark would change a character from narrow to ambiguous width.
@property(nonatomic, assign) iTermUnicodeNormalization normalization;

// Is a background image in use?
@property(nonatomic, assign) BOOL hasBackgroundImage;

// Number of lines of scrollback history.
@property(nonatomic, assign) int numberOfScrollbackLines;

// Should the entire screen have foreground and background swapped?
@property(nonatomic, assign) BOOL reverseVideo;

// Is this view active (receiving user input)?
@property(nonatomic, assign) BOOL textViewIsActiveSession;

// Is "smart cursor color" on?
@property(nonatomic, assign) BOOL useSmartCursorColor;

// Is this view in the key window?
@property(nonatomic, assign) BOOL isInKeyWindow;

// Should a box cursor be drawn filled in?
@property(nonatomic, assign) BOOL shouldDrawFilledInCursor;

// Does bold text render as the bright version of a dim ansi color?
@property(nonatomic, assign) BOOL useBrightBold;

// Is this the current text view of the "front" terminal window?
// TODO: This might be the same as textViewIsActiveSession.
@property(nonatomic, assign) BOOL isFrontTextView;

// Background transparency level. Should be 1 if transparency is off for this view.
@property(nonatomic, assign) double transparencyAlpha;

// Is the cursor visible?
@property(nonatomic, assign) BOOL cursorVisible;

// What kind of cursor to draw.
@property(nonatomic, assign) ITermCursorType cursorType;

// Amount to blend background color over background image, 0-1.
@property(nonatomic, assign) float blend;

// Should transparency not affect background colors other than the default?
@property(nonatomic, assign) BOOL transparencyAffectsOnlyDefaultBackgroundColor;

// Should the cursor guide be shown?
@property(nonatomic, assign) BOOL highlightCursorLine;

// Mimimum contrast level, 0-1.
@property(nonatomic, assign) double minimumContrast;

// Should the non-ascii font be used?
@property(nonatomic, assign) BOOL useNonAsciiFont;

// Should text with the blink flag actually blink?
@property(nonatomic, assign) BOOL blinkAllowed;

// Underlined selection range (inclusive of all values), indicating clickable url.
@property(nonatomic, assign) VT100GridAbsWindowedRange underlinedRange;

// If set, the last-modified time of each line on the screen is shown on the right side of the display.
@property(nonatomic, assign) BOOL showTimestamps;

// Amount to shift anti-aliased text by horizontally to simulate bold
@property(nonatomic, assign) CGFloat antiAliasedShift;

// NSTextInputClient support
@property(nonatomic, retain) NSAttributedString *markedText;

// Marked text may have a selection. This gives the range of selected characters.
@property(nonatomic, assign) NSRange inputMethodSelectedRange;

// This gives the range of marked text. Used here to determine if there is marked text.
@property(nonatomic, assign) NSRange inputMethodMarkedRange;

// This gives the number of lines added to the bottom of the frame that do
// not correspond to a line in the _dataSource. They are used solely for
// IME text.
@property(nonatomic, assign) int numberOfIMELines;

// The current time since reference date. Exposed to facilitate testing timestamps.
@property(nonatomic, assign) NSTimeInterval now;

// If set, use GMT timezone for timestamps to make tests locale-independent.
@property(nonatomic, assign) BOOL useTestingTimezone;

// Is the cursor blinking because "Find Cursor" has been activated?
@property(nonatomic, readonly) BOOL blinkingFound;

// Origin in view coordinates of the cursor. Valid only if there is marked text.
@property(nonatomic, readonly) NSPoint imeCursorLastPos;

// Where the cursor is drawn based on current cellSize and cursorCoord.
@property(nonatomic, readonly) NSRect cursorFrame;

// Draw debug info?
@property(nonatomic, assign) BOOL debug;

// Set to YES if part of an animated image was drawn.
@property(nonatomic, assign) BOOL animated;

@property(nonatomic, assign) BOOL isRetina;

// Draw mark indicators?
@property(nonatomic, assign) BOOL drawMarkIndicators;

// Use light font smoothing?
@property(nonatomic, assign) iTermThinStrokesSetting thinStrokes;

// Change the cursor to indicate that a search is being performed.
@property(nonatomic, assign) BOOL showSearchingCursor;

// Should drop targets be indicated?
@property(nonatomic, assign) BOOL showDropTargets;

// Line number that is being hovered over for drop
@property(nonatomic, assign) int dropLine;

// Lazily loading images that could not be drawn. Contains unique identifiers of iTermImageInfo*s
@property(nonatomic, readonly) NSSet<NSString *> *missingImages;

// Smallest of the baseline offset for the available fonts. Is a negative number.
@property(nonatomic, assign) CGFloat baselineOffset;

// Underline offset to use. Negative.
@property(nonatomic, assign) CGFloat underlineOffset;

// Is bold text allowed? If so, then double struck text may be used when a bold version of the font
// is not available.
@property(nonatomic, assign) BOOL boldAllowed;

// Version of unicode. Determines character widths.
@property(nonatomic, assign) NSInteger unicodeVersion;

// Are ligatures allowed?
@property(nonatomic, assign) BOOL asciiLigatures;
@property(nonatomic, assign) BOOL nonAsciiLigatures;

// Show the password input cursor?
@property(nonatomic) BOOL passwordInput;

@property(nonatomic) NSRect indicatorFrame;

@property(nonatomic, readonly) iTermTimestampDrawHelper *timestampDrawHelper;

@property(nonatomic, readonly) NSColor *defaultBackgroundColor;

// Does the current ascii font have ligatures? Used to determine if ASCII
// symbols (non-alphanumerics) get to use the fastpath.
@property (nonatomic, readonly) BOOL asciiLigaturesAvailable;

@property (nonatomic, readonly, class) NSColor *successMarkColor;
@property (nonatomic, readonly, class) NSColor *errorMarkColor;
@property (nonatomic, readonly, class) NSColor *otherMarkColor;

// imageSize: size of image to draw
// destinationRect: rect bounding the region of a scrollview's content view (i.e., very tall view) that's being drawn
// destinationFrameSize: size of the scrollview's content view
// visibleSize: size of visible portion of scrollview
// sourceRectPtr: filled in with source frame to draw from
//
// Returns: destination frame to draw to
+ (NSRect)rectForBadgeImageOfSize:(NSSize)imageSize
                  destinationRect:(NSRect)destinationRect
             destinationFrameSize:(NSSize)destinationFrameSize
                      visibleSize:(NSSize)visibleSize
                    sourceRectPtr:(NSRect *)sourceRectPtr;

// Indicates whether the cursor should take its color from the background (if YES) or text color (if NO).
+ (BOOL)cursorUsesBackgroundColorForScreenChar:(screen_char_t)screenChar
                                wantBackground:(BOOL)wantBackgroundColor
                                  reverseVideo:(BOOL)reverseVideo;

+ (NSRect)frameForMarkContainedInRect:(NSRect)container
                             cellSize:(CGSize)cellSize
               cellSizeWithoutSpacing:(CGSize)cellSizeWithoutSpacing
                                scale:(CGFloat)scale;

// Updates self.blinkingFound.
- (void)drawTextViewContentInRect:(NSRect)rect
                         rectsPtr:(const NSRect *)rectArray
                        rectCount:(NSInteger)rectCount;

// If timestamps are to be shown, call this just before drawing.
- (void)createTimestampDrawingHelper;

// Draw timestamps.
- (void)drawTimestamps;

- (VT100GridCoordRange)coordRangeForRect:(NSRect)rect;

- (CGFloat)yOriginForUnderlineForFont:(NSFont *)font yOffset:(CGFloat)yOffset cellHeight:(CGFloat)cellHeight;
- (CGFloat)underlineThicknessForFont:(NSFont *)font;
- (NSRange)underlinedRangeOnLine:(long long)row;

- (void)updateCachedMetrics;

@end

NS_INLINE BOOL iTermTextDrawingHelperIsCharacterDrawable(screen_char_t *c,
                                                         BOOL isStringifiable,
                                                         BOOL blinkingItemsVisible,
                                                         BOOL blinkAllowed) {
    const unichar code = c->code;
    if (c->image) {
        return YES;
    }
    if (!c->complexChar) {
        if (code == DWC_RIGHT ||
            code == DWC_SKIP ||
            code == TAB_FILLER ||
            code < ' ') {
            return NO;
        } else if (code == ' ' && !c->underline && !c->urlCode) {
            return NO;
        }
    }
    if (blinkingItemsVisible || !(blinkAllowed && c->blink)) {
        // This char is either not blinking or during the "on" cycle of the
        // blink. It should be drawn.

        if (c->complexChar) {
            // TODO: Not all composed/surrogate pair grapheme clusters are drawable
            return isStringifiable;
        } else {
            // Non-complex char
            // TODO: There are other spaces in unicode that should be supported.
            return (code != 0 &&
                    code != '\t' &&
                    !(code >= ITERM2_PRIVATE_BEGIN && code <= ITERM2_PRIVATE_END));

        }
    } else {
        // Chatacter hidden because of blinking.
        return NO;
    }
}
