#import <Cocoa/Cocoa.h>
#import "CharacterRun.h"
#import "iTerm.h"
#import "iTermColorMap.h"
#import "iTermIndicatorsHelper.h"
#import "iTermSemanticHistoryController.h"
#import "iTermTextDrawingHelper.h"
#import "LineBuffer.h"
#import "PasteEvent.h"
#import "PointerController.h"
#import "PreferencePanel.h"
#import "PTYFontInfo.h"
#import "ScreenChar.h"
#import "VT100Output.h"
#include <sys/time.h>

@class CRunStorage;
@class iTermFindCursorView;
@class iTermFindOnPageHelper;
@class iTermSelection;
@protocol iTermSemanticHistoryControllerDelegate;
@class MovingAverage;
@class PTYScroller;
@class PTYScrollView;
@class PTYTask;
@class PTYTextView;
@class SCPPath;
@class SearchResult;
@class SmartMatch;
@class ThreeFingerTapGestureRecognizer;
@class VT100Screen;
@class VT100Terminal;

#define NSLeftAlternateKeyMask  (0x000020 | NSAlternateKeyMask)
#define NSRightAlternateKeyMask (0x000040 | NSAlternateKeyMask)

// Types of characters. Used when classifying characters for word selection.
typedef enum {
    CHARTYPE_WHITESPACE,  // whitespace chars or NUL
    CHARTYPE_WORDCHAR,    // Any character considered part of a word, including user-defined chars.
    CHARTYPE_DW_FILLER,   // Double-width character effluvia.
    CHARTYPE_OTHER,       // Symbols, etc. Anything that doesn't fall into the other categories.
} PTYCharType;

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
- (BOOL)textViewCanPasteFile;
- (void)textViewPasteFileWithBase64Encoding;
- (void)paste:(id)sender;
- (void)pasteOptions:(id)sender;
- (void)textViewFontDidChange;
- (void)textViewSizeDidChange;
- (void)textViewDrawBackgroundImageInView:(NSView *)view
                                 viewRect:(NSRect)rect
                   blendDefaultBackground:(BOOL)blendDefaultBackground;
- (BOOL)textViewHasBackgroundImage;
- (PTYScrollView *)scrollview;
- (void)sendEscapeSequence:(NSString *)text;
- (void)sendHexCode:(NSString *)codes;
- (void)sendText:(NSString *)text;
- (void)launchCoprocessWithCommand:(NSString *)command;
- (void)insertText:(NSString *)string;
- (PTYTask *)shell;
- (BOOL)alertOnNextMark;
- (void)startDownloadOverSCP:(SCPPath *)path;
- (void)uploadFiles:(NSArray *)localFilenames toPath:(SCPPath *)destinationPath;
- (void)launchProfileInCurrentTerminal:(Profile *)profile
                               withURL:(NSString *)url;
- (void)selectPaneLeftInCurrentTerminal;
- (void)selectPaneRightInCurrentTerminal;
- (void)selectPaneAboveInCurrentTerminal;
- (void)selectPaneBelowInCurrentTerminal;
- (void)writeTask:(NSData*)data;
- (void)textViewDidBecomeFirstResponder;
- (void)refreshAndStartTimerIfNeeded;
- (BOOL)textViewIsActiveSession;
- (BOOL)textViewSessionIsBroadcastingInput;
- (BOOL)textViewIsMaximized;
- (BOOL)textViewTabHasMaximizedPanel;
- (void)textViewWillNeedUpdateForBlink;
- (BOOL)textViewDelegateHandlesAllKeystrokes;
- (BOOL)textViewInSameTabAsTextView:(PTYTextView *)other;
- (void)textViewSplitVertically:(BOOL)vertically withProfileGuid:(NSString *)guid;
- (void)textViewSelectNextTab;
- (void)textViewSelectPreviousTab;
- (void)textViewSelectNextWindow;
- (void)textViewSelectPreviousWindow;
- (void)textViewCreateWindowWithProfileGuid:(NSString *)guid;
- (void)textViewCreateTabWithProfileGuid:(NSString *)guid;
- (void)textViewSelectNextPane;
- (void)textViewSelectPreviousPane;
- (void)textViewEditSession;
- (void)textViewToggleBroadcastingInput;
- (void)textViewCloseWithConfirmation;
- (void)textViewRestartWithConfirmation;
- (void)textViewPasteFromSessionWithMostRecentSelection:(PTYSessionPasteFlags)flags;
- (BOOL)textViewWindowUsesTransparency;
- (BOOL)textViewAmbiguousWidthCharsAreDoubleWidth;
- (PTYScroller *)textViewVerticalScroller;
- (BOOL)textViewHasCoprocess;
- (void)textViewPostTabContentsChangedNotification;
- (void)textViewInvalidateRestorableState;
- (void)textViewBeginDrag;
- (void)textViewMovePane;
- (void)textViewSwapPane;
- (NSStringEncoding)textViewEncoding;
- (NSString *)textViewCurrentWorkingDirectory;
- (BOOL)textViewShouldPlaceCursorAt:(VT100GridCoord)coord verticalOk:(BOOL *)verticalOk;
// If the textview isn't in the key window, the delegate can return YES in this
// method to cause the cursor to be drawn as though it were key.
- (BOOL)textViewShouldDrawFilledInCursor;

