#import <Cocoa/Cocoa.h>
#import "iTermColorMap.h"
#import "iTermEncoderAdapter.h"
#import "iTermIntervalTreeObserver.h"
#import "iTermMetadata.h"
#import "HighlightTrigger.h"
#import "PTYAnnotation.h"
#import "PTYTextViewDataSource.h"
#import "PTYTriggerEvaluator.h"
#import "Trigger.h"
#import "SCPPath.h"
#import "ScreenCharArray.h"
#import "VT100ScreenDelegate.h"
#import "VT100ScreenProgress.h"
#import "VT100SyncResult.h"
#import "VT100Terminal.h"
#import "VT100Token.h"

@class DVR;
@class iTermNotificationController;
@class iTermMark;
@class iTermStringLine;
@protocol iTermTemporaryDoubleBufferedGridControllerReading;
@class LineBuffer;
@class LineBufferPosition;
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
@protocol iTermLargeContentProvider;
@protocol iTermMark;
@class iTermSlownessDetector;
@class iTermTerminalContentSnapshot;
@class iTermTokenExecutor;

NS_ASSUME_NONNULL_BEGIN

// Key into dictionaryValue to get screen state.
extern NSString *const kScreenStateKey;

extern int kVT100ScreenMinColumns;
extern int kVT100ScreenMinRows;
extern const NSInteger VT100ScreenBigFileDownloadThreshold;

@interface VT100Screen : NSObject <
    PTYTextViewDataSource,
    PTYTriggerEvaluatorDataSource,
    iTermTriggerSession,
    iTermTriggerScopeProvider,
    iTermTriggerCallbackScheduler>

@property(nonatomic) BOOL terminalEnabled;
@property(atomic, weak, nullable) id<VT100ScreenDelegate> delegate;
@property(nonatomic, readonly) unsigned int maxScrollbackLines;
@property(nonatomic, readonly) BOOL unlimitedScrollback;
@property(nonatomic, readonly) BOOL useColumnScrollRegion;
@property(nonatomic, readonly) BOOL saveToScrollbackInAlternateScreen;
// Main thread only! Unlike all other state in VT100Screen, this one is never seen by the screen mutator.
@property(nonatomic, retain, nullable) DVR *dvr;
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

@property(nonatomic, weak, nullable) id<iTermIntervalTreeObserver> intervalTreeObserver;

@property(nonatomic, retain, readonly) id<iTermColorMapReading> colorMap;
@property(nonatomic, readonly, nullable) id<iTermTemporaryDoubleBufferedGridControllerReading> temporaryDoubleBuffer;
@property(nonatomic, readonly, nullable) id<VT100ScreenConfiguration> config;
@property(nonatomic, readonly) long long fakePromptDetectedAbsLine;
@property(nonatomic, readonly) long long lastPromptLine;
@property(nonatomic, readonly) BOOL echoProbeIsActive;

@property (nonatomic, readonly) BOOL terminalSoftAlternateScreenMode;
@property (nonatomic, readonly) MouseMode terminalMouseMode;
@property (nonatomic, readonly) NSStringEncoding terminalEncoding;
@property (nonatomic, readonly) BOOL terminalSendReceiveMode;
@property (nonatomic, readonly, nullable) VT100Output *terminalOutput;
@property (nonatomic, readonly) BOOL terminalAllowPasteBracketing;
@property (nonatomic, readonly) BOOL terminalBracketedPasteMode;
@property (nonatomic, readonly, nullable) NSArray<NSNumber *> *terminalSendModifiers;
@property (nonatomic, readonly) VT100TerminalKeyReportingFlags terminalKeyReportingFlags;
@property (nonatomic, readonly) BOOL terminalLiteralMode;
@property (nonatomic, readonly) iTermEmulationLevel terminalEmulationLevel;
@property (nonatomic, readonly) BOOL terminalReportFocus;
@property (nonatomic, readonly) BOOL terminalReportKeyUp;
@property (nonatomic, readonly) BOOL terminalCursorMode;
@property (nonatomic, readonly) BOOL terminalKeypadMode;
@property (nonatomic, readonly) BOOL terminalReceivingFile;
@property (nonatomic, readonly) BOOL terminalMetaSendsEscape;
@property (nonatomic, readonly) BOOL terminalReverseVideo;
@property (nonatomic, readonly) BOOL terminalAlternateScrollMode;
@property (nonatomic, readonly) BOOL terminalAutorepeatMode;
@property (nonatomic, readonly) BOOL terminalSendResizeNotifications;
@property (nonatomic, readonly) int terminalCharset;
@property (nonatomic, readonly, nullable) NSDictionary *terminalState;

// Where the next tail-find needs to begin.
@property (nonatomic) long long savedFindContextAbsPos;
@property (nonatomic, readonly) BOOL sendingIsBlocked;

