//
//  NSScroller+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/7/21.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSScroller (iTerm)

// Width of a scrollbar as it affects layout, taking whether scrollbars are hidden in to account.
CGFloat iTermScrollbarWidth(void);

+ (CGFloat)it_layoutAffectingWidth;

@end

NS_ASSUME_NONNULL_END
