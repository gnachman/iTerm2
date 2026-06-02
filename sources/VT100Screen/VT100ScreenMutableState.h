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
@protocol iTermLargeContentProvider;
@protocol iTermOrderedToken;
@class iTermTokenExecutor;
@class TmuxHistory;
@class iTermEventuallyConsistentIntervalTree;
@class iTermResilientCoordinate;
@protocol iTermResilientCoordinateDataSource;

NS_ASSUME_NONNULL_BEGIN

@protocol VT100ScreenSideEffectPerforming<NSObject>
- (nullable id<VT100ScreenDelegate>)sideEffectPerformingScreenDelegate;
- (nullable id<iTermIntervalTreeObserver>)sideEffectPerformingIntervalTreeObserver;
@end

// A lightweight ResilientCoordinateDataSource that proxies width /
// numberOfLines / scrollbackOverflow to a backing data source but
// returns its OWN rcGuid. Used to give the saved interval tree a
// distinct RC pool guid from the primary tree, so the resize / fold /
// porthole notification broadcasts can target only the right tree's
// marks. One instance per pool: mutation-thread (backed by
// VT100ScreenMutableState) and main-thread (backed by VT100ScreenState).
@interface iTermSavedTreeRCDataSource : NSObject <iTermResilientCoordinateDataSource>
@property (nonatomic, weak, nullable) id<iTermResilientCoordinateDataSource> backing;
@property (nonatomic, copy) NSString *guid;
- (instancetype)initWithGuid:(NSString *)guid
                     backing:(id<iTermResilientCoordinateDataSource>)backing NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface VT100ScreenMutableState: VT100ScreenState<NSCopying, VT100ScreenMutableState>
@property (nonatomic, strong, readwrite) iTermOrderEnforcer *currentDirectoryDidChangeOrderEnforcer;
@property (nullable, nonatomic, strong) VT100InlineImageHelper *inlineImageHelper;
@property (nonatomic, strong, readwrite) iTermOrderEnforcer *setWorkingDirectoryOrderEnforcer;
@property (atomic, weak, nullable) id<VT100ScreenSideEffectPerforming> sideEffectPerformer;
@property (nonatomic, readonly) iTermTokenExecutor *tokenExecutor;
@property (nonatomic) BOOL exited;
@property (nonatomic, strong, readonly, nullable) VT100Terminal *terminal;
@property (nonatomic, strong) iTermEchoProbe *echoProbe;
@property (nonatomic, weak, nullable) id<iTermEchoProbeDelegate> echoProbeDelegate;
@property (nullable, nonatomic, strong) VT100ScreenState *mainThreadCopy;

// Saved-tree RC pool: distinct guid from the primary tree so resize /
// fold / porthole notifications can target only the right tree's
// marks. Held strongly so VT100Screen.init can wire them onto the
// tree's mainThreadDataSource / mutationThreadDataSource and leave
// lifetime management to mutableState. Configured by VT100Screen.init.
@property (nullable, nonatomic, strong) iTermSavedTreeRCDataSource *savedTreeMutationThreadDataSource;
@property (nullable, nonatomic, strong) iTermSavedTreeRCDataSource *savedTreeMainThreadDataSource;

- (instancetype)initWithSideEffectPerformer:(id<VT100ScreenSideEffectPerforming>)performer NS_DESIGNATED_INITIALIZER;
- (VT100ScreenState *)copy;

- (iTermEventuallyConsistentIntervalTree *)mutableIntervalTree;
- (iTermEventuallyConsistentIntervalTree *)mutableSavedIntervalTree;
- (void)setConfig:(VT100MutableScreenConfiguration *)config;

// Specific to the mutable state. Not related to PTYSession's guid.
@property (nonatomic, readonly) NSString *uniqueIdentifier;

// Sets the foreground job ancestor chain on the trigger evaluator (atomic, safe from any thread).
// The array contains lowercased argv0 values ordered deepest-first.
- (void)setForegroundJobAncestorsForTriggerFiltering:(nullable NSArray<NSString *> *)ancestors;

#pragma mark - Internal

