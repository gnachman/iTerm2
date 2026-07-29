//
//  iTermCursorBlinkFadePreset.h
//  iTerm2
//
//  Named presets for the smooth cursor blink configuration. Each preset sets
//  all six knobs (the two fade durations, the two easing curves, and the two
//  dwell times). The order matches the tags of the presets popup.
//

#import <Foundation/Foundation.h>

#import "iTermCursorBlinkFadeAnimator.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCursorBlinkFadePreset : NSObject

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSTimeInterval fadeInDuration;
@property (nonatomic, readonly) NSTimeInterval fadeOutDuration;
@property (nonatomic, readonly) iTermCursorBlinkFadeCurve fadeInCurve;
@property (nonatomic, readonly) iTermCursorBlinkFadeCurve fadeOutCurve;
@property (nonatomic, readonly) NSTimeInterval visibleDwell;
@property (nonatomic, readonly) NSTimeInterval hiddenDwell;

// Presets in tag order: 0=Breathing, 1=Linear, 2=Fast, 3=Slow, 4=Subtle.
+ (NSArray<iTermCursorBlinkFadePreset *> *)presets;

// The preset for a popup item's tag, or nil if out of range.
+ (nullable iTermCursorBlinkFadePreset *)presetWithTag:(NSInteger)tag;

// YES if all six values match this preset (durations/dwells within a small
// tolerance, curves exactly). Used to decide which preset, if any, the current
// configuration corresponds to.
- (BOOL)matchesFadeInDuration:(NSTimeInterval)fadeInDuration
             fadeOutDuration:(NSTimeInterval)fadeOutDuration
                 fadeInCurve:(iTermCursorBlinkFadeCurve)fadeInCurve
                fadeOutCurve:(iTermCursorBlinkFadeCurve)fadeOutCurve
                visibleDwell:(NSTimeInterval)visibleDwell
                 hiddenDwell:(NSTimeInterval)hiddenDwell;

@end

NS_ASSUME_NONNULL_END
