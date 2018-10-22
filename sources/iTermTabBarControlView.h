//
//  iTermTabBarControlView.h
//  iTerm
//
//  Created by George Nachman on 5/29/14.
//
//

#import "PSMTabBarControl.h"

extern CGFloat iTermTabBarControlViewDefaultHeight;

// NOTE: The delegate should nil out of itermTabBarDelegate when it gets dealloced; we may live on because of delayed performs.
@protocol iTermTabBarControlViewDelegate <NSObject>

- (BOOL)iTermTabBarShouldFlashAutomatically;
- (void)iTermTabBarWillBeginFlash;
- (void)iTermTabBarDidFinishFlash;
- (BOOL)iTermTabBarWindowIsFullScreen;
- (BOOL)iTermTabBarCanDragWindow;

@end

// A customized version of PSMTabBarControl.
@interface iTermTabBarControlView : PSMTabBarControl

@property(nonatomic, assign) id<iTermTabBarControlViewDelegate> itermTabBarDelegate;

// Set to yes when cmd pressed, no when released. We take care of the timing.
@property(nonatomic, assign) BOOL cmdPressed;

// Getter indicates if the tab bar is currently flashing. Setting starts or
// stops flashing. We take care of fading.
@property(nonatomic, assign) BOOL flashing;

// Call this when the result of iTermTabBarShouldFlash would change.
- (void)updateFlashing;

- (void)setAlphaValue:(CGFloat)alphaValue animated:(BOOL)animated;
- (void)setAlphaValue:(CGFloat)alphaValue NS_UNAVAILABLE;

@end
