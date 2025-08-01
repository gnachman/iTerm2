#import <Cocoa/Cocoa.h>
#import "ITAddressBookMgr.h"
#import "iTerm.h"
#import "iTermBadgeLabel.h"
#import "iTermClickSideEffects.h"
#import "iTermColorMap.h"
#import "iTermFindDriver.h"
#import "iTermFocusFollowsMouseController.h"
#import "iTermIndicatorsHelper.h"
#import "iTermKeyBindingAction.h"
#import "iTermKeyboardHandler.h"
#import "iTermLogicalMovementHelper.h"
#import "iTermObject.h"
#import "iTermPopupWindowController.h"
#import "iTermSemanticHistoryController.h"
#import "iTermTextDrawingHelper.h"
#import "LineBuffer.h"
#import "NSEvent+iTerm.h"
#import "PasteEvent.h"
#import "PointerController.h"
#import "PreferencePanel.h"
#import "PTYFontInfo.h"
#import "ScreenChar.h"
#import "VT100Output.h"
#import "VT100SyncResult.h"
#include <sys/time.h>

#define AccLog DLog

@class CRunStorage;
@class iTermAction;
@class iTermExpect;
@class iTermFindCursorView;
@class iTermFindOnPageHelper;
@class iTermFocusFollowsMouse;
@protocol iTermFocusFollowsMouseFocusReceiver;
@class iTermFontTable;
@class iTermImageWrapper;
@protocol iTermPathMarkReading;
@class iTermQuickLookController;
@class iTermSelection;
@protocol iTermSemanticHistoryControllerDelegate;
@protocol iTermSwipeHandler;
@class iTermTerminalButton;
@class iTermURLActionHelper;
@class iTermVariableScope;
@class MovingAverage;
@protocol PTYAnnotationReading;
@class PTYScroller;
@class PTYScrollView;
@class PTYTask;
@class PTYTextView;
@class SCPPath;
@class SSHIdentity;
@class SearchResult;
@class SmartMatch;
@class ThreeFingerTapGestureRecognizer;
@class VT100Screen;
@class VT100Terminal;

// Types of characters. Used when classifying characters for word selection.
typedef NS_ENUM(NSInteger, PTYCharType) {
    CHARTYPE_WHITESPACE,  // whitespace chars or NUL
    CHARTYPE_WORDCHAR,    // Any character considered part of a word, including user-defined chars.
    CHARTYPE_DW_FILLER,   // Double-width character effluvia.
    CHARTYPE_OTHER,       // Symbols, etc. Anything that doesn't fall into the other categories.
};

extern NSTimeInterval PTYTextViewHighlightLineAnimationDuration;

extern NSNotificationName iTermPortholesDidChange;
extern NSNotificationName PTYTextViewWillChangeFontNotification;
extern const CGFloat PTYTextViewMarginClickGraceWidth;

@protocol PTYTextViewDelegate <NSObject, iTermBadgeLabelDelegate, iTermObject>

@property (nonatomic, readonly) NSEdgeInsets textViewEdgeInsets;

// Returns scrollback overflow.
- (VT100SyncResult)textViewWillRefresh;
- (BOOL)xtermMouseReporting;
- (BOOL)xtermMouseReportingAllowMouseWheel;
- (BOOL)xtermMouseReportingAllowClicksAndDrags;
- (BOOL)isPasting;
- (void)queueKeyDown:(NSEvent *)event;
- (void)keyDown:(NSEvent *)event;
- (void)keyUp:(NSEvent *)event;
- (void)textViewhandleSpecialKeyDown:(NSEvent *)event;
- (BOOL)hasActionableKeyMappingForEvent:(NSEvent *)event;
- (iTermOptionKeyBehavior)optionKey;
- (iTermOptionKeyBehavior)rightOptionKey;
// Contextual menu
- (void)menuForEvent:(NSEvent *)theEvent menu:(NSMenu *)theMenu;
- (void)pasteString:(NSString *)aString;
- (void)pasteStringWithoutBracketing:(NSString *)theString;
- (void)paste:(id)sender;
- (void)pasteOptions:(id)sender;
- (void)textViewFontDidChange;
- (BOOL)textViewDrawBackgroundImageInView:(NSView *)view
                                 viewRect:(NSRect)rect
                   blendDefaultBackground:(BOOL)blendDefaultBackground
                            virtualOffset:(CGFloat)virtualOffset;
