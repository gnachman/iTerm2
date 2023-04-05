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

extern const NSInteger VT100ScreenMutableStateSideEffectFlagDidReceiveLineFeed;

@interface VT100ScreenMutableState()<
PTYAnnotationDelegate,
PTYTriggerEvaluatorDelegate,
VT100GridDelegate,
VT100InlineImageHelperDelegate,
iTermColorMapDelegate,
iTermEchoProbeDelegate,
iTermEventuallyConsistentIntervalTreeSideEffectPerformer,
iTermLineBufferDelegate,
iTermMarkDelegate,
iTermPromptStateMachineDelegate,
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
}

@property (atomic) BOOL hadCommand;
// This is a class variable because there is a single mutation queue. If that queue gets locked up
// in a joined block, then any VT100ScreenMutableState can consider itself joined while on the
// main thread. This can happen when performBlockWithJoinedThreads is reentrant with two different
// VT100ScreenMutableState objects (for example, when detaching in tmux mode).
@property (class, atomic, readwrite) BOOL performingJoinedBlock;
@property (nonatomic) BOOL allowNextReport;

- (iTermEventuallyConsistentIntervalTree *)mutableIntervalTree;
- (iTermEventuallyConsistentIntervalTree *)mutableSavedIntervalTree;
- (iTermColorMap *)mutableColorMap;

- (void)addJoinedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect;

// Main thread/synchronized access only.
@property (nonatomic, readonly) IntervalTree *derivativeIntervalTree;

// Main thread/synchronized access only.
@property (nonatomic, readonly) IntervalTree *derivativeSavedIntervalTree;

- (void)addPausedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate, iTermTokenExecutorUnpauser *unpauser))sideEffect;

- (void)addDeferredSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect;

// Runs even if there is no delegate yet.
- (void)addNoDelegateSideEffect:(void (^)(void))sideEffect;

- (void)willSendReport;
- (void)didSendReport:(id<VT100ScreenDelegate>)delegate;

- (void)executePostTriggerActions;
- (void)performBlockWithoutTriggers:(void (^)(void))block;
- (void)movePromptUnderComposerIfNeeded;

@end
