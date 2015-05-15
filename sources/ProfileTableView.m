//
//  ProfileTableView.m
//  iTerm
//
//  Created by George Nachman on 1/9/12.
//

#import "ProfileTableView.h"

@implementation ProfileTableView

- (void)setMenuHandler:(NSObject<ProfileTableMenuHandler> *)handler
{
    handler_ = handler;
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    if ([handler_ respondsToSelector:@selector(menuForEvent:)]) {
        return [handler_ menuForEvent:theEvent];
    }
    return nil;
}

// This is done to keep the framework from drawing the highlight and letting
// higlightSelectionInClipRect: do it instead.
- (NSCell *)preparedCellAtColumn:(NSInteger)column row:(NSInteger)row {
    NSCell *cell = [super preparedCellAtColumn:column row:row];
    if (cell.isHighlighted) {
        cell.backgroundStyle = NSBackgroundStyleDark;
        cell.highlighted = NO;
    }

    return cell;
}

- (void)highlightSelectionInClipRect:(NSRect)theClipRect {
    NSColor *color = [NSColor colorWithCalibratedRed:17/255.0 green:108/255.0 blue:214/255.0 alpha:1];

    [self.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [color set];
        NSRectFill([self rectOfRow:idx]);
    }];
}

@end