@property (nonatomic, readonly) BOOL isAtCommandPrompt;
@property (nonatomic, readonly) VT100ScreenMutableState *mutableState;  // for tests
@property (nonatomic, readonly) VT100ScreenState *immutableState;  // for tests
@property (nonatomic, readonly) VT100ScreenProgress progress;

// Indicates if line drawing mode is enabled for any character set, or if the current character set
// is not G0.
- (BOOL)allCharacterSetPropertiesHaveDefaultValues;

// Preserves the prompt, but erases screen and scrollback buffer.
- (void)clearBuffer;

- (iTermAsyncFilter *)newAsyncFilterWithDestination:(id<iTermFilterDestination>)destination
                                              query:(NSString *)query
                                               mode:(iTermFindMode)mode
                                           refining:(nullable iTermAsyncFilter *)refining
                                       absLineRange:(NSRange)absLineRange
                                           progress:(nullable void (^)(double))progress;

- (NSString *)compactLineDump;
- (NSString *)compactLineDumpWithHistory;
- (NSString *)compactLineDumpWithHistoryAndContinuationMarks;
- (NSString *)compactLineDumpWithDividedHistoryAndContinuationMarks;

// This is provided for testing only.
- (id<VT100GridReading>)currentGrid;

- (void)resetAnimatedLines;

- (nullable iTermStringLine *)stringLineAsStringAtAbsoluteLineNumber:(long long)absoluteLineNumber
                                                           startPtr:(long long *)startAbsLineNumber;

#pragma mark - Marks and notes

- (nullable id<VT100ScreenMarkReading>)lastMark;
- (nullable id<VT100ScreenMarkReading>)lastPromptMark;
- (nullable id<VT100ScreenMarkReading>)lastScreenMark;
- (nullable id<VT100ScreenMarkReading>)firstPromptMark;
- (nullable id<VT100ScreenMarkReading>)firstScreenMark;
- (nullable id<VT100RemoteHostReading>)lastRemoteHost;
- (nullable id<VT100ScreenMarkReading>)promptMarkWithGUID:(NSString *)guid;
- (nullable id<VT100ScreenMarkReading>)namedMarkWithGUID:(NSString *)guid;
- (BOOL)markIsValid:(iTermMark *)mark;
- (VT100GridRange)lineNumberRangeOfInterval:(nullable Interval *)interval;
- (VT100GridAbsCoordRange)absCoordRangeForInterval:(nullable Interval *)interval;
- (void)enumeratePromptsFrom:(nullable NSString *)maybeFirst
                          to:(nullable NSString *)maybeLast
                       block:(void (^ NS_NOESCAPE)(id<VT100ScreenMarkReading> mark))block;
- (void)enumeratePortholes:(void (^ NS_NOESCAPE)(id<PortholeMarkReading> mark))block;

// These methods normally only return one object, but if there is a tie, all of the equally-positioned marks/notes are returned.

- (nullable NSArray<id<VT100ScreenMarkReading>> *)lastMarks;
- (nullable NSArray<id<VT100ScreenMarkReading>> *)firstMarks;
- (nullable NSArray<id<PTYAnnotationReading>> *)lastAnnotations;
- (nullable NSArray<id<PTYAnnotationReading>> *)firstAnnotations;

- (nullable NSArray *)marksOrNotesBefore:(nullable Interval *)location;
- (nullable NSArray *)marksOrNotesAfter:(nullable Interval *)location;

- (nullable NSArray *)marksBefore:(nullable Interval *)location;
- (nullable NSArray *)marksAfter:(nullable Interval *)location;

- (nullable id<VT100ScreenMarkReading>)screenMarkBefore:(nullable Interval *)location;

- (nullable NSArray *)annotationsBefore:(nullable Interval *)location;
- (nullable NSArray *)annotationsAfter:(nullable Interval *)location;

- (nullable id<VT100ScreenMarkReading>)commandMarkAtOrBeforeLine:(int)line;
- (nullable id<VT100ScreenMarkReading>)screenMarkAfterScreenMark:(nullable id<VT100ScreenMarkReading>)predecessor;
- (nullable id<VT100ScreenMarkReading>)promptMarkAfterScreenMark:(nullable id<VT100ScreenMarkReading>)predecessor;
- (nullable id<VT100ScreenMarkReading>)firstCommandMarkWithCommandInRange:(NSRange)absLineRange;
- (nullable id<VT100ScreenMarkReading>)lastCommandMarkWithCommandInRange:(NSRange)absLineRange;

- (BOOL)containsMark:(id<iTermMark>)mark;
- (void)clearToLastMark;

- (nullable NSString *)workingDirectoryOnLine:(int)line;
- (nullable id<VT100RemoteHostReading>)remoteHostOnLine:(int)line;
- (nullable id<VT100ScreenMarkReading>)lastCommandMark;  // last mark representing a command
- (nullable id<VT100ScreenMarkReading>)penultimateCommandMark;

