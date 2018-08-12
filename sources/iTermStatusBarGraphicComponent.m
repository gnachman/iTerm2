//
//  iTermStatusBarGraphicComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/20/18.
//

#import "iTermStatusBarGraphicComponent.h"

#import "iTermStatusBarViewController.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"

@implementation iTermStatusBarImageComponentView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _imageView = [[NSImageView alloc] initWithFrame:self.bounds];
        [self addSubview:_imageView];
        self.layer.backgroundColor = [[NSColor clearColor] CGColor];
    }
    return self;
}

- (NSColor *)backgroundColor {
    return [NSColor colorWithCGColor:self.layer.backgroundColor];
}

- (void)setBackgroundColor:(NSColor *)backgroundColor {
    self.layer.backgroundColor = backgroundColor.CGColor;
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    _imageView.frame = self.bounds;
}

@end

@implementation iTermStatusBarGraphicComponent {
    CGFloat _preferredWidth;
    CGFloat _renderedWidth;
    iTermStatusBarImageComponentView *_view;
}

- (NSColor *)defaultTextColor {
    NSColor *provided = [self.delegate statusBarComponentDefaultTextColor];
    if (provided) {
        return provided;
    } else {
        return [NSColor labelColor];
    }
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *backgroundColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Background Color"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarSharedBackgroundColorKey];

    return [@[ backgroundColorKnob ] arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
}

- (iTermStatusBarImageComponentView *)newView {
    return [[iTermStatusBarImageComponentView alloc] initWithFrame:NSZeroRect];
}

- (iTermStatusBarImageComponentView *)view {
    if (!_view) {
        _view = [self newView];
    }
    return _view;
}

- (NSColor *)backgroundColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    return [knobValues[iTermStatusBarSharedBackgroundColorKey] colorValue];
}

- (BOOL)shouldUpdateValue:(NSObject *)proposed {
    iTermStatusBarImageComponentView *view = self.view;
    NSObject *existing = self.model;
    const BOOL hasValue = existing != nil;
    const BOOL haveProposedvalue = proposed != nil;

    if (hasValue != haveProposedvalue) {
        return YES;
    }
    if (hasValue || haveProposedvalue) {
        return !([NSObject object:existing isEqualToObject:proposed] &&
                 [NSObject object:view.backgroundColor isEqualToObject:self.backgroundColor]);
    }

    return NO;
}

- (void)updateViewIfNeeded {
    CGFloat preferredWidth = 0;
    NSObject *newPreferred = [self widestModel:&preferredWidth];

    if (preferredWidth != _preferredWidth) {
        _preferredWidth = preferredWidth;
        [self.delegate statusBarComponentPreferredSizeDidChange:self];
    }

    NSObject *proposedForCurrentWidth = [self modelForCurrentWidth];

    const CGFloat viewWidth = self.view.frame.size.width;
    if ([self shouldUpdateValue:proposedForCurrentWidth] || viewWidth != _renderedWidth) {
        [self redraw];
        _renderedWidth = viewWidth;
    }

    _model = proposedForCurrentWidth;
    _preferredModel = newPreferred;
}

- (void)redraw {
    NSSize size = NSMakeSize(self.view.frame.size.width, iTermStatusBarHeight);
    if (size.width > 0) {
        NSImage *image = [NSImage imageOfSize:size drawBlock:^{
            [[NSColor clearColor] set];
            NSRect rect = NSMakeRect(0, 0, size.width, size.height);
            NSRectFill(rect);
            [self drawRect:rect];
        }];
        self.view.imageView.image = image;
    }
    NSRect frame = self.view.frame;
    frame.size = size;
    self.view.frame = frame;
}

- (NSObject *)modelForCurrentWidth {
    CGFloat currentWidth = self.view.frame.size.width;
    return [self modelForWidth:currentWidth width:nil];
}

- (NSObject *)widestModel:(out CGFloat *)width {
    return [self modelForWidth:INFINITY width:width];
}

- (CGFloat)statusBarComponentPreferredWidth {
    CGFloat width = 0;
    [self widestModel:&width];
    return width;
}

- (void)statusBarComponentSizeView:(NSView *)view toFitWidth:(CGFloat)width {
    self.view.frame = NSMakeRect(0, 0, width, iTermStatusBarHeight);
}

- (CGFloat)statusBarComponentMinimumWidth {
    return 1;
}

