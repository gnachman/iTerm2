//
//  iTermDisclosableView.m
//  iTerm2
//
//  Created by George Nachman on 11/29/16.
//
//

#import "iTermDisclosableView.h"
#import "iTerm2SharedARC-Swift.h"
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
    NSLayoutConstraint *_bottomAnchor;
}

+ (NSTextView *)newTextViewWithFrame:(NSRect)frame scrollview:(out NSScrollView **)scrollViewPtr {
    NSTextView *textView = [[NSTextView alloc] initWithFrame:frame];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
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
        _disclosureButton.controlSize = NSControlSizeSmall;
        [_disclosureButton setButtonType:NSButtonTypeOnOff];
        [_disclosureButton setBezelStyle:NSBezelStyleDisclosure];
        [_disclosureButton setImagePosition:NSImageOnly];
        [_disclosureButton setState:NSControlStateValueOff];
        [_disclosureButton setTarget:self];
        [_disclosureButton setAction:@selector(disclosureButtonPressed:)];
        [_disclosureButton sizeToFit];
        _disclosureButton.translatesAutoresizingMaskIntoConstraints = NO;

        NSFont *font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        _labelField = [[NSTextField alloc] initWithFrame:NSMakeRect(NSMaxX(_disclosureButton.frame), 0, frameRect.size.width-NSMaxX(_disclosureButton.frame), 18)];
        _labelField.font = font;
        [_labelField setDrawsBackground:NO];
        [_labelField setBordered:NO];
        [_labelField setEditable:NO];
        [_labelField setSelectable:NO];
        [_labelField setStringValue:prompt];
        [_labelField setAlignment:NSTextAlignmentLeft];
        [_labelField setTextColor:[NSColor headerTextColor]];
        _labelField.translatesAutoresizingMaskIntoConstraints = NO;
        [_labelField sizeToFit];
        _headerWidth = _labelField.frame.size.width;

        NSScrollView *scrollview;
        _textView = [self.class newTextViewWithFrame:NSMakeRect(8, NSMaxY(_disclosureButton.frame) + 3, 100, 100)
                                          scrollview:&scrollview];
        if (scrollview) {
            _textView.translatesAutoresizingMaskIntoConstraints = YES;
        }
        _scrollView = scrollview;
        scrollview.translatesAutoresizingMaskIntoConstraints = NO;

        _textView.drawsBackground = NO;
        _textView.selectable = NO;
        _textView.editable = NO;
        [_textView setMinSize:NSMakeSize(0.0, 0)];
        [_textView setString:message];
        _textView.font = font;
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

        [_disclosureButton.centerYAnchor constraintEqualToAnchor:_labelField.centerYAnchor].active = YES;
        [_labelField.leadingAnchor constraintEqualToAnchor:_disclosureButton.trailingAnchor constant:4].active = YES;
        [_labelField.centerXAnchor constraintEqualToAnchor:self.centerXAnchor].active = YES;
        [_labelField.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
        if (_scrollView) {
            [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8].active = YES;
            [_scrollView.topAnchor constraintEqualToAnchor:_disclosureButton.bottomAnchor constant:3].active = YES;
            [_scrollView.widthAnchor constraintEqualToConstant:iTermDisclosableViewTextViewWidth].active = YES;
            [_scrollView.heightAnchor constraintEqualToConstant:100].active = YES;
        } else {
            [_textView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8].active = YES;
            [_textView.topAnchor constraintEqualToAnchor:_disclosureButton.bottomAnchor constant:3].active = YES;
            [_textView.widthAnchor constraintEqualToConstant:iTermDisclosableViewTextViewWidth].active = YES;
            _bottomAnchor = [_textView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor];
            _bottomAnchor.active = NO;
            [_textView setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        }
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (CGFloat)heightWhenOpen {
    const CGFloat h = [_textView desiredHeightForWidth:NSWidth(_textView.frame)];
    return NSMinY(_textView.frame) + h;
}

- (CGFloat)heightWhenClosed {
    return NSMaxY(_disclosureButton.frame);
}

- (NSSize)intrinsicContentSize {
    NSSize size = NSMakeSize(_disclosureButton.state == NSControlStateValueOn ? MAX(_headerWidth, iTermDisclosableViewTextViewWidth) : _headerWidth,
                             _disclosureButton.state == NSControlStateValueOn ? [self heightWhenOpen] : [self heightWhenClosed]);
    size.width += _disclosureButton.frame.size.width;
    return size;
}

- (void)disclosureButtonPressed:(id)sender {
    const BOOL isOpen = (_disclosureButton.state == NSControlStateValueOn);
    _bottomAnchor.active = isOpen;
    _scrollView.hidden = !isOpen;
    _textView.hidden = !isOpen;
    self.requestLayout();
}

- (void)callRequestLayout {
    self.requestLayout();
}

- (void)viewDidMoveToWindow {
    _originalWindowFrame = self.window.frame;
}

@end

@implementation iTermAccessoryViewUnfucker: NSView

- (instancetype)initWithView:(NSView *)contentView {
    self = [super initWithFrame:NSMakeRect(0, 0, contentView.bounds.size.width, contentView.bounds.size.height)];
    if (self) {
        _contentView = contentView;
        [self addSubview:_contentView];
    }
    return self;
}

- (void)layout {
    NSRect frame = self.frame;
    const NSSize ics = _contentView.intrinsicContentSize;
    if (ics.width >= 0 && ics.height >= 0) {
        frame.size = _contentView.intrinsicContentSize;
    } else {
        frame.size = _contentView.frame.size;
    }
    self.frame = frame;
    _contentView.frame = self.bounds;
}

@end

