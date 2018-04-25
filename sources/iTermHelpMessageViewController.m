//
//  iTermHelpMessageViewController.m
//  iTerm2
//
//  Created by George Nachman on 3/8/17.
//
//

#import "iTermHelpMessageViewController.h"
#import "NSMutableAttributedString+iTerm.h"

@interface iTermFittedTextField : NSTextField
@end

@interface iTermHelpMessageViewController ()

@end

@implementation iTermHelpMessageViewController {
    __weak IBOutlet NSTextField *_textField;
}

- (void)setMessage:(NSString *)message {
    [self view];
    _textField.stringValue = message;
    [_textField sizeToFit];
}

@end
