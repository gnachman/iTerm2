//
//  iTermStatusIndicatingTextFieldCell.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/28/19.
//

#import "iTermStatusIndicatingTextFieldCell.h"

@implementation iTermStatusIndicatingTextFieldCell

- (instancetype)initTextCell:(NSString *)string {
    self = [super initTextCell:string];
    if (self) {
        _rightInset = 23;
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        _rightInset = 23;
    }
    return self;
}

- (NSRect)drawingRectForBounds:(NSRect)theRect {
    NSRect rect = [super drawingRectForBounds:theRect];
    rect.size.width -= _rightInset;  // Width of warning icon
    return rect;
}

@end
