//
//  iTermShortcutInputView.m
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import "iTermShortcutInputView.h"
#import "iTermKeyBindingMgr.h"
#import "NSStringITerm.h"

@interface iTermShortcutInputView()
@property(nonatomic, copy) NSString *hotkeyBeingRecorded;
@end

@implementation iTermShortcutInputView {
    NSButton *_clearButton;
    BOOL _acceptFirstResponder;
    BOOL _mouseDown;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self addClearButton];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self addClearButton];
    }
    return self;
}

- (void)dealloc {
    [_clearButton release];
    [_hotkeyBeingRecorded release];
    [super dealloc];
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    if (backgroundStyle == NSBackgroundStyleLight) {
        [_clearButton setImage:[NSImage imageNamed:@"Erase"]];
    } else {
        [_clearButton setImage:[NSImage imageNamed:@"EraseDarkBackground"]];
    }
    _backgroundStyle = backgroundStyle;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] set];
    NSRectFillUsingOperation(self.bounds, NSCompositeSourceOver);

    BOOL isFirstResponder = ([self.window firstResponder] == self);

    NSColor *outerLineColor;
    NSColor *innerLineColor;
    NSColor *textColor;
    NSColor *fieldColor;
    if (self.backgroundStyle == NSBackgroundStyleLight) {
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
    NSRectFillUsingOperation(frame, NSCompositeSourceOver);
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];

    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
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
        string = @"Recording";
    } else if (isFirstResponder) {
        string = self.hotkeyBeingRecorded;
    } else if (self.stringValue.length == 0) {
        string = self.isEnabled ? @"Click to Set" : @"";
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
    NSSize buttonSize = [[NSImage imageNamed:@"Erase"] size];

    _clearButton = [[NSButton alloc] initWithFrame:NSMakeRect(size.width - buttonSize.width - 2,
                                                              (size.height - buttonSize.height) / 2.0,
                                                              buttonSize.width,
                                                              buttonSize.height)];
    [_clearButton setTarget:self];
    [_clearButton setImage:[NSImage imageNamed:@"Erase"]];
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
    if (event.type == NSKeyDown) {
        self.hotkeyBeingRecorded = nil;
        self.shortcut = [iTermShortcut shortcutWithEvent:event];
        [_shortcutDelegate shortcutInputView:self didReceiveKeyPressEvent:event];
        [[self window] makeFirstResponder:[self window]];
    } else if (event.type == NSFlagsChanged) {
        self.hotkeyBeingRecorded = [NSString stringForModifiersWithMask:event.modifierFlags];
    }
    [self setNeedsDisplay:YES];
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
    [_stringValue autorelease];
    _stringValue = [stringValue copy];
    _clearButton.hidden = stringValue.length == 0;
    [self setNeedsDisplay:YES];
}

- (void)setShortcut:(iTermShortcut *)shortcut {
    [_shortcut autorelease];
    _shortcut = [shortcut retain];
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

@end
