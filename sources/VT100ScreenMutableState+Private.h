//
//  VT100ScreenMutableState+Private.h
//  iTerm2
//
//  Created by George Nachman on 1/10/22.
//

#import "VT100ScreenMutableState.h"

#import "PTYTriggerEvaluator.h"
#import "iTermMark.h"
#import "Trigger.h"
#import "VT100GridTypes.h"
#import "iTerm2SharedARC-Swift.h"

@interface VT100ScreenMutableState()<
PTYTriggerEvaluatorDelegate,
iTermMarkDelegate,
iTermTriggerSession,
iTermTriggerScopeProvider> {
    VT100GridCoordRange _previousCommandRange;
    iTermIdempotentOperationJoiner *_commandRangeChangeJoiner;
    dispatch_queue_t _queue;
    PTYTriggerEvaluator *_triggerEvaluator;
}

@property (atomic) BOOL hadCommand;

@end
