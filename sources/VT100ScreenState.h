//
//  VT100ScreenState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/21.
//
// All state from VT100Screen should eventually migrate here to facilitate a division between
// mutable and immutable code paths.

#import <Foundation/Foundation.h>

#import "IntervalTree.h"
#import "LineBuffer.h"
#import "PTYTriggerEvaluator.h"
#import "VT100Grid.h"
#import "VT100ScreenConfiguration.h"
#import "VT100ScreenMark.h"
#import "VT100Terminal.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermColorMap.h"
#import "iTermIntervalTreeObserver.h"
#import "iTermMark.h"
#import "iTermTemporaryDoubleBufferedGridController.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kScreenStateKey;

extern NSString *const kScreenStateTabStopsKey;
extern NSString *const kScreenStateTerminalKey;
extern NSString *const kScreenStateLineDrawingModeKey;
extern NSString *const kScreenStateNonCurrentGridKey;
extern NSString *const kScreenStateCurrentGridIsPrimaryKey;
extern NSString *const kScreenStateIntervalTreeKey;
extern NSString *const kScreenStateSavedIntervalTreeKey;
extern NSString *const kScreenStateCommandStartXKey;
extern NSString *const kScreenStateCommandStartYKey;
extern NSString *const kScreenStateNextCommandOutputStartKey;
extern NSString *const kScreenStateCursorVisibleKey;
extern NSString *const kScreenStateTrackCursorLineMovementKey;
extern NSString *const kScreenStateLastCommandOutputRangeKey;
extern NSString *const kScreenStateShellIntegrationInstalledKey;
extern NSString *const kScreenStateLastCommandMarkKey;
extern NSString *const kScreenStatePrimaryGridStateKey;
extern NSString *const kScreenStateAlternateGridStateKey;
extern NSString *const kScreenStateCursorCoord;
extern NSString *const kScreenStateProtectedMode;
extern NSString *const kScreenStateExfiltratedEnvironmentKey;

@class IntervalTree;
@class iTermOrderEnforcer;

@protocol VT100ScreenState<NSObject>

@property (nonatomic, readonly) BOOL audibleBell;
@property (nonatomic, readonly) BOOL showBellIndicator;
@property (nonatomic, readonly) BOOL flashBell;
@property (nonatomic, readonly) BOOL postUserNotifications;
@property (nonatomic, readonly) BOOL cursorBlinks;

// When set, strings, newlines, and linefeeds are appended to printBuffer_. When ANSICSI_PRINT
// with code 4 is received, it's sent for printing.
@property (nonatomic, readonly) BOOL collectInputForPrinting;

@property (nullable, nonatomic, strong, readonly) NSString *printBuffer;

// OK to report window title?
@property (nonatomic, readonly) BOOL allowTitleReporting;

@property (nonatomic, readonly) NSTimeInterval lastBell;

// base64 value to copy to pasteboard, being built up bit by bit.
@property (nullable, nonatomic, strong, readonly) NSString *pasteboardString;

// All currently available marks and notes. Maps an interval of
//   (startx + absstarty * (width+1)) to (endx + absendy * (width+1))
// to an id<IntervalTreeObject>, which is either PTYNoteViewController or VT100ScreenMark.
@property (nonatomic, strong, readonly) id<IntervalTreeReading> intervalTree;

@property (nonatomic, strong, readonly) id<VT100GridReading> primaryGrid;
@property (nullable, nonatomic, strong, readonly) id<VT100GridReading> altGrid;
// Points to either primaryGrid or altGrid.
@property (nonatomic, strong, readonly) id<VT100GridReading> currentGrid;
// When a saved grid is swapped in, this is the live current grid.
@property (nonatomic, strong, readonly) id<VT100GridReading> realCurrentGrid;

// Holds notes on alt/primary grid (the one we're not in). The origin is the top-left of the
// grid.
@property (nullable, nonatomic, strong, readonly) id<IntervalTreeReading> savedIntervalTree;

// Cached copies of terminal attributes
@property (nonatomic, readonly) BOOL wraparoundMode;
@property (nonatomic, readonly) BOOL ansi;
@property (nonatomic, readonly) BOOL insert;

// This flag overrides maxScrollbackLines:
@property (nonatomic, readonly) BOOL unlimitedScrollback;

@property (nonatomic, readonly) int scrollbackOverflow;

// Location of the start of the current command, or (-1, -1) for none.
@property (nonatomic, readonly) VT100GridAbsCoord commandStartCoord;

// Maps an absolute line number to a VT100ScreenMark.
@property (nonatomic, strong, readonly) id<iTermMarkCacheReading> markCache;

