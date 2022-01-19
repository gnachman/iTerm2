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

@interface VT100ScreenMutableState()<
PTYAnnotationDelegate,
PTYTriggerEvaluatorDelegate,
VT100GridDelegate,
VT100InlineImageHelperDelegate,
iTermColorMapDelegate,
iTermEchoProbeDelegate,
iTermJournalingIntervalTreeSideEffectPerformer,
iTermMarkDelegate,
iTermTemporaryDoubleBufferedGridControllerDelegate,
iTermTriggerSession,
iTermTriggerScopeProvider> {
    VT100GridCoordRange _previousCommandRange;
    iTermIdempotentOperationJoiner *_commandRangeChangeJoiner;
    dispatch_queue_t _queue;
    PTYTriggerEvaluator *_triggerEvaluator;
}

@property (atomic) BOOL hadCommand;
@property (atomic) BOOL performingJoinedBlock;

- (iTermColorMap *)colorMap;

- (void)addJoinedSideEffect:(void (^)(id<VT100ScreenDelegate> delegate))sideEffect;

@end
