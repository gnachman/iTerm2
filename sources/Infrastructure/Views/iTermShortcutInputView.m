//
//  iTermShortcutInputView.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermShortcutInputView.h"

#import "NSEvent+iTerm.h"
#import "NSStringITerm.h"
#import "NSImage+iTerm.h"
#import "iTermKeyMappings.h"
#import "iTermWarning.h"

@interface iTermShortcutInputView()
@property(nonatomic, copy) NSString *hotkeyBeingRecorded;
@end

@implementation iTermShortcutInputView {
    NSButton *_clearButton;
    BOOL _acceptFirstResponder;
    BOOL _mouseDown;
    iTermShortcut *_savedShortcut;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _leaderAllowed = YES;
        [self addClearButton];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(leaderDidChange:)
                                                     name:iTermKeyMappingsLeaderDidChange
                                                   object:nil];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _leaderAllowed = YES;
        [self addClearButton];
    }
    return self;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    if (backgroundStyle == NSBackgroundStyleNormal) {
        [_clearButton setImage:[NSImage it_imageNamed:@"Erase" forClass:self.class]];
    } else {
        [_clearButton setImage:[NSImage it_imageNamed:@"EraseDarkBackground" forClass:self.class]];
    }
    _backgroundStyle = backgroundStyle;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] set];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);

    BOOL isFirstResponder = ([self.window firstResponder] == self);

    NSColor *outerLineColor;
    NSColor *innerLineColor;
    NSColor *textColor;
    NSColor *fieldColor;
    if (self.backgroundStyle == NSBackgroundStyleNormal) {
        if (self.isEnabled) {
            outerLineColor = [NSColor colorWithWhite:169.0/255.0 alpha:1];
            innerLineColor = [NSColor colorWithWhite:240.0/255.0 alpha:1];
            textColor = [NSColor controlTextColor];
        } else {
            outerLineColor = [NSColor colorWithWhite:207.0/255.0 alpha:1];
            innerLineColor = [NSColor colorWithWhite:242.0/255.0 alpha:1];
            textColor = [NSColor disabledControlTextColor];
        }
        if (isFirstResponder) {
            fieldColor = [NSColor selectedControlColor];
        } else {
            if (_mouseDown && self.enabled) {
                fieldColor = [NSColor colorWithWhite:0.9 alpha:1];
            } else {
                fieldColor = [NSColor controlBackgroundColor];
            }
        }
    } else {
        if (self.isEnabled) {
            outerLineColor = [NSColor colorWithWhite:169.0/255.0 alpha:1];
            innerLineColor = [NSColor colorWithWhite:240.0/255.0 alpha:1];
            textColor = [NSColor whiteColor];
        } else {
            outerLineColor = [NSColor colorWithWhite:207.0/255.0 alpha:1];
            innerLineColor = [NSColor colorWithWhite:242.0/255.0 alpha:1];
            textColor = [NSColor grayColor];
        }
        if (isFirstResponder) {
            fieldColor = [NSColor selectedControlColor];
            textColor = [NSColor controlTextColor];
        } else {
            if (_mouseDown && self.enabled) {
                fieldColor = [NSColor colorWithWhite:0.9 alpha:1];
                textColor = [NSColor controlTextColor];
            } else {
                fieldColor = [NSColor clearColor];
            }
        }
    }


    [[NSGraphicsContext currentContext] setShouldAntialias:NO];
    [outerLineColor set];
    NSRect frame = self.bounds;
    frame.size.width -= 1;
    frame.size.height -= 1;
    frame.origin.x += 0.5;
    frame.origin.y += 0.5;

    frame.size.width -= 0.5;
    frame.size.height -= 0.5;
    NSBezierPath *path = [NSBezierPath bezierPathWithRect:frame];
    [path setLineWidth:0.5];
    [path stroke];

    frame.origin.x += 0.5;
    frame.origin.y += 0.5;
    frame.size.width -= 1;
    frame.size.height -= 1;
    path = [NSBezierPath bezierPathWithRect:frame];
    [innerLineColor set];
    [path setLineWidth:0.5];
    [path stroke];

    [fieldColor set];
    frame.origin.x += 0.5;
    frame.origin.y += 0.5;
    frame.size.width -= 0.5;
    frame.size.height -= 0.5;
    NSRectFillUsingOperation(frame, NSCompositingOperationSourceOver);
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];

    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    NSDictionary<NSString *, id> *attributes = @{ NSForegroundColorAttributeName: textColor,
                                                  NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]],
                                                  NSParagraphStyleAttributeName: paragraphStyle };
    frame = self.bounds;
    frame.size.height -= 2;
    if (!_clearButton.hidden) {
        frame.size.width = NSMinX(_clearButton.frame) - 1;
    }
    NSString *string;
    if (isFirstResponder && self.hotkeyBeingRecorded.length == 0) {
        string = NSLocalizedStringWithDefaultValue(@"ShortcutInput.Recording", nil, [NSBundle mainBundle], @"Recording", @"Placeholder shown in a shortcut field while recording a shortcut");
    } else if (isFirstResponder) {
        string = self.hotkeyBeingRecorded;
    } else if (self.stringValue.length == 0) {
        string = self.isEnabled ? NSLocalizedStringWithDefaultValue(@"ShortcutInput.ClickToSet", nil, [NSBundle mainBundle], @"Click to Set", @"Placeholder in an empty shortcut field prompting the user to set a shortcut") : @"";
    } else {
        string = self.stringValue;
    }
    [string drawInRect:frame withAttributes:attributes];
}

