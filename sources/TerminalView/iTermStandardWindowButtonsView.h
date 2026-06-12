//
//  iTermStandardWindowButtonsView.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/7/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermStandardWindowButtonsView : NSView

- (void)setOptionModifier:(BOOL)optionModifier;
- (void)zoomButtonEvent;

@end

NS_ASSUME_NONNULL_END