// Max size of scrollback buffer
@property (nonatomic, readonly) unsigned int maxScrollbackLines;

@property (nonatomic, strong, readonly) NSSet<NSNumber *> *tabStops;

// Indicates which character set (they are represented by numbers) are in line-drawing mode.
// Valid charsets are in 0..<NUM_CHARSETS
@property (nonatomic, strong, readonly) NSSet<NSNumber *> *charsetUsesLineDrawingMode;

// For REP
@property (nonatomic, readonly) screen_char_t lastCharacter;
@property (nonatomic, readonly) BOOL lastCharacterIsDoubleWidth;
@property (nullable, nonatomic, strong, readonly) iTermExternalAttribute *lastExternalAttribute;

@property (nonatomic, readonly) BOOL saveToScrollbackInAlternateScreen;
@property (nonatomic, readonly) BOOL cursorVisible;
@property (nonatomic, readonly) BOOL shellIntegrationInstalled;
@property (nonatomic, readonly) VT100GridAbsCoordRange lastCommandOutputRange;

// Valid while at the command prompt only. Gives the range of the current prompt. Meaningful
// only if the end is not equal to the start.
@property(nonatomic, readonly) VT100GridAbsCoordRange currentPromptRange;

@property (nonatomic, readonly) VT100GridAbsCoord startOfRunningCommandOutput;
@property (nonatomic, readonly) VT100TerminalProtectedMode protectedMode;

// Initial size before calling -restoreFromDictionary… or -1,-1 if invalid.
@property (nonatomic, readonly) VT100GridSize initialSize;

// A rarely reset count of the number of lines lost to scrollback overflow. Adding this to a
// line number gives a unique line number that won't be reused when the linebuffer overflows.
@property (nonatomic, readonly) long long cumulativeScrollbackOverflow;

@property (nonatomic, strong, readonly) id<LineBufferReading> linebuffer;
@property (nonatomic, readonly) BOOL trackCursorLineMovement;
@property (nonatomic, readonly) BOOL appendToScrollbackWithStatusBar;
@property (nonatomic, readonly) iTermUnicodeNormalization normalization;
@property (nonatomic, weak, readonly) id<iTermIntervalTreeObserver> intervalTreeObserver;
// Note that the ivar for lastCommandMark *is* mutable because it is used as a cache.
@property (nullable, nonatomic, strong, readonly) id<VT100ScreenMarkReading> lastCommandMark;
@property (nonatomic, strong, readonly) id<iTermColorMapReading> colorMap;
@property (nonatomic, strong, readonly) id<iTermTemporaryDoubleBufferedGridControllerReading> temporaryDoubleBuffer;

// -2: Within command output (inferred)
// -1: Uninitialized
// >= 0: The line the prompt is at
@property (nonatomic, readonly) long long fakePromptDetectedAbsLine;

// Line where last prompt begain
@property (nonatomic, readonly) long long lastPromptLine;

// Did we get FinalTerm codes that report info about prompt? Used to decide if advanced paste
// can wait for prompts.
@property (nonatomic, readonly) BOOL shouldExpectPromptMarks;
@property (nonatomic, readonly) BOOL echoProbeIsActive;

// From VT100Terminal - no mutable equivalents provided.
@property (nonatomic, readonly) BOOL terminalSoftAlternateScreenMode;
@property (nonatomic, readonly) MouseMode terminalMouseMode;
@property (nonatomic, readonly) NSStringEncoding terminalEncoding;
@property (nonatomic, readonly) BOOL terminalSendReceiveMode;
@property (nonatomic, readonly) VT100Output *terminalOutput;
@property (nonatomic, readonly) BOOL terminalAllowPasteBracketing;
@property (nonatomic, readonly) BOOL terminalBracketedPasteMode;
@property (nonatomic, readonly) NSArray<NSNumber *> *terminalSendModifiers;
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
@property (nonatomic, readonly) MouseMode terminalPreviousMouseMode;
@property (nonatomic, readonly) screen_char_t terminalForegroundColorCode;
@property (nonatomic, readonly) screen_char_t terminalBackgroundColorCode;
@property (nonatomic, readonly) NSDictionary *terminalState;
@property (nonatomic, copy, readonly) id<VT100ScreenConfiguration> config;
@property (nullable, nonatomic, strong, readonly) NSArray<iTermTuple<NSString *, NSString *> *> *exfiltratedEnvironment;

@end

