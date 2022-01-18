//
//  VT100ScreenState+Private.h
//  iTerm2
//
//  Created by George Nachman on 12/28/21.
//

#import "VT100ScreenMutableState.h"

@interface VT100ScreenState() <VT100ScreenMutableState>
- (instancetype)initForMutationOnQueue:(dispatch_queue_t)queue;
- (instancetype)initWithState:(VT100ScreenMutableState *)source;
@end
