//
//  iTermFocusReportingTextField.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/22/18.
//

#import "iTermFocusReportingTextField.h"
#import "iTermSearchFieldCell.h"
#import "NSObject+iTerm.h"
#import "NSResponder+iTerm.h"
#import "PTYWindow.h"

@implementation iTermFocusReportingTextField

@dynamic delegate;

- (BOOL)becomeFirstResponder {
    BOOL result = [super becomeFirstResponder];
    if (result &&
        [self.delegate respondsToSelector:@selector(focusReportingTextFieldWillBecomeFirstResponder:)]) {
        [self.delegate focusReportingTextFieldWillBecomeFirstResponder:self];
    }
    return result;
}

@end

@interface iTermFocusReportingSearchField()<iTermSearchFieldControl>
@end

@implementation iTermTextView: NSTextView

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(performFindPanelAction:) &&
        menuItem.tag == NSFindPanelActionShowFindPanel) {
        return YES;
    }
    return [super validateMenuItem:menuItem];
}

- (void)performFindPanelAction:(id)sender {
    NSMenuItem *item = [NSMenuItem castFrom:sender];
    if (item.tag == NSFindPanelActionShowFindPanel) {
        NSResponder *responder = self.nextResponder;
        while (responder) {
            if ([responder respondsToSelector:_cmd]) {
                [(id)responder performFindPanelAction:sender];
                return;
            }
            responder = responder.nextResponder;
        }
    }
    [super performFindPanelAction:sender];
}

@end

@implementation iTermFocusReportingSearchField

@dynamic delegate;

- (id<PTYWindow>)enclosingTerminalWindow {
    id<PTYWindow> window = (id<PTYWindow>)self.window;
    if (![window conformsToProtocol:@protocol(PTYWindow)]) {
        return nil;
    }
    return window;
}

- (BOOL)enclosingTerminalWindowIsBecomingKey {
    id<PTYWindow> window = [self enclosingTerminalWindow];
    return window.it_becomingKey;
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent {
    return [super performKeyEquivalent:theEvent];
}

- (BOOL)isControlC:(NSEvent *)e {
    const NSUInteger flags = (e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
    const BOOL isControl = flags == NSEventModifierFlagControl;
    const BOOL isC = [e.charactersIgnoringModifiers isEqualToString:@"c"];
    return (isControl && isC);
}

- (void)doCommandBySelector:(SEL)selector {
    if ([NSStringFromSelector(selector) isEqualToString:@"noop:"] &&
        [self isControlC:[NSApp currentEvent]]) {
        id<PTYWindow> window = [self enclosingTerminalWindow];
        [[window ptyDelegate] ptyWindowMakeCurrentSessionFirstResponder];
    } else {
        [super doCommandBySelector:selector];
    }
}

- (BOOL)becomeFirstResponder {
    if ([self enclosingTerminalWindowIsBecomingKey]) {
        return NO;
    }
    const BOOL result = [super becomeFirstResponder];
    if (result &&
        [self.delegate respondsToSelector:@selector(focusReportingSearchFieldWillBecomeFirstResponder:)]) {
        [self.delegate focusReportingSearchFieldWillBecomeFirstResponder:self];
    }
    return result;
}

// In issue 9370, we see that PTYTextView gets the mouseUp if this is allowed to call -[super mouseUp:].
- (void)mouseUp:(NSEvent *)event {
}

- (BOOL)it_preferredFirstResponder {
    return YES;
}

#pragma mark - iTermSearchFieldControl

- (BOOL)searchFieldControlHasCounts:(iTermSearchFieldCell *)cell {
    return ([self.delegate respondsToSelector:@selector(focusReportingSearchFieldNumberOfResults:)] &&
            [self.delegate respondsToSelector:@selector(focusReportingSearchFieldCurrentIndex:)]);
}

- (iTermSearchFieldCounts)searchFieldControlGetCounts:(iTermSearchFieldCell *)cell {
    return (iTermSearchFieldCounts){
        .currentIndex = [self.delegate focusReportingSearchFieldCurrentIndex:self],
        .numberOfResults = [self.delegate focusReportingSearchFieldNumberOfResults:self]
    };
}

@end

@implementation ShiftEnterTextView

- (void)insertNewline:(id)sender {
    if (([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagShift) != 0) {
        self.shiftEnterPressed();
        return;
    }
    [super insertNewline:sender];
}

@end