// Send the appropriate mouse-reporting escape codes.
- (BOOL)textViewReportMouseEvent:(NSEventType)eventType
                       modifiers:(NSUInteger)modifiers
                          button:(MouseButtonNumber)button
                      coordinate:(VT100GridCoord)coord
                          deltaY:(CGFloat)deltaY;

- (VT100GridAbsCoordRange)textViewRangeOfLastCommandOutput;
- (BOOL)textViewCanSelectOutputOfLastCommand;
- (NSColor *)textViewCursorGuideColor;
- (BOOL)textViewUseHFSPlusMapping;
- (NSColor *)textViewBadgeColor;
- (NSDictionary *)textViewVariables;
- (BOOL)textViewSuppressingAllOutput;
- (BOOL)textViewIsZoomedIn;
- (BOOL)textViewShouldShowMarkIndicators;

// Is it possible to restart this session?
- (BOOL)isRestartable;

@end

@interface PTYTextView : NSView <
  iTermColorMapDelegate,
  iTermSemanticHistoryControllerDelegate,
  NSDraggingDestination,
  NSTextInputClient,
  PointerControllerDelegate>

// Current selection
@property(nonatomic, readonly) iTermSelection *selection;

// Draw a highlight along the entire line the cursor is on.
@property(nonatomic, assign) BOOL highlightCursorLine;

// Use the non-ascii font? If not set, use the regular font for all characters.
@property(nonatomic, assign) BOOL useNonAsciiFont;

// Provider for screen contents, plus misc. other stuff.
@property(nonatomic, assign) id<PTYTextViewDataSource> dataSource;

// The delegate. Interfaces to the rest of the app for this view.
@property(nonatomic, assign) id<PTYTextViewDelegate> delegate;

// Array of dictionaries.
@property(nonatomic, copy) NSArray *smartSelectionRules;

// Intercell spacing as a proportion of cell size.
@property(nonatomic, assign) double horizontalSpacing;
@property(nonatomic, assign) double verticalSpacing;

// Use a different font for bold, if available?
@property(nonatomic, assign) BOOL useBoldFont;

// Use a bright version of the text color for bold text?
@property(nonatomic, assign) BOOL useBrightBold;

// Ok to render italic text as italics?
@property(nonatomic, assign) BOOL useItalicFont;

// Should cursor blink?
@property(nonatomic, assign) BOOL blinkingCursor;

// Is blinking text drawn blinking?
@property(nonatomic, assign) BOOL blinkAllowed;

// When dimming inactive views, should only text be dimmed (not bg?)
@property(nonatomic, assign) BOOL dimOnlyText;

// Should smart cursor color be used.
@property(nonatomic, assign) BOOL useSmartCursorColor;

// Transparency level. 0 to 1.
@property(nonatomic, assign) double transparency;

// Should transparency be used?
@property(nonatomic, readonly) BOOL useTransparency;

// Indicates if the last key pressed was a repeat.
@property(nonatomic, readonly) BOOL keyIsARepeat;

// Returns the currently selected text.
@property(nonatomic, readonly) NSString *selectedText;

// Returns the entire content of the view as a string.
@property(nonatomic, readonly) NSString *content;

// Returns the time (since 1970) when the selection was last modified, or 0 if there is no selection
@property(nonatomic, readonly) NSTimeInterval selectionTime;

// Regular and non-ascii fonts.
@property(nonatomic, readonly) NSFont *font;
@property(nonatomic, readonly) NSFont *nonAsciiFont;

// Returns the non-ascii font, even if it's not being used.
@property(nonatomic, readonly) NSFont *nonAsciiFontEvenIfNotUsed;

