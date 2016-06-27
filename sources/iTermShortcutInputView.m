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
@property(nonatomic, copy) NSString *newHotKey;
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
    [_newHotKey release];
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] set];
    NSRectFillUsingOperation(self.bounds, NSCompositeSourceOver);
    
    NSColor *outerLineColor;
    NSColor *innerLineColor;
    NSColor *textColor;
    if (self.isEnabled) {
        outerLineColor = [NSColor colorWithWhite:169.0/255.0 alpha:1];
        innerLineColor = [NSColor colorWithWhite:240.0/255.0 alpha:1];
        textColor = [NSColor controlTextColor];
    } else {
        outerLineColor = [NSColor colorWithWhite:207.0/255.0 alpha:1];
        innerLineColor = [NSColor colorWithWhite:242.0/255.0 alpha:1];
        textColor = [NSColor disabledControlTextColor];
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

    BOOL isFirstResponder = ([self.window firstResponder] == self);
    if (isFirstResponder) {
        [[NSColor selectedControlColor] set];
    } else {
        if (_mouseDown && self.enabled) {
            [[NSColor colorWithWhite:0.9 alpha:1] set];
        } else {
            [[NSColor controlBackgroundColor] set];
        }
    }
    frame.origin.x += 0.5;
    frame.origin.y += 0.5;
    frame.size.width -= 0.5;
    frame.size.height -= 0.5;
    NSRectFill(frame);
    [[NSGraphicsContext currentContext] setShouldAntialias:YES];
    
    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    NSDictionary<NSString *, id> *attributes = @{ NSForegroundColorAttributeName: textColor,
                                                  NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]],
                                                  NSParagraphStyleAttributeName: paragraphStyle };
    frame = self.bounds;
    frame.size.height -= 3;
    NSString *string;
    if (isFirstResponder && self.newHotKey.length == 0) {
        string = @"Recording";
    } else if (isFirstResponder) {
        string = self.newHotKey;
    } else if (self.stringValue.length == 0) {
        string = @"Click to Set";
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
        _acceptFirstResponder = YES;
        self.newHotKey = nil;
        [self.window makeFirstResponder:self];
        _acceptFirstResponder = NO;
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
    [_shortcutDelegate shortcutInputView:self didReceiveKeyPressEvent:nil];
}

- (void)handleShortcutEvent:(NSEvent *)event {
    if (event.type == NSKeyDown) {
        self.newHotKey = nil;
        [_shortcutDelegate shortcutInputView:self didReceiveKeyPressEvent:event];
        [[self window] makeFirstResponder:[self window]];
    } else if (event.type == NSFlagsChanged) {
        self.newHotKey = [NSString stringForModifiersWithMask:event.modifierFlags];
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

- (void)setKeyCode:(NSUInteger)code
         modifiers:(NSEventModifierFlags)modifiers
         character:(NSUInteger)character {
    NSString *identifier = [self identifierForCode:code modifiers:modifiers character:character];
    if (identifier) {
        self.stringValue = [iTermKeyBindingMgr formatKeyCombination:identifier];
    } else {
        self.stringValue = @"";
    }
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
