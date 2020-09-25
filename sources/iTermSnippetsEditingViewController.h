//
//  iTermSnippetsEditingViewController.h
//  iTerm2
//
//  Created by George Nachman on 9/7/20.
//

#import <Cocoa/Cocoa.h>

@class iTermPreferencesBaseViewController;
@class iTermSnippetsModel;

NS_ASSUME_NONNULL_BEGIN

@interface iTermSnippetsEditingViewController : NSViewController
@property (nonatomic, strong) iTermSnippetsModel *model;

// Call exactly one of these:
- (void)defineControlsInContainer:(iTermPreferencesBaseViewController *)container
                    containerView:(NSView *)containerView;
- (void)finishInitialization;

@end

NS_ASSUME_NONNULL_END
