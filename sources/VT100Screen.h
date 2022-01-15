#import <Cocoa/Cocoa.h>
#import "iTermColorMap.h"
#import "iTermEncoderAdapter.h"
#import "iTermIntervalTreeObserver.h"
#import "iTermMetadata.h"
#import "HighlightTrigger.h"
#import "PTYAnnotation.h"
#import "PTYTextViewDataSource.h"
#import "PTYTriggerEvaluator.h"
#import "SCPPath.h"
#import "ScreenCharArray.h"
#import "VT100ScreenDelegate.h"
#import "VT100Terminal.h"
#import "VT100Token.h"

@class DVR;
@class iTermNotificationController;
@class iTermMark;
@class iTermStringLine;
@protocol iTermTemporaryDoubleBufferedGridControllerReading;
@class LineBuffer;
@class IntervalTree;
@class PTYTask;
@class VT100Grid;
@class VT100RemoteHost;
@class VT100ScreenMark;
@protocol VT100ScreenConfiguration;
@class VT100ScreenMutableState;
@class VT100Terminal;
@class iTermAsyncFilter;
@protocol iTermEchoProbeDelegate;
@class iTermExpect;
@protocol iTermFilterDestination;
@protocol iTermMark;
@class iTermSlownessDetector;
@class iTermTokenExecutor;

// Key into dictionaryValue to get screen state.
extern NSString *const kScreenStateKey;

extern int kVT100ScreenMinColumns;
extern int kVT100ScreenMinRows;
extern const NSInteger VT100ScreenBigFileDownloadThreshold;

@interface VT100Screen : NSObject <
    PTYTextViewDataSource,
    PTYTriggerEvaluatorDataSource>

@property(nonatomic, readonly, strong) VT100Terminal *terminal;
@property(nonatomic) BOOL terminalEnabled;
@property(nonatomic, assign) BOOL audibleBell;
@property(nonatomic, assign) BOOL showBellIndicator;
@property(nonatomic, assign) BOOL flashBell;
@property(nonatomic, weak) id<VT100ScreenDelegate> delegate;
@property(nonatomic, assign) BOOL postUserNotifications;
@property(nonatomic, assign) BOOL cursorBlinks;
@property(nonatomic, assign) BOOL allowTitleReporting;
@property(nonatomic, assign) unsigned int maxScrollbackLines;
@property(nonatomic, assign) BOOL unlimitedScrollback;
@property(nonatomic, readonly) BOOL useColumnScrollRegion;
@property(nonatomic, assign) BOOL saveToScrollbackInAlternateScreen;
// Main thread only! Unlike all other state in VT100Screen, this one is never seen by the screen mutator.
@property(nonatomic, retain) DVR *dvr;
@property(nonatomic, assign) BOOL trackCursorLineMovement;
@property(nonatomic, assign) BOOL appendToScrollbackWithStatusBar;
@property(nonatomic, readonly) VT100GridAbsCoordRange lastCommandOutputRange;
@property(nonatomic, assign) iTermUnicodeNormalization normalization;
@property(nonatomic, readonly) BOOL shellIntegrationInstalled;  // Just a guess.
@property(nonatomic, readonly) NSIndexSet *animatedLines;
@property(nonatomic, readonly) VT100GridAbsCoord startOfRunningCommandOutput;
@property(nonatomic, readonly) int lineNumberOfCursor;
@property(nonatomic, readonly) NSSize viewSize;

// Valid only if its x component is nonnegative.
// Gives the coordinate where the current command begins.
@property(nonatomic, readonly) VT100GridAbsCoord commandStartCoord;

// Assigning to `size` resizes the session and tty. Its contents are reflowed. The alternate grid's
// contents are reflowed, and the selection is updated. It is a little slow so be judicious.
@property(nonatomic, assign) VT100GridSize size;

@property(nonatomic, weak) id<iTermIntervalTreeObserver> intervalTreeObserver;

@property(nonatomic, retain, readonly) id<iTermColorMapReading> colorMap;
@property(nonatomic, readonly) id<iTermTemporaryDoubleBufferedGridControllerReading> temporaryDoubleBuffer;
@property(nonatomic, retain) id<VT100ScreenConfiguration> config;
@property(nonatomic) long long fakePromptDetectedAbsLine;
@property(nonatomic) long long lastPromptLine;
@property(nonatomic, readonly) BOOL echoProbeIsActive;

