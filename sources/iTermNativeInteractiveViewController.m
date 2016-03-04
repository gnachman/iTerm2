//
//  iTermNativeInteractiveViewController.m
//  iTerm2
//
//  Created by George Nachman on 3/2/16.
//
//

#import "iTermNativeInteractiveViewController.h"
#import "SolidColorView.h"

@interface iTermNativeInteractiveViewController ()<NSTextFieldDelegate>

@end

@implementation iTermNativeInteractiveViewController {
    NSTextField *_textField;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    self = [super initWithDictionary:dictionary];
    if (self) {
        [self notifyViewReadyForDisplay];
    }
    return self;
}

- (void)iterm_dealloc {
    [_textField release];
    [super iterm_dealloc];
}

- (void)loadView {
    NSLog(@"view did load");
    self.view = [[SolidColorView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)
                                                color:[NSColor blueColor]];
    NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(8,
                                                                            8,
                                                                            0,
                                                                           0)];
    _textField = textField;
    [textField setBezeled:YES];
    [textField setDrawsBackground:YES];
    [textField setEditable:YES];
    [textField setSelectable:YES];
    textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    textField.textColor = [NSColor blackColor];
    textField.backgroundColor = [NSColor whiteColor];
    textField.stringValue = @"100";
    [textField sizeToFit];
    NSRect rect = textField.frame;
    rect.size.width = 100;
    textField.frame = rect;
    textField.delegate = self;
    [self.view addSubview:textField];

}

- (void)viewDidLayout {
    [super viewDidLayout];
    _textField.integerValue = self.view.frame.size.height;
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    CGFloat height = _textField.integerValue;
    [self requestSizeChangeTo:NSMakeSize(0, height)];
}

@end
