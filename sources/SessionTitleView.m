//
//  SessionTitleView.m
//  iTerm
//
//  Created by George Nachman on 10/21/11.
//  Copyright 2011 George Nachman. All rights reserved.
//

#import "SessionTitleView.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermHamburgerButton.h"
#import "iTermPreferences.h"
#import "iTermStatusBarViewController.h"
#import "NSAppearance+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "PSMMinimalTabStyle.h"
#import "PSMTabBarControl.h"
#import "PTYWindow.h"
#import "SFSymbolEnum.h"

const double kBottomMargin = 0;
static const CGFloat kButtonSize = 17;

@interface NoFirstResponderButton : NSButton
@end

@implementation NoFirstResponderButton

// Sometimes the button becomes the first responder for some weird reason.
// Prevent that from happening. Bug 1924. This is just an experiment to see if it works (4/16/13)
- (BOOL)acceptsFirstResponder {
    return NO;
}

@end

@implementation SessionTitleView {
    NSTextField *label_;
    NSButton *closeButton_;
    NSButton *lockButton_;
    iTermHamburgerButton *menuButton_;
}

@synthesize title = title_;
@synthesize delegate = delegate_;
@synthesize dimmingAmount = dimmingAmount_;
@synthesize statusBarViewController = _statusBarViewController;

static const double kMargin = 5;
static const CGFloat kLockButtonSize = 14;

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        NSImage *closeImage = [NSImage it_imageNamed:@"closebutton" forClass:self.class];
        closeButton_ = [[NoFirstResponderButton alloc] initWithFrame:NSMakeRect(0, 0, kButtonSize, kButtonSize)];
        [closeButton_ setButtonType:NSButtonTypeMomentaryPushIn];
        [closeButton_ setImage:closeImage];
        [closeButton_ setTarget:self];
        [closeButton_ setAction:@selector(close:)];
        [closeButton_ setBordered:NO];
        [closeButton_ setTitle:@""];
        [[closeButton_ cell] setHighlightsBy:NSContentsCellMask];
        [self addSubview:closeButton_];

        __weak __typeof(self) weakSelf = self;
        menuButton_ = [[iTermHamburgerButton alloc] initWithMenuProvider:^NSMenu * _Nonnull {
            return [weakSelf menu];
        }];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(modifierShortcutDidChange:)
                                                     name:kPSMModifierChangedNotification
                                                   object:nil];

        // Menu button - positioned at right edge
        [self addSubview:menuButton_];

        // Create lock button - positioned to the left of menu button, hidden by default
        NSImage *lockImage = [NSImage imageWithSystemSymbolName:SFSymbolGetString(SFSymbolLockFill)
                                         accessibilityDescription:@"Pane is locked"];
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightMedium];
        lockImage = [lockImage imageWithSymbolConfiguration:config];

        lockButton_ = [[NoFirstResponderButton alloc] initWithFrame:NSMakeRect(0, 0, kLockButtonSize, kLockButtonSize)];
        [lockButton_ setButtonType:NSButtonTypeMomentaryPushIn];
        [lockButton_ setImage:lockImage];
        [lockButton_ setTarget:self];
        [lockButton_ setAction:@selector(toggleLock:)];
        [lockButton_ setBordered:NO];
        [lockButton_ setTitle:@""];
        [lockButton_ setToolTip:@"This pane is locked. It cannot be moved, swapped, or dragged, and closing it requires confirmation. Right-click to unlock."];
        [[lockButton_ cell] setHighlightsBy:NSContentsCellMask];
        [lockButton_ setHidden:YES]; // Hidden by default until delegate says it's locked
        [self addSubview:lockButton_];

        label_ = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, frame.size.height)];
        label_.lineBreakMode = NSLineBreakByTruncatingTail;
        [label_ setStringValue:@""];
        [label_ setBezeled:NO];
        [label_ setDrawsBackground:NO];
        [label_ setEditable:NO];
        [label_ setSelectable:NO];
        [label_ setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [label_ sizeToFit];

        [self addSubview:label_];

        [self layoutSubviews];
        [menuButton_ setAutoresizingMask:NSViewMinXMargin];
        [lockButton_ setAutoresizingMask:NSViewMinXMargin]; // Stay at right side
        [label_ setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];
        [self addCursorRect:NSMakeRect(0, 0, frame.size.width, frame.size.height)
                     cursor:[NSCursor arrowCursor]];

        [self updateTextColor];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)layoutSubviews {
    const NSRect frame = self.frame;
    double x = kMargin;
    closeButton_.frame = NSMakeRect(x,
                                    (frame.size.height - kButtonSize) / 2,
                                    kButtonSize,
                                    kButtonSize);
    x += closeButton_.frame.size.width + kMargin;
    menuButton_.frame = NSMakeRect(frame.size.width - menuButton_.image.size.width - 6,
                                   (frame.size.height - menuButton_.image.size.height) / 2,
                                   menuButton_.image.size.width,
                                   menuButton_.image.size.height);
    lockButton_.frame = NSMakeRect(menuButton_.frame.origin.x - kMargin - kLockButtonSize,
                                   (frame.size.height - kLockButtonSize) / 2,
                                   kLockButtonSize,
                                   kLockButtonSize);
    [label_ sizeToFit];
    NSRect lframe = label_.frame;
    lframe.origin.x = x;
    lframe.origin.y = (frame.size.height - lframe.size.height) / 2 + kBottomMargin;
    lframe.size.width = menuButton_.frame.origin.x - x - kMargin;
    if (!lockButton_.isHidden) {
        lframe.size.width -= kMargin + kLockButtonSize;
    }
    label_.frame = lframe;
}

