//
//  VT100ScreenMutableState.h
//  iTerm2
//
//  Created by George Nachman on 12/28/21.
//

#import <Foundation/Foundation.h>
#import "VT100ScreenState.h"
#import "VT100ScreenDelegate.h"

@protocol VT100ScreenConfiguration;
@protocol iTermOrderedToken;
@class iTermTokenExecutor;

NS_ASSUME_NONNULL_BEGIN

@protocol VT100ScreenSideEffectPerforming<NSObject>
- (id<VT100ScreenDelegate>)sideEffectPerformingScreenDelegate;
- (id<iTermIntervalTreeObserver>)sideEffectPerformingIntervalTreeObserver;
@end

@interface VT100ScreenMutableState: VT100ScreenState<NSCopying, VT100ScreenMutableState>
@property (nonatomic, strong, readwrite) iTermOrderEnforcer *currentDirectoryDidChangeOrderEnforcer;
@property (nullable, nonatomic, strong) VT100InlineImageHelper *inlineImageHelper;
@property (nonatomic, strong, readwrite) iTermOrderEnforcer *setWorkingDirectoryOrderEnforcer;
@property (atomic, weak) id<VT100ScreenSideEffectPerforming> sideEffectPerformer;
@property (nonatomic, copy) id<VT100ScreenConfiguration> config;
@property (nonatomic, readonly) iTermTokenExecutor *tokenExecutor;
@property (nonatomic) BOOL exited;

#warning TODO: Remove slownessDetector
- (instancetype)initWithSideEffectPerformer:(id<VT100ScreenSideEffectPerforming>)performer NS_DESIGNATED_INITIALIZER;
- (id<VT100ScreenState>)copy;

#pragma mark - Internal

// This is how mutation code schedules work to be done on the main thread later. In particular, this
// is the only way for it to call delegate methods. It will be performed asynchronously at some
// later time.
- (void)addSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect;
- (void)addIntervalTreeSideEffect:(void (^)(id<iTermIntervalTreeObserver> observer))sideEffect;

- (void)setNeedsRedraw;

#pragma mark - Scrollback

- (void)incrementOverflowBy:(int)overflowCount;
- (void)resetScrollbackOverflow;

#pragma mark - Reset

- (void)resetPreservingPrompt:(BOOL)preservePrompt modifyContent:(BOOL)modifyContent;

#pragma mark - Terminal Fundamentals

#pragma mark Cursor Movement

- (void)appendLineFeed;
- (void)carriageReturn;
- (void)appendCarriageReturnLineFeed;
- (void)cursorToX:(int)x;
- (void)cursorToY:(int)y;
- (void)cursorToX:(int)x Y:(int)y;
- (void)removeSoftEOLBeforeCursor;
- (void)cursorLeft:(int)n;
- (void)cursorRight:(int)n;
- (void)cursorDown:(int)n andToStartOfLine:(BOOL)toStart;
- (void)cursorUp:(int)n andToStartOfLine:(BOOL)toStart;
- (void)backTab:(int)n;
- (void)advanceCursorPastLastColumn;

#pragma mark Alternate Screen

- (void)showAltBuffer;
- (void)showPrimaryBuffer;
- (void)softAlternateScreenModeDidChange;
- (void)hideOnScreenNotesAndTruncateSpanners;

#pragma mark Write Text

- (void)appendAsciiDataAtCursor:(AsciiData *)asciiData;
- (void)appendStringAtCursor:(NSString *)string;
- (void)appendScreenCharArrayAtCursor:(const screen_char_t *)buffer
                               length:(int)len
               externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributes;
- (void)appendTabAtCursor:(BOOL)setBackgroundColors;

#pragma mark Erase

- (void)backspace;
- (BOOL)selectiveEraseRange:(VT100GridCoordRange)range eraseAttributes:(BOOL)eraseAttributes;
- (void)eraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec;
- (void)eraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec;
- (int)numberOfLinesToPreserveWhenClearingScreen;
- (void)clearAndResetScreenSavingLines:(int)linesToSave;
- (void)clearScrollbackBuffer;
- (void)clearBufferSavingPrompt:(BOOL)savePrompt;
- (void)eraseCharactersAfterCursor:(int)j;
- (void)eraseScreenAndRemoveSelection;

void VT100ScreenEraseCell(screen_char_t *sct,
                          iTermExternalAttribute **eaOut,
                          BOOL eraseAttributes,
                          const screen_char_t *defaultChar);

#pragma mark Bell

- (void)activateBell;

#pragma mark - Scroll Regions

- (void)setUseColumnScrollRegion:(BOOL)mode;
- (void)setLeftMargin:(int)scrollLeft rightMargin:(int)scrollRight;
- (void)setScrollRegionTop:(int)top bottom:(int)bottom;

#pragma mark - Scrolling

- (void)reverseIndex;
- (void)forwardIndex;
- (void)backIndex;
- (void)insertColumns:(int)n;
- (void)deleteColumns:(int)n;

#pragma mark - Bulk Operations

- (void)setAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect;
- (void)toggleAttribute:(int)sgrAttribute inRect:(VT100GridRect)rect;
- (void)copyFrom:(VT100GridRect)source to:(VT100GridCoord)dest;

#pragma mark - Character Sets

- (void)setCharacterSet:(int)charset usesLineDrawingMode:(BOOL)lineDrawingMode;

#pragma mark - Interval Tree

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass;

- (void)removeObjectFromIntervalTree:(id<IntervalTreeObject>)obj;

- (void)removeIntervalTreeObjectsInRange:(VT100GridCoordRange)coordRange;