- (BOOL)textViewHasBackgroundImage;
- (void)sendEscapeSequence:(NSString *)text;
- (void)sendHexCode:(NSString *)codes;
- (void)sendText:(NSString *)text escaping:(iTermSendTextEscaping)escaping;
- (void)openAdvancedPasteWithText:(NSString *)text escaping:(iTermSendTextEscaping)escaping;
- (void)sendTextSlowly:(NSString *)text;
- (void)textViewSelectionDidChangeToTruncatedString:(NSString *)maybeSelection;
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
- (void)writeTask:(NSString *)string;
- (void)writeStringWithLatin1Encoding:(NSString *)string;
- (void)textViewDidBecomeFirstResponder;
- (void)textViewDidResignFirstResponder;
- (void)refresh;
- (BOOL)textViewIsActiveSession;
- (BOOL)textViewSessionIsBroadcastingInput;
- (BOOL)textViewIsMaximized;
- (BOOL)textViewTabHasMaximizedPanel;
- (void)textViewWillNeedUpdateForBlink;
- (BOOL)textViewDelegateHandlesAllKeystrokes;
- (void)textViewSplitVertically:(BOOL)vertically withProfileGuid:(NSString *)guid;
- (void)textViewSelectNextTab;
- (void)textViewSelectPreviousTab;
- (void)textViewSelectNextWindow;
- (void)textViewSelectPreviousWindow;
- (void)textViewCreateWindowWithProfileGuid:(NSString *)guid;
- (void)textViewCreateTabWithProfileGuid:(NSString *)guid;
- (void)textViewSelectNextPane;
- (void)textViewSelectPreviousPane;
- (void)textViewSelectMenuItemWithIdentifier:(NSString *)identifier
                                       title:(NSString *)title;
- (void)textViewPasteSpecialWithStringConfiguration:(NSString *)configuration
                                      fromSelection:(BOOL)fromSelection;
- (void)textViewInvokeScriptFunction:(NSString *)function;
- (void)textViewEditSession;
- (void)textViewToggleBroadcastingInput;
- (void)textViewCloseWithConfirmation;
- (void)textViewRestartWithConfirmation;
- (void)textViewPasteFromSessionWithMostRecentSelection:(PTYSessionPasteFlags)flags;
- (BOOL)textViewWindowUsesTransparency;
- (BOOL)textViewAmbiguousWidthCharsAreDoubleWidth;
- (PTYScroller *)textViewVerticalScroller;
- (BOOL)textViewHasCoprocess;
- (void)textViewStopCoprocess;
- (void)textViewPostTabContentsChangedNotification;
- (void)textViewInvalidateRestorableState;
- (void)textViewDidFindDirtyRects;
- (void)textViewBeginDrag;
- (void)textViewMovePane;
- (void)textViewSwapPane;
- (NSStringEncoding)textViewEncoding;
- (void)textViewGetCurrentWorkingDirectoryWithCompletion:(void (^)(NSString *workingDirectory))completion;

- (BOOL)textViewShouldPlaceCursorAt:(VT100GridCoord)coord verticalOk:(BOOL *)verticalOk;
// If the textview isn't in the key window, the delegate can return YES in this
// method to cause the cursor to be drawn as though it were key.
- (BOOL)textViewShouldDrawFilledInCursor;

