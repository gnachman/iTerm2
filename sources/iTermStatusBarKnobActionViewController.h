//
//  iTermStatusBarKnobActionViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/22/19.
//

#import <Cocoa/Cocoa.h>
#import "iTermStatusBarComponentKnob.h"
#import "ProfileModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermStatusBarKnobActionViewController : NSViewController<iTermStatusBarKnobViewController>

@property (nonatomic) NSDictionary *value;
@property (nonatomic, readonly) ProfileType profileType;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(NSNibName)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

- (instancetype)initWithProfileType:(ProfileType)profileType NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
