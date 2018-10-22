//
//  iTermLionFullScreenTabBarViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/21/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_14)
@interface iTermLionFullScreenTabBarViewController : NSTitlebarAccessoryViewController

- (instancetype)initWithView:(NSView *)view NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
