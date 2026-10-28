//
//  iTermSlider.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/8/21.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermSlider : NSView
@property (nonatomic, readonly) NSSlider *slider;

// Call after changing the slider's minValue or maxValue so the stepper and text field match.
- (void)sliderRangeDidChange;
@end

NS_ASSUME_NONNULL_END
