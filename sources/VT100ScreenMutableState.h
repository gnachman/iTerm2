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
@class iTermEchoProbe;
@protocol iTermEchoProbeDelegate;
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
@property (nonatomic, readonly) iTermTokenExecutor *tokenExecutor;
@property (nonatomic) BOOL exited;
@property (nonatomic, strong, readonly) VT100Terminal *terminal;
@property (nonatomic, strong) iTermEchoProbe *echoProbe;
@property (nonatomic, weak) id<iTermEchoProbeDelegate> echoProbeDelegate;
@property (nullable, nonatomic, strong) VT100ScreenState *mainThreadCopy;

- (instancetype)initWithSideEffectPerformer:(id<VT100ScreenSideEffectPerforming>)performer NS_DESIGNATED_INITIALIZER;
- (VT100ScreenState *)copy;

- (iTermEventuallyConsistentIntervalTree *)mutableIntervalTree;
- (iTermEventuallyConsistentIntervalTree *)mutableSavedIntervalTree;
- (void)setConfig:(VT100MutableScreenConfiguration *)config;

#pragma mark - Internal

@property (class, atomic, readonly) BOOL performingJoinedBlock;
@property (nonatomic) BOOL terminalEnabled;
@property (nonatomic, readonly) VT100ScreenState *sanitizingAdapter;
@property (atomic) BOOL performingSideEffect;
@property (atomic) BOOL performingPausedSideEffect;

// This is how mutation code schedules work to be done on the main thread later. In particular, this
// is the only way for it to call delegate methods. It will be performed asynchronously at some
// later time.
- (void)addSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect;
- (void)addIntervalTreeSideEffect:(void (^)(id<iTermIntervalTreeObserver> observer))sideEffect;
- (void)addUnmanagedPausedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser))block;

- (void)setNeedsRedraw;
- (iTermTokenExecutorUnpauser *)pauseTokenExecution;

#pragma mark - Scrollback

- (void)incrementOverflowBy:(int)overflowCount;
- (void)resetScrollbackOverflow;

#pragma mark - Reset

- (void)resetPreservingPrompt:(BOOL)preservePrompt modifyContent:(BOOL)modifyContent;

#pragma mark - Terminal Fundamentals

#pragma mark Cursor Movement

// Move the cursor down one position, scrolling if needed. Scroll regions are respected.
- (void)appendLineFeed;
- (void)carriageReturn;

// This disregards scroll regions. It's useful for system messages, like the tmux mode menu.
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

// Append a string to the screen at the current cursor position. The terminal's insert and wrap-
// around modes are respected, the cursor is advanced, the screen may be scrolled, and the line
// buffer may change.
- (void)appendStringAtCursor:(NSString *)string;
- (void)appendScreenCharArrayAtCursor:(const screen_char_t *)buffer
                               length:(int)len
               externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributes;
- (void)appendTabAtCursor:(BOOL)setBackgroundColors;
- (void)appendScreenChars:(const screen_char_t *)line
                      length:(int)length
      externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributeIndex
             continuation:(screen_char_t)continuation;
- (void)appendBannerMessage:(NSString *)message;

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
- (void)clearFromAbsoluteLineToEnd:(long long)absLine;
- (void)removeLastLine;

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
- (void)fillRectangle:(VT100GridRect)rect
                 with:(screen_char_t)c
   externalAttributes:(iTermExternalAttribute * _Nullable)ea;
- (void)selectiveEraseRectangle:(VT100GridRect)rect;

#pragma mark - Character Sets

- (void)setCharacterSet:(int)charset usesLineDrawingMode:(BOOL)lineDrawingMode;

#pragma mark - Interval Tree

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass;

// Returns nil if it was not accepted, otherwise it returns `mark`.
- (id<iTermMark>)addMark:(iTermMark *)mark
                  onLine:(long long)line
              singleLine:(BOOL)oneLine;

- (BOOL)removeObjectFromIntervalTree:(id<IntervalTreeObject>)obj;

- (void)removeIntervalTreeObjectsInRange:(VT100GridCoordRange)coordRange;

- (NSMutableArray<id<IntervalTreeObject>> *)removeIntervalTreeObjectsInRange:(VT100GridCoordRange)coordRange exceptCoordRange:(VT100GridCoordRange)coordRangeToSave;

// Swap onscreen notes between intervalTree_ and savedIntervalTree_.
// IMPORTANT: Call -reloadMarkCache after this.
- (void)swapOnscreenIntervalTreeObjects;

- (void)removeInaccessibleIntervalTreeObjects;

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
- (void)incrementClearCountForCommandMark:(id<VT100ScreenMarkReading>)screenMarkDoppelganger;

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
- (void)didInferEndOfCommand;

#pragma mark Working Directory

- (void)setWorkingDirectory:(NSString * _Nullable)workingDirectory
                  onAbsLine:(long long)absLine
                     pushed:(BOOL)pushed
                      token:(id<iTermOrderedToken> _Nullable)token;

// This is async because it could trigger a profile change.
- (void)currentDirectoryDidChangeTo:(NSString *)dir
                         completion:(void (^)(void))completion;

- (void)setWorkingDirectoryFromURLString:(NSString *)URLString;