// Send the appropriate mouse-reporting escape codes.
- (BOOL)textViewReportMouseEvent:(NSEventType)eventType
                       modifiers:(NSUInteger)modifiers
                          button:(MouseButtonNumber)button
                      coordinate:(VT100GridCoord)coord
                           point:(NSPoint)point
                           delta:(CGSize)delta
        allowDragBeforeMouseDown:(BOOL)allowDragBeforeMouseDown
                        testOnly:(BOOL)testOnly;

- (VT100GridAbsCoordRange)textViewRangeOfLastCommandOutput;
- (VT100GridAbsCoordRange)textViewRangeOfCurrentCommand;
- (BOOL)textViewCanSelectOutputOfLastCommand;
- (BOOL)textViewCanSelectCurrentCommand;
- (NSColor *)textViewCursorGuideColor;
- (iTermUnicodeNormalization)textViewUnicodeNormalizationForm;
- (NSColor *)textViewBadgeColor;
- (NSDictionary *)textViewVariables;
- (BOOL)textViewSuppressingAllOutput;
- (BOOL)textViewIsZoomedIn;
- (BOOL)textViewShouldShowMarkIndicators;
- (BOOL)textViewIsFiltered;
- (BOOL)textViewInPinnedHotkeyWindow;
- (BOOL)textViewSessionIsLinkedToAIChat;
- (BOOL)textViewSessionIsStreamingToAIChat;
- (BOOL)textViewSessionHasChannelParent;

// Is it possible to restart this session?
- (BOOL)isRestartable;
- (void)textViewToggleAnnotations;
- (BOOL)textViewShouldAcceptKeyDownEvent:(NSEvent *)event;
- (void)textViewDidReceiveFlagsChangedEvent:(NSEvent *)event;
- (void)textViewHaveVisibleBlocksDidChange;
- (iTermExpect *)textViewExpect;

// We guess the user is trying to send arrow keys with the scroll wheel in alt screen.
- (void)textViewThinksUserIsTryingToSendArrowKeysWithScrollWheel:(BOOL)trying;

// Update the text view's frame needed.
- (BOOL)textViewResizeFrameIfNeeded;

- (NSInteger)textViewUnicodeVersion;
- (void)textViewDidRefresh;

// The background color in the color map changed.
- (void)textViewBackgroundColorDidChangeFrom:(NSColor *)before to:(NSColor *)after;
- (void)textViewForegroundColorDidChangeFrom:(NSColor *)before to:(NSColor *)after;
- (void)textViewCursorColorDidChangeFrom:(NSColor *)before to:(NSColor *)after;
- (void)textViewTransparencyDidChange;
- (void)textViewProcessedBackgroundColorDidChange;

// Describes the current user, host, and path.
- (NSURL *)textViewCurrentLocation;
- (void)textViewBurySession;
// anchor is a visual range
- (BOOL)textViewShowHoverURL:(NSString *)url anchor:(VT100GridWindowedRange)anchor;

- (BOOL)textViewCopyMode;
- (BOOL)textViewCopyModeSelecting;
- (VT100GridCoord)textViewCopyModeCursorCoord;
- (BOOL)textViewPasswordInput;
- (void)textViewDidSelectRangeForFindOnPage:(VT100GridCoordRange)range;
- (void)textViewNeedsDisplayInRect:(NSRect)rect;
- (void)textViewDidSelectPasswordPrompt;
- (iTermImageWrapper *)textViewBackgroundImage;
- (iTermBackgroundImageMode)backgroundImageMode;
- (BOOL)textViewShouldDrawRect;
- (void)textViewDidHighlightMark;
- (BOOL)textViewInInteractiveApplication;
- (BOOL)textViewTerminalStateForMenuItem:(NSMenuItem *)menuItem;
- (iTermEmulationLevel)textViewTerminalStateEmulationLevel;
- (void)textViewToggleTerminalStateForMenuItem:(NSMenuItem *)menuItem;
- (void)textViewResetTerminal;
- (CGRect)textViewRelativeFrame;
- (CGRect)textViewContainerRect;
- (CGFloat)textViewBadgeTopMargin;
- (CGFloat)textViewBadgeRightMargin;
- (iTermVariableScope *)textViewVariablesScope;
- (BOOL)textViewTerminalBackgroundColorDeterminesWindowDecorationColor;
- (void)textViewDidUpdateDropTargetVisibility;
- (void)textViewDidDetectMouseReportingFrustration;
- (BOOL)textViewCanBury;
- (void)textViewFindOnPageLocationsDidChange;
- (void)textViewFindOnPageSelectedResultDidChange;
- (CGFloat)textViewBlend;
- (NSEdgeInsets)textViewExtraMargins;
- (id<iTermSwipeHandler>)textViewSwipeHandler;
- (void)textViewAddContextMenuItems:(NSMenu *)menu;
- (NSString *)textViewShell;
- (void)textViewContextMenuInvocation:(NSString *)invocation
                      failedWithError:(NSError *)error
                          forMenuItem:(NSString *)title;
