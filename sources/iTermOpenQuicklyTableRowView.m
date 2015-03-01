#import "iTermOpenQuicklyTableRowView.h"

@implementation iTermOpenQuicklyTableRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    NSColor *darkBlue = [NSColor colorWithCalibratedRed:89.0/255.0
                                                  green:119.0/255.0
                                                   blue:199.0/255.0
                                                  alpha:1];
    NSColor *lightBlue = [NSColor colorWithCalibratedRed:90.0/255.0
                                                   green:124.0/255.0
                                                    blue:214.0/255.0
                                                   alpha:1];
    NSGradient *gradient = [[NSGradient alloc] initWithColors:@[ darkBlue, lightBlue ]];
    [gradient drawInRect:self.bounds angle:-90];
    [gradient release];
}

@end