@property (class, atomic, readonly) BOOL performingJoinedBlock;
@property (nonatomic) BOOL terminalEnabled;
@property (nonatomic, readonly) VT100ScreenState *sanitizingAdapter;
@property (atomic) BOOL performingSideEffect;
@property (atomic) BOOL performingPausedSideEffect;

// This is how mutation code schedules work to be done on the main thread later. In particular, this
// is the only way for it to call delegate methods. It will be performed asynchronously at some
// later time.
- (void)addSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect name:(NSString *)name;
- (void)addIntervalTreeSideEffect:(void (^)(id<iTermIntervalTreeObserver> observer))sideEffect
                             name:(NSString *)name;
- (void)addUnmanagedPausedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser))block
                                name:(NSString *)name;

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
- (BOOL)shouldConvertCharactersToGraphicsCharacterSetInTerminal:(VT100Terminal *)terminal;

// Append a string to the screen at the current cursor position. The terminal's insert and wrap-
// around modes are respected, the cursor is advanced, the screen may be scrolled, and the line
// buffer may change.
- (void)appendStringAtCursor:(NSString *)string;
- (void)appendStringAtCursor:(NSString *)string
          preconvertedData:(nullable PreconvertedStringData *)preconvertedData;

- (void)appendScreenCharArrayAtCursor:(const screen_char_t *)buffer
                               length:(int)len
               externalAttributeIndex:(id<iTermExternalAttributeIndexReading> _Nullable)externalAttributes
                             rtlFound:(BOOL)rtlFound
                              dwcFree:(BOOL)dwcFree;

- (void)appendTabAtCursor:(BOOL)setBackgroundColors;

- (void)appendScreenChars:(const screen_char_t *)line
                      length:(int)length
      externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributeIndex
             continuation:(screen_char_t)continuation
                 rtlFound:(BOOL)rtlFound;

// Like appendScreenChars: but handles DWL/DHL source data: sets the
// lineAttribute on the current grid line and strips DWL_SPACERs before
// appending so the append code can re-expand correctly.
- (void)appendScreenChars:(const screen_char_t *)line
                   length:(int)length
   externalAttributeIndex:(id<iTermExternalAttributeIndexReading>)externalAttributeIndex
             continuation:(screen_char_t)continuation
                 rtlFound:(BOOL)rtlFound
            lineAttribute:(iTermLineAttribute)lineAttribute;

- (void)appendBannerMessage:(NSString *)message;

#pragma mark Bidi

- (void)populateRTLStateIfNeeded;

#pragma mark Erase

- (void)backspace;
- (BOOL)selectiveEraseRange:(VT100GridCoordRange)range eraseAttributes:(BOOL)eraseAttributes;
- (void)eraseInDisplayBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec;
- (void)eraseLineBeforeCursor:(BOOL)before afterCursor:(BOOL)after decProtect:(BOOL)dec;
- (int)numberOfLinesToPreserveWhenClearingScreen;
- (void)clearAndResetScreenSavingLines:(int)linesToSave;
- (void)clearScrollbackBuffer;
- (void)clearBufferSavingPrompt:(BOOL)savePrompt;
- (void)clearBufferWithoutTriggersSavingPrompt:(BOOL)savePrompt;
- (void)eraseCharactersAfterCursor:(int)j;
- (void)eraseScreenAndRemoveSelection;
- (void)clearFromAbsoluteLineToEnd:(long long)absLine;
- (void)clearForComposer;
- (void)removeLastLine;

