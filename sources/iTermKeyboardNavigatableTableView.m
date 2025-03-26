//
//  iTermKeyboardNavigatableTableView.m
//  iTerm2
//
//  Created by George Nachman on 5/14/15.
//
//

#import "iTermKeyboardNavigatableTableView.h"
#import "NSObject+iTerm.h"

@implementation iTermKeyboardNavigatableTableView

- (void)keyDown:(NSEvent *)theEvent {
  [self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
}

// Our superclass responds to selectAll but it can't actually be used because these tables only
// allow selection of one row. If we pretend not to respond to it then iTermPopupWindowController
// gets a whack at it, and it can forward it to its owning window.
- (BOOL)respondsToSelector:(SEL)aSelector {
    if (aSelector == @selector(selectAll:)) {
        return NO;
    } else {
        return [super respondsToSelector:aSelector];
    }
}

@end

@implementation iTermAutomaticKeyboardNavigatableTableView

- (void)keyDown:(NSEvent *)theEvent {
  [self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
}

- (void)moveDown:(id)sender {
    NSInteger row = self.selectedRow;
    if (row == -1) {
        return;
    }
    if (row + 1 == self.numberOfRows) {
        return;
    }
    NSInteger newRow = row + 1;
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
    [self scrollRowToVisible:newRow];
}

- (void)moveUp:(id)sender {
    NSInteger row = self.selectedRow;
    if (row <= 0) {
        return;
    }
    NSInteger newRow = row - 1;
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
    [self scrollRowToVisible:newRow];
}

- (void)insertNewline:(id)sender {
    SEL doubleSel = [self doubleAction];
    if (!doubleSel) {
        return;
    }
    [self sendAction:doubleSel to:[self target]];
}

@end

@implementation iTermAutomaticKeyboardNavigatableOutlineView

- (void)keyDown:(NSEvent *)theEvent {
  [self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
}

- (void)moveDown:(id)sender {
    NSInteger row = self.selectedRow;
    if (row == -1) {
        return;
    }
    if (row + 1 == self.numberOfRows) {
        return;
    }
    NSInteger newRow = row + 1;
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
    [self scrollRowToVisible:newRow];
}

- (void)moveUp:(id)sender {
    NSInteger row = self.selectedRow;
    if (row <= 0) {
        return;
    }
    NSInteger newRow = row - 1;
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:newRow] byExtendingSelection:NO];
    [self scrollRowToVisible:newRow];
}

- (void)moveLeft:(id)sender {
    NSInteger row = self.selectedRow;
    if (row == -1) return;
    id item = [self itemAtRow:row];
    if ([self isExpandable:item] && [self isItemExpanded:item]) {
        [self collapseItem:item];
        [self scrollRowToVisible:row];
    }
}

- (void)moveRight:(id)sender {
    NSInteger row = self.selectedRow;
    if (row == -1) return;
    id item = [self itemAtRow:row];
    if ([self isExpandable:item] && ![self isItemExpanded:item]) {
        [self expandItem:item];
        [self scrollRowToVisible:row];
    }
}

- (void)moveWordRight:(id)sender {
    NSInteger row = self.selectedRow;
    if (row == -1) return;
    id item = [self itemAtRow:row];
    if ([self isExpandable:item] && ![self isItemExpanded:item]) {
        [self expandItem:item expandChildren:YES];
        [self scrollRowToVisible:row];
    }
}

- (void)moveWordLeft:(id)sender {
    NSInteger row = self.selectedRow;
    if (row == -1) return;
    id item = [self itemAtRow:row];
    if ([self isExpandable:item] && [self isItemExpanded:item]) {
        [self collapseItem:item collapseChildren:YES];
        [self scrollRowToVisible:row];
    }
}

- (void)insertNewline:(id)sender {
    SEL doubleSel = [self doubleAction];
    if (!doubleSel) {
        return;
    }
    [self sendAction:doubleSel to:[self target]];
}

@end