@property (nonatomic, readonly) BOOL terminalSoftAlternateScreenMode;
@property (nonatomic, readonly) MouseMode terminalMouseMode;
@property (nonatomic, readonly) NSStringEncoding terminalEncoding;
@property (nonatomic, readonly) BOOL terminalSendReceiveMode;
@property (nonatomic, readonly) VT100Output *terminalOutput;
@property (nonatomic, readonly) BOOL terminalAllowPasteBracketing;
@property (nonatomic, readonly) BOOL terminalBracketedPasteMode;
@property (nonatomic, readonly) NSMutableArray<NSNumber *> *terminalSendModifiers;
@property (nonatomic, readonly) VT100TerminalKeyReportingFlags terminalKeyReportingFlags;
@property (nonatomic, readonly) BOOL terminalReportFocus;
@property (nonatomic, readonly) BOOL terminalReportKeyUp;
@property (nonatomic, readonly) BOOL terminalCursorMode;
@property (nonatomic, readonly) BOOL terminalKeypadMode;
@property (nonatomic, readonly) BOOL terminalReceivingFile;
@property (nonatomic, readonly) BOOL terminalMetaSendsEscape;

// Designated initializer.
- (instancetype)initWithDarkMode:(BOOL)darkMode
                   configuration:(id<VT100ScreenConfiguration>)config;

// Indicates if line drawing mode is enabled for any character set, or if the current character set
// is not G0.
- (BOOL)allCharacterSetPropertiesHaveDefaultValues;

// Preserves the prompt, but erases screen and scrollback buffer.
- (void)clearBuffer;
- (void)clearBufferSavingPrompt:(BOOL)savePrompt;

// Clears the scrollback buffer, leaving screen contents alone.
- (void)clearScrollbackBuffer;

- (void)appendScreenChars:(const screen_char_t *)line
                   length:(int)length
   externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributes
             continuation:(screen_char_t)continuation;
- (void)setContentsFromLineBuffer:(LineBuffer *)lineBuffer;

// Append a string to the screen at the current cursor position. The terminal's insert and wrap-
// around modes are respected, the cursor is advanced, the screen may be scrolled, and the line
// buffer may change.
- (void)appendStringAtCursor:(NSString *)string;

- (void)removeLastLine;

// This is a hacky thing that moves the cursor to the next line, not respecting scroll regions.
// It's used for the tmux status screen.
- (void)crlf;

// Move the cursor down one position, scrolling if needed. Scroll regions are respected.
- (void)linefeed;

// Sets the primary grid's contents and scrollback history. |history| is an array of NSData
// containing screen_char_t's. It contains a bizarre workaround for tmux bugs.
- (void)setHistory:(NSArray *)history;

// Sets the alt grid's contents. |lines| is NSData with screen_char_t's.
- (void)setAltScreen:(NSArray *)lines;

// Load state from tmux. The |state| dictionary has keys from the kStateDictXxx values.
- (void)setTmuxState:(NSDictionary *)state;

// Set the colors in the range relative to the start of the given line number.
// See kHighlightXxxColor constants at the top of this file for dict keys, values are NSColor*s.
- (void)highlightTextInRange:(NSRange)range
   basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                      colors:(NSDictionary *)colors;

- (void)linkTextInRange:(NSRange)range
   basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                     URLCode:(unsigned int)code;

// Load a frame from a dvr decoder.
- (void)setFromFrame:(screen_char_t*)s len:(int)len metadata:(NSArray<NSArray *> *)metadataArrays info:(DVRFrameInfo)info;

// Save the position of the end of the scrollback buffer without the screen appended.
- (void)storeLastPositionInLineBufferAsFindContextSavedPosition;

// Restore the saved position into a passed-in find context (see saveFindContextAbsPos and
// storeLastPositionInLineBufferAsFindContextSavedPosition).
- (void)restoreSavedPositionToFindContext:(FindContext *)context;
- (void)restorePreferredCursorPositionIfPossible;

- (iTermAsyncFilter *)newAsyncFilterWithDestination:(id<iTermFilterDestination>)destination
                                              query:(NSString *)query
                                           refining:(iTermAsyncFilter *)refining
                                           progress:(void (^)(double))progress;

- (NSString *)compactLineDump;
- (NSString *)compactLineDumpWithHistory;
- (NSString *)compactLineDumpWithHistoryAndContinuationMarks;

// This is provided for testing only.
- (id<VT100GridReading>)currentGrid;

- (void)resetAnimatedLines;

- (iTermStringLine *)stringLineAsStringAtAbsoluteLineNumber:(long long)absoluteLineNumber
                                                   startPtr:(long long *)startAbsLineNumber;

#pragma mark - Marks and notes

- (VT100ScreenMark *)lastMark;
- (VT100ScreenMark *)lastPromptMark;
- (VT100RemoteHost *)lastRemoteHost;
- (VT100ScreenMark *)promptMarkWithGUID:(NSString *)guid;
- (BOOL)markIsValid:(iTermMark *)mark;
- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass;
- (VT100GridRange)lineNumberRangeOfInterval:(Interval *)interval;
- (void)enumeratePromptsFrom:(NSString *)maybeFirst
                          to:(NSString *)maybeLast
                       block:(void (^ NS_NOESCAPE)(VT100ScreenMark *mark))block;