@protocol VT100ScreenMutableState<VT100ScreenState>
@property (nonatomic, readwrite) BOOL audibleBell;
@property (nonatomic, readwrite) BOOL showBellIndicator;
@property (nonatomic, readwrite) BOOL flashBell;
@property (nonatomic, readwrite) BOOL postUserNotifications;
@property (nonatomic, readwrite) BOOL cursorBlinks;
@property (nonatomic, readwrite) BOOL collectInputForPrinting;
@property (nullable, nonatomic, strong, readwrite) NSMutableString *printBuffer;
@property (nonatomic, readwrite) BOOL allowTitleReporting;
@property (nonatomic, readwrite) NSTimeInterval lastBell;
@property (nullable, nonatomic, strong, readwrite) NSMutableString *pasteboardString;
@property (nonatomic, strong, readwrite) id<IntervalTreeReading> intervalTree;

@property (nonatomic, strong, readwrite) VT100Grid *primaryGrid;
@property (nullable, nonatomic, strong, readwrite) VT100Grid *altGrid;
@property (nonatomic, strong, readwrite) VT100Grid *currentGrid;
// When a saved grid is swapped in, this is the live current grid.
@property (nullable, nonatomic, strong, readwrite) VT100Grid *realCurrentGrid;
@property (nullable, nonatomic, strong, readwrite) id<IntervalTreeReading> savedIntervalTree;
@property (nonatomic, readwrite) BOOL wraparoundMode;
@property (nonatomic, readwrite) BOOL ansi;
@property (nonatomic, readwrite) BOOL insert;

// How many scrollback lines have been lost due to overflow. Periodically reset with
// -resetScrollbackOverflow.
@property (nonatomic, readwrite) int scrollbackOverflow;
@property (nonatomic, readwrite) VT100GridAbsCoord commandStartCoord;
@property (nonatomic, strong, readwrite) iTermMarkCache *markCache;
@property (nonatomic, readwrite) unsigned int maxScrollbackLines;
@property (nonatomic, strong, readwrite) NSMutableSet<NSNumber *> *tabStops;
@property (nonatomic, strong) NSMutableSet<NSNumber *> *charsetUsesLineDrawingMode;
@property (nonatomic, readwrite) screen_char_t lastCharacter;
@property (nonatomic, readwrite) BOOL lastCharacterIsDoubleWidth;
@property (nullable, nonatomic, strong, readwrite) iTermExternalAttribute *lastExternalAttribute;
@property (nonatomic, readwrite) BOOL saveToScrollbackInAlternateScreen;
@property (nonatomic, readwrite) BOOL cursorVisible;
@property (nonatomic, readwrite) BOOL shellIntegrationInstalled;
@property (nonatomic, readwrite) VT100GridAbsCoordRange lastCommandOutputRange;
@property (nonatomic, readwrite) VT100GridAbsCoordRange currentPromptRange;
@property (nonatomic, readwrite) VT100GridAbsCoord startOfRunningCommandOutput;
@property (nonatomic, readwrite) VT100TerminalProtectedMode protectedMode;
@property (nonatomic, readwrite) VT100GridSize initialSize;
@property (nonatomic, readwrite) long long cumulativeScrollbackOverflow;
@property (nonatomic, strong, readwrite) LineBuffer *linebuffer;
@property (nonatomic, readwrite) BOOL trackCursorLineMovement;
@property (nonatomic, weak, readwrite) id<iTermIntervalTreeObserver> intervalTreeObserver;
@property (nullable, nonatomic, strong, readwrite) id<VT100ScreenMarkReading> lastCommandMark;
@property (nonatomic, strong, readwrite) iTermTemporaryDoubleBufferedGridController *temporaryDoubleBuffer;
@property (nonatomic, readwrite) long long fakePromptDetectedAbsLine;
@property (nonatomic, readwrite) long long lastPromptLine;
@property (nonatomic, readwrite) BOOL shouldExpectPromptMarks;
@property (nonatomic, copy, readwrite) id<VT100ScreenConfiguration> config;
@property (nullable, nonatomic, strong, readwrite) NSArray<iTermTuple<NSString *, NSString *> *> *exfiltratedEnvironment;

@end

@interface VT100ScreenState: NSObject<
    PTYTriggerEvaluatorDataSource,
    VT100GridDelegate,
    VT100ScreenState,
    iTermTextDataSource>

- (instancetype)init NS_UNAVAILABLE;
- (void)mergeFrom:(VT100ScreenMutableState *)source;

#pragma mark - Grid

