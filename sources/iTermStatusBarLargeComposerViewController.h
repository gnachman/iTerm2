//
//  iTermStatusBarLargeComposerViewController.h
//  iTerm2
//
//  Created by George Nachman on 8/12/18.
//

#import <Cocoa/Cocoa.h>

#import "iTerm2SharedARC-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermStatusBarLargeComposerViewController;
@class TmuxController;
@protocol VT100RemoteHostReading;

@protocol iTermStatusBarLargeComposerViewControllerDelegate<NSObject>
- (void)largeComposerViewControllerTextDidChange:(iTermStatusBarLargeComposerViewController *)controller;
- (BOOL)largeComposerViewControllerShouldFetchSuggestions:(iTermStatusBarLargeComposerViewController *)controller
                                                  forHost:(id<VT100RemoteHostReading>)remoteHost
                                           tmuxController:(TmuxController *)tmuxController;
- (void)largeComposerViewController:(iTermStatusBarLargeComposerViewController *)controller
                   fetchSuggestions:(iTermSuggestionRequest *)request;
@end

@interface iTermStatusBarLargeComposerViewController : NSViewController
@property (nonatomic, strong) IBOutlet iTermComposerTextView *textView;
@property (nonatomic, strong, nullable) id<VT100RemoteHostReading> host;
@property (nonatomic, strong, nullable) NSString *workingDirectory;
@property (nonatomic, copy) iTermVariableScope *scope;
@property (nonatomic, weak, nullable) TmuxController *tmuxController;
@property (nonatomic) BOOL hideAccessories;
@property (nonatomic, weak) IBOutlet id<iTermStatusBarLargeComposerViewControllerDelegate> delegate;

- (void)fetchCompletions:(void (^)(NSString *, NSArray<NSString *> *))completionBlock;

@end

NS_ASSUME_NONNULL_END
