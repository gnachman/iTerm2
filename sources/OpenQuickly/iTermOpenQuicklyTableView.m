#import "iTermOpenQuicklyTableView.h"

@implementation iTermOpenQuicklyTableView

- (BOOL)acceptsFirstResponder {
    return NO;
}

- (void)keyDown:(NSEvent *)event {
    NSString *const characters = event.characters;
    const unichar unicode = [characters length] > 0 ? [characters characterAtIndex:0] : 0;
    const NSEventModifierFlags mask = (NSEventModifierFlagCommand |
                                       NSEventModifierFlagOption |
                                       NSEventModifierFlagShift |
                                       NSEventModifierFlagControl);
    if ((event.modifierFlags & mask) == 0 && [self numberOfRows] > 0) {
        switch (unicode) {
            case NSDownArrowFunctionKey:
                if ([self selectedRow] + 1 == [self numberOfRows]) {
                    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                      byExtendingSelection:NO];
                    return;
                }
                break;
            case NSUpArrowFunctionKey:
                if ([self selectedRow] == 0) {
                    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:self.numberOfRows - 1]
                      byExtendingSelection:NO];
                    return;
                }
                break;
        }
    }
    [super keyDown:event];
}

@end
