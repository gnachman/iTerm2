//
//  iTermStatusBarLargeComposerViewController.h
//  iTerm2
//
//  Created by George Nachman on 8/12/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol iTermComposerTextViewDelegate<NSObject>
- (void)composerTextViewDidFinish;
@end

@interface iTermComposerTextView : NSTextView
@property (nonatomic, weak) IBOutlet id<iTermComposerTextViewDelegate> composerDelegate;
@end

@interface iTermStatusBarLargeComposerViewController : NSViewController
@property (nonatomic, strong) IBOutlet iTermComposerTextView *textView;

@end

NS_ASSUME_NONNULL_END
