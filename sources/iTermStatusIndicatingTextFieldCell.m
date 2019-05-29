//
//  iTermStatusIndicatingTextFieldCell.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/28/19.
//

#import "iTermStatusIndicatingTextFieldCell.h"

@implementation iTermStatusIndicatingTextFieldCell

- (NSRect)drawingRectForBounds:(NSRect)theRect {
    NSRect rect = [super drawingRectForBounds:theRect];
    rect.size.width -= 23;  // Width of warning icon
    return rect;
}

@end
