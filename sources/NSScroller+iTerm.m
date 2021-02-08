//
//  NSScroller+iTerm.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/7/21.
//

#import "NSScroller+iTerm.h"
#import "iTermPreferences.h"

@implementation NSScroller (iTerm)

CGFloat iTermScrollbarWidth(void) {
    return [iTermPreferences boolForKey:kPreferenceKeyHideScrollbar] ? 0 : [NSScroller it_layoutAffectingWidth];
}

+ (CGFloat)it_layoutAffectingWidth {
    const NSScrollerStyle style = [NSScroller preferredScrollerStyle];
    switch (style) {
        case NSScrollerStyleOverlay:
            return 0;
        default:
            break;
    }
    return [self scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:style];
}

@end
