//
//  iTermWindowSizeView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/4/19.
//

#import <Cocoa/Cocoa.h>
#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_14)
@interface iTermWindowSizeView : NSView

- (void)setWindowSize:(VT100GridSize)size;

@end

NS_ASSUME_NONNULL_END