- (BOOL)encodeContents:(id<iTermEncoderAdapter>)encoder
          linesDropped:(int * _Nullable)linesDroppedOut
             unlimited:(BOOL)unlimited;

// WARNING: This may change the screen size! Use -restoreInitialSize to restore it.
// This is useful for restoring other stuff that depends on the screen having its original size
// such as selections.
- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner
                   reattached:(BOOL)reattached
                    isArchive:(BOOL)isArchive
         largeContentProvider:(nullable id<iTermLargeContentProvider>)largeContentProvider;

// Uninitialize timestamps.
- (void)resetTimestamps;

- (void)enumerateLinesInRange:(NSRange)range block:(void (^)(int line, ScreenCharArray *, iTermImmutableMetadata, BOOL *))block;

- (void)enumerateObservableMarks:(void (^ NS_NOESCAPE)(iTermIntervalTreeObjectType, NSInteger, id<IntervalTreeObject>))block;
- (void)setColorsFromDictionary:(NSDictionary<NSNumber *, id> *)dict harmonize:(BOOL)harmonize;
- (void)setColor:(nullable NSColor *)color forKey:(int)key;
- (void)userDidPressReturn;

- (BOOL)shouldExpectPromptMarks;
- (BOOL)shouldExpectWorkingDirectoryUpdates;

- (nullable NSString *)commandInRange:(VT100GridCoordRange)range;
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
                                  expect:(nullable iTermExpect *)maybeExpect
                           checkTriggers:(VT100ScreenTriggerCheckType)checkTriggers
                           resetOverflow:(BOOL)resetOverflow
                            mutableState:(VT100ScreenMutableState *)mutableState;
- (void)performBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100Terminal * _Nullable terminal,
                                                            VT100ScreenMutableState *mutableState,
                                                            id<VT100ScreenDelegate> _Nullable delegate))block;
- (void)performBlockWithJoinedThreadsReentrantSafe:(void (^ NS_NOESCAPE)(VT100Terminal * _Nullable terminal,
                                                                         VT100ScreenMutableState *mutableState,
                                                                         id<VT100ScreenDelegate> _Nullable delegate))block;
- (void)performLightweightBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100ScreenMutableState *mutableState))block;
- (void)mutateAsynchronously:(void (^)(VT100Terminal * _Nullable terminal,
                                       VT100ScreenMutableState *mutableState,
                                       id<VT100ScreenDelegate> _Nullable delegate))block;
- (void)setForegroundJobAncestorsForTriggerFiltering:(nullable NSArray<NSString *> *)ancestors;
- (void)beginEchoProbeWithBackspace:(nullable NSData *)backspace
                           password:(NSString *)password
                           delegate:(id<iTermEchoProbeDelegate>)echoProbeDelegate;
- (void)sendPasswordInEchoProbe;
- (void)setEchoProbeDelegate:(id<iTermEchoProbeDelegate>)echoProbeDelegate;
- (void)resetEchoProbe;
- (void)threadedReadTask:(char *)buffer length:(int)length;

- (void)destructivelySetScreenWidth:(int)width
                             height:(int)height
                       mutableState:(VT100ScreenMutableState *)mutableState;
- (NSDictionary<NSString *, NSString *> *)exfiltratedEnvironmentVariables:(nullable NSArray<NSString *> *)names;

// These record the state that should be restored when ssh ends.
- (void)restoreSavedState:(NSDictionary *)savedState;
- (NSArray<id<VT100ScreenMarkReading>> *)namedMarks;
- (long long)startAbsLineForBlock:(NSString *)blockID;
- (VT100GridCoordRange)rangeOfOutputForCommandMark:(id<VT100ScreenMarkReading>)mark;
- (void)pauseAtNextPrompt:(nullable void (^)(void))paused;
- (long long)absLineNumberOfLastLineInLineBuffer;
- (iTermTerminalContentSnapshot *)snapshotForcingPrimaryGrid:(BOOL)forcePrimary;
- (LineBufferPosition *)positionForTailSearchOfScreen;
- (void)foldAbsLineRange:(NSRange)range;
- (NSString *)intervalTreeDump;
- (NSString *)wordEndingAt:(VT100GridCoord)coord
                     range:(nullable VT100GridWindowedRange *)rangePtr;
- (NSString *)wordBefore:(VT100GridCoord)coord
additionalWordCharacters:(nullable NSString *)additionalWordCharacters
                   range:(nullable VT100GridWindowedRange *)rangePtr;

// Fire an event trigger action. Must be called on the main queue.
- (void)fireEventTrigger:(Trigger *)trigger
         capturedStrings:(NSArray<NSString *> *)capturedStrings
        useInterpolation:(BOOL)useInterpolation;

@end

NS_ASSUME_NONNULL_END
