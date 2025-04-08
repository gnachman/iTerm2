//
//  iTermAnnouncementView.m
//  iTerm
//
//  Created by George Nachman on 5/16/14.
//
//

#import "iTermAnnouncementView.h"
#import "iTerm2SharedARC-Swift.h"
#import "DebugLogging.h"
#import "NSColor+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSStringITerm.h"
#import "NSImage+iTerm.h"
#import "NSWindow+iTerm.h"

static const CGFloat kMargin = 8;

@interface iTermAnnouncementView ()
@property(nonatomic, assign) iTermAnnouncementViewStyle style;
@end

@implementation iTermAnnouncementView {
    CGFloat _buttonWidth;
    iTermAutoResizingTextView *_textView;
    NSImageView *_icon;
    NSButton *_closeButton;
    NSMutableArray *_actionButtons;
    SolidColorView *_internalView;
    SolidColorView *_lineView;
    NSVisualEffectView *_visualEffectView;
    iTermShadowView *_shadowView;
    void (^_block)(int);
}

+ (id)announcementViewWithTitle:(NSString *)title
                           style:(iTermAnnouncementViewStyle)style
                        actions:(NSArray *)actions
                          block:(void (^)(int index))block {
    iTermAnnouncementView *view = [[self alloc] initWithFrame:NSMakeRect(0, 0, 1000, 44)];
    view.style = style;
    [view setTitle:title];
    [view createButtonsFromActions:actions block:block];
    return view;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        frameRect.size.height -= 10;
        frameRect.origin.y = 10;
        frameRect.origin.x = 0;

        _shadowView = [[iTermShadowView alloc] initWithFrame:frameRect];
        _shadowView.nsShadow.shadowOffset = CGSizeMake(0, 0);
        _shadowView.nsShadow.shadowBlurRadius = 4;
        _shadowView.nsShadow.shadowColor = [[NSColor blackColor] colorWithAlphaComponent:0.1];
        _shadowView.inset = 0;
        _shadowView.cornerRadius = 0;
        [self addSubview:_shadowView];

        _visualEffectView = [[NSVisualEffectView alloc] initWithFrame:frameRect];
        _visualEffectView.material = NSVisualEffectMaterialMenu;
        _visualEffectView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        _visualEffectView.state = NSVisualEffectStateActive;
        _visualEffectView.emphasized = NO;
        _visualEffectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:_visualEffectView];

        _internalView = [[SolidColorView alloc] initWithFrame:frameRect
                                                        color:[NSColor it_dynamicColorForLightMode:[NSColor colorWithSRGBRed:1 green:1 blue:0.9 alpha:0.6]
                                                                                          darkMode:[NSColor colorWithSRGBRed:0.25 green:0.25 blue:0.1 alpha:0.15]]];
        _internalView.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        [self addSubview:_internalView];

        const NSRect lineFrame = NSMakeRect(0, NSMinY(frameRect), NSWidth(frameRect), 1);
        _lineView = [[SolidColorView alloc] initWithFrame:lineFrame
                                                    color:[NSColor it_dynamicColorForLightMode:[NSColor colorWithWhite:0.8 alpha:1.0]
                                                                                      darkMode:[NSColor colorWithWhite:0.2 alpha:1.0]]];
        [self addSubview:_lineView];

        NSImage *closeImage = [NSImage it_imageNamed:@"closebutton" forClass:self.class];
        NSSize closeSize = closeImage.size;
        _buttonWidth = ceil(closeSize.width + kMargin);
        NSButton *closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(frameRect.size.width - _buttonWidth,
                                                                           floor((frameRect.size.height - closeSize.height) / 2),
                                                                           closeSize.width,
                                                                           closeSize.height)];
        closeButton.autoresizingMask = NSViewMinXMargin;
        [closeButton setButtonType:NSButtonTypeMomentaryPushIn];
        [closeButton setImage:closeImage];
        [closeButton setTarget:self];
        [closeButton setAction:@selector(close:)];
        [closeButton setBordered:NO];
        [[closeButton cell] setHighlightsBy:NSContentsCellMask];
        [closeButton setTitle:@""];
        _closeButton = closeButton;

        [_internalView addSubview:closeButton];

        _actionButtons = [[NSMutableArray alloc] init];
        self.autoresizesSubviews = YES;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(windowAppearanceDidChange:)
                                                     name:iTermWindowAppearanceDidChange
                                                   object:nil];
    }
    return self;
}