- (void)textViewApplyAction:(iTermAction *)action;
- (void)textViewAddTrigger:(NSString *)text;
- (void)textViewEditTriggers;
- (void)textViewToggleEnableTriggersInInteractiveApps;
- (BOOL)textViewTriggersAreEnabledInInteractiveApps;
- (iTermTimestampsMode)textviewTimestampsMode;
- (void)textviewToggleTimestampsMode;
- (void)textViewSetClickCoord:(VT100GridAbsCoord)coord
                       button:(NSInteger)button
                        count:(NSInteger)count
                    modifiers:(NSEventModifierFlags)modifiers
                  sideEffects:(iTermClickSideEffects)sideEffects
                        state:(iTermMouseState)state;

- (BOOL)textViewCanWriteToTTY;
- (BOOL)textViewAnyMouseReportingModeIsEnabled;
- (BOOL)textViewSmartSelectionActionsShouldUseInterpolatedStrings;
- (void)textViewShowFindPanel;
- (void)textViewDidAddOrRemovePorthole;
- (NSString *)textViewCurrentSSHSessionName;
- (void)textViewDisconnectSSH;
- (void)textViewShowFindIndicator:(VT100GridCoordRange)range;
- (void)textViewOpen:(NSString *)string
    workingDirectory:(NSString *)folder
          remoteHost:(id<VT100RemoteHostReading>)remoteHost;
- (void)textViewEnterShortcutNavigationMode:(BOOL)clearOnEnd;
- (void)textViewExitShortcutNavigationMode;
- (void)textViewWillHandleMouseDown:(NSEvent *)event;
- (BOOL)textViewPasteFiles:(NSArray<NSString *> *)filenames;
- (NSString *)textViewNaturalLanguageQuery;
- (void)textViewPerformNaturalLanguageQuery;
- (BOOL)textViewCanExplainOutputWithAI;
- (void)textViewExplainOutputWithAI;
- (void)textViewUpdateTrackingAreas;
- (BOOL)textViewShouldShowOffscreenCommandLineAt:(int)location;
- (BOOL)textViewShouldUseSelectedTextColor;
- (void)textViewOpenComposer:(NSString *)string;
- (BOOL)textViewIsAutoComposerOpen;
- (VT100GridRange)textViewLinesToSuppressDrawing;
- (CGFloat)textViewPointsOnBottomToSuppressDrawing;
- (NSRect)textViewCursorFrameInScreenCoords;
- (void)textViewDidReceiveSingleClick;
- (void)textViewDisableOffscreenCommandLine;
- (void)textViewSaveScrollPositionForMark:(id<VT100ScreenMarkReading>)mark withName:(NSString *)name;
- (void)textViewRemoveBookmarkForMark:(id<VT100ScreenMarkReading>)mark;
- (BOOL)textViewEnclosingTabHasMultipleSessions;
- (BOOL)textViewSelectionScrollAllowed;
- (void)textViewRemoveSelectedCommand;
- (void)textViewSelectCommandRegionAtCoord:(VT100GridCoord)coord;
- (id<VT100ScreenMarkReading>)textViewMarkForCommandAt:(VT100GridCoord)coord;
- (void)textViewReloadSelectedCommand;
- (id<VT100ScreenMarkReading>)textViewSelectedCommandMark;
- (NSCursor *)textViewDefaultPointer;
- (BOOL)textViewOrComposerIsFirstResponder;
- (VT100GridAbsCoordRange)textViewCoordRangeForCommandAndOutputAtMark:(id<iTermMark>)mark;
- (BOOL)textViewCanUploadOverSSHIntegrationTo:(SCPPath *)path;
- (BOOL)textViewSplitPaneWidthIsLocked:(out BOOL *)allowedPtr;
- (void)textViewToggleLockSplitPaneWidth;
- (BOOL)textViewWouldReportControlReturn;
- (BOOL)textViewCanChangeProfileInArrangement;
- (void)textViewChangeProfileInArrangement;
- (void)textViewSmearCursorFrom:(NSRect)from
                             to:(NSRect)to
                          color:(NSColor *)color;
