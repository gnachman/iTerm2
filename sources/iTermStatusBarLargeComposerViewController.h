//
//  iTermStatusBarLargeComposerViewController.h
//  iTerm2
//
//  Created by George Nachman on 8/12/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TmuxController;
@class VT100RemoteHost;

@protocol iTermComposerTextViewDelegate<NSObject>
- (void)composerTextViewDidFinishWithCancel:(BOOL)cancel;
- (void)composerTextViewSendToAdvancedPaste:(NSString *)content;

@optional
- (void)composerTextViewDidResignFirstResponder;
@end

@interface iTermComposerTextView : NSTextView
@property (nonatomic, weak) IBOutlet id<iTermComposerTextViewDelegate> composerDelegate;
@end

@interface iTermStatusBarLargeComposerViewController : NSViewController
@property (nonatomic, strong) IBOutlet iTermComposerTextView *textView;
@property (nonatomic, strong, nullable) VT100RemoteHost *host;
@property (nonatomic, strong, nullable) NSString *workingDirectory;
@property (nonatomic, copy) NSString *shell;
@property (nonatomic, weak, nullable) TmuxController *tmuxController;

@end

NS_ASSUME_NONNULL_END
