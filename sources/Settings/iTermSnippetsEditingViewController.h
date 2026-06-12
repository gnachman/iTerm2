//
//  iTermSnippetsEditingViewController.h
//  iTerm2
//
//  Created by George Nachman on 9/7/20.
//

#import <Cocoa/Cocoa.h>

@class iTermPreferencesBaseViewController;

NS_ASSUME_NONNULL_BEGIN

@interface iTermSnippetsEditingViewController : NSViewController

- (void)defineControlsInContainer:(iTermPreferencesBaseViewController *)container
                    containerView:(NSView *)containerView;

@end

NS_ASSUME_NONNULL_END