- (void)scrollWheel:(NSEvent *)event {
    DLog(@"%@", event);
    [super scrollWheel:event];
}

- (NSMenu *)menu {
    return delegate_.menu;
}

- (void)setStatusBarViewController:(iTermStatusBarViewController *)statusBarViewController {
    [_statusBarViewController.view removeFromSuperview];
    _statusBarViewController = statusBarViewController;
    if (statusBarViewController) {
        [self addSubview:statusBarViewController.view];
    }
    [self layoutStatusBar];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutStatusBar];
}

- (void)layoutStatusBar {
    if (_statusBarViewController) {
        const CGFloat margin = 5;
        const CGFloat minX = NSMaxX(closeButton_.frame) + margin;
        _statusBarViewController.view.frame = NSMakeRect(minX,
                                                         1,
                                                         NSMinX(menuButton_.frame) - margin - minX,
                                                         self.frame.size.height);
        label_.hidden = YES;
    } else {
        // You can have either a label or a status bar but not both.
        label_.hidden = NO;
    }
}

- (void)close:(id)sender
{
    [delegate_ close];
}

- (void)toggleLock:(id)sender {
    [delegate_ sessionTitleViewToggleLock];
    [self updateLockButton];
}

- (void)updateLockButton {
    BOOL locked = [delegate_ sessionTitleViewIsLocked];
    [lockButton_ setHidden:!locked];
    [self layoutSubviews];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)insaneRect {
    const NSRect dirtyRect = NSIntersectionRect(insaneRect, self.bounds);
    NSColor *color = [self.delegate sessionTitleViewBackgroundColor];
    [color set];
    NSRectFill(dirtyRect);

    if (!self.window.ptyWindow.it_terminalWindowUseMinimalStyle) {
        if ([color perceivedBrightness] > 0.5) {
            [[[NSColor blackColor] colorWithAlphaComponent:0.25] set];
        } else {
            [[[NSColor whiteColor] colorWithAlphaComponent:0.25] set];
        }
        NSRectFillUsingOperation(NSMakeRect(dirtyRect.origin.x, 0, dirtyRect.size.width, 1), NSCompositingOperationSourceOver);
    }

    [super drawRect:insaneRect];
}

- (void)setDelegate:(id<SessionTitleViewDelegate>)delegate {
    delegate_ = delegate;
    [self updateBackgroundColor];
}

