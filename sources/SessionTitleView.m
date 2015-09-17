//
//  SessionTitleView.m
//  iTerm
//
//  Created by George Nachman on 10/21/11.
//  Copyright 2011 George Nachman. All rights reserved.
//

#import "SessionTitleView.h"
#import "iTermPreferences.h"
#import "NSImage+iTerm.h"
#import "NSStringITerm.h"
#import "PSMTabBarControl.h"

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
    NSString *title_;
    NSTextField *label_;
    NSButton *closeButton_;
    NSPopUpButton *menuButton_;
    NSObject<SessionTitleViewDelegate> *delegate_;
    double dimmingAmount_;
}

@synthesize title = title_;
@synthesize delegate = delegate_;
@synthesize dimmingAmount = dimmingAmount_;

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        const double kMargin = 5;
        double x = kMargin;

        NSImage *closeImage = [NSImage imageNamed:@"closebutton"];
        closeButton_ = [[[NoFirstResponderButton alloc] initWithFrame:NSMakeRect(x,
                                                                                 (frame.size.height - kButtonSize) / 2,
                                                                                 kButtonSize,
                                                                                 kButtonSize)] autorelease];
        [closeButton_ setButtonType:NSMomentaryPushInButton];
        [closeButton_ setImage:closeImage];
        [closeButton_ setTarget:self];
        [closeButton_ setAction:@selector(close:)];
        [closeButton_ setBordered:NO];
        [closeButton_ setTitle:@""];
        [[closeButton_ cell] setHighlightsBy:NSContentsCellMask];
        [self addSubview:closeButton_];

        x += closeButton_.frame.size.width + kMargin;
        // Popup buttons want to have huge margins on the sides. This one look best right up against
        // the right margin, though. So I'll make it as small as it can be and then push it right so
        // some of it is clipped.
        menuButton_ = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 36, 16.0) pullsDown:YES];
        [(NSPopUpButtonCell *)[menuButton_ cell] setBezeled:NO];
        [[menuButton_ cell] setArrowPosition:NSPopUpNoArrow];
        [menuButton_ setBordered:NO];
        [menuButton_ addItemWithTitle:@""];
        NSMenuItem *item = [menuButton_ itemAtIndex:0];
        [self setImagesForActionItem:item];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(popupWillOpen:)
                                                     name:NSPopUpButtonWillPopUpNotification
                                                   object:menuButton_];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(modifierShortcutDidChange:)
                                                     name:kPSMModifierChangedNotification
                                                   object:nil];
        [menuButton_ addItemWithTitle:@"Foo"];

        menuButton_.frame = NSMakeRect(frame.size.width - menuButton_.frame.size.width + 6,
                                       (frame.size.height - menuButton_.frame.size.height) / 2 + 1,
                                       menuButton_.frame.size.width,
                                       menuButton_.frame.size.height);
        [menuButton_ setAutoresizingMask:NSViewMinXMargin];
        [self addSubview:menuButton_];

        label_ = [[[NSTextField alloc] initWithFrame:NSMakeRect(x, 0, menuButton_.frame.origin.x - x - kMargin, frame.size.height)] autorelease];
        [label_ setStringValue:@""];
        [label_ setBezeled:NO];
        [label_ setDrawsBackground:NO];
        [label_ setEditable:NO];
        [label_ setSelectable:NO];
        [label_ setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
        [label_ sizeToFit];
        [label_ setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];

        NSRect lframe = label_.frame;
        lframe.origin.y += (frame.size.height - lframe.size.height) / 2 + kBottomMargin;
        lframe.size.width = menuButton_.frame.origin.x - x - kMargin;
        label_.frame = lframe;
        [self addSubview:label_];

        [self addCursorRect:NSMakeRect(0, 0, frame.size.width, frame.size.height)
                     cursor:[NSCursor arrowCursor]];

        [self updateTextColor];
    }
    return self;
}

