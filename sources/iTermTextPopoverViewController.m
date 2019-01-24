//
//  iTermTextPopoverViewController.m
//  iTerm2
//
//  Created by George Nachman on 1/21/19.
//

#import "iTermTextPopoverViewController.h"

#import "SolidColorView.h"

const CGFloat iTermTextPopoverViewControllerHorizontalMarginWidth = 4;

@interface iTermTextPopoverViewController ()

@end

@implementation iTermTextPopoverViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    if (@available(macOS 10.14, *)) {
        return;
    }
    _textView.textContainerInset = NSMakeSize(8, 8);
}

- (void)appendString:(NSString *)string {
    NSDictionary *attributes = @{ NSFontAttributeName: self.textView.font,
                                  NSForegroundColorAttributeName: self.textView.textColor ?: [NSColor textColor] };
    [_textView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:string attributes:attributes]];
}

@end
