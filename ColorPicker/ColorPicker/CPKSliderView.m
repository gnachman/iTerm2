#import "CPKSliderView.h"
#import "NSObject+CPK.h"

@interface CPKSliderView ()
@property(nonatomic, copy) void (^block)(CGFloat);
@property(nonatomic) NSImageView *indicatorView;
@end

@implementation CPKSliderView

- (instancetype)initWithFrame:(NSRect)frame
                        value:(CGFloat)value
                        block:(void (^)(CGFloat))block {
    self = [super initWithFrame:frame];
    if (self) {
        self.selectedValue = value;
        self.block = block;
        NSImage *image = [self cpk_imageNamed:@"SelectionIndicator"];
        self.indicatorView =
            [[NSImageView alloc] initWithFrame:NSMakeRect(0,
                                                          0,
                                                          image.size.width,
                                                          image.size.height)];
        self.indicatorView.image = image;
        self.indicatorView.frame = self.indicatorFrame;

        [self addSubview:self.indicatorView];
    }
    return self;
}

- (NSBezierPath *)boundingPath {
    NSRect rect = NSMakeRect(0.5,
                             0.5,
                             self.bounds.size.width - 1,
                             NSHeight(self.bounds) - 1);
    return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:2 yRadius:2];
}

- (BOOL)isFlipped {
    return YES;
}

- (NSRect)indicatorFrame {
    NSRect frame =
        NSMakeRect(self.selectedValue * NSWidth(self.bounds) -
                   NSWidth(self.indicatorView.bounds) / 2,
                   NSHeight(self.bounds) - NSHeight(self.indicatorView.bounds) - 1,
                   NSWidth(self.indicatorView.bounds),
                   NSHeight(self.indicatorView.bounds));
    frame.origin.x = MIN(MAX(0, NSMinX(frame)), NSWidth(self.bounds) - NSWidth(frame));
    frame.origin.y = MIN(MAX(0, NSMinY(frame)), NSHeight(self.bounds) - NSHeight(frame));
    return frame;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    self.indicatorView.frame = [self indicatorFrame];
}

- (void)mouseDown:(NSEvent *)theEvent {
    [self setValueFromPointInWindow:theEvent.locationInWindow];
}

- (void)mouseDragged:(NSEvent *)theEvent {
    [self setValueFromPointInWindow:theEvent.locationInWindow];
}

- (void)setSelectedValue:(CGFloat)selectedValue {
    _selectedValue = MIN(MAX(0, selectedValue), 1);
    self.indicatorView.frame = self.indicatorFrame;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsDisplay:YES];;
    });
}

- (void)setValueFromPointInWindow:(NSPoint)pointInWindow {
    CGFloat previousValue = _selectedValue;
    CGFloat fraction = [self convertPoint:pointInWindow fromView:nil].x / NSWidth(self.bounds);
    fraction = MAX(MIN(1, fraction), 0);
    self.selectedValue = fraction;
    if (_selectedValue == previousValue) {
        return;
    }
    self.block(_selectedValue);
}

@end
