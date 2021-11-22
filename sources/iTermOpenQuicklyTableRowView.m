#import "iTermOpenQuicklyTableRowView.h"

@implementation iTermOpenQuicklyTableRowView

- (BOOL)isEmphasized {
    return YES;
}

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    [super drawSelectionInRect:dirtyRect];
}

@end

@implementation iTermOpenQuicklyTableRowView_BigSur
- (BOOL)isEmphasized {
    return YES;
}
@end

