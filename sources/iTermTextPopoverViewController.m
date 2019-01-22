//
//  iTermTextPopoverViewController.m
//  iTerm2
//
//  Created by George Nachman on 1/21/19.
//

#import "iTermTextPopoverViewController.h"

const CGFloat iTermTextPopoverViewControllerHorizontalMarginWidth = 4;

@interface iTermTextPopoverViewController ()

@end

@implementation iTermTextPopoverViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
}

- (void)appendString:(NSString *)string {
    NSDictionary *attributes = @{ NSFontAttributeName: self.textView.font,
                                  NSForegroundColorAttributeName: self.textView.textColor };
    [_textView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:string attributes:attributes]];
}

@end
