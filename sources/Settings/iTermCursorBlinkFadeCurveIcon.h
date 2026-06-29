//
//  iTermCursorBlinkFadeCurveIcon.h
//  iTerm2
//
//  Generates small template images that visualize a cursor blink fade curve,
//  used as the icons in the fade-in/fade-out curve popup menus.
//

#import <Cocoa/Cocoa.h>

#import "iTermCursorBlinkFadeAnimator.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCursorBlinkFadeCurveIcon : NSObject

// A small template image plotting the curve with time on the x axis and opacity
// on the y axis. When fadeOut is YES the plot is flipped vertically so it shows
// opacity falling from 1 to 0 (the fade-out shape) instead of rising from 0 to
// 1. The curve is sampled from iTermCursorBlinkFadeAnimator so the picture
// always matches the animation.
+ (NSImage *)imageForCurve:(iTermCursorBlinkFadeCurve)curve fadeOut:(BOOL)fadeOut;

@end

NS_ASSUME_NONNULL_END
