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

- (NSColor *)textColor {
    NSDictionary *knobValues = self.configuration[iTermStatusBarComponentConfigurationKeyKnobValues];
    NSColor *configuredColor = [knobValues[iTermStatusBarSharedTextColorKey] colorValue];
    if (configuredColor) {
        return configuredColor;
    }

    NSColor *defaultTextColor = [self defaultTextColor];
    if (defaultTextColor) {
        return defaultTextColor;
    }

    NSColor *provided = [self.delegate statusBarComponentDefaultTextColor];
    if (provided) {
        return provided;
    } else {
        return [NSColor labelColor];
    }
}

- (NSColor *)statusBarTextColor {
    return [self textColor];
}

- (NSColor *)statusBarBackgroundColor {
    return [self backgroundColor];
}

- (NSArray<iTermStatusBarComponentKnob *> *)statusBarComponentKnobs {
    iTermStatusBarComponentKnob *backgroundColorKnob =
        [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Background Color:"
                                                          type:iTermStatusBarComponentKnobTypeColor
                                                   placeholder:nil
                                                  defaultValue:nil
                                                           key:iTermStatusBarSharedBackgroundColorKey];
    NSArray<iTermStatusBarComponentKnob *> *knobs = [@[ backgroundColorKnob ] arrayByAddingObjectsFromArray:[super statusBarComponentKnobs]];
    if (self.shouldHaveTextColorKnob) {
        iTermStatusBarComponentKnob *textColorKnob =
            [[iTermStatusBarComponentKnob alloc] initWithLabelText:@"Text Color:"
                                                              type:iTermStatusBarComponentKnobTypeColor
                                                       placeholder:nil
                                                      defaultValue:nil
                                                               key:iTermStatusBarSharedTextColorKey];
        knobs = [knobs arrayByAddingObject:textColorKnob];
    }
    return knobs;
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
    return [knobValues[iTermStatusBarSharedBackgroundColorKey] colorValue] ?: [super statusBarBackgroundColor];
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

- (NSView *)statusBarComponentView {
    return self.view;
}

- (void)statusBarComponentUpdate {
    [self updateViewIfNeeded];
}

- (void)statusBarComponentWidthDidChangeTo:(CGFloat)newWidth {
    [self updateViewIfNeeded];
}

- (void)statusBarDefaultTextColorDidChange {
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

- (BOOL)shouldHaveTextColorKnob {
    return YES;
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

- (NSInteger)maximumNumberOfValues {
    return 60;
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
    [[self statusBarTextColor] set];
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
        [[self statusBarTextColor] set];
        [bezierPath stroke];
    } else if (self.numberOfTimeSeries == 2) {
        if (timeSeriesIndex == 0) {
            [[[NSColor blueColor] colorWithAlphaComponent:1] set];
        } else {
            [[[NSColor redColor] colorWithAlphaComponent:1] set];
        }
        [bezierPath stroke];
    }
}

- (NSBezierPath *)bezierPathWithValues:(NSArray<NSNumber *> *)values
                                inRect:(NSRect)rect {
    const CGFloat barWidth = rect.size.width / self.maximumNumberOfValues;
    if (barWidth == 0) {
        return nil;
    }

    CGFloat x = NSMaxX(rect) - values.count * barWidth;
    const CGFloat y = iTermStatusBarSparklineBottomMargin + rect.origin.y + 0.5;
    NSBezierPath *path = [[NSBezierPath alloc] init];
    path.miterLimit = 1;
    [path moveToPoint:NSMakePoint(x, y)];
    const double ceiling = MAX(1, self.ceiling);
    for (NSNumber *n in values) {
        const CGFloat height = n.doubleValue * (rect.size.height - iTermStatusBarSparklineBottomMargin * 2) / ceiling;
        [path lineToPoint:NSMakePoint(x, y + height + 0.5)];
        x += barWidth;
    }
    [path lineToPoint:NSMakePoint(x, y + 0.5)];
    return path;
}

- (void)invalidate {
    [self updateViewIfNeeded];
}

@end
