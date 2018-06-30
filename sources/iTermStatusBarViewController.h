//
//  iTermStatusBarViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermStatusBarLayout;

@interface iTermStatusBarViewController : NSViewController<NSSecureCoding>

@property (nonatomic, readonly) iTermStatusBarLayout *layout;

- (instancetype)initWithLayout:(iTermStatusBarLayout *)layout NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
