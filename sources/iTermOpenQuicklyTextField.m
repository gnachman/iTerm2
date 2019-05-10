#import "iTermOpenQuicklyTextField.h"

#import "NSEvent+iTerm.h"
#import "NSTextField+iTerm.h"

@implementation iTermOpenQuicklyTextField

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent {
    unsigned int modflag;
    unsigned short keycode;
    modflag = [theEvent it_modifierFlags];
    keycode = [theEvent keyCode];

    if (![self textFieldIsFirstResponder]) {
        return NO;
    }

    const int mask = NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand;
    // TODO(georgen): Not getting normal keycodes here, but 125 and 126 are up and down arrows.
    // This is a pretty ugly hack. Also, calling keyDown from here is probably not cool.
    BOOL handled = NO;
    if (_arrowHandler && !(mask & modflag) && (keycode == 125 || keycode == 126)) {
        static BOOL running;
        if (!running) {
            running = YES;
            [_arrowHandler keyDown:theEvent];
            running = NO;
        }
        handled = YES;
    } else {
        handled = [super performKeyEquivalent:theEvent];
    }
    return handled;
}

@end
