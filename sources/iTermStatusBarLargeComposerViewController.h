//
//  iTermStatusBarLargeComposerViewController.h
//  iTerm2
//
//  Created by George Nachman on 8/12/18.
//

#import <Cocoa/Cocoa.h>

#import "iTerm2SharedARC-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@class TmuxController;
@protocol VT100RemoteHostReading;

@interface iTermStatusBarLargeComposerViewController : NSViewController
@property (nonatomic, strong) IBOutlet iTermComposerTextView *textView;
@property (nonatomic, strong, nullable) id<VT100RemoteHostReading> host;
@property (nonatomic, strong, nullable) NSString *workingDirectory;
@property (nonatomic, copy) iTermVariableScope *scope;
@property (nonatomic, weak, nullable) TmuxController *tmuxController;

@end

NS_ASSUME_NONNULL_END