- (CGFloat)textViewRightExtra;
- (void)textViewLiveSelectionDidEnd;
- (void)textViewShowJSONPromotion;
- (void)textViewUserDidClickPathMark:(id<iTermPathMarkReading>)pathMark;
- (void)textViewCancelSingleClick;
- (void)textViewRevealChannelWithUID:(NSString *)uid;
- (BOOL)textViewAlternateMouseScroll:(out BOOL *)verticalOnly;
- (void)textViewMarginColorDidChange;
- (BOOL)textViewProfileTypeIsTerminal;
@end

@interface iTermHighlightedRow : NSObject
@property (nonatomic, readonly) long long absoluteLineNumber;
@property (nonatomic, readonly) NSTimeInterval creationDate;
@property (nonatomic, readonly) BOOL success;
@end

@interface PTYTextView : NSView <
  iTermImmutableColorMapDelegate,
  iTermIndicatorsHelperDelegate,
  iTermSemanticHistoryControllerDelegate,
  iTermSpecialHandlerForAPIKeyDownNotifications,
  iTermTextDrawingHelperDelegate,
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
@property(nonatomic, weak) id<PTYTextViewDataSource> dataSource;

// The delegate. Interfaces to the rest of the app for this view.
@property(nonatomic, assign) id<PTYTextViewDelegate> delegate;

// Array of dictionaries.
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *smartSelectionRules;

// Intercell spacing as a proportion of cell size.
@property(nonatomic, assign) CGFloat horizontalSpacing;
@property(nonatomic, assign) CGFloat verticalSpacing;

// Use a different font for bold, if available?
@property(nonatomic, assign) BOOL useBoldFont;

// Draw text with light font smoothing?
@property(nonatomic, assign) iTermThinStrokesSetting thinStrokes;

// Are ligatures allowed?
@property(nonatomic, assign) BOOL asciiLigatures;
@property(nonatomic, assign) BOOL nonAsciiLigatures;

// Use the custom bold color
@property(nonatomic, readonly) BOOL useCustomBoldColor;

// Brighten bold text?
@property(nonatomic, assign) BOOL brightenBold;

// Ok to render italic text as italics?
@property(nonatomic, assign) BOOL useItalicFont;

// Should cursor blink?
@property(nonatomic, assign) BOOL blinkingCursor;

// Should bar/underscore cursors have a shadow?
@property(nonatomic) BOOL cursorShadow;

// Hide cursor when keyboard focus lost?
@property (nonatomic) BOOL hideCursorWhenUnfocused;

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

@property(nonatomic, readonly) iTermFontTable *fontTable;

// Size of a character.
@property(nonatomic, readonly) double lineHeight;
@property(nonatomic, readonly) double charWidth;

@property(nonatomic, readonly) double charWidthWithoutSpacing;
@property(nonatomic, readonly) double charHeightWithoutSpacing;

