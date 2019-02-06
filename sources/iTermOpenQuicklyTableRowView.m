#import "iTermOpenQuicklyTableRowView.h"

@implementation iTermOpenQuicklyTableRowView

- (BOOL)isEmphasized {
    if (@available(macOS 10.14, *)) {
        return YES;
    }
    return [super isEmphasized];
}

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    if (@available(macOS 10.14, *)) {
        [super drawSelectionInRect:dirtyRect];
        return;
    }
    NSColor *blue = [NSColor colorWithCalibratedRed:99.0 / 255.0
                                              green:142.0 / 255.0
                                               blue:248.0 / 255.0
                                              alpha:1];
    [blue set];
    NSRectFill(dirtyRect);
}

@end
