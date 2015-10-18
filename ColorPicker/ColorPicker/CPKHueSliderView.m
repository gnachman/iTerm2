#import "CPKHueSliderView.h"
#import "NSColor+CPK.h"
#import "NSObject+CPK.h"

@interface CPKHueSliderView ()
@property(nonatomic) NSGradient *gradient;
@end

@implementation CPKHueSliderView

- (instancetype)initWithFrame:(NSRect)frame
                          hue:(CGFloat)hue
                        block:(void (^)(CGFloat))block {
    self = [super initWithFrame:frame value:hue block:block];
    if (self) {
        NSMutableArray *colors = [NSMutableArray array];
        int parts = 20;
        for (int i = 0; i <= parts; i++) {
            [colors addObject:[NSColor cpk_colorWithHue:(double)i / (double)parts
                                             saturation:1
                                             brightness:1
                                                  alpha:1]];
        }
        self.gradient = [[NSGradient alloc] initWithColors:colors];
    }
    return self;
}
 
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSBezierPath *path = [self boundingPath];
    [self.gradient drawInBezierPath:path angle:0];

    [[NSColor lightGrayColor] set];
    [path stroke];
}

@end
