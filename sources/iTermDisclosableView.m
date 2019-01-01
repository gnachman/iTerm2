//
//  iTermDisclosableView.m
//  iTerm2
//
//  Created by George Nachman on 11/29/16.
//
//

#import "iTermDisclosableView.h"
#import "NSMutableAttributedString+iTerm.h"

static const CGFloat iTermDisclosableViewTextViewWidth = 300;

@interface iTermDisclosableView()
@property (nonatomic, strong) NSButton *disclosureButton;
@property (nonatomic, strong) NSScrollView *scrollView;  // optional

- (void)callRequestLayout;
@end

@implementation iTermScrollingDisclosableView {
    CGFloat _maximumHeight;
}

+ (NSTextView *)newTextViewWithFrame:(NSRect)frame scrollview:(out NSScrollView **)scrollViewPtr {
    NSScrollView *scrollview = [[NSScrollView alloc] initWithFrame:frame];
    NSSize contentSize = [scrollview contentSize];

    [scrollview setBorderType:NSNoBorder];
    [scrollview setHasVerticalScroller:YES];
    [scrollview setHasHorizontalScroller:NO];
    [scrollview setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    scrollview.drawsBackground = NO;

    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
    [textView setMinSize:NSMakeSize(0.0, contentSize.height)];
    [textView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [textView setVerticallyResizable:YES];
    [textView setHorizontallyResizable:NO];
    [textView setAutoresizingMask:NSViewWidthSizable];

    [[textView textContainer] setContainerSize:NSMakeSize(contentSize.width, FLT_MAX)];
    [[textView textContainer] setWidthTracksTextView:YES];

    [scrollview setDocumentView:textView];
    *scrollViewPtr = scrollview;
    return textView;
}

- (instancetype)initWithFrame:(NSRect)frameRect prompt:(NSString *)prompt message:(NSString *)message maximumHeight:(CGFloat)maximumHeight {
    self = [super initWithFrame:frameRect prompt:prompt message:message];
    if (self) {
        _maximumHeight = maximumHeight;
    }
    return self;
}

- (CGFloat)heightWhenOpen {
    NSDictionary *attributes = @{ NSFontAttributeName: self.textView.font };
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:self.textView.string
                                                                           attributes:attributes];
    const CGFloat height = [attributedString heightForWidth:self.textView.frame.size.width];

    return MIN(_maximumHeight, height);
}

- (void)callRequestLayout {
    [self.textView sizeToFit];
    [super callRequestLayout];
}


- (NSRect)desiredContentFrame {
    NSSize size = self.bounds.size;
    const CGFloat y = NSMaxY(self.disclosureButton.frame) + 3;
    return NSMakeRect(8, y, size.width, size.height - y);
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    self.scrollView.frame = [self desiredContentFrame];
}

@end

@implementation iTermDisclosableView {
    NSRect _originalWindowFrame;
    NSTextField *_labelField;
    CGFloat _headerWidth;
}

+ (NSTextView *)newTextViewWithFrame:(NSRect)frame scrollview:(out NSScrollView **)scrollViewPtr {
    NSTextView *textView = [[NSTextView alloc] initWithFrame:frame];
    [[textView textContainer] setContainerSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    *scrollViewPtr = nil;
    [textView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [textView setVerticallyResizable:YES];
    [textView setHorizontallyResizable:YES];
    [[textView textContainer] setWidthTracksTextView:YES];
    return textView;
}

- (instancetype)initWithFrame:(NSRect)frameRect prompt:(NSString *)prompt message:(NSString *)message {
    self = [super initWithFrame:frameRect];
    if (self) {
        _disclosureButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 2, 24, 24)];
        [_disclosureButton setButtonType:NSOnOffButton];
        [_disclosureButton setBezelStyle:NSDisclosureBezelStyle];
        [_disclosureButton setImagePosition:NSImageOnly];
        [_disclosureButton setState:NSOffState];
        [_disclosureButton setTarget:self];
        [_disclosureButton setAction:@selector(disclosureButtonPressed:)];
        [_disclosureButton sizeToFit];

        _labelField = [[NSTextField alloc] initWithFrame:NSMakeRect(NSMaxX(_disclosureButton.frame), 0, frameRect.size.width-NSMaxX(_disclosureButton.frame), 18)];
        [_labelField setDrawsBackground:NO];
        [_labelField setBordered:NO];
        [_labelField setEditable:NO];
        [_labelField setSelectable:NO];
        [_labelField setStringValue:prompt];
        [_labelField setAlignment:NSTextAlignmentLeft];
        [_labelField setAutoresizingMask:NSViewWidthSizable];
        [_labelField setTextColor:[NSColor headerTextColor]];
        [_labelField sizeToFit];
        _headerWidth = _labelField.frame.size.width;

        NSScrollView *scrollview;
        _textView = [self.class newTextViewWithFrame:NSMakeRect(8, NSMaxY(_disclosureButton.frame) + 3, 100, 100)
                     scrollview:&scrollview];
        _scrollView = scrollview;

        _textView.drawsBackground = NO;
        _textView.selectable = NO;
        _textView.editable = NO;
        [_textView setMinSize:NSMakeSize(0.0, 0)];
        [_textView setString:message];
        [_textView sizeToFit];

        NSTextStorage *storage = [_textView textStorage];
        NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        [style setLineBreakMode:NSLineBreakByWordWrapping];
        [storage addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, [storage length])];

        CGFloat height = [_textView.attributedString heightForWidth:iTermDisclosableViewTextViewWidth];
        NSRect frame = _textView.frame;
        frame.size.width = iTermDisclosableViewTextViewWidth;
        frame.size.height = height;
        _textView.frame = frame;

        _scrollView.hidden = YES;
        _textView.hidden = YES;

        [self addSubview:_disclosureButton];
        [self addSubview:_labelField];
        if (_scrollView) {
            [self addSubview:_scrollView];
        } else {
            [self addSubview:_textView];
        }
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (CGFloat)heightWhenOpen {
    return NSMaxY(_textView.frame);
}

- (CGFloat)heightWhenClosed {
    return NSMaxY(_disclosureButton.frame);
}

- (NSSize)intrinsicContentSize {
    NSSize size = NSMakeSize(_disclosureButton.state == NSOnState ? MAX(_headerWidth, iTermDisclosableViewTextViewWidth) : _headerWidth,
                             _disclosureButton.state == NSOnState ? [self heightWhenOpen] : [self heightWhenClosed]);
    size.width += _disclosureButton.frame.size.width;
    return size;
}

- (void)disclosureButtonPressed:(id)sender {
    NSRect myFrame = self.frame;
    self.frame = NSMakeRect(NSMinX(myFrame), NSMinY(myFrame), self.intrinsicContentSize.width, self.intrinsicContentSize.height);
    const BOOL isOpen = (_disclosureButton.state == NSOnState);
    _scrollView.hidden = !isOpen;
    _textView.hidden = !isOpen;
    [self callRequestLayout];
}

- (void)callRequestLayout {
    self.requestLayout();
}

- (void)viewDidMoveToWindow {
    _originalWindowFrame = self.window.frame;
}

@end
