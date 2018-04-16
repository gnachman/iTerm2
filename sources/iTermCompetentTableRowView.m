//
//  iTermCompetentTableRowView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/18.
//

#import "iTermCompetentTableRowView.h"

@implementation iTermCompetentTableRowView

- (BOOL)it_dark {
    return [self.window.appearance.name isEqual:NSAppearanceNameVibrantDark];
}

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    if (self.selectionHighlightStyle != NSTableViewSelectionHighlightStyleNone) {
        if ([self it_dark]) {
            [[NSColor darkGrayColor] set];
            NSRectFill(dirtyRect);
            return;
        }
    }
    [super drawSelectionInRect:dirtyRect];
}

@end
