//
//  VT100ScreenState+Private.h
//  iTerm2
//
//  Created by George Nachman on 12/28/21.
//

#import "VT100ScreenMutableState.h"

@interface VT100ScreenState() <VT100ScreenMutableState>
- (instancetype)initForMutation;
- (instancetype)initWithState:(VT100ScreenMutableState *)source;
@end