- (BOOL)acceptsFirstResponder {
    return _acceptFirstResponder;
}

- (BOOL)becomeFirstResponder {
    [self setNeedsDisplay:YES];
    if (_acceptFirstResponder) {
        _savedShortcut = self.shortcut;
    }
    return _acceptFirstResponder;
}

- (BOOL)resignFirstResponder {
    [self setNeedsDisplay:YES];
    return YES;
}

- (void)mouseDown:(NSEvent *)theEvent {
    _mouseDown = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)theEvent {
    _mouseDown = NO;
    if (theEvent.clickCount == 1 && self.isEnabled) {
        if (self.window.firstResponder == self) {
            [self.window makeFirstResponder:self.window];
            self.hotkeyBeingRecorded = nil;
        } else {
            _acceptFirstResponder = YES;
            self.hotkeyBeingRecorded = nil;
            [self.window makeFirstResponder:self];
            _acceptFirstResponder = NO;
        }
    }
    [self setNeedsDisplay:YES];
}

- (void)addClearButton {
    NSSize size = self.bounds.size;
    NSSize buttonSize = [[NSImage it_imageNamed:@"Erase" forClass:self.class] size];

    _clearButton = [[NSButton alloc] initWithFrame:NSMakeRect(size.width - buttonSize.width - 2,
                                                              (size.height - buttonSize.height) / 2.0,
                                                              buttonSize.width,
                                                              buttonSize.height)];
    [_clearButton setTarget:self];
    [_clearButton setImage:[NSImage it_imageNamed:@"Erase" forClass:self.class]];
    [_clearButton setAction:@selector(clear:)];
    [_clearButton setBordered:NO];
    self.autoresizesSubviews = YES;
    _clearButton.autoresizingMask = (NSViewMinXMargin);
    [self addSubview:_clearButton];

    self.enabled = YES;
}

- (void)clear:(id)sender {
    self.shortcut = nil;
    self.stringValue = @"";
    [_shortcutDelegate shortcutInputView:self didReceiveKeyPressEvent:nil];
}

