//
//  iTermsStatusBarComposerViewController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/12/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol VT100RemoteHostReading;
@class iTermsStatusBarComposerViewController;

@protocol iTermsStatusBarComposerViewControllerDelegate<NSObject>

- (void)statusBarComposer:(iTermsStatusBarComposerViewController *)composer
              sendCommand:(NSString *)command;

- (NSArray<NSString *> *)statusBarComposerSuggestions:(iTermsStatusBarComposerViewController *)composer;
- (NSFont *)statusBarComposerFont:(iTermsStatusBarComposerViewController *)composer;
- (BOOL)statusBarComposerShouldForceDarkAppearance:(iTermsStatusBarComposerViewController *)composer;
- (void)statusBarComposerDidEndEditing:(iTermsStatusBarComposerViewController *)composer;
- (void)statusBarComposerRevealComposer:(iTermsStatusBarComposerViewController *)composer;
@end

@interface iTermsStatusBarComposerViewController : NSViewController
@property (nonatomic, weak) id<iTermsStatusBarComposerViewControllerDelegate> delegate;
@property (nonatomic, copy) NSString *stringValue;
@property (nonatomic, readonly) NSRect cursorFrameInScreenCoordinates;

- (void)setTintColor:(NSColor *)tintColor;

- (void)reloadData;
- (void)makeFirstResponder;
- (void)setHost:(id<VT100RemoteHostReading>)host;
- (void)deselect;
- (void)insertText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
