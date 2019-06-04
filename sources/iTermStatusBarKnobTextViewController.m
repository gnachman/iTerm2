//
//  iTermStatusBarKnobTextViewController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/30/18.
//

#import "iTermStatusBarKnobTextViewController.h"

#import "NSObject+iTerm.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermVariableHistory.h"

@interface iTermStatusBarKnobTextViewController ()

@end

@implementation iTermStatusBarKnobTextViewController {
    NSString *_value;
    iTermFunctionCallTextFieldDelegate *_suggester;
    NSURL *_helpURL;
    CGFloat _textFieldWidth;
    NSButton *_helpButton;
}

- (instancetype)init {
    return [super init];
}

- (instancetype)initWithInvocationSuggester {
    self = [super init];
    if (self) {
        _suggester = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                                        passthrough:self
                                                                      functionsOnly:YES];
    }
    return self;
}

- (void)viewDidLoad {
    self.view.autoresizesSubviews = NO;
    if (_suggester) {
        self.textField.delegate = _suggester;
    }
    _textFieldWidth = self.textField.frame.size.width;
    if (_helpURL) {
        _textFieldWidth -= _helpButton.frame.size.width - 4;
    }
}

- (void)setHelpURL:(NSURL *)url {
    _helpURL = url;

    _helpButton = [[NSButton alloc] initWithFrame:CGRectZero];
    _helpButton.bezelStyle = NSHelpButtonBezelStyle;
    _helpButton.buttonType = NSMomentaryPushInButton;
    _helpButton.bordered = YES;
    [_helpButton sizeToFit];
    _helpButton.target = self;
    _helpButton.action = @selector(help:);
    _helpButton.title = @"";
    [self.view addSubview:_helpButton];
}

- (void)help:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:_helpURL];
}

- (void)setValue:(NSString *)value {
    if (value == nil) {
        [self setValue:@""];
        return;
    }
    _textField.stringValue = value;
}

- (NSString *)value {
    return _value ?: _textField.stringValue;
}

- (void)setDescription:(NSString *)description placeholder:(nonnull NSString *)placeholder {
    _label.stringValue = description;
    _textField.placeholderString = placeholder;
    [self sizeToFit];
}

- (void)sizeToFit {
    const CGFloat marginBetweenLabelAndField = NSMinX(_textField.frame) - NSMaxX(_label.frame);

    [_label sizeToFit];
    NSRect rect = _label.frame;
    rect.origin.x = 0;
    _label.frame = rect;

    rect = _textField.frame;
    rect.origin.x = NSMaxX(_label.frame) + marginBetweenLabelAndField;
    rect.size.width = _textFieldWidth;
    _textField.frame = rect;

    CGFloat maxX = NSMaxX(_textField.frame);

    if (_helpButton) {
        [_helpButton sizeToFit];
        _helpButton.frame = NSMakeRect(maxX + 4,
                                       -4,
                                       _helpButton.frame.size.width,
                                       _helpButton.frame.size.height);
        maxX = NSMaxX(_helpButton.frame);
    }
    rect = self.view.frame;
    rect.size.width = maxX;
    self.view.frame = rect;
}

- (CGFloat)controlOffset {
    return NSMinX(_textField.frame);
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)fieldEditor doCommandBySelector:(SEL)commandSelector {
    if ([self respondsToSelector:commandSelector]) {
        [self it_performNonObjectReturningSelector:commandSelector withObject:control];
        return YES;
    } else {
        return NO;
    }
}

- (void)insertNewline:(id)sender {
    // Mysteriously, calling parentViewController nukes the text field's value.
    _value = self.textField.stringValue;
    [self.view.window.sheetParent endSheet:self.view.window returnCode:NSModalResponseOK];
}

@end