- (void)handleShortcutEvent:(NSEvent *)event {
    if (event.type == NSEventTypeKeyDown) {
        iTermShortcut *shortcut = [iTermShortcut shortcutWithEvent:event
                                                     leaderAllowed:_leaderAllowed];
        if (self.purpose != iTermShortcutInputViewPurposeNone && shortcut.smellsAccidental) {
            // Build a complete localized sentence per purpose rather than injecting a translated
            // clause into a frame, whose word order and grammar differ by language.
            NSString *confirmTitle = nil;
            switch (self.purpose) {
                case iTermShortcutInputViewPurposeNone:
                    return;
                case iTermShortcutInputViewPurposeHotkey:
                    confirmTitle = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ShortcutInput.AccidentalConfirmHotkey", nil, [NSBundle mainBundle], @"Are you sure you want to use “%@” as a hotkey? This looks like a commonly used keystroke.", @"Confirmation when a chosen hotkey looks like a common keystroke; the placeholder is the shortcut"), shortcut.stringValue];
                    break;
                case iTermShortcutInputViewPurposeLeader:
                    confirmTitle = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ShortcutInput.AccidentalConfirmLeader", nil, [NSBundle mainBundle], @"Are you sure you want to use “%@” as the leader? This looks like a commonly used keystroke.", @"Confirmation when a chosen leader key looks like a common keystroke; the placeholder is the shortcut"), shortcut.stringValue];
                    break;
                case iTermShortcutInputViewPurposeOpenQuicklyHotkey:
                    confirmTitle = [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"ShortcutInput.AccidentalConfirmOpenQuickly", nil, [NSBundle mainBundle], @"Are you sure you want to use “%@” as the Open Quickly hotkey? This looks like a commonly used keystroke.", @"Confirmation when a chosen Open Quickly hotkey looks like a common keystroke; the placeholder is the shortcut"), shortcut.stringValue];
                    break;
            }
            const iTermWarningSelection selection =
            [iTermWarning showWarningWithTitle:confirmTitle
                                       actions:@[ iTermLocalizedOK(), iTermLocalizedCancel() ]
                                     accessory:nil
                                    identifier:nil
                                   silenceable:kiTermWarningTypePersistent
                                       heading:NSLocalizedStringWithDefaultValue(@"ShortcutInput.ConfirmHeading", nil, [NSBundle mainBundle], @"Confirm Shortcut", @"Heading of the confirmation shown when a chosen shortcut looks accidental")
                                        window:self.window];
            if (selection == kiTermWarningSelection1) {
                [self revert];
                self.hotkeyBeingRecorded = nil;
                [[self window] makeFirstResponder:[self window]];
                [self setNeedsDisplay:YES];
                return;
            }
        }
        self.hotkeyBeingRecorded = nil;
        self.shortcut = shortcut;
        [_shortcutDelegate shortcutInputView:self didReceiveKeyPressEvent:event];
        _savedShortcut = nil;
        [[self window] makeFirstResponder:[self window]];
    } else if (event.type == NSEventTypeFlagsChanged) {
        self.hotkeyBeingRecorded = [NSString stringForModifiersWithMask:event.it_modifierFlags];
    }
    [self setNeedsDisplay:YES];
}

- (void)revert {
    self.shortcut = _savedShortcut;
}

- (void)setEnabled:(BOOL)flag {
    _enabled = flag;
    _clearButton.enabled = flag;
    if (!flag && self.window.firstResponder == self) {
        [self.window makeFirstResponder:self.window];
    }
    [self setNeedsDisplay:YES];
}

- (void)setStringValue:(NSString *)stringValue {
    _stringValue = [stringValue copy];
    _clearButton.hidden = stringValue.length == 0;
    [self setNeedsDisplay:YES];
}

- (void)setShortcut:(iTermShortcut *)shortcut {
    _shortcut = shortcut;
    self.stringValue = self.shortcut.stringValue;
}

- (NSString *)identifierForCode:(NSUInteger)code
                      modifiers:(NSEventModifierFlags)modifiers
                      character:(NSUInteger)character {
    if (code || character) {
        return [NSString stringWithFormat:@"0x%x-0x%x", (int)character, (int)modifiers];
    } else {
        return nil;
    }
}

- (void)leaderDidChange:(NSNotification *)notification {
    self.stringValue = self.shortcut.stringValue;
}

@end
