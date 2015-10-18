#import "CPKAlphaSliderView.h"
#import "NSObject+CPK.h"

@interface CPKAlphaSliderView ()
@property(nonatomic) NSImageView *indicatorView;
@end

@implementation CPKAlphaSliderView

- (instancetype)initWithFrame:(NSRect)frame
                        alpha:(CGFloat)alpha
                        color:(NSColor *)color
                        block:(void (^)(CGFloat))block {
    self = [super initWithFrame:frame value:alpha block:block];
    if (self) {
        self.color = color;
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSBezierPath *path = [self boundingPath];
    [[NSColor colorWithPatternImage:[self cpk_imageNamed:@"SwatchCheckerboard"]] set];
    [[NSGraphicsContext currentContext] setPatternPhase:NSMakePoint(1, 2)];
    [path fill];

    [[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOver];

    // I don't know why NSGradient is misbehaving here. If I have it go from clearColor to
    // [self.color colorWithAlphaComponent:1] it looks all wrong.
    NSMutableArray *colors = [NSMutableArray array];
    int parts = 20;
    for (int i = 0; i <= parts; i++) {
        [colors addObject:[self.color colorWithAlphaComponent:i / (double)parts]];
    }
    NSGradient *gradient = [[NSGradient alloc] initWithColors:colors];
    [gradient drawInBezierPath:path angle:0];

    [[NSColor lightGrayColor] set];
    [path stroke];
}

@end
