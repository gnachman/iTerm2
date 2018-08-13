//
//  iTermStatusBarLargeComposerViewController.m
//  iTerm2
//
//  Created by George Nachman on 8/12/18.
//

#import "iTermStatusBarLargeComposerViewController.h"

@interface iTermStatusBarLargeComposerViewController ()

@end

@implementation iTermStatusBarLargeComposerViewController {
    IBOutlet NSTextView *_textView;
}

- (NSString *)stringValue {
    return _textView.string;
}

@end