- (void)close:(id)sender {
    if (_block) {
        _block(-1);
    }
}

- (void)willDismiss {
    _block = nil;
}

- (void)createButtonsFromActions:(NSArray *)actions block:(void (^)(int index))block {
    _block = [block copy];
    NSRect rect = _internalView.frame;

    NSPopUpButton *pullDown = nil;

    // If there are <=2 buttons, create all as buttons. Otherwise create first as button.
    int start;
    int limit;
    int step;
    BOOL shouldCreatePopup;
    if (actions.count <= 2) {
        start = actions.count - 1;
        limit = -1;
        step = -1;
        shouldCreatePopup = NO;
    } else {
        start = 0;
        limit = 1;
        step = 1;
        shouldCreatePopup = YES;
    }

    if (shouldCreatePopup) {
        pullDown = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 0, 0) pullsDown:YES];
        pullDown.autoresizingMask = NSViewMinXMargin;
        [pullDown setBezelStyle:NSBezelStyleTexturedRounded];
        [pullDown setTarget:self];
        [pullDown setAction:@selector(pullDownItemSelected:)];
        [_internalView addSubview:pullDown];
        [pullDown addItemWithTitle:@"More Actions…"];
        for (int i = limit; i < actions.count; i++) {
            NSString *action = actions[i];
            [pullDown addItemWithTitle:[self stringByAddingShortcutInString:action]];
            [[[pullDown itemArray] lastObject] setTag:i];
        }
        [pullDown sizeToFit];
        _buttonWidth += pullDown.frame.size.width + kMargin;
        pullDown.frame = NSMakeRect(rect.size.width - _buttonWidth,
                                    floor((rect.size.height - pullDown.frame.size.height) / 2),
                                    pullDown.frame.size.width,
                                    pullDown.frame.size.height);
        [_actionButtons addObject:pullDown];
    }

    for (int i = start; i != limit; i += step) {
        NSString *action = actions[i];
        NSButton *button = [[NSButton alloc] init];
        [button setButtonType:NSButtonTypeMomentaryPushIn];
        [button setTarget:self];
        [button setAction:@selector(buttonPressed:)];
        [button setTag:i];

        [button setTitle:[self stringByAddingShortcutInString:action]];
        [button setBezelStyle:NSBezelStyleTexturedRounded];
        [button sizeToFit];
        button.autoresizingMask = NSViewMinXMargin;
        _buttonWidth += kMargin;
        _buttonWidth += button.frame.size.width;
        button.frame = NSMakeRect(rect.size.width - _buttonWidth,
                                  floor((rect.size.height - button.frame.size.height) / 2),
                                  button.frame.size.width,
                                  button.frame.size.height);
        [_actionButtons addObject:button];
        [_internalView addSubview:button];
    }
}

- (NSString *)stringByAddingShortcutInString:(NSString *)original {
    const NSInteger index = [original rangeOfString:@"_"].location;
    if (index == NSNotFound) {
        return original;
    } else {
        NSString *shortcut = [NSString stringWithLongCharacter:[original characterAtIndex:index + 1]];
        NSString *modifiedOriginal = [original stringByReplacingCharactersInRange:NSMakeRange(index, 1) withString:@""];
        return [NSString stringWithFormat:@"%@ (⌥%@)", modifiedOriginal, shortcut];
    }
}

- (void)viewDidMoveToWindow {
    [self updateAppearance];
}

- (void)updateAppearance {
}

- (void)windowAppearanceDidChange:(NSNotification *)notification {
    if (notification.object == self.window) {
        [self updateAppearance];
    }
}

