//
//  iTermActionsEditingViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/20.
//

#import <Cocoa/Cocoa.h>

@class iTermPreferencesBaseViewController;

NS_ASSUME_NONNULL_BEGIN

@interface iTermActionsEditingViewController : NSViewController

- (void)defineControlsInContainer:(iTermPreferencesBaseViewController *)container
                    containerView:(NSView *)containerView;
@end

NS_ASSUME_NONNULL_END
