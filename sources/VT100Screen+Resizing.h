//
//  VT100Screen+Resizing.h
//  iTerm2Shared
//
//  Created by George Nachman on 12/21/21.
//

#import "VT100Screen.h"

@class iTermSelection;

NS_ASSUME_NONNULL_BEGIN

@interface VT100Screen (Resizing)

- (void)mutSetSize:(VT100GridSize)proposedSize
      visibleLines:(VT100GridRange)previouslyVisibleLineRange
         selection:(iTermSelection *)selection
           hasView:(BOOL)hasView;

@end

NS_ASSUME_NONNULL_END
