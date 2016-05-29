#import "iTermOpenQuicklyTableRowView.h"

@implementation iTermOpenQuicklyTableRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect {
  NSColor *blue = [NSColor colorWithCalibratedRed:99.0 / 255.0
                                            green:142.0 / 255.0
                                             blue:248.0 / 255.0
                                            alpha:1];
  [blue set];
  NSRectFill(dirtyRect);
}

@end
