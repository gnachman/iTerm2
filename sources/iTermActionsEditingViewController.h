//
//  iTermActionsEditingViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/20.
//

#import <Cocoa/Cocoa.h>

@class iTermActionsModel;

@class iTermPreferencesBaseViewController;

NS_ASSUME_NONNULL_BEGIN

@interface iTermActionsEditingViewController : NSViewController
@property (nonatomic, strong) iTermActionsModel *model;

- (void)defineControlsInContainer:(iTermPreferencesBaseViewController *)container
                    containerView:(NSView *)containerView;
- (void)finishInitialization;

@end

NS_ASSUME_NONNULL_END
