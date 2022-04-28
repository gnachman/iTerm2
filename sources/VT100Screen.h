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
#import "VT100SyncResult.h"
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
@protocol PortholeMarkReading;
@class VT100Grid;
@class VT100MutableScreenConfiguration;
@protocol VT100RemoteHostReading;
@class VT100ScreenMark;
@protocol VT100ScreenMarkReading;
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

@property(nonatomic) BOOL terminalEnabled;
@property(nonatomic, assign) BOOL audibleBell;
@property(nonatomic, assign) BOOL showBellIndicator;
@property(nonatomic, assign) BOOL flashBell;
@property(atomic, weak) id<VT100ScreenDelegate> delegate;
@property(nonatomic, assign) BOOL postUserNotifications;
@property(nonatomic, assign) BOOL cursorBlinks;
@property(nonatomic, assign) BOOL allowTitleReporting;
@property(nonatomic, readonly) unsigned int maxScrollbackLines;
@property(nonatomic, readonly) BOOL unlimitedScrollback;
@property(nonatomic, readonly) BOOL useColumnScrollRegion;
@property(nonatomic, readonly) BOOL saveToScrollbackInAlternateScreen;
// Main thread only! Unlike all other state in VT100Screen, this one is never seen by the screen mutator.
@property(nonatomic, retain) DVR *dvr;
@property(nonatomic, assign) BOOL trackCursorLineMovement;
@property(nonatomic, readonly) BOOL appendToScrollbackWithStatusBar;
@property(nonatomic, readonly) VT100GridAbsCoordRange lastCommandOutputRange;
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
@property(nonatomic, readonly) id<VT100ScreenConfiguration> config;
@property(nonatomic, readonly) long long fakePromptDetectedAbsLine;
@property(nonatomic, readonly) long long lastPromptLine;
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
@property (nonatomic, readonly) BOOL terminalReverseVideo;
@property (nonatomic, readonly) BOOL terminalAlternateScrollMode;
@property (nonatomic, readonly) BOOL terminalAutorepeatMode;
@property (nonatomic, readonly) int terminalCharset;

// Where the next tail-find needs to begin.
@property (nonatomic) long long savedFindContextAbsPos;
@property (nonatomic, strong) FindContext *findContext;

// Indicates if line drawing mode is enabled for any character set, or if the current character set
// is not G0.
- (BOOL)allCharacterSetPropertiesHaveDefaultValues;

// Preserves the prompt, but erases screen and scrollback buffer.
- (void)clearBuffer;

// Save the position of the end of the scrollback buffer without the screen appended.
- (void)storeLastPositionInLineBufferAsFindContextSavedPosition;

// Restore the saved position into a passed-in find context (see saveFindContextAbsPos and
// storeLastPositionInLineBufferAsFindContextSavedPosition).
- (void)restoreSavedPositionToFindContext:(FindContext *)context;

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

- (id<VT100ScreenMarkReading>)lastMark;
- (id<VT100ScreenMarkReading>)lastPromptMark;
- (id<VT100RemoteHostReading>)lastRemoteHost;
- (id<VT100ScreenMarkReading>)promptMarkWithGUID:(NSString *)guid;
- (BOOL)markIsValid:(iTermMark *)mark;
- (VT100GridRange)lineNumberRangeOfInterval:(Interval *)interval;
- (void)enumeratePromptsFrom:(NSString *)maybeFirst
                          to:(NSString *)maybeLast
                       block:(void (^ NS_NOESCAPE)(id<VT100ScreenMarkReading> mark))block;
- (void)enumeratePortholes:(void (^ NS_NOESCAPE)(id<PortholeMarkReading> mark))block;

// These methods normally only return one object, but if there is a tie, all of the equally-positioned marks/notes are returned.

- (NSArray<id<VT100ScreenMarkReading>> *)lastMarks;
- (NSArray<id<VT100ScreenMarkReading>> *)firstMarks;
- (NSArray<id<PTYAnnotationReading>> *)lastAnnotations;
- (NSArray<id<PTYAnnotationReading>> *)firstAnnotations;

