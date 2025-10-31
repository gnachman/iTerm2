//
//  PSMProgressIndicator.h
//  PSMTabBarControl
//
//  Created by John Pannell on 2/23/06.
//  Copyright 2006 Positive Spin Media. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// This must be kept in sync with VT100ScreenProgress
typedef NS_ENUM(NSInteger, PSMProgress) {
    PSMProgressStopped = 0,
    PSMProgressError = -1,
    PSMProgressIndeterminate = -2,
    PSMProgressSuccessBase = 1000,  // values base...base+100 are percentages.
    PSMProgressErrorBase = 2000,  // values base...base+100 are percentages.
    PSMProgressWarningBase = 3000,  // values base...base+100 are percentages.
};

typedef NS_ENUM(NSInteger, PSMStatus) {
    PSMStatusSuccess,
    PSMStatusWarning,
    PSMStatusError
};


@protocol PSMProgressIndicatorDelegate
- (void)progressIndicatorNeedsUpdate;
@end

// This is a wrapper around an NSProgressIndicator. The main difference between this and
// NSProgressIndicator is that setting the |light| property changes the appearance of the progress
// indicator so it looks good against a dark background.
@interface PSMProgressIndicator : NSView

// Should the progress indicator render in a "light" style, suitable for use over a dark background?
@property(nonatomic, assign) BOOL light;
@property(nonatomic, assign) id<PSMProgressIndicatorDelegate> delegate;
@property(nonatomic, assign) BOOL animate;

@property(nonatomic, readonly) BOOL indeterminate;
@property(nonatomic, readonly) PSMStatus status;
@property(nonatomic, readonly) double fraction;

// Enters determinate mode.
- (void)becomeDeterminateWithFraction:(CGFloat)fraction status:(PSMStatus)PSMStatus animated:(BOOL)animated;
- (void)becomeIndeterminate;

@end
