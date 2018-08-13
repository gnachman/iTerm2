//
//  iTermsStatusBarComposerViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermsStatusBarComposerViewController;

@protocol iTermsStatusBarComposerViewControllerDelegate<NSObject>

- (void)statusBarComposer:(iTermsStatusBarComposerViewController *)composer
              sendCommand:(NSString *)command;

- (NSArray<NSString *> *)statusBarComposerSuggestions:(iTermsStatusBarComposerViewController *)composer;

@end

@interface iTermsStatusBarComposerViewController : NSViewController
@property (nonatomic, weak) id<iTermsStatusBarComposerViewControllerDelegate> delegate;

- (void)reloadData;

@end

NS_ASSUME_NONNULL_END