// Size of a character.
@property(nonatomic, readonly) double lineHeight;
@property(nonatomic, readonly) double charWidth;

// Is the cursor visible? Defaults to YES.
@property(nonatomic, assign) BOOL cursorVisible;

// Indicates if a find is in progress.
@property(nonatomic, readonly) BOOL findInProgress;

// An absolute scroll position which won't change as lines in history are dropped.
@property(nonatomic, readonly) long long absoluteScrollPosition;

// Returns the current find context, or one initialized to empty.
@property(nonatomic, readonly) FindContext *findContext;

// Indicates if the "find cursor" mode is active.
@property(nonatomic, readonly) BOOL isFindingCursor;

// Stores colors. This object is its delegate.
@property(nonatomic, readonly) iTermColorMap *colorMap;

// Semantic history. TODO: Move this into PTYSession.
@property(nonatomic, readonly) iTermSemanticHistoryController *semanticHistoryController;

// Is this view in the key window?
@property(nonatomic, readonly) BOOL isInKeyWindow;

// Blending level for background color over background image
@property(nonatomic, assign) float blend;

// Used by tests to modify drawing helper. Called within -drawRect:.
typedef void (^PTYTextViewDrawingHookBlock)(iTermTextDrawingHelper *);
@property(nonatomic, copy) PTYTextViewDrawingHookBlock drawingHook;

// For tests.
@property(nonatomic, readonly) NSRect cursorFrame;

// Returns the size of a cell for a given font. hspace and vspace are multipliers and the width
// and height.
+ (NSSize)charSizeForFont:(NSFont*)aFont
        horizontalSpacing:(double)hspace
          verticalSpacing:(double)vspace;

// This is the designated initializer. The color map should have the
// basic colors plus the 8-bit ansi colors set shortly after this is
// called.
- (id)initWithFrame:(NSRect)frame colorMap:(iTermColorMap *)colorMap;

// Sets the "changed since last Exposé" flag to NO and returns its original value.
- (BOOL)getAndResetChangedSinceLastExpose;

// Changes the document cursor, if needed. The event is used to get modifier flags.
- (void)updateCursor:(NSEvent *)event;

// Call this to process a mouse-down, bypassing 3-finger-tap-gesture-recognizer. Returns YES if the
// superview's mouseDown: should be called.
- (BOOL)mouseDownImpl:(NSEvent*)event;

// Locates (but does not select) a smart match at a given set of coordinates. The range of the match
// is stored in |range|. If |ignoringNewlines| is set then selection can span a hard newline.
// If |actionRequired| is set then only smart selection rules with an attached action are considered.
// If |respectDividers| is set then software-drawn dividers are wrapped around.
- (SmartMatch *)smartSelectAtX:(int)x
                             y:(int)y
                            to:(VT100GridWindowedRange *)range
              ignoringNewlines:(BOOL)ignoringNewlines
                actionRequired:(BOOL)actionRequred
               respectDividers:(BOOL)respectDividers;

// Returns range modified by removing nulls (and possibly spaces) from its ends.
- (VT100GridCoordRange)rangeByTrimmingNullsFromRange:(VT100GridCoordRange)range
                                          trimSpaces:(BOOL)trimSpaces;

// Returns the currently selected text.
- (NSString *)selectedText;

// Copy with or without styles, as set by user defaults. Not for use when a copy item in the menu is invoked.
- (void)copySelectionAccordingToUserPreferences;

// Copy the current selection to the pasteboard.
- (void)copy:(id)sender;

// Copy the current selection to the pasteboard, preserving style.
- (IBAction)copyWithStyles:(id)sender;

// Paste from the pasteboard.
- (void)paste:(id)sender;

// Cause the next find to start at the top/bottom of the buffer
- (void)resetFindCursor;

// Expands the current selection by one word.
- (BOOL)growSelectionLeft;
- (void)growSelectionRight;

// Updates the preferences for semantic history.
- (void)setSemanticHistoryPrefs:(NSDictionary *)prefs;

// Various accessors (TODO: convert as many as possible into properties)
- (void)setFont:(NSFont*)aFont
    nonAsciiFont:(NSFont *)nonAsciiFont
    horizontalSpacing:(double)horizontalSpacing
    verticalSpacing:(double)verticalSpacing;
- (NSRect)scrollViewContentSize;
- (void)setAntiAlias:(BOOL)asciiAA nonAscii:(BOOL)nonAsciiAA;

