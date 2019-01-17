//
//  iTermStatusBarSetupViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE(10_11, NA)
@interface iTermStatusBarSetupViewController : NSViewController 
@property (nonatomic, readonly) NSDictionary *layoutDictionary;
@property (nonatomic, readonly) BOOL ok;

- (nullable instancetype)initWithLayoutDictionary:(NSDictionary *)layoutDictionary
                                   darkBackground:(BOOL)darkbackground
                                     allowRainbow:(BOOL)allowRainbow NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