- (NSArray *)marksOrNotesBefore:(Interval *)location;
- (NSArray *)marksOrNotesAfter:(Interval *)location;

- (NSArray *)marksBefore:(Interval *)location;
- (NSArray *)marksAfter:(Interval *)location;

- (NSArray *)annotationsBefore:(Interval *)location;
- (NSArray *)annotationsAfter:(Interval *)location;

- (BOOL)containsMark:(id<iTermMark>)mark;
- (void)clearToLastMark;

- (NSString *)workingDirectoryOnLine:(int)line;
- (id<VT100RemoteHostReading>)remoteHostOnLine:(int)line;
- (id<VT100ScreenMarkReading>)lastCommandMark;  // last mark representing a command

- (BOOL)encodeContents:(id<iTermEncoderAdapter>)encoder
          linesDropped:(int *)linesDroppedOut;

// WARNING: This may change the screen size! Use -restoreInitialSize to restore it.
// This is useful for restoring other stuff that depends on the screen having its original size
// such as selections.
- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner
                   reattached:(BOOL)reattached;

// Uninitialize timestamps.
- (void)resetTimestamps;

- (void)enumerateLinesInRange:(NSRange)range block:(void (^)(int line, ScreenCharArray *, iTermImmutableMetadata, BOOL *))block;

- (void)enumerateObservableMarks:(void (^ NS_NOESCAPE)(iTermIntervalTreeObjectType, NSInteger))block;
- (void)setColorsFromDictionary:(NSDictionary<NSNumber *, id> *)dict;
- (void)setColor:(NSColor *)color forKey:(int)key;
- (void)userDidPressReturn;

- (BOOL)shouldExpectPromptMarks;

- (NSString *)commandInRange:(VT100GridCoordRange)range;
- (BOOL)haveCommandInRange:(VT100GridCoordRange)range;
- (VT100GridCoordRange)commandRange;
- (VT100GridCoordRange)extendedCommandRange;
- (void)injectData:(NSData *)data;

typedef NS_ENUM(NSUInteger, VT100ScreenTriggerCheckType) {
    VT100ScreenTriggerCheckTypeNone,
    VT100ScreenTriggerCheckTypePartialLines,
    VT100ScreenTriggerCheckTypeFullLines
};

- (VT100ScreenState *)switchToSharedState;
- (void)restoreState:(VT100ScreenState *)state;

- (VT100SyncResult)synchronizeWithConfig:(VT100MutableScreenConfiguration *)sourceConfig
                                  expect:(iTermExpect *)maybeExpect
                           checkTriggers:(VT100ScreenTriggerCheckType)checkTriggers
                           resetOverflow:(BOOL)resetOverflow
                            mutableState:(VT100ScreenMutableState *)mutableState;
- (void)performBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100Terminal *terminal,
                                                            VT100ScreenMutableState *mutableState,
                                                            id<VT100ScreenDelegate> delegate))block;
- (void)performLightweightBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100ScreenMutableState *mutableState))block;
- (void)mutateAsynchronously:(void (^)(VT100Terminal *terminal,
                                       VT100ScreenMutableState *mutableState,
                                       id<VT100ScreenDelegate> delegate))block;
- (void)beginEchoProbeWithBackspace:(NSData *)backspace
                           password:(NSString *)password
                           delegate:(id<iTermEchoProbeDelegate>)echoProbeDelegate;
- (void)sendPasswordInEchoProbe;
- (void)setEchoProbeDelegate:(id<iTermEchoProbeDelegate>)echoProbeDelegate;
- (void)resetEchoProbe;
- (void)threadedReadTask:(char *)buffer length:(int)length;

- (void)destructivelySetScreenWidth:(int)width
                             height:(int)height
                       mutableState:(VT100ScreenMutableState *)mutableState;

@end

@interface VT100Screen (Testing)

// Destructively sets the screen size.
- (void)destructivelySetScreenWidth:(int)width height:(int)height;

@end