// Update the scroller color for light or dark backgrounds.
- (void)updateScrollerForBackgroundColor;

// Remove underline indicating clickable URL.
- (void)removeUnderline;

// Toggles whether line timestamps are displayed.
- (void)toggleShowTimestamps;

// Update the scroll position and schedule a redraw. Returns true if anything
// onscreen is blinking.
- (BOOL)refresh;
- (void)setNeedsDisplayOnLine:(int)line;

// selection
- (IBAction)selectAll:(id)sender;
- (void)deselect;

// Scrolling control
- (void)scrollLineNumberRangeIntoView:(VT100GridRange)range;
- (void)scrollLineUp:(id)sender;
- (void)scrollLineDown:(id)sender;
- (void)scrollPageUp:(id)sender;
- (void)scrollPageDown:(id)sender;
- (void)scrollHome;
- (void)scrollEnd;
- (void)scrollToAbsoluteOffset:(long long)absOff height:(int)height;
- (void)scrollToSelection;

// Saving/printing
- (void)saveDocumentAs:(id)sender;
- (void)print:(id)sender;
- (void)printContent:(NSString *)aString;

// Begins a new search. You may need to call continueFind repeatedly after this.
- (void)findString:(NSString*)aString
  forwardDirection:(BOOL)direction
      ignoringCase:(BOOL)ignoreCase
             regex:(BOOL)regex
        withOffset:(int)offset;

// Remove highlighted terms from previous search.
- (void)clearHighlights;

// Performs a find on the next chunk of text.
- (BOOL)continueFind:(double *)progress;

// This textview is about to become invisible because another tab is selected.
- (void)aboutToHide;

// Flash a graphic.
- (void)beginFlash:(NSString *)identifier;

// Returns true if any character in the buffer is selected.
- (BOOL)isAnyCharSelected;

// The "find cursor" mode will show for a bit and then hide itself.
- (void)placeFindCursorOnAutoHide;

// Begins the "find cursor" mode.
- (void)beginFindCursor:(BOOL)hold;

// Stops the "find cursor" mode.
- (void)endFindCursor;

// Begin click-to-move mode.
- (void)movePane:(id)sender;

// Returns the range of coords for the word at (x,y).
- (NSString *)getWordForX:(int)x
                        y:(int)y
                    range:(VT100GridWindowedRange *)range
          respectDividers:(BOOL)respectDividers;

// Add a search result for highlighting in yellow.
- (void)addSearchResult:(SearchResult *)searchResult;

// When a new note is created, call this to add a view for it.
- (void)addViewForNote:(PTYNoteViewController *)note;

// Makes sure not view frames are in the right places (e.g., after a resize).
- (void)updateNoteViewFrames;

// Show a visual highlight of a mark on the given line number.
- (void)highlightMarkOnLine:(int)line;

- (IBAction)installShellIntegration:(id)sender;

// Open a semantic history path.
- (BOOL)openSemanticHistoryPath:(NSString *)path
               workingDirectory:(NSString *)workingDirectory
                         prefix:(NSString *)prefix
                         suffix:(NSString *)suffix;

- (PTYFontInfo*)getFontForChar:(UniChar)ch
                     isComplex:(BOOL)complex
                    renderBold:(BOOL*)renderBold
                  renderItalic:(BOOL*)renderItalic;

- (NSColor*)colorForCode:(int)theIndex
                   green:(int)green
                    blue:(int)blue
               colorMode:(ColorMode)theMode
                    bold:(BOOL)isBold
                   faint:(BOOL)isFaint
            isBackground:(BOOL)isBackground;

- (BOOL)charBlinks:(screen_char_t)sct;

- (iTermColorMapKey)colorMapKeyForCode:(int)theIndex
                                 green:(int)green
                                  blue:(int)blue
                             colorMode:(ColorMode)theMode
                                  bold:(BOOL)isBold
                          isBackground:(BOOL)isBackground;

- (void)setCursorType:(ITermCursorType)value;

// Minimum contrast level. 0 to 1.
- (void)setMinimumContrast:(double)value;

- (BOOL)getAndResetDrawingAnimatedImageFlag;

// A text badge shown in the top right of the window
- (void)setBadgeLabel:(NSString *)badgeLabel;

#pragma mark - Testing only

- (id)selectedTextAttributed:(BOOL)attributed
                cappedAtSize:(int)maxBytes
           minimumLineNumber:(int)minimumLineNumber;

@end

