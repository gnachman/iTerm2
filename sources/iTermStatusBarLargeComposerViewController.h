//
//  iTermStatusBarLargeComposerViewController.h
//  iTerm2
//
//  Created by George Nachman on 8/12/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class VT100RemoteHost;

@protocol iTermComposerTextViewDelegate<NSObject>
- (void)composerTextViewDidFinishWithCancel:(BOOL)cancel;

@optional
- (void)composerTextViewDidResignFirstResponder;
@end

@interface iTermComposerTextView : NSTextView
@property (nonatomic, weak) IBOutlet id<iTermComposerTextViewDelegate> composerDelegate;
@end

@interface iTermStatusBarLargeComposerViewController : NSViewController
@property (nonatomic, strong) IBOutlet iTermComposerTextView *textView;
@property (nonatomic, strong) VT100RemoteHost *host;

@end

NS_ASSUME_NONNULL_END