#pragma mark Remote Host

- (void)setRemoteHostFromString:(NSString *)remoteHost;

#pragma mark - Annotations

- (void)removeAnnotation:(id<PTYAnnotationReading>)annotation;

- (id<PTYAnnotationReading>)addNoteWithText:(NSString *)text inAbsoluteRange:(VT100GridAbsCoordRange)absRange;

- (void)addAnnotation:(id<PTYAnnotationReading>)annotation
              inRange:(VT100GridCoordRange)range
                focus:(BOOL)focus
              visible:(BOOL)visible;

- (void)setStringValueOfAnnotation:(id<PTYAnnotationReading>)annotation to:(NSString *)stringValue;

#pragma mark - Portholes

- (void)replaceRange:(VT100GridAbsCoordRange)range
        withPorthole:(id<Porthole>)porthole
            ofHeight:(int)numLines;

- (void)replaceMark:(iTermMark *)mark withLines:(NSArray<ScreenCharArray *> *)lines;

// This assumes that the range the mark spans is empty lines.
- (void)changeHeightOfMark:(iTermMark *)mark to:(int)newHeight;

#pragma mark - URLs

- (void)linkTextInRange:(NSRange)range
basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                URLCode:(unsigned int)code;

- (void)linkRun:(VT100GridRun)run
    withURLCode:(unsigned int)code;

- (void)addURLMarkAtLineAfterCursorWithCode:(unsigned int)code;

#pragma mark - Highlighting

- (void)highlightRun:(VT100GridRun)run
 withForegroundColor:(NSColor *)fgColor
     backgroundColor:(NSColor *)bgColor;

- (void)highlightTextInRange:(NSRange)range
   basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                      colors:(NSDictionary *)colors;

#pragma mark - Token Execution

// Factors that could cause tokens to queue instead of execute.
@property (nonatomic) BOOL taskPaused;
@property (nonatomic) BOOL copyMode;

// Factors that cause tokens to be discarded.
@property (nonatomic) BOOL isTmuxGateway;
@property (nonatomic) BOOL hasMuteCoprocess;
@property (nonatomic) BOOL suppressAllOutput;

- (void)threadedReadTask:(char *)buffer length:(int)length;
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
- (void)setColorsFromDictionary:(NSDictionary<NSNumber *, id> *)dict;

// This is the only safe way to modify the color map. Call it from the mutation thread.
- (void)mutateColorMap:(void (^)(iTermColorMap *colorMap))block;

#pragma mark - Cross-Thread Sync

- (void)willSynchronize;
- (void)updateExpectFrom:(iTermExpect *)source;
- (void)didSynchronize:(BOOL)resetOverflow;

// Call this on the main thread to sync with the mutation thread. In the block you can adjust
// mutable state and main thread state safely. The block does not escape and is called synchronously.
// It may block for some time until the current token or other high-priority tasks finish processing.
// Pass a nil block to sync state without doing anything else.
- (void)performBlockWithJoinedThreads:(void (^ _Nullable NS_NOESCAPE)(VT100Terminal *terminal,
                                                                      VT100ScreenMutableState *mutableState,
                                                                      id<VT100ScreenDelegate> delegate))block;

// This is called eventually. It does not block the caller. It should be called from the main thread.
- (void)performBlockAsynchronously:(void (^ _Nullable)(VT100Terminal *terminal,
                                                       VT100ScreenMutableState *mutableState,
                                                       id<VT100ScreenDelegate> delegate))block;

// Doesn't sync before or after running the block. Calls it even if there is no delegate.
- (void)performLightweightBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100ScreenMutableState *mutableState))block;

#pragma mark - State Restoration

- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner
                   reattached:(BOOL)reattached;

// Sets the primary grid's contents and scrollback history. `history` is an array of NSData
// containing screen_char_t's. It contains a bizarre workaround for tmux bugs.
- (void)setHistory:(NSArray<NSData *> *)history;

// Sets the alt grid's contents. `lines` is NSData with screen_char_t's.
- (void)setAltScreen:(NSArray<NSData *> *)lines;

#pragma mark - Inline Images

- (void)stopTerminalReceivingFile;
- (void)fileReceiptEndedUnexpectedly;
- (void)appendNativeImageAtCursorWithName:(NSString *)name width:(int)width;
// Main queue
- (BOOL)confirmBigDownloadWithBeforeSize:(NSInteger)sizeBefore
                               afterSize:(NSInteger)afterSize
                                    name:(NSString *)name
                                delegate:(id<VT100ScreenDelegate>)delegate
                                   queue:(dispatch_queue_t)queue
                                unpauser:(iTermTokenExecutorUnpauser *)unpauser;

#pragma mark - Tmux

- (void)setTmuxState:(NSDictionary *)state;

#pragma mark - SSH

- (NSString *)sshEndBannerTerminatingCount:(NSInteger)count newLocation:(NSString *)sshLocation;

#pragma mark - DVR

// Load a frame from a dvr decoder.
- (void)setFromFrame:(const screen_char_t *)s
                 len:(int)len
            metadata:(NSArray<NSArray *> *)metadataArrays
                info:(DVRFrameInfo)info;

@end

NS_ASSUME_NONNULL_END
