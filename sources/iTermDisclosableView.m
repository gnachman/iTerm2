//
//  iTermDisclosableView.m
//  iTerm2
//
//  Created by George Nachman on 11/29/16.
//
//

#import "iTermDisclosableView.h"

@implementation iTermDisclosableView {
    NSTextView *_textView;
    __unsafe_unretained NSButton *_disclosureButton;
    NSRect _originalWindowFrame;
    __unsafe_unretained NSTextField *_labelField;
}

- (instancetype)initWithFrame:(NSRect)frameRect prompt:(NSString *)prompt message:(NSString *)message {
    self = [super initWithFrame:frameRect];
    if (self) {
        _disclosureButton = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 2, 24, 24)] autorelease];
        [_disclosureButton setButtonType:NSButtonTypeOnOff];
        [_disclosureButton setBezelStyle:NSBezelStyleDisclosure];
        [_disclosureButton setImagePosition:NSImageOnly];
        [_disclosureButton setState:NSControlStateValueOff];
        [_disclosureButton setTarget:self];
        [_disclosureButton setAction:@selector(disclosureButtonPressed:)];
        [_disclosureButton sizeToFit];

        _labelField = [[[NSTextField alloc] initWithFrame:NSMakeRect(NSMaxX(_disclosureButton.frame), 0, frameRect.size.width-NSMaxX(_disclosureButton.frame), 18)] autorelease];
        [_labelField setDrawsBackground:NO];
        [_labelField setBordered:NO];
        [_labelField setEditable:NO];
        [_labelField setSelectable:NO];
        [_labelField setStringValue:prompt];
        [_labelField setAlignment:NSTextAlignmentLeft];
        [_labelField setAutoresizingMask:NSViewWidthSizable];
        [_labelField setTextColor:[NSColor headerTextColor]];
        [_labelField sizeToFit];

        _textView = [[NSTextView alloc] initWithFrame:NSMakeRect(8, NSMaxY(_disclosureButton.frame) + 3, 100, 100)];
        [[_textView textContainer] setContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)];
        _textView.drawsBackground = NO;
        _textView.selectable = NO;
        _textView.editable = NO;
        [_textView setMinSize:NSMakeSize(0.0, 0)];
        [_textView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
        [_textView setString:message];
        [_textView setVerticallyResizable:YES];
        [_textView setHorizontallyResizable:YES];
        [[_textView textContainer] setWidthTracksTextView:YES];
        [_textView sizeToFit];

        [self addSubview:_disclosureButton];
        [self addSubview:_labelField];
        [self addSubview:_textView];
    }
    return self;
}

- (void)dealloc {
    [_textView release];
    [super dealloc];
}

- (BOOL)isFlipped {
    return YES;
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize(_disclosureButton.state == NSControlStateValueOn ? NSMaxX(_textView.frame) : NSMaxX(_labelField.frame),
                      _disclosureButton.state == NSControlStateValueOn ? NSMaxY(_textView.frame) : NSMaxY(_disclosureButton.frame));
}

- (void)disclosureButtonPressed:(id)sender {
    NSRect myFrame = self.frame;
    self.frame = NSMakeRect(NSMinX(myFrame), NSMinY(myFrame), self.intrinsicContentSize.width, self.intrinsicContentSize.height);
    self.requestLayout();
}

- (void)viewDidMoveToWindow {
    _originalWindowFrame = self.window.frame;
}

@end
