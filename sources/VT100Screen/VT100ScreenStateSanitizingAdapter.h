//
//  VT100ScreenStateSanitizingAdapter.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/29/22.
//

#import <Foundation/Foundation.h>
#import "VT100ScreenMutableState.h"

NS_ASSUME_NONNULL_BEGIN

// Behaves like a VT100ScreenState. Feel free to cast it to VT100ScreenState.
// Converts marks to doppelgangers.
@interface VT100ScreenStateSanitizingAdapter : NSProxy

- (instancetype)initWithSource:(VT100ScreenMutableState *)source;

@end

NS_ASSUME_NONNULL_END