// These methods normally only return one object, but if there is a tie, all of the equally-positioned marks/notes are returned.

- (NSArray<VT100ScreenMark *> *)lastMarks;
- (NSArray<VT100ScreenMark *> *)firstMarks;
- (NSArray<PTYAnnotation *> *)lastAnnotations;
- (NSArray<PTYAnnotation *> *)firstAnnotations;

- (NSArray *)marksOrNotesBefore:(Interval *)location;
- (NSArray *)marksOrNotesAfter:(Interval *)location;

- (NSArray *)marksBefore:(Interval *)location;
- (NSArray *)marksAfter:(Interval *)location;

- (NSArray *)annotationsBefore:(Interval *)location;
- (NSArray *)annotationsAfter:(Interval *)location;

- (BOOL)containsMark:(id<iTermMark>)mark;
- (void)clearToLastMark;
- (void)clearFromAbsoluteLineToEnd:(long long)absLine;

- (void)setWorkingDirectory:(NSString *)workingDirectory onLine:(int)line pushed:(BOOL)pushed;
- (NSString *)workingDirectoryOnLine:(int)line;
- (VT100RemoteHost *)remoteHostOnLine:(int)line;
- (VT100ScreenMark *)lastCommandMark;  // last mark representing a command
- (id<iTermMark>)markAddedAtCursorOfClass:(Class)theClass;

- (BOOL)encodeContents:(id<iTermEncoderAdapter>)encoder
          linesDropped:(int *)linesDroppedOut;

// WARNING: This may change the screen size! Use -restoreInitialSize to restore it.
// This is useful for restoring other stuff that depends on the screen having its original size
// such as selections.
- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner
                   reattached:(BOOL)reattached;
- (void)restoreInitialSize;

// Uninitialize timestamps.
- (void)resetTimestamps;

- (void)enumerateLinesInRange:(NSRange)range block:(void (^)(int line, ScreenCharArray *, iTermImmutableMetadata, BOOL *))block;

// Fake shell integration via triggers APIs
- (void)promptDidStartAt:(VT100GridAbsCoord)coord;
- (void)commandDidStartAt:(VT100GridAbsCoord)coord;

- (void)enumerateObservableMarks:(void (^ NS_NOESCAPE)(iTermIntervalTreeObjectType, NSInteger))block;
// Load 256 colors, but not ANSI (0-15).
- (void)loadInitialColorTable;
- (void)setColor:(NSColor *)color forKey:(int)key;
- (void)setDimOnlyText:(BOOL)dimOnlyText;
- (void)setDarkMode:(BOOL)darkMode;
- (void)setUseSeparateColorsForLightAndDarkMode:(BOOL)value;
- (void)setMinimumContrast:(float)value;
- (void)setMutingAmount:(double)value;
- (void)setDimmingAmount:(double)value;
- (void)userDidPressReturn;

// This changes shared state and is called during initialization.
- (void)setShouldExpectPromptMarks:(BOOL)value;
- (BOOL)shouldExpectPromptMarks;

- (NSString *)commandInRange:(VT100GridCoordRange)range;
- (BOOL)haveCommandInRange:(VT100GridCoordRange)range;
- (VT100GridCoordRange)commandRange;
- (void)addTokens:(CVector)vector length:(int)length highPriority:(BOOL)highPriority;
- (void)scheduleTokenExecution;
- (PTYAnnotation *)addNoteWithText:(NSString *)text inAbsoluteRange:(VT100GridAbsCoordRange)absRange;
- (void)injectData:(NSData *)data;
- (void)setExited:(BOOL)exited;
- (void)forceCheckTriggers;
- (void)performPeriodicTriggerCheck;
- (void)synchronizeWithConfig:(id<VT100ScreenConfiguration>)sourceConfig
                       expect:(iTermExpect *)maybeExpect
                checkTriggers:(BOOL)checkTriggers;
- (void)performBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100Terminal *terminal,
                                                            VT100ScreenMutableState *mutableState,
                                                            id<VT100ScreenDelegate> delegate))block;
- (void)beginEchoProbeWithBackspace:(NSData *)backspace
                           password:(NSString *)password
                           delegate:(id<iTermEchoProbeDelegate>)echoProbeDelegate;
- (void)sendPasswordInEchoProbe;
- (void)setEchoProbeDelegate:(id<iTermEchoProbeDelegate>)echoProbeDelegate;
- (void)resetEchoProbe;
- (void)threadedReadTask:(char *)buffer length:(int)length;

@end

@interface VT100Screen (Testing)

- (void)setMayHaveDoubleWidthCharacters:(BOOL)value;
// Destructively sets the screen size.
- (void)destructivelySetScreenWidth:(int)width height:(int)height;

@end