- (NSImage *)iconImage {
    if (@available(macOS 11.0, *)) {
        NSImage *image;
        switch (_style) {
            case kiTermAnnouncementViewStyleWarning:
                image = [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle" accessibilityDescription:@"Warning icon"];
                break;
            case kiTermAnnouncementViewStyleQuestion:
                image = [NSImage imageWithSystemSymbolName:@"questionmark.circle" accessibilityDescription:@"Question icon"];
                break;
        }
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:22.0 weight:NSFontWeightRegular];
        image = [image imageWithSymbolConfiguration:config];
        image.template = YES;
        return image;
    }

    NSString *iconString;
    switch (_style) {
        case kiTermAnnouncementViewStyleWarning:
            iconString = @"⚠";  // Warning sign
            break;
        case kiTermAnnouncementViewStyleQuestion:
            return [NSImage it_imageNamed:@"QuestionMarkSign" forClass:self.class];
    }

    NSFont *emojiFont = [NSFont fontWithName:@"Apple Color Emoji" size:18];
    NSDictionary *attributes = @{ NSFontAttributeName: emojiFont };

    NSSize size = [iconString sizeWithAttributes:attributes];
    // This is a better estimate of the height. Maybe it doesn't include leading?
    size.height = [emojiFont ascender] - [emojiFont descender];
    NSImage *iconImage = [[NSImage alloc] initWithSize:size];
    [iconImage lockFocus];
    [iconString drawAtPoint:NSMakePoint(0, 0) withAttributes:attributes];
    [iconImage unlockFocus];

    return iconImage;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    NSImage *iconImage = [self iconImage];

    CGFloat y = floor((_internalView.frame.size.height - iconImage.size.height) / 2);
    {
        [_icon removeFromSuperview];
        _icon = [[NSImageView alloc] initWithFrame:NSMakeRect(kMargin,
                                                              y,
                                                              iconImage.size.width,
                                                              iconImage.size.height)];
        [_icon setImage:iconImage];
        [_internalView addSubview:_icon];
    }

    {
        NSRect rect = _internalView.frame;
        rect.origin.x += kMargin + _icon.frame.size.width + _icon.frame.origin.x;
        rect.size.width -= rect.origin.x;

        rect.size.width -= _buttonWidth;
        iTermAutoResizingTextView *textView = [[iTermAutoResizingTextView alloc] initWithFrame:rect];
        NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:12],
                                      NSForegroundColorAttributeName: [NSColor textColor] };
        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:title
                                                                               attributes:attributes];
        textView.textStorage.attributedString = attributedString;
        [textView setEditable:NO];
        textView.autoresizingMask = NSViewWidthSizable | NSViewMaxXMargin;
        textView.drawsBackground = NO;

        [textView setSelectable:NO];

        [_textView removeFromSuperview];
        _textView = textView;

        CGFloat height = [title heightWithAttributes:attributes
                                  constrainedToWidth:rect.size.width];
        CGFloat maxHeight = [self maximumHeightForWidth:rect.size.width];
        height = MIN(height, maxHeight);
        _textView.frame = NSMakeRect(rect.origin.x,
                                     floor((_internalView.frame.size.height - height) / 2),
                                     rect.size.width,
                                     height);
        [self updateTextViewFrame];

        [_internalView addSubview:textView];

        _textView.toolTip = title;
        _textView.enableAutoResizing = YES;
        [_textView adjustFontSizes];
    }
}

- (void)updateTrackingAreas {
    if (self.window) {
        while (self.trackingAreas.count) {
            [self removeTrackingArea:self.trackingAreas[0]];
        }
        NSTrackingArea *trackingArea =
        [[NSTrackingArea alloc] initWithRect:_internalView.frame
                                     options:NSTrackingInVisibleRect | NSTrackingActiveInKeyWindow | NSTrackingCursorUpdate
                                       owner:self
                                    userInfo:nil];
        [self addTrackingArea:trackingArea];
    }
}

- (void)cursorUpdate:(NSEvent *)event {
    [[NSCursor arrowCursor] set];
}