@property (nonatomic, readonly) int cursorY;
@property (nonatomic, readonly) int cursorX;
@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int height;
@property (nonatomic, readonly) BOOL cursorOutsideLeftRightMargin;
@property (nonatomic, readonly) BOOL cursorOutsideTopBottomMargin;

@property (nonatomic, readonly) int lineNumberOfCursor;

#pragma mark - Scollback

@property (nonatomic, readonly) int numberOfScrollbackLines;

#pragma mark - Combined Grid And Scrollback

@property (nonatomic, readonly) int numberOfLines;

- (iTermImmutableMetadata)metadataOnLine:(int)lineNumber;

// Like getLineAtIndex:withBuffer:, but uses dedicated storage for the result.
// This function is dangerous! It writes to an internal buffer and returns a
// pointer to it. Better to use getLineAtIndex:withBuffer:.
- (const screen_char_t *)getLineAtIndex:(int)theIndex;

- (const screen_char_t *)getLineAtIndex:(int)theIndex withBuffer:(screen_char_t *)buffer;

- (iTermStringLine *)stringLineAsStringAtAbsoluteLineNumber:(long long)absoluteLineNumber
                                                   startPtr:(long long *)startAbsLineNumber;

- (void)enumerateLinesInRange:(NSRange)range
                        block:(void (^)(int,
                                        ScreenCharArray *,
                                        iTermImmutableMetadata,
                                        BOOL *))block;

- (int)numberOfLinesDroppedWhenEncodingContentsIncludingGrid:(BOOL)includeGrid
                                                     encoder:(id<iTermEncoderAdapter>)encoder
                                              intervalOffset:(long long *)intervalOffsetPtr;

#pragma mark - Interval Tree

// WARNING - If you add any new APIs that return interval tree objects update VT100ScreenStateSanitizingAdapter

- (VT100GridCoordRange)coordRangeForInterval:(Interval *)interval;
- (VT100GridAbsCoordRange)absCoordRangeForInterval:(Interval *)interval;
- (VT100GridRange)lineNumberRangeOfInterval:(Interval *)interval;
- (Interval *)intervalForGridCoordRange:(VT100GridCoordRange)range;
- (Interval *)intervalForGridAbsCoordRange:(VT100GridAbsCoordRange)range;
- (Interval *)intervalForGridAbsCoordRange:(VT100GridAbsCoordRange)absRange
                                     width:(int)width;

- (__kindof id<IntervalTreeImmutableObject>)objectOnOrBeforeLine:(int)line ofClass:(Class)cls;

// WARNING - If you add any new APIs that return interval tree objects update VT100ScreenStateSanitizingAdapter

#pragma mark - Shell Integration

// WARNING - If you add any new APIs that return interval tree objects update VT100ScreenStateSanitizingAdapter

@property (nonatomic, readonly) id<VT100RemoteHostReading> lastRemoteHost;
@property (nonatomic, readonly) id<VT100ScreenMarkReading> lastPromptMark;

// If at a shell prompt, this gives the range of the command being edited not past the cursor.
// If not at a prompt (no shell integration or command is running) this is -1,-1,-1,-1.
@property (nonatomic, readonly) VT100GridCoordRange commandRange;

// Like commandRange but goes past the cursor position if it's in the middle of a command.
@property (nonatomic, readonly) VT100GridCoordRange extendedCommandRange;

- (BOOL)haveCommandInRange:(VT100GridCoordRange)range;

- (id<VT100ScreenMarkReading> _Nullable)markOnLine:(int)line;

- (NSString *)commandInRange:(VT100GridCoordRange)range;

- (id<IntervalTreeImmutableObject>)lastMarkMustBePrompt:(BOOL)wantPrompt class:(Class)theClass;

- (id<VT100RemoteHostReading>)remoteHostOnLine:(int)line;

- (NSString *)workingDirectoryOnLine:(int)line;

// WARNING - If you add any new APIs that return interval tree objects update VT100ScreenStateSanitizingAdapter

#pragma mark - Colors

- (int)colorMapKeyForTerminalColorIndex:(VT100TerminalColorIndex)n;

#pragma mark - Advanced Prefs

@property (nonatomic, readonly) BOOL terminalIsTrusted;

#pragma mark - Double Buffer

@property (nonatomic, readonly) iTermTemporaryDoubleBufferedGridController *unconditionalTemporaryDoubleBuffer;

- (void)performBlockWithSavedGrid:(void (^)(id<PTYTextViewSynchronousUpdateStateReading> _Nullable state))block;

#pragma mark - Development

- (NSString *)compactLineDumpWithHistoryAndContinuationMarksAndLineNumbers;

@end


NS_ASSUME_NONNULL_END