// Is the cursor visible? Defaults to YES.
@property(nonatomic, assign) BOOL cursorVisible;

// Indicates if a find is in progress.
@property(nonatomic, readonly) BOOL findInProgress;

// An absolute scroll position which won't change as lines in history are dropped.
@property(nonatomic, readonly) long long absoluteScrollPosition;

// Indicates if the "find cursor" mode is active.
@property(nonatomic, readonly) BOOL isFindingCursor;

// Stores colors. Gets updated on sync.
@property(nonatomic, retain) id<iTermColorMapReading> colorMap;

// Semantic history. TODO: Move this into PTYSession.
@property(nonatomic, readonly) iTermSemanticHistoryController *semanticHistoryController;

// Is this view in the key window?
@property(nonatomic, readonly) BOOL isInKeyWindow;

// Used by tests to modify drawing helper. Called within -drawRect:.
typedef void (^PTYTextViewDrawingHookBlock)(iTermTextDrawingHelper *);
@property(nonatomic, copy) PTYTextViewDrawingHookBlock drawingHook;

@property(nonatomic, readonly) BOOL showTimestamps;
@property(nonatomic, readonly) iTermTimestampsMode timestampsMode;

@property(nonatomic, readonly) BOOL anyAnnotationsAreVisible;

// For tests.
@property(nonatomic, readonly) NSRect cursorFrame;

// Change the cursor to indicate that a search is being performed.
@property(nonatomic, assign) BOOL showSearchingCursor;

@property(nonatomic, readonly) iTermQuickLookController *quickLookController;

// Returns the desired height of this view that exactly fits its contents.
@property(nonatomic, readonly) CGFloat desiredHeight;

// Lines that are currently visible on the screen.
@property(nonatomic, readonly) VT100GridRange rangeOfVisibleLines;

// Helps drawing text and background.
@property (nonatomic, readonly) iTermTextDrawingHelper *drawingHelper;

@property (nonatomic, readonly) double transparencyAlpha;

// Is the cursor eligible to blink?
@property (nonatomic, readonly) BOOL isCursorBlinking;

@property (nonatomic, readonly) iTermIndicatorsHelper *indicatorsHelper;

@property (nonatomic, readonly) NSArray<iTermHighlightedRow *> *highlightedRows;

@property (nonatomic) BOOL suppressDrawing;
@property (nonatomic, readonly) long long firstVisibleAbsoluteLineNumber;
@property (nonatomic) BOOL useNativePowerlineGlyphs;

@property (nonatomic, readonly) iTermKeyboardHandler *keyboardHandler;

@property (nonatomic, readonly) iTermURLActionHelper *urlActionHelper;

@property (nonatomic, readonly) VT100GridCoord cursorCoord;
@property (nonatomic, readonly) iTermFindOnPageHelper *findOnPageHelper;

// This is the height of the bottom margin.
@property (nonatomic, readonly) double excess;
@property (nonatomic, readonly) CGFloat virtualOffset;

@property (nonatomic, readonly) BOOL wantsMouseMovementEvents;

// Checked and at the end of -refresh. Meant to be use when a reentrant call failed.
@property (nonatomic) BOOL needsUpdateSubviewFrames;
@property (nonatomic, readonly) NSArray<iTermTerminalButton *> *terminalButtons NS_AVAILABLE_MAC(11);
@property (nonatomic, readonly) BOOL scrolledToBottom;
@property (nonatomic, readonly) BOOL shouldBeAlphaedOut;
@property (nonatomic, readonly) BOOL drawingHelperIsValid;
@property (nonatomic, readonly) BOOL canCopy;
@property (nonatomic) BOOL animateMovement;
@property (nonatomic) NSTimeInterval timestampBaseline;


// If there is a dominant color around the sides of the view and we are allowed
// to extend that color into the margins, this will have that color. Its
// enabled property will be true if a dominant color was found.
@property (nonatomic) VT100MarginColor marginColor;

