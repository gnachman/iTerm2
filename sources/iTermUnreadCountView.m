//
//  iTermUnreadCountView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/6/19.
//

#import "iTermUnreadCountView.h"
#import "NSBezierPath+iTerm.h"
#import "NSTextField+iTerm.h"
#import <QuartzCore/QuartzCore.h>

@implementation iTermUnreadCountView {
    NSView *_bubbleView;
    NSTextField *_textField;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = NO;
    }
    return self;
}

- (BOOL)wantsDefaultClipping {
    return NO;
}

- (void)setCount:(NSInteger)count {
    assert(count >= 0);
    if (count == _count) {
        return;
    }
    _count = count;
    self.hidden = (count == 0);
    if (count == 0) {
        return;
    }
    [_bubbleView removeFromSuperview];
    [_textField removeFromSuperview];

    _textField = [NSTextField newLabelStyledTextField];
    _textField.font = [NSFont systemFontOfSize:11];
    _textField.textColor = [NSColor whiteColor];
    _textField.drawsBackground = NO;
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    _textField.stringValue = [formatter stringFromNumber:@(count)];
    [_textField sizeToFit];

    _bubbleView = [self newBubbleViewWithTextField:_textField];
    [self addSubview:_bubbleView];

    NSRect frame = self.frame;
    frame.size = _bubbleView.frame.size;
    self.frame = frame;
}

- (NSView *)newBubbleViewWithTextField:(NSTextField *)textField {
    const CGFloat topBottomMargin = 2;
    const CGFloat height = NSHeight(textField.frame) + topBottomMargin;
    const CGFloat sideMargin = 2;
    const CGFloat width = MAX(height, NSWidth(textField.frame) + sideMargin);
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0,
                                                            0,
                                                            width,
                                                            height)];
    view.wantsLayer = YES;

    CAShapeLayer *shapeLayer = [[CAShapeLayer alloc] init];
    const CGFloat radius = height / 2.0;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:view.bounds
                                                         xRadius:radius
                                                         yRadius:radius];
    shapeLayer.path = [path iterm_CGPath];
    shapeLayer.fillColor = [[NSColor colorWithSRGBRed:0.976 green:0.243 blue:0.223 alpha:0.92] CGColor];
    shapeLayer.shadowRadius = 1;
    shapeLayer.shadowColor = [[NSColor blackColor] CGColor];
    shapeLayer.shadowOpacity = 0.25;
    shapeLayer.shadowOffset = CGSizeZero;
    view.layer = shapeLayer;
    shapeLayer.masksToBounds = NO;

    [view addSubview:textField];
    textField.frame = NSMakeRect((NSWidth(view.frame) - NSWidth(textField.frame)) / 2.0,
                                 (NSHeight(view.frame) - NSHeight(textField.frame)) / 2.0,
                                 NSWidth(textField.frame),
                                 NSHeight(textField.frame));
    return view;
}

@end
