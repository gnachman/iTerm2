//
//  VT100ScreenMutableState+Resizing.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/10/22.
//

#import "VT100ScreenMutableState.h"

@class iTermSelection;

NS_ASSUME_NONNULL_BEGIN

@interface VT100ScreenMutableState (Resizing)

- (void)setSize:(VT100GridSize)proposedSize
      visibleLines:(VT100GridRange)previouslyVisibleLineRange
         selection:(iTermSelection *)selection
           hasView:(BOOL)hasView
       delegate:(id<VT100ScreenDelegate>)delegate;

- (void)restoreInitialSizeWithDelegate:(id<VT100ScreenDelegate>)delegate;

- (void)setSize:(VT100GridSize)size delegate:(id<VT100ScreenDelegate>)delegate;

- (void)destructivelySetScreenWidth:(int)width height:(int)height;

@end

NS_ASSUME_NONNULL_END