// Should the dominant edge color be extended into the margins?
@property (nonatomic) BOOL marginColorAllowed;

// nil if no color is extended into the margins, otherwise the color.
@property (nonatomic, readonly) NSColor *colorForMargins;

@property (nonatomic, readonly) iTermFocusFollowsMouse *focusFollowsMouse;

// Returns the size of a cell for a given font. hspace and vspace are multipliers and the width
// and height.
+ (NSSize)charSizeForFont:(NSFont*)aFont
        horizontalSpacing:(CGFloat)hspace
          verticalSpacing:(CGFloat)vspace;

- (instancetype)initWithFrame:(NSRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

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
                actionRequired:(BOOL)actionRequired
               respectDividers:(BOOL)respectDividers;

// Returns range modified by removing nulls (and possibly spaces) from its ends.
- (VT100GridCoordRange)rangeByTrimmingNullsFromRange:(VT100GridCoordRange)range
                                          trimSpaces:(BOOL)trimSpaces;

// Returns the currently selected text.
- (NSString *)selectedText;

// Copy with or without styles, as set by user defaults. Not for use when a copy item in the menu is invoked.
- (void)copySelectionAccordingToUserPreferences;
- (BOOL)copyString:(NSString *)string;
- (BOOL)copyData:(NSData *)data;

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

- (void)configureAsBrowser;

// Various accessors (TODO: convert as many as possible into properties)
- (void)setFontTable:(iTermFontTable *)fontTable
   horizontalSpacing:(CGFloat)horizontalSpacing
     verticalSpacing:(CGFloat)verticalSpacing;
- (NSRect)scrollViewContentSize;
- (NSRect)offscreenCommandLineFrameForView:(NSView *)view;
- (void)setAntiAlias:(BOOL)asciiAA nonAscii:(BOOL)nonAsciiAA;

// Update the scroller color for light or dark backgrounds.
- (void)updateScrollerForBackgroundColor;

// Remove underline indicating clickable URL. Returns if it changed.
- (BOOL)removeUnderline;

// Update the scroll position and schedule a redraw. Returns true if anything
// onscreen is blinking.
- (BOOL)refresh;

// Like refresh, but doesn't call sync.
- (BOOL)refreshAfterSync:(VT100SyncResult)syncResult;

- (void)setNeedsDisplayOnLine:(int)line;
- (void)setCursorNeedsDisplay;

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
- (void)lockScroll;

// Saving/printing
- (void)saveDocumentAs:(id)sender;
- (void)print:(id)sender;
// aString is either an NSString or an NSAttributedString.
- (void)printContent:(id)aString;

// Begins a new search. You may need to call continueFind repeatedly after this.
- (void)findString:(NSString*)aString
  forwardDirection:(BOOL)direction
      mode:(iTermFindMode)mode
        withOffset:(int)offset
scrollToFirstResult:(BOOL)scrollToFirstResult
             force:(BOOL)force;

// Remove highlighted terms from previous search.
// If resetContext is set then the search state will get reset to empty.
// Otherwise, search results and highlights are removed and can be updated
// on the next search.
- (void)clearHighlights:(BOOL)resetContext;

// Performs a find on the next chunk of text.
- (BOOL)continueFind:(double *)progress range:(NSRange *)rangePtr;

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
- (void)removeSearchResultsInRange:(VT100GridAbsCoordRange)range;

// When a new note is created, call this to add a view for it.
- (void)addViewForNote:(id<PTYAnnotationReading>)annotation focus:(BOOL)focus visible:(BOOL)visible;

// Makes sure not view frames are in the right places (e.g., after a resize).
- (void)updateNoteViewFrames;

// Show a visual highlight of a mark on the given line number.
- (void)highlightMarkOnLine:(int)line hasErrorCode:(BOOL)hasErrorCode;

// Open a semantic history path.
- (void)openSemanticHistoryPath:(NSString *)path
                  orRawFilename:(NSString *)rawFileName
                       fragment:(NSString *)fragment
               workingDirectory:(NSString *)workingDirectory
                     lineNumber:(NSString *)lineNumber
                   columnNumber:(NSString *)columnNumber
                         prefix:(NSString *)prefix
                         suffix:(NSString *)suffix
                     completion:(void (^)(BOOL ok))completion;

- (PTYFontInfo *)getFontForChar:(UniChar)ch
                      isComplex:(BOOL)isComplex
                     renderBold:(BOOL *)renderBold
                   renderItalic:(BOOL *)renderItalic
                       remapped:(UTF32Char *)ch;

- (NSColor*)colorForCode:(int)theIndex
                   green:(int)green
                    blue:(int)blue
               colorMode:(ColorMode)theMode
                    bold:(BOOL)isBold
                   faint:(BOOL)isFaint
            isBackground:(BOOL)isBackground;

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

// Menu for session title bar hamburger button
- (NSMenu *)titleBarMenu;

- (void)moveSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint
                  inDirection:(PTYTextViewSelectionExtensionDirection)direction
                           by:(PTYTextViewSelectionExtensionUnit)unit;

- (void)moveSelectionEndpoint:(PTYTextViewSelectionEndpoint)endpoint
                  inDirection:(PTYTextViewSelectionExtensionDirection)direction
                           by:(PTYTextViewSelectionExtensionUnit)unit
                  cursorCoord:(VT100GridCoord)cursorCoord;

- (void)selectCoordRange:(VT100GridCoordRange)range;
- (void)selectAbsWindowedCoordRange:(VT100GridAbsWindowedRange)windowedRange;

- (NSRect)frameForCoord:(VT100GridCoord)coord;

- (iTermLogicalMovementHelper *)logicalMovementHelperForCursorCoordinate:(VT100GridCoord)cursorCoord;

- (void)setTransparencyAffectsOnlyDefaultBackgroundColor:(BOOL)value;

- (IBAction)selectCurrentCommand:(id)sender;
- (IBAction)selectOutputOfLastCommand:(id)sender;

- (void)showFireworks;

// Turns on the flicker fixer (if enabled) while drawing.
- (void)performBlockWithFlickerFixerGrid:(void (NS_NOESCAPE ^)(void))block;

- (id)contentWithAttributes:(BOOL)attributes timestamps:(BOOL)timestamps;
- (void)setUseBoldColor:(BOOL)flag brighten:(BOOL)brighten;

- (void)drawRect:(NSRect)rect inView:(NSView *)view;

- (void)setAlphaValue:(CGFloat)alphaValue NS_UNAVAILABLE;
- (NSRect)rectForCoord:(VT100GridCoord)coord;
- (void)updateSubviewFrames;
- (NSDictionary *(^)(screen_char_t, iTermExternalAttribute *))attributeProviderUsingProcessedColors:(BOOL)processed
                                                                        elideDefaultBackgroundColor:(BOOL)elideDefaultBackgroundColor;
- (BOOL)copyBlock:(NSString *)block includingAbsLine:(long long)absLine;
- (void)setNeedsDisplay:(BOOL)needsDisplay NS_UNAVAILABLE;
- (void)setNeedsDisplayInRect:(NSRect)invalidRect NS_UNAVAILABLE;  // Use this instead of setNeedsDisplay:
- (void)requestDelegateRedraw;  // Use this instead of setNeedsDisplay:

- (iTermSelection *)selectionForCommandAndOutputOfMark:(id<VT100ScreenMarkReading>)mark;
- (void)smearCursorIfNeededWithDrawingHelper:(iTermTextDrawingHelper *)drawingHelper;
- (void)didFoldOrUnfold;
- (BOOL)updateMarginColor;

#pragma mark - Testing only

typedef NS_ENUM(NSUInteger, iTermCopyTextStyle) {
    iTermCopyTextStylePlainText,
    iTermCopyTextStyleAttributed,
    iTermCopyTextStyleWithControlSequences
};

@end

