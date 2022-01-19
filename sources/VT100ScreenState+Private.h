//
//  VT100ScreenState+Private.h
//  iTerm2
//
//  Created by George Nachman on 12/28/21.
//

#import "VT100ScreenMutableState.h"

@interface VT100ScreenState() <VT100ScreenMutableState>
- (instancetype _Nonnull)initForMutationOnQueue:(dispatch_queue_t _Nonnull)queue;
- (instancetype _Nonnull)initWithState:(VT100ScreenMutableState * _Nonnull)source
                           predecessor:(VT100ScreenState * _Nullable)predecessor;
@end