- (void)setImagesForActionItem:(NSMenuItem *)item {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    CGFloat whiteLevel = 0;
    switch (preferredStyle) {
        case TAB_STYLE_LIGHT:
            whiteLevel = 0.45;
            break;
        case TAB_STYLE_DARK:
            whiteLevel = 0.45;
            break;
    }
    NSColor *color = [NSColor colorWithCalibratedWhite:whiteLevel alpha:1];
    NSImage *theImage = [[NSImage imageNamed:@"Hamburger"] imageWithColor:color];
    [item setImage:theImage];
}

- (void)dealloc {
    [title_ release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)popupWillOpen:(NSNotification *)notification
{
    if ([notification object] == menuButton_) {
        NSMenu *menu = [delegate_ menu];
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""] autorelease];
        [menu insertItem:item atIndex:0];
        [self setImagesForActionItem:item];
        [menuButton_ setMenu:menu];
    }
}

- (void)close:(id)sender
{
    [delegate_ close];
}

+ (NSColor *)colorByDimmingColor:(NSColor *)origColor byDimmingAmount:(double)dimmingAmount {
    NSColor *color = [origColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    double r = [color redComponent];
    double g = [color greenComponent];
    double b = [color blueComponent];
    double alpha = 1 - dimmingAmount;
    
    // Biases the input color by 1-alpha toward gray of (basis, basis, basis).
    double basis = 0.15;

    r = alpha * r + (1 - alpha) * basis;
    g = alpha * g + (1 - alpha) * basis;
    b = alpha * b + (1 - alpha) * basis;

    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1];
}

- (NSColor *)dimmedBackgroundColor {
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    CGFloat whiteLevel = 0;
    switch (preferredStyle) {
        case TAB_STYLE_LIGHT:
            if (![delegate_ sessionTitleViewIsFirstResponder]) {
                // Not selected
                whiteLevel = 0.58;
            } else {
                // selected
                whiteLevel = 0.70;
            }
            break;
        case TAB_STYLE_DARK:
            if (![delegate_ sessionTitleViewIsFirstResponder]) {
                // Not selected
                whiteLevel = 0.18;
            } else {
                // selected
                whiteLevel = 0.27;
            }
            break;
    }

    return [NSColor colorWithCalibratedWhite:whiteLevel alpha:1];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSColor *tabColor = delegate_.tabColor;
    if (tabColor) {
        if ([delegate_ sessionTitleViewIsFirstResponder]) {
            [tabColor set];
        } else {
            [[SessionTitleView colorByDimmingColor:tabColor byDimmingAmount:0.3] set];
        }
    } else {
        [[self dimmedBackgroundColor] set];
    }
    NSRectFill(dirtyRect);

    [[NSColor blackColor] set];
    NSRectFill(NSMakeRect(dirtyRect.origin.x, 0, dirtyRect.size.width, 1));

    [super drawRect:dirtyRect];
}

- (void)setTitle:(NSString *)title {
    [title_ autorelease];
    title_ = [title copy];
    [self updateTitle];
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
            prefix = [NSString stringForModifiersWithMask:NSCommandKeyMask];
            break;

        case kPreferencesModifierTagEitherOption:
            prefix = [NSString stringForModifiersWithMask:NSAlternateKeyMask];
            break;

        case kPreferencesModifierTagCommandAndOption:
            prefix = [NSString stringForModifiersWithMask:(NSCommandKeyMask | NSAlternateKeyMask)];
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
}

- (void)updateTextColor {
    CGFloat whiteLevel = 0;
    iTermPreferencesTabStyle preferredStyle = [iTermPreferences intForKey:kPreferenceKeyTabStyle];
    switch (preferredStyle) {
        case TAB_STYLE_LIGHT:
            if (dimmingAmount_ > 0) {
                // Not selected
                whiteLevel = 0.3;
            } else {
                // selected
                whiteLevel = 0.2;
            }
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
    }
    [label_ setTextColor:[NSColor colorWithCalibratedWhite:whiteLevel alpha:1]];
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    [delegate_ beginDrag];
}

- (void)setOrdinal:(int)ordinal {
    _ordinal = ordinal;
    [self updateTitle];
}

- (void)modifierShortcutDidChange:(NSNotification *)notification {
    [self updateTitle];
}

@end
