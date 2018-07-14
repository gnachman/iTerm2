//
//  iTermStatusBarSetupKnobsViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermStatusBarComponent.h"
#import "iTermStatusBarComponentKnob.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermStatusBarSetupKnobsViewController : NSViewController

@property (nonatomic, readonly) NSDictionary *knobValues;
@property (nonatomic, readonly) NSArray<iTermStatusBarComponentKnob *> *knobs;

- (instancetype)initWithComponent:(id<iTermStatusBarComponent>)component NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (void)commit;

@end

NS_ASSUME_NONNULL_END
