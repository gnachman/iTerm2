//
//  iTermsStatusBarComposerViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class VT100RemoteHost;
@class iTermsStatusBarComposerViewController;

@protocol iTermsStatusBarComposerViewControllerDelegate<NSObject>

- (void)statusBarComposer:(iTermsStatusBarComposerViewController *)composer
              sendCommand:(NSString *)command;

- (NSArray<NSString *> *)statusBarComposerSuggestions:(iTermsStatusBarComposerViewController *)composer;
- (NSFont *)statusBarComposerFont:(iTermsStatusBarComposerViewController *)composer;
- (BOOL)statusBarComposerShouldForceDarkAppearance:(iTermsStatusBarComposerViewController *)composer;
- (void)statusBarComposerDidEndEditing:(iTermsStatusBarComposerViewController *)composer;
- (BOOL)statusBarComposerShouldUsePopover:(iTermsStatusBarComposerViewController *)composer;
@end

@interface iTermsStatusBarComposerViewController : NSViewController
@property (nonatomic, weak) id<iTermsStatusBarComposerViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *stringValue;

- (void)setTintColor:(NSColor *)tintColor;

- (void)reloadData;
- (void)makeFirstResponder;
- (BOOL)dismissPopover;
- (void)setHost:(VT100RemoteHost *)host;

@end

NS_ASSUME_NONNULL_END