void VT100ScreenEraseCell(screen_char_t *sct,
                          iTermExternalAttribute * _Nullable * _Nonnull eaOut,
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

- (void)setName:(NSString * _Nullable)name forMark:(VT100ScreenMark *)mark;

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass;

- (id<iTermMark>)addMarkStartingAtAbsoluteLine:(long long)line
                                       oneLine:(BOOL)oneLine
                                       ofClass:(Class)markClass
                                      modifier:(void (^ NS_NOESCAPE _Nullable)(id<iTermMark>))modifier;

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

@property (nonatomic) BOOL namedMarksDirty;

// This is like addMarkStartingAtAbsoluteLine:oneLine:ofClass: but it notifies the delegate of a new mark.
- (id<iTermMark>)addMarkOnLine:(int)line ofClass:(Class)markClass;
- (id<iTermMark>)addMarkOnLine:(int)line column:(int)column ofClass:(Class)markClass;
- (void)saveCursorLine;
- (void)reloadMarkCache;
- (void)removeNamedMark:(VT100ScreenMark *)mark;

#pragma mark Prompt

// This is like setPromptStartLine: but with lots of side effects that are desirable for the
// regular shell integration flow.
// freshLine controls the "insert a CR+LF if the cursor isn't at column 0"
// behavior (further gated by config.shouldPlacePromptAtFirstColumn). YES for
// OSC 133;A and for trigger-detected prompts; NO for OSC 133;P.
// `aid` is the OSC 133 `aid=<id>` attribute (nil for trigger-detected or
// shells that don't emit aid); when non-nil it's stamped on the resulting
// mark and the mark is registered in marksByAid/openAidStack so the
// matching `D;aid=<id>` can close it.
- (VT100ScreenMark * _Nullable)promptDidStartAt:(VT100GridAbsCoord)coord
                                   wasInCommand:(BOOL)wasInCommand
                              detectedByTrigger:(BOOL)detectedByTrigger
                                      freshLine:(BOOL)freshLine
                                            aid:(NSString * _Nullable)aid;

- (VT100ScreenMark * _Nullable)setPromptStartLine:(int)line
                                detectedByTrigger:(BOOL)detectedByTrigger
                                              aid:(NSString * _Nullable)aid;
- (void)didUpdatePromptLocation;
- (void)incrementClearCountForCommandMark:(id<VT100ScreenMarkReading>)screenMarkDoppelganger;
- (void)pauseAtNextPrompt:(nullable void (^)(void))paused;

#pragma mark Command

- (void)commandDidStart;
// This is used when sending a command when the previous prompt was detected by a trigger since
// we won't get any indication of the start/end of a running command.
- (void)didSendCommand;
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
// Anything we read from here until FinalTerm C can be assumed to be the shell echoing back the command.
- (void)composerWillSendCommand:(NSString *)command
                     startingAt:(VT100GridAbsCoord)startAbsCoord;

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

- (void)removeAnnotation:(PTYAnnotation *)annotation;
- (void)removeAnnotationsOnLine:(long long)line;

- (id<PTYAnnotationReading> _Nullable)addNoteWithText:(NSString *)text inAbsoluteRange:(VT100GridAbsCoordRange)absRange;

- (void)addAnnotation:(id<PTYAnnotationReading>)annotation
              inRange:(VT100GridCoordRange)range
                focus:(BOOL)focus
              visible:(BOOL)visible;

- (void)setStringValueOfAnnotation:(id<PTYAnnotationReading>)annotation to:(NSString *)stringValue;

#pragma mark - Folding

- (BOOL)removeFoldsInRange:(NSRange)absRange;

- (void)replaceRange:(VT100GridAbsCoordRange)range
            withLine:(ScreenCharArray *)line
        promptLength:(NSInteger)promptLength;

// Use negative prompt length to just replace without creating a fold.
- (void)replaceRange:(VT100GridAbsCoordRange)range
           withLines:(NSArray<ScreenCharArray *> *)lines
        promptLength:(NSInteger)promptLength
          blockMarks:(NSDictionary<NSString *, iTermRange *> * _Nullable)blockMarks;

#pragma mark - Portholes

- (void)replaceRange:(VT100GridAbsCoordRange)range
        withPorthole:(id<Porthole>)porthole
            ofHeight:(int)numLines;
- (void)addSavedIntervalTreeObjects:(NSArray<iTermSavedIntervalTreeObject *> *)savedITOs
                           baseLine:(long long)baseLine;

#pragma mark - Folding

// Unfold
- (void)replaceMark:(iTermMark *)mark
          withLines:(NSArray<ScreenCharArray *> *)lines
          savedITOs:(NSArray<iTermSavedIntervalTreeObject *> *)savedITOs;

// This assumes that the range the mark spans is empty lines.
- (void)changeHeightOfMark:(iTermMark *)mark to:(int)newHeight;

#pragma mark - URLs

- (void)linkTextInRange:(NSRange)range
basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                    URL:(iTermURL *)url;

- (void)linkRun:(VT100GridRun)run
        withURL:(iTermURL *)url;

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
@property (nonatomic) BOOL shortcutNavigationMode;

// Factors that cause tokens to be discarded.
@property (nonatomic) BOOL isTmuxGateway;
@property (nonatomic) BOOL hasMuteCoprocess;
@property (nonatomic) BOOL suppressAllOutput;

// Kind of the most-recently-opened OSC 133;A / 133;P. The delegate methods
// for `terminalCommandDidStart` and friends consult this to decide whether
// the matching B closes a real command read (.initial) or a non-input
// region like a PS2 or right-prompt. Reset to .initial after each B/C/D.
@property (nonatomic) VT100PromptKind currentPromptKind;

// Cursor position recorded at a non-initial OSC 133;A (PS2 or right-prompt
// open). Consumed by the matching `terminalCommandDidStart` to append
// (pendingNonInitialPromptStart.coord, cursor) as an excluded subrange on
// the active prompt mark. Resilient so resize / scrollback overflow that
// happens between the A and the B doesn't corrupt the recorded coord.
// nil means "no pending range".
@property (nonatomic, strong, nullable) iTermResilientCoordinate *pendingNonInitialPromptStart;

// Registry of currently-open command marks keyed by OSC 133 `aid=<id>`.
// Populated when an aid'd prompt mark is created (at A) and removed when
// that aid's matching D arrives (or its parent closes via cascade).
// Empty in the common case where shells don't emit aid. Used to dispatch
// `D;aid=X` close-by-aid and to compute `parentAid` (set on a new mark to
// the deepest-open aid at the moment its first marker arrives — drives
// the cascade-close that prevents leaked open marks when an outer
// command like ssh dies).
@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, VT100ScreenMark *> *marksByAid;

// Stack of currently-open aids in arrival order (top = deepest). Pushed
// at A;aid=X (when X isn't already present), popped at D;aid=X. The
// deepest entry is the `parentAid` for any new aid'd mark that opens
// while a parent is still in-flight.
//
// Maintenance comes in two flavors:
//   1. The D-by-aid close paths in +TerminalDelegate.m (setReturnCodeForAidMark:,
//      closeAidMark:'s cascade loop) drop targeted aids inline — the marks
//      stay in the tree after the close (endDate set, mark not removed),
//      so the removal hook can't help here.
//   2. PERMANENT removals from the tree fire
//      -willRemoveScreenMarksFromIntervalTree:, which drops the aid'd
//      mark's registry entry centrally. That covers every path that goes
//      through -removeObjectFromIntervalTree: / -removeObjectsFromIntervalTree:
//      (scrollback clear, prompt-marks-below, removeInaccessibleIntervalTreeObjects,
//      etc.).
//   3. Two paths use -[mutableIntervalTree removeObject:] directly and
//      thereby bypass the will/did hooks: -commandWasAborted (legacy abort)
//      and -abortSpecificAidMark: (close-by-aid abort). Both call
//      -pruneAidRegistry explicitly because their removals are permanent.
//
// Patterns that temporarily remove + re-add a mark (replaceMark:,
// changeHeightOfMark:, reallyReplaceRange:, intervalTree's internal
// move-and-rebind during bulkMoveObjects:) use -[mutableIntervalTree
// removeObject:] directly too. Because they bypass the will/did hooks,
// the registry stays correct for those — the mark survives the operation
// and its entry is restored by the matching addObject:.
//
// Serialized through kScreenStateOpenAidStackKey; marksByAid rebuilds
// from the restored stack at the end of fixUpDeserializedIntervalTree:.
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *openAidStack;

// Drop registry entries whose mark is no longer in the interval tree
// (mark.entry == nil). Called from the two PERMANENT direct-removal
// paths (commandWasAborted, abortSpecificAidMark:) that bypass the
// willRemove hook. Safe to call unconditionally — it's a no-op when
// nothing's stale.
- (void)pruneAidRegistry;

- (void)threadedReadTask:(char *)buffer length:(int)length;
- (void)addTokens:(CVector)vector
      lengthTotal:(int)lengthTotal
lengthExcludingInBandSignaling:(int)lengthExcludingInBandSignaling
     highPriority:(BOOL)highPriority;

- (void)scheduleTokenExecution;
- (void)injectData:(NSData *)data;

// This will be true while there's a request for a report that hasn't been responded to yet.
@property (atomic, readonly) BOOL sendingIsBlocked;

#pragma mark - Triggers

- (void)performPeriodicTriggerCheck;
- (void)clearTriggerLine;
- (void)appendStringToTriggerLine:(NSString *)string;
- (BOOL)appendAsciiDataToTriggerLine:(AsciiData *)asciiData;
- (void)forceCheckTriggers;
- (BOOL)shouldEvaluateTriggers;
- (NSArray<iTermHistogram *> *)triggerStats;

#pragma mark - Color

- (void)loadInitialColorTable;
- (void)setColor:(NSColor *)color forKey:(int)key;
- (void)restoreColorsFromSlot:(VT100SavedColorsSlot *)slot;
- (void)setColorsFromDictionary:(NSDictionary<NSNumber *, id> *)dict harmonize:(BOOL)harmonize;

// This is the only safe way to modify the color map. Call it from the mutation thread.
- (void)mutateColorMap:(void (^)(iTermColorMap *colorMap))block;
- (void)darknessDidChange;

#pragma mark - Cross-Thread Sync

- (void)willSynchronize;
- (void)updateExpectFrom:(iTermExpect *)source;
- (void)didSynchronize:(BOOL)resetOverflow;

// Call this on the main thread to sync with the mutation thread. In the block you can adjust
// mutable state and main thread state safely. The block does not escape and is called synchronously.
// It may block for some time until the current token or other high-priority tasks finish processing.
// Pass a nil block to sync state without doing anything else.
- (void)performBlockWithJoinedThreads:(void (^ _Nullable NS_NOESCAPE)(VT100Terminal * _Nullable terminal,
                                                                      VT100ScreenMutableState *mutableState,
                                                                      id<VT100ScreenDelegate> _Nullable delegate))block;

// This is called eventually. It does not block the caller. It should be called from the main thread.
- (void)performBlockAsynchronously:(void (^ _Nullable)(VT100Terminal * _Nullable terminal,
                                                       VT100ScreenMutableState *mutableState,
                                                       id<VT100ScreenDelegate> _Nullable delegate))block;

// Doesn't sync before or after running the block. Calls it even if there is no delegate.
- (void)performLightweightBlockWithJoinedThreads:(void (^ NS_NOESCAPE)(VT100ScreenMutableState *mutableState))block;

#pragma mark - State Restoration

- (void)restoreFromDictionary:(NSDictionary *)dictionary
     includeRestorationBanner:(BOOL)includeRestorationBanner
                   reattached:(BOOL)reattached
                    isArchive:(BOOL)isArchive
         largeContentProvider:(id<iTermLargeContentProvider> _Nullable)largeContentProvider;

// Sets the primary grid's contents and scrollback history. `history` is an array of NSData
// containing screen_char_t's. It contains a bizarre workaround for tmux bugs.
- (void)setHistory:(TmuxHistory *)history;

// Sets the alt grid's contents. `lines` is NSData with screen_char_t's.
- (void)setAltScreen:(NSArray<NSData *> *)lines;

// This is for ssh-related state only.
- (void)restoreFromSavedState:(NSDictionary *)savedState;

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

#pragma mark - Testing

// Exposed for testing. Shifts interval tree objects in the given range down by deltaLines.
// If deltaLines is negative, objects move up. The startingAfter parameter specifies that
// only the end of intervals moves for objects whose start.y <= startingAfter.
- (void)shiftIntervalTreeObjectsInRange:(VT100GridCoordRange)range
                          startingAfter:(int)startingAfter
                            downByLines:(int)deltaLines;

@end

NS_ASSUME_NONNULL_END