- (NSMutableArray<id<IntervalTreeObject>> *)removeIntervalTreeObjectsInRange:(VT100GridCoordRange)coordRange exceptCoordRange:(VT100GridCoordRange)coordRangeToSave;

// Swap onscreen notes between intervalTree_ and savedIntervalTree_.
// IMPORTANT: Call -reloadMarkCache after this.
- (void)swapOnscreenIntervalTreeObjects;

#pragma mark Tabstops

- (void)setTabStopAtCursor;
- (void)removeTabStopAtCursor;

#pragma mark - Shell Integration

#pragma mark Marks

// This is like addMarkStartingAtAbsoluteLine:oneLine:ofClass: but it notifies the delegate of a new mark.
- (id<iTermMark>)addMarkOnLine:(int)line ofClass:(Class)markClass;
- (void)saveCursorLine;
- (void)reloadMarkCache;

#pragma mark Prompt

// This is like setPromptStartLine: but with lots of side effects that are desirable for the
// regular shell integration flow.
- (void)promptDidStartAt:(VT100GridAbsCoord)coord;

- (void)setPromptStartLine:(int)line;
- (void)didUpdatePromptLocation;

#pragma mark Command

- (void)commandDidStart;
- (void)setCoordinateOfCommandStart:(VT100GridAbsCoord)coord;
- (void)setCommandStartCoordWithoutSideEffects:(VT100GridAbsCoord)coord;
- (void)commandDidStartAtScreenCoord:(VT100GridCoord)coord;
- (void)commandDidStartAt:(VT100GridAbsCoord)coord;
- (void)invalidateCommandStartCoordWithoutSideEffects;

// Update the commandRange in the current prompt's mark, if present. Asynchronously
- (void)commandRangeDidChange;

- (void)setReturnCodeOfLastCommand:(int)returnCode;
- (void)commandDidEnd;
- (BOOL)commandDidEndAtAbsCoord:(VT100GridAbsCoord)coord;
- (void)commandDidEndWithRange:(VT100GridCoordRange)range;
- (void)commandWasAborted;
- (void)assignCurrentCommandEndDate;

#pragma mark Working Directory

- (void)setWorkingDirectory:(NSString * _Nullable)workingDirectory
                  onAbsLine:(long long)absLine
                     pushed:(BOOL)pushed
                      token:(id<iTermOrderedToken> _Nullable)token;

- (void)currentDirectoryDidChangeTo:(NSString *)dir;
- (void)setWorkingDirectoryFromURLString:(NSString *)URLString;

#pragma mark Remote Host

- (void)setRemoteHostFromString:(NSString *)remoteHost;
- (void)setHost:(NSString * _Nullable)host user:(NSString * _Nullable)user;

#pragma mark - Annotations

- (void)removeAnnotation:(PTYAnnotation *)annotation;

- (PTYAnnotation *)addNoteWithText:(NSString *)text inAbsoluteRange:(VT100GridAbsCoordRange)absRange;

- (void)addAnnotation:(PTYAnnotation *)annotation
              inRange:(VT100GridCoordRange)range
                focus:(BOOL)focus;

#pragma mark - URLs

- (void)linkTextInRange:(NSRange)range
basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                URLCode:(unsigned int)code;

- (void)linkRun:(VT100GridRun)run
    withURLCode:(unsigned int)code;

#pragma mark - Highlighting

- (void)highlightRun:(VT100GridRun)run
 withForegroundColor:(NSColor *)fgColor
     backgroundColor:(NSColor *)bgColor;

- (void)highlightTextInRange:(NSRange)range
   basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                      colors:(NSDictionary *)colors;

#pragma mark - Token Execution

- (void)addTokens:(CVector)vector length:(int)length highPriority:(BOOL)highPriority;
- (void)scheduleTokenExecution;
- (void)injectData:(NSData *)data;

#pragma mark - Triggers

- (void)performPeriodicTriggerCheck;
- (void)clearTriggerLine;
- (void)appendStringToTriggerLine:(NSString *)string;
- (BOOL)appendAsciiDataToTriggerLine:(AsciiData *)asciiData;
- (void)forceCheckTriggers;

#pragma mark - Color

- (void)loadInitialColorTable;
- (void)setColor:(NSColor *)color forKey:(int)key;
- (void)restoreColorsFromSlot:(VT100SavedColorsSlot *)slot;

#pragma mark - Cross-Thread Sync

- (void)willSynchronize;
- (void)updateExpectFrom:(iTermExpect *)source;

// Call this on the main thread to sync with the mutation thread. In the block you can adjust
// mutable state and main thread state safely. The block does not escape and is called synchronously.
// It may block for some time until the current token or other high-priority tasks finish processing.
- (void)performBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100Terminal *terminal,
                                                            VT100ScreenMutableState *mutableState,
                                                            id<VT100ScreenDelegate> delegate))block;

#pragma mark - State Restoration

- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner;

#pragma mark - Inline Images

- (void)stopTerminalReceivingFile;
- (void)fileReceiptEndedUnexpectedly;
- (void)appendNativeImageAtCursorWithName:(NSString *)name width:(int)width;
- (BOOL)confirmBigDownloadWithBeforeSize:(NSInteger)sizeBefore
                               afterSize:(NSInteger)afterSize
                                    name:(NSString *)name
                                delegate:(id<VT100ScreenDelegate>)delegate;

#pragma mark - Temporary

- (void)setTokenExecutorDelegate:(id)delegate;

@end

NS_ASSUME_NONNULL_END