#pragma mark - iTermStatusBarComponent

- (NSView *)statusBarComponentCreateView {
    return self.view;
}

- (void)statusBarComponentUpdate {
    [self updateViewIfNeeded];
}

- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth {
    [self updateViewIfNeeded];
}

#pragma mark - Required overrides

- (NSObject *)modelForWidth:(CGFloat)maximumWidth width:(out CGFloat *)preferredWidth {
    [self doesNotRecognizeSelector:_cmd];
    return @{};
}

- (void)drawRect:(NSRect)rect {
    [self doesNotRecognizeSelector:_cmd];
}

@end

static const CGFloat iTermStatusBarSparklineBottomMargin = 2;

@implementation iTermStatusBarSparklinesComponent {
    NSInteger _currentCount;
}

- (NSColor *)lineColor {
    return [NSColor blackColor];
}

- (NSInteger)numberOfTimeSeries {
    return 1;
}

- (double)ceiling {
    return 1.0;
}

- (NSObject *)modelForWidth:(CGFloat)maximumWidth width:(out CGFloat *)preferredWidth {
    NSArray *model = self.values;
    if (model.count > maximumWidth) {
        model = [model subarrayWithRange:NSMakeRange(model.count - maximumWidth, maximumWidth)];
    }
    if (preferredWidth) {
        *preferredWidth = model.count;
    }
    return model;
}

- (void)drawRect:(NSRect)rect {
    NSArray<NSNumber *> *values = self.model;
    if (values.count == 0) {
        return;
    }

    // Draw baseline
    [[NSColor colorWithWhite:0.5 alpha:1] set];
    NSRectFill(NSMakeRect(NSMinX(rect), rect.origin.y + iTermStatusBarSparklineBottomMargin, NSWidth(rect), 1));

    if (self.numberOfTimeSeries == 1) {
        NSBezierPath *path = [self bezierPathWithValues:self.values inRect:rect];
        [self drawBezierPath:path forTimeSeries:0];
    } else {
        for (NSInteger i = 0; i < self.numberOfTimeSeries; i++) {
            NSArray<NSNumber *> *values = [self.values mapWithBlock:^id(id anObject) {
                return [[NSArray castFrom:anObject] objectAtIndex:i];
            }];
            NSBezierPath *path = [self bezierPathWithValues:values inRect:rect];
            [self drawBezierPath:path forTimeSeries:i];
        }
    }
}

- (void)drawBezierPath:(NSBezierPath *)bezierPath forTimeSeries:(NSInteger)timeSeriesIndex {
    if (self.numberOfTimeSeries == 1) {
        NSGradient *gradient = [[NSGradient alloc] initWithColors:@[ [NSColor blackColor],
                                                                     [NSColor colorWithRed:1 green:0.25 blue:0 alpha:1] ]];
        [gradient drawInBezierPath:bezierPath angle:90];
    } else if (self.numberOfTimeSeries == 2) {
        if (timeSeriesIndex == 0) {
            [[[NSColor blueColor] colorWithAlphaComponent:0.5] setFill];
        } else {
            [[[NSColor redColor] colorWithAlphaComponent:0.5] setFill];
        }
        [bezierPath fill];
    }
}

- (NSBezierPath *)bezierPathWithValues:(NSArray<NSNumber *> *)values
                                inRect:(NSRect)rect {
    const CGFloat numBars = values.count;
    const CGFloat barWidth = MIN(1, rect.size.width / numBars);

    CGFloat x = NSMaxX(rect) - values.count * barWidth;
    const CGFloat y = iTermStatusBarSparklineBottomMargin + rect.origin.y;
    NSBezierPath *path = [[NSBezierPath alloc] init];
    const CGFloat x0 = x;
    [path moveToPoint:NSMakePoint(x, y)];
    const double ceiling = MAX(1, self.ceiling);
    for (NSNumber *n in values) {
        const CGFloat height = n.doubleValue * (rect.size.height - iTermStatusBarSparklineBottomMargin * 2) / ceiling;
        [path lineToPoint:NSMakePoint(x, y + height)];
        x += barWidth;
    }
    [path lineToPoint:NSMakePoint(x, y)];
    [path lineToPoint:NSMakePoint(x0, y)];
    return path;
}

- (void)invalidate {
    [self updateViewIfNeeded];
}

@end
