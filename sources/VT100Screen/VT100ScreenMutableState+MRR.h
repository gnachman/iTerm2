//
//  VT100ScreenMutableState+MRR.h
//  iTerm2
//
//  Created by George Nachman on 2/29/24.
//

#import <Foundation/Foundation.h>
#import "VT100ScreenMutableState.h"

NS_ASSUME_NONNULL_BEGIN

@interface VT100ScreenMutableState(MRR)

// This was a bottleneck mostly because of objc overhead (autoreleases and
// such). This provides a very fast path, which makes a difference since this
// is called for each token.
- (void)fastTerminal:(VT100Terminal *)terminal
willExecuteToken:(VT100Token *)token
     defaultChar:(const screen_char_t *)defaultChar
            encoding:(NSStringEncoding)encoding __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