- (void)updateBackgroundColor {
    if (@available(macOS 10.16, *)) {
        return;
    }
    label_.backgroundColor = [self.delegate sessionTitleViewBackgroundColor];
    label_.drawsBackground = YES;
    [self setNeedsDisplay:YES];
}

- (void)setTitle:(NSString *)title {
    if ([title isEqualToString:title_]) {
        return;
    }
    title_ = [title copy];
    [self updateTitle];
    [self setNeedsDisplay:YES];
}

- (NSString *)titleString {
    if (_ordinal == 0) {
        return title_;
    }
    NSString *prefix = @"";
    switch ([iTermPreferences intForKey:kPreferenceKeySwitchPaneModifier]) {
        case kPreferenceModifierTagNone:
            return title_;
            break;

        case kPreferencesModifierTagEitherCommand:
            prefix = [NSString stringForModifiersWithMask:NSEventModifierFlagCommand];
            break;

        case kPreferencesModifierTagEitherOption:
            prefix = [NSString stringForModifiersWithMask:NSEventModifierFlagOption];
            break;

        case kPreferencesModifierTagCommandAndOption:
            prefix = [NSString stringForModifiersWithMask:(NSEventModifierFlagCommand | NSEventModifierFlagOption)];
            break;

        case kPreferencesModifierTagLegacyRightControl:
            prefix = [NSString stringForModifiersWithMask:NSEventModifierFlagControl];
            break;
    }
    return [NSString stringWithFormat:@"%@%@   %@", prefix, @(_ordinal), title_];
}

- (void)updateTitle {
    [label_ setStringValue:[self titleString]];
    [self setNeedsDisplay:YES];
}

- (void)setDimmingAmount:(double)value
{
    dimmingAmount_ = value;
    [self updateTextColor];
    [_statusBarViewController.view setNeedsDisplay:YES];
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateTextColor];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateTextColor];
}

- (void)updateTextColor {
    CGFloat whiteLevel = 0;
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    if (self.window.ptyWindow.it_terminalWindowUseMinimalStyle) {
        label_.textColor = [self.window.ptyWindow it_terminalWindowDecorationTextColorForBackgroundColor:[delegate_ sessionTitleViewBackgroundColor]];
        [self setNeedsDisplay:YES];
        return;
    }
    switch ([self.effectiveAppearance it_tabStyle:preferredStyle]) {
        case TAB_STYLE_AUTOMATIC:
        case TAB_STYLE_COMPACT:
        case TAB_STYLE_MINIMAL:
            assert(NO);
            
        case TAB_STYLE_LIGHT:
            if (dimmingAmount_ > 0) {
                // Not selected
                whiteLevel = 0.3;
            } else {
                // selected
                whiteLevel = 0.2;
            }
            break;

        case TAB_STYLE_LIGHT_HIGH_CONTRAST:
            whiteLevel = 0;
            break;

        case TAB_STYLE_DARK:
            if (dimmingAmount_ > 0) {
                // Not selected
                whiteLevel = 0.6;
            } else {
                // selected
                whiteLevel = 0.8;
            }
            break;

        case TAB_STYLE_DARK_HIGH_CONTRAST:
            whiteLevel = 1;
            break;
    }
    [label_ setTextColor:[NSColor colorWithCalibratedWhite:whiteLevel alpha:1]];
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)theEvent {
    if ([iTermAdvancedSettingsModel requireOptionToDragSplitPaneTitleBar]) {
        if ((NSApp.currentEvent.modifierFlags & NSEventModifierFlagOption) == 0) {
            return;
        }
    }
    [delegate_ beginDrag];
}

- (void)mouseUp:(NSEvent *)theEvent {
    if (theEvent.clickCount == 2) {
        [self.delegate doubleClickOnTitleView];
    } else {
        if (self.window.firstResponder == self) {
            [self.delegate sessionTitleViewBecomeFirstResponder];
        }
        [super mouseUp:theEvent];
    }
}

- (void)setOrdinal:(int)ordinal {
    _ordinal = ordinal;
    [self updateTitle];
}

- (void)modifierShortcutDidChange:(NSNotification *)notification {
    [self updateTitle];
}

@end
