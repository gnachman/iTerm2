//
//  iTermStoplightHotbox.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/7/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermHotboxSuppressing<NSObject>
- (BOOL)supressesHotbox;
@end

@protocol iTermStoplightHotboxDelegate<NSObject>
// Returns whether the hotbox was revealed. While it is not revealed, clicks
// pass through it.
- (BOOL)stoplightHotboxMouseEnter;
// Called whenever the mouse leaves, whether or not the hotbox was revealed.
- (void)stoplightHotboxMouseExit;
- (NSColor *)stoplightHotboxColor;
- (NSColor *)stoplightHotboxOutlineColor;
- (BOOL)stoplightHotboxCanDrag;
@end

@interface iTermStoplightHotbox : NSView
@property (nonatomic, weak) id<iTermStoplightHotboxDelegate> delegate;
// While revealed, the hotbox claims clicks in its bounds. The delegate may
// change this while the mouse is inside, e.g., to collapse or expand it.
@property (nonatomic) BOOL revealed;
// How far the hotbox's contents are shifted left, past its leading edge. The
// frame (and thus the tracking area) stays put so sliding the contents out
// doesn't move the hotbox out from under the mouse.
@property (nonatomic) CGFloat slideOffset;
@end

NS_ASSUME_NONNULL_END