- (void)buttonPressed:(id)sender {
    DLog(@"Button with tag %d pressed in view %@", (int)[sender tag], self);
    if (_block) {
        DLog(@"Invoking its block");
        _block([sender tag]);
    }
}

- (void)selectIndex:(NSInteger)index {
    DLog(@"selectIndex:%@", @(index));
    if (_block) {
        _block(index);
    }
}

- (NSDictionary *)attributesForHeightMeasurement {
    return @{ NSFontAttributeName: [NSFont systemFontOfSize:12] };
}

- (CGFloat)maximumHeightForWidth:(CGFloat)width {
    NSDictionary *attributes = [self attributesForHeightMeasurement];
    return [@"x\nx\nx" heightWithAttributes:attributes constrainedToWidth:width];
}

- (CGFloat)minimumHeightForWidth:(CGFloat)width {
    NSDictionary *attributes = [self attributesForHeightMeasurement];
    return [@"x" heightWithAttributes:attributes constrainedToWidth:width];
}

- (void)updateTextViewFrame {
    NSRect rect = _internalView.frame;
    rect.origin.x += kMargin + _icon.frame.size.width + _icon.frame.origin.x;
    rect.size.width -= rect.origin.x;
    rect.size.width -= _buttonWidth;

    CGFloat height = [_textView.originalAttributedString heightForWidth:rect.size.width];
    CGFloat maxHeight = [self maximumHeightForWidth:rect.size.width];
    CGFloat minHeight = [self minimumHeightForWidth:rect.size.width];
    height = MAX(minHeight, MIN(height, maxHeight));

    NSRect textRect = NSMakeRect(rect.origin.x,
                                 floor((_internalView.frame.size.height - height) / 2),
                                 _internalView.frame.size.width - _buttonWidth - NSMaxX(_icon.frame) - kMargin,
                                 height);
    _textView.frame = textRect;
    _textView.maxSize = textRect.size;
    _textView.minSize = textRect.size;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];

    NSRect frameRect = self.bounds;
    frameRect.size.height -= 10;
    frameRect.origin.y = 10;
    frameRect.origin.x = 0;
    _visualEffectView.frame = frameRect;
    _internalView.frame = frameRect;
    _lineView.frame = NSMakeRect(0, NSMinY(frameRect), NSWidth(frameRect), 1);
    _shadowView.frame = frameRect;

    [self updateTextViewFrame];
    NSSize closeSize = [_closeButton frame].size;
    _closeButton.frame = NSMakeRect(self.frame.size.width - closeSize.width - kMargin,
                                    floor((_internalView.frame.size.height - closeSize.height) / 2),
                                    closeSize.width,
                                    closeSize.height);

    for (NSButton *button in _actionButtons) {
        NSRect buttonFrame = button.frame;
        button.frame = NSMakeRect(buttonFrame.origin.x,
                                  floor((_internalView.frame.size.height - buttonFrame.size.height) / 2),
                                  buttonFrame.size.width,
                                  buttonFrame.size.height);
    }

    CGRect iconFrame = _icon.frame;
    CGFloat y = floor((_internalView.frame.size.height - iconFrame.size.height) / 2);
    _icon.frame = NSMakeRect(kMargin,
                             y,
                             iconFrame.size.width,
                             iconFrame.size.height);
}

- (void)sizeToFit {
    [self updateTextViewFrame];
    NSRect frame = self.frame;
    frame.size.height = _textView.frame.size.height + 29;
    self.frame = frame;
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor arrowCursor]];
}

- (void)pullDownItemSelected:(id)sender {
    if (_block) {
        _block([[sender selectedItem] tag]);
    }
}

- (void)addDismissOnKeyDownLabel {
    NSMutableAttributedString *string = [_textView.originalAttributedString mutableCopy];
    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:10],
                                  NSForegroundColorAttributeName: [NSColor textColor] };
    NSAttributedString *notice = [[NSAttributedString alloc] initWithString:@"\nPress any key to dismiss this message."
                                                                 attributes:attributes];
    [string appendAttributedString:notice];
    _textView.textStorage.attributedString = string;
    _textView.originalAttributedString = string;
}

@end
