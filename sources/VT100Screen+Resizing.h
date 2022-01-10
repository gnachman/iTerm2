//
//  VT100Screen+Resizing.h
//  iTerm2Shared
//
//  Created by George Nachman on 12/21/21.
//

#import "VT100Screen.h"

NS_ASSUME_NONNULL_BEGIN

@interface VT100Screen (Resizing)

- (void)mutSetSize:(VT100GridSize)proposedSize
      visibleLines:(VT100GridRange)previouslyVisibleLineRange;
- (void)mutSetWidth:(int)width preserveScreen:(BOOL)preserveScreen;

@end

NS_ASSUME_NONNULL_END
