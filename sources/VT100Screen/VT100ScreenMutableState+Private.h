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
}

@property (atomic) BOOL hadCommand;
// This is a class variable because there is a single mutation queue. If that queue gets locked up
// in a joined block, then any VT100ScreenMutableState can consider itself joined while on the
// main thread. This can happen when performBlockWithJoinedThreads is reentrant with two different
// VT100ScreenMutableState objects (for example, when detaching in tmux mode).
@property (class, atomic, readwrite) BOOL performingJoinedBlock;
@property (nonatomic) BOOL allowNextReport;

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

- (void)addDeferredSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect
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
