//
//  VT100ScreenMutableState+Private.h
//  iTerm2
//
//  Created by George Nachman on 1/10/22.
//

#import "VT100ScreenMutableState.h"

#import "PTYTriggerEvaluator.h"

#import "PTYAnnotation.h"
#import "Trigger.h"
#import "VT100Grid.h"
#import "VT100GridTypes.h"
#import "VT100InlineImageHelper.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermEchoProbe.h"
#import "iTermMark.h"
#import "iTermTemporaryDoubleBufferedGridController.h"

extern const int64_t VT100ScreenMutableStateSideEffectFlagDidReceiveLineFeed;

@class iTermKittyImageDraw;
@class iTermProgramStatusReportBatch;
@class iTermTitleBatch;
@class iTermTitleDirectoryFetch;

@interface VT100ScreenMutableState()<
PTYAnnotationDelegate,
PTYTriggerEvaluatorDelegate,
VT100GridDelegate,
VT100InlineImageHelperDelegate,
iTermColorMapDelegate,
iTermEchoProbeDelegate,
iTermEventuallyConsistentIntervalTreeSideEffectPerformer,
iTermKittyImageControllerDelegate,
iTermLineBufferDelegate,
iTermMarkDelegate,
iTermPathSnifferDelegate,
iTermPromptStateMachineDelegate,
iTermStatFileProtocol,
iTermTemporaryDoubleBufferedGridControllerDelegate,
iTermTokenExecutorDelegate,
iTermTriggerCallbackScheduler,
iTermTriggerSession,
iTermTriggerScopeProvider> {
    VT100GridCoordRange _previousCommandRange;
    iTermIdempotentOperationJoiner *_commandRangeChangeJoiner;
    // The batch the next OSC 7501 report may join, if its side effect is
    // still the last one added. Mutation thread only.
    iTermProgramStatusReportBatch *_programStatusBatch;
    // The token executor's side effect serial just after the batch's side
    // effect was added.
    int64_t _programStatusBatchSideEffectSerial;
    // The batch the next title change may join, if its side effect is still
    // the last one added. Mutation thread only.
    iTermTitleBatch *_titleBatch;
    // The token executor's side effect serial just after the title batch's
    // side effect was added.
    int64_t _titleBatchSideEffectSerial;
    // Whether the title batch's side effect was added with addSideEffect
    // rather than deferred. A working directory request needs that.
    BOOL _titleBatchIsImmediate;
    dispatch_queue_t _queue;
    PTYTriggerEvaluator *_triggerEvaluator;
    dispatch_group_t _tmuxGroup;
    NSArray<NSString *> *_sshIntegrationFlags;
    _Atomic int _pendingReportCount;
    BOOL _compressionScheduled;
    iTermPromptStateMachine *_promptStateMachine;
    NSString *_currentBlockIDList;
    BOOL _triggerDidDetectPrompt;
    BOOL _autoComposerEnabled;
    iTermKittyImageController *_kittyImageController;
    // When YES, terminal input is collected into printBuffer for ANSI print commands.
    BOOL _collectInputForPrinting;
    // Absolute line of the bottommost fold ANYWHERE in the buffer (grid or history), or -1 if there
    // are no folds at all. Cached so the cursor-moved-above-a-fold check (which runs on every
    // cursor-positioning command) is a few integer compares instead of an interval-tree query. The hot
    // check derives grid-membership by comparing against the current grid-top absolute line, so
    // ordinary scrolling and lines moving between the line buffer and the grid need NO invalidation:
    // absolute coordinates don't change when a line moves between history and grid, only the split
    // does. _foldCacheDirty must be set by any event that changes the fold SET or a fold's absolute
    // COORDINATE. Two chokepoints cover most of it: -shiftIntervalTreeObjectsInRange: catches
    // coordinate relocations (porthole add/resize, composer reflow, fold create/unfold), and
    // -didRemoveObjectFromIntervalTree: catches fold-mark removals (clear-to-mark, range clears,
    // overflow). The paths that rebuild or relocate folds WITHOUT going through either set it directly:
    // reflow, clearScrollbackBuffer (bulkMoveObjects:), removeLastLine, interval-tree deserialization
    // (session restore), and the alt-screen / tmux grid swap. The value is recomputed lazily on next
    // use, when the screen state is fully settled.
    long long _bottommostFoldAbsLine;
    BOOL _foldCacheDirty;
    // YES once this session has received a proprietary location code (1337;RemoteHost
    // or CurrentDir). If we've seen those, disabling OSC 7 doesn't break shell
    // integration's location reporting, so we don't warn about it.
    BOOL _sawProprietaryLocationCode;
    // YES once this session has queued the "AcceptOSC7 is off" warning, so a
    // session reporting OSC 7 every prompt doesn't enqueue a side effect every
    // prompt. Cleared whenever the setting is seen on, so a later off-episode
    // can warn again.
    BOOL _queuedOSC7DisabledWarning;
}

@property (atomic) BOOL hadCommand;
// The join state of this state's mutation queue. If the queue is shared and gets locked up in a
// joined block, any VT100ScreenMutableState on it can consider itself joined while on the main
// thread. This happens when performBlockWithJoinedThreads is reentrant with two different
// VT100ScreenMutableState objects (for example, when detaching in tmux mode). With a queue of its
// own, joining another state from inside a join pauses that state's queue too.
@property (nonatomic, readonly) iTermMutationQueueJoinState *joinState;

// One-shot: set inside a report's joined sync so the rolled-back report token,
// when it re-executes, is allowed to send (returns YES) instead of rolling back
// and syncing again forever. Applies to ALL reports. The OSC-4 coalescing
// skip-sync flag lives separately on the token executor. See
// terminalShouldSendReport:. (Mutation queue.)
@property (nonatomic) BOOL allowNextReport;

// Redeclared readwrite; see VT100ScreenMutableState.h. Incremented in the report
// gate's sync path.
@property (nonatomic, readwrite) NSInteger reportSyncCount;

// Absolute line number of the cursor right after contents were restored from saved state, or
// -1. Lets -restorePreferredCursorPositionIfPossible tell a resize that slid the screen over
// history apart from output that moved the cursor.
@property (nonatomic) long long restoredCursorAbsLine;
// Height of the current grid right after contents were restored from saved state.
@property (nonatomic) int restoredGridHeight;
// cursor.y - preferredCursorPosition.y right after contents were restored from saved state.
// Usually 0; the restoration banner can leave it nonzero.
@property (nonatomic) int restoredCursorOffsetFromPreferred;
- (long long)absLineOfCursor;

// Has the running command appended any output since it began executing (FTCS C)? Reset at FTCS C,
// set whenever text is appended. Used to decide whether a program that moves the cursor above its
// output region (without using the alternate screen) is doing a launch-time takeover that should
// preserve the prior screen, versus a mid-run repaint of its own output that must not be disturbed.
@property (nonatomic) BOOL appendedTextSinceCommandExecuted;

- (iTermEventuallyConsistentIntervalTree *)mutableIntervalTree;
- (iTermEventuallyConsistentIntervalTree *)mutableSavedIntervalTree;
- (iTermColorMap *)mutableColorMap;

- (void)addJoinedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect
                       name:(NSString *)name;

// Main thread/synchronized access only.
@property (nonatomic, readonly) IntervalTree *derivativeIntervalTree;

// Main thread/synchronized access only.
@property (nonatomic, readonly) IntervalTree *derivativeSavedIntervalTree;

- (void)addPausedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser))sideEffect
                       name:(NSString *)name;

// Urgent variants of addSideEffect:name: and addPausedSideEffect:name:. A background
// session batches its side effects at a much longer period than a visible one; these opt
// out of that. Reach for one only when a batching period would stall a protocol or hold a
// pause, not merely delay output. Two things make that a narrow test. Urgency does nothing
// for a visible session, whose period is already the short one, so it is only ever about
// off-screen sessions. And all the tiers share one FIFO, which executeSideEffects drains
// whole, so an urgent flush carries every side effect queued ahead of it: a non-urgent one
// is delayed only when it is the tail with no urgent sibling behind it. See
// -[TokenExecutorImpl addUrgentSideEffect:]. Issue 13013.
- (void)addUrgentSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect
                       name:(NSString *)name;

- (void)addUrgentPausedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser))sideEffect
                             name:(NSString *)name;

// Paused variant of addReportSideEffect: for outbound report sends that must
// pause (e.g. an async pasteboard read). Does not disarm skip-sync.
- (void)addPausedReportSideEffect:(void (^)(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser))sideEffect
                             name:(NSString *)name;

- (void)addDeferredSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect
                         name:(NSString *)name;

// Main thread, in a side effect. Fetches the working directory once and
// records it at each fetch's line, in order, as
// setWorkingDirectory:onAbsLine:pushed:token: would for a nil directory.
- (void)fetchWorkingDirectoryWithDelegate:(id<VT100ScreenDelegate>)delegate
                                  fetches:(NSArray<iTermTitleDirectoryFetch *> *)fetches
                                   pushed:(BOOL)pushed;

// The screen line for an absolute line where setWorkingDirectory:onAbsLine:pushed:token:
// may record a directory, or -1 if it may not.
- (int)workingDirectoryLineForAbsLine:(long long)absLine;

// Runs a side effect's block now, if there is a delegate. For a side effect
// added straight to the token executor.
- (void)performSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))block
                     name:(NSString *)name;

// Runs even if there is no delegate yet.
- (void)addNoDelegateSideEffect:(void (^)(void))sideEffect
                           name:(NSString *)name;

- (void)willSendReport;
- (void)didSendReport:(id<VT100ScreenDelegate>)delegate;

- (void)executePostTriggerActions;
- (void)performBlockWithoutTriggers:(void (^)(void))block;
- (void)movePromptUnderComposerIfNeeded;
- (iTermBlockMark *)mutableBlockMarkWithID:(NSString *)blockID;

// Refresh _bottommostFoldAbsLine from the interval tree. Call after any event that adds, removes, or
// repositions folds in the grid (fold create/unfold, the fold-preserving scroll, reflow).
- (void)recomputeBottommostFoldAbsLine;

@end
