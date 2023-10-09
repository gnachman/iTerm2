//
//  iTermStatusBarSparklinesComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/9/20.
//

#import "iTermStatusBarSparklinesComponent.h"

#import "iTermAdvancedSettingsModel.h"
#import "NSArray+iTerm.h"
#import "NSBezierPath+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"

#import <QuartzCore/QuartzCore.h>

static const CGFloat iTermStatusBarSparklineBottomMargin = 2;

@implementation iTermStatusBarTimeSeries

- (instancetype)initWithValues:(NSArray<NSNumber *> *)values {
    self = [super init];
    if (self) {
        _values = [values copy];
    }
    return self;
}

- (iTermStatusBarTimeSeries *)timeSeriesWithLastN:(NSInteger)n {
    if (n >= self.values.count) {
        return self;
    }
    return [[iTermStatusBarTimeSeries alloc] initWithValues:[self.values it_arrayByKeepingLastN:n]];
}

- (NSInteger)count {
    return _values.count;
}

@end

@implementation iTermStatusBarTimeSeriesRendition

- (instancetype)initWithTimeSeries:(iTermStatusBarTimeSeries *)timeSeries color:(NSColor *)color {
    self = [super init];
    if (self) {
        _timeSeries = timeSeries;
        _color = color;
    }
    return self;
}

- (iTermStatusBarTimeSeriesRendition *)renditionKeepingLast:(NSInteger)n {
    if (n >= _timeSeries.values.count) {
        return self;
    }
    return [[iTermStatusBarTimeSeriesRendition alloc] initWithTimeSeries:[self.timeSeries timeSeriesWithLastN:n]
                                                                   color:self.color];
}

@end

@interface iTermStatusBarTimeSeriesLayer: CALayer
@property (nonatomic, strong) iTermStatusBarTimeSeriesRendition *rendition;
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly) NSInteger maximumNumberOfValues;
@property (nonatomic) double ceiling;

- (instancetype)initWithLabel:(NSString *)label
                    rendition:(iTermStatusBarTimeSeriesRendition *)rendition
        maximumNumberOfValues:(NSInteger)maximumNumberOfValues
                      ceiling:(double)ceiling NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithLayer:(id)layer NS_UNAVAILABLE;
@end

@implementation iTermStatusBarTimeSeriesLayer {
    NSArray<CAShapeLayer *> *_shapeLayers;
    // Grows from 0 up to self.width, then back to 0. Gives how much to shift the shapeLayers to
    // the left by.
    CGFloat _offset;
}

- (instancetype)initWithLabel:(NSString *)label
                    rendition:(iTermStatusBarTimeSeriesRendition *)rendition
        maximumNumberOfValues:(NSInteger)maximumNumberOfValues
                      ceiling:(double)ceiling {
    self = [super init];
    if (self) {
        _label = [label copy];
        _rendition = rendition;
        _maximumNumberOfValues = maximumNumberOfValues;
        _ceiling = ceiling;

        CAShapeLayer *sublayer1 = [[CAShapeLayer alloc] init];
        [self addSublayer:sublayer1];

        CAShapeLayer *sublayer2 = [[CAShapeLayer alloc] init];
        [self addSublayer:sublayer2];

        _shapeLayers = @[ sublayer1, sublayer2 ];
        [self initializeSublayerFramesAndPaths:YES];
        self.masksToBounds = YES;
    }
    return self;
}

- (void)setRendition:(iTermStatusBarTimeSeriesRendition *)rendition
             ceiling:(double)ceiling
            animated:(BOOL)animated {
    _rendition = rendition;
    _ceiling = ceiling;
    [self updateAnimated:animated];
}

- (void)resizeWithOldSuperlayerSize:(CGSize)size {
    [super resizeWithOldSuperlayerSize:size];
    [self initializeSublayerFramesAndPaths:YES];
    [self updateAnimated:NO];
}

- (void)initializeSublayerFramesAndPaths:(BOOL)andPaths {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self removeAnimationForKey:@"animateLeft"];
    CGRect frame = self.bounds;
    for (CALayer *layer in _shapeLayers) {
        [layer removeAnimationForKey:@"animateLeft"];
    }
    _shapeLayers[0].bounds = frame;
    _shapeLayers[0].position = CGPointZero;
    _shapeLayers[0].anchorPoint = CGPointMake(0, 0);
    if (andPaths) {
        _shapeLayers[0].path = [self desiredPathDroppingFirst:1];
    }
    _shapeLayers[0].strokeColor = self.rendition.color.CGColor;
    _shapeLayers[0].fillColor = [NSColor clearColor].CGColor;
    _shapeLayers[0].masksToBounds = YES;

    _shapeLayers[1].bounds = frame;
    _shapeLayers[1].position = CGPointMake(NSWidth(frame), 0);
    _shapeLayers[1].anchorPoint = CGPointMake(0, 0);
    if (andPaths) {
        _shapeLayers[1].path = [self desiredPathDroppingFirst:1];
    }
    _shapeLayers[1].strokeColor = self.rendition.color.CGColor;
    _shapeLayers[1].fillColor = [NSColor clearColor].CGColor;
    _shapeLayers[1].masksToBounds = YES;
    _offset = 0;

    [CATransaction commit];
}

- (CABasicAnimation *)animationToMoveLayer:(CALayer *)layer positionXBy:(CGFloat)dx {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"position"];
    CGPoint position = layer.position;
    animation.fromValue = [layer valueForKey:@"position"];
    position.x += dx;
    animation.toValue = (id)[NSValue valueWithPoint:position];
    animation.duration = 1.0;
    if (@available(macOS 12, *)) {
        if ([[NSProcessInfo processInfo] isLowPowerModeEnabled]) {
            animation.preferredFrameRateRange = CAFrameRateRangeMake(1, 1, 1);
        } else {
            animation.preferredFrameRateRange = CAFrameRateRangeMake(1, 60, 5);
        }
    }
    layer.position = position;
    [layer addAnimation:animation forKey:@"animateLeft"];
    return animation;
}

- (void)animateSublayersLeftBy:(CGFloat)dx {
    if ([self shouldAnimate]) {
        [self animationToMoveLayer:_shapeLayers[0] positionXBy:-dx];
        [self animationToMoveLayer:_shapeLayers[1] positionXBy:-dx];
    } else {
        [CATransaction setDisableActions:YES];
        for (size_t i = 0; i < 2; i++) {
            CGPoint p = _shapeLayers[i].position;
            p.x -= dx;
            _shapeLayers[i].position = p;
        }
        [CATransaction commit];
    }
}

- (BOOL)shouldAnimate {
    return [iTermAdvancedSettingsModel animateGraphStatusBarComponents];
}

- (CGPathRef)desiredPathDroppingFirst:(NSInteger)count {
    NSArray<NSNumber *> *values = [[self.rendition.timeSeries.values subarrayFromIndex:count] it_arrayByKeepingLastN:self.maximumNumberOfValues];
    return [self bezierPathWithValues:values
                               inRect:self.bounds].iterm_openCGPath;
}

- (CGPathRef)desiredPathFromLast:(NSInteger)count offset:(CGFloat)offset {
    NSArray *values = [self.rendition.timeSeries.values it_arrayByKeepingLastN:count];
    values = [self postPaddedValues:values toLength:self.maximumNumberOfValues];
    NSRect rect = self.bounds;
    rect.origin.x += offset;
    return [self bezierPathWithValues:values
                               inRect:rect].iterm_openCGPath;
}

- (void)updateAnimated:(BOOL)animated {
    if (animated) {
        // Can the layers be moved left?
        const CGFloat viewWidth = NSWidth(self.bounds);
        const CGFloat barWidth = [self barWidthForViewWidth:viewWidth];
        if (_offset + barWidth > viewWidth) {
            // layer 0 is completely off the left side.
            _offset = 0;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [self initializeSublayerFramesAndPaths:NO];
            _shapeLayers[0].path = _shapeLayers[1].path;
            _shapeLayers[1].path = [self desiredPathFromLast:_offset / barWidth + 2
                                                      offset:0];
            [CATransaction commit];
        } else {
            // Both layers are visible
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _shapeLayers[1].path = [self desiredPathFromLast:_offset / barWidth + 2
                                                      offset:0];
            [CATransaction commit];
        }
        _offset += barWidth;
        [self animateSublayersLeftBy:barWidth];
        return;
    }

    // Non-animated
    CGPathRef newPath = [self desiredPathDroppingFirst:1];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self initializeSublayerFramesAndPaths:YES];
    _shapeLayers[0].path = newPath;
    _shapeLayers[0].strokeColor = self.rendition.color.CGColor;
    _shapeLayers[0].fillColor = [NSColor clearColor].CGColor;
    _shapeLayers[1].path = newPath;
    _shapeLayers[1].strokeColor = self.rendition.color.CGColor;
    _shapeLayers[1].fillColor = [NSColor clearColor].CGColor;
    [CATransaction commit];
}

- (NSArray<NSNumber *> *)postPaddedValues:(NSArray<NSNumber *> *)values
                                 toLength:(NSInteger)length {
    if (values.count >= length) {
        return values;
    }
    NSMutableArray *result = [values mutableCopy];
    NSInteger count = length - values.count;
    NSNumber *last = values.lastObject ?: @0;
    for (NSInteger i = 0; i < count; i++) {
        [result addObject:last];
    }
    return result;
}

- (CGFloat)barWidthForViewWidth:(CGFloat)viewWidth {
    return viewWidth / (self.maximumNumberOfValues - 1);
}

- (NSBezierPath *)bezierPathWithValues:(NSArray<NSNumber *> *)originalValues
                                inRect:(NSRect)rect {
    if (self.maximumNumberOfValues == 0) {
        return nil;
    }
    const CGFloat barWidth = [self barWidthForViewWidth:rect.size.width];
    if (barWidth == 0) {
        return nil;
    }

    NSArray<NSNumber *> *values = [originalValues subarrayToIndex:self.maximumNumberOfValues];
    if (values.count == 0) {
        return [NSBezierPath bezierPath];
    }

    NSInteger segments = MAX(0, ((NSInteger)values.count) - 1);
    const CGFloat x0 = NSMaxX(rect) - segments * barWidth;
    const CGFloat y = iTermStatusBarSparklineBottomMargin + rect.origin.y + 0.5;
    NSBezierPath *path = [[NSBezierPath alloc] init];
    path.miterLimit = 1;
    const double ceiling = MAX(1, self.ceiling);
    int i = 0;
    for (NSNumber *n in values) {
        const CGFloat height = n.doubleValue * (rect.size.height - iTermStatusBarSparklineBottomMargin * 2) / ceiling;
        const CGFloat x = x0 + i * barWidth;
        const NSPoint point = NSMakePoint(x, y + height);
        if (i == 0) {
            [path moveToPoint:point];
        } else {
            [path lineToPoint:point];
        }
        i++;
    }
    [path lineToPoint:NSMakePoint(NSMaxX(rect) + 1, y)];
    return path;
}

@end

@implementation iTermStatusBarSparklinesModel

- (instancetype)initWithDictionary:(NSDictionary<NSString *,iTermStatusBarTimeSeriesRendition *> *)timeSeriesDict {
    self = [super init];
    if (self) {
        _timeSeriesDict = [timeSeriesDict copy];
    }
    return self;
}

- (iTermStatusBarSparklinesModel *)modelKeepingLast:(NSInteger)n {
    return [[iTermStatusBarSparklinesModel alloc] initWithDictionary:[_timeSeriesDict mapValuesWithBlock:^id(NSString *key, iTermStatusBarTimeSeriesRendition *object) {
        return [object renditionKeepingLast:n];
    }]];
}

- (NSInteger)count {
    return [[[_timeSeriesDict.allValues maxWithBlock:^NSComparisonResult(iTermStatusBarTimeSeriesRendition *obj1, iTermStatusBarTimeSeriesRendition *obj2) {
        return [@(obj1.timeSeries.count) compare:@(obj2.timeSeries.count)];
    }] timeSeries] count];
}

- (NSNumber *)maximumValue {
    if (_timeSeriesDict.count == 0) {
        return nil;
    }
    NSArray<NSNumber *> *allValues =
    [_timeSeriesDict.allValues flatMapWithBlock:^NSArray *(iTermStatusBarTimeSeriesRendition *rendition) {
        return rendition.timeSeries.values;
    }];
    return [allValues maxWithComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        return [a compare:b];
    }];
}

@end

@implementation iTermStatusBarSparklinesComponent {
    NSInteger _currentCount;
    NSDictionary<NSString *, iTermStatusBarTimeSeriesLayer *> *_layers;
    NSTextField *_leftTextView;
    NSTextField *_rightTextView;
    NSImageView *_leftImageView;
    NSImageView *_rightImageView;
    NSView *_baseline;
}

- (BOOL)shouldHaveTextColorKnob {
    return YES;
}

- (NSColor *)lineColor {
    return [NSColor blackColor];
}

- (double)ceiling {
    return self.sparklinesModel.maximumValue.doubleValue ?: 1.0;
}

- (NSInteger)maximumNumberOfValues {
    return 60;
}

- (iTermStatusBarSparklinesModel *)modelForWidth:(CGFloat)maximumWidth width:(out CGFloat *)preferredWidth {
    if (maximumWidth <= 0) {
        if (preferredWidth != nil) {
            *preferredWidth = 0;
        }
        return [[iTermStatusBarSparklinesModel alloc] initWithDictionary:@{}];
    }

    NSInteger width;
    if (maximumWidth > NSIntegerMax) {
        width = NSIntegerMax;
    } else {
        width = maximumWidth;
    }
    iTermStatusBarSparklinesModel *model = [self.sparklinesModel modelKeepingLast:width];
    if (preferredWidth) {
        *preferredWidth = [self maximumNumberOfValues];
    }
    return model;
}

- (void)redrawAnimated:(BOOL)animated {
    iTermStatusBarSparklinesModel *model = [self sparklinesModel];
    const double ceiling = self.ceiling;
    if (!_layers) {
        self.view.contentView = [[NSView alloc] initWithFrame:self.view.bounds];
        self.view.contentView.wantsLayer = YES;
        self.view.contentView.layer = [[CALayer alloc] init];
        self.view.contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.view addSubview:self.view.contentView];
        _layers = [model.timeSeriesDict mapValuesWithBlock:^id(NSString *key, iTermStatusBarTimeSeriesRendition *rendition) {
            iTermStatusBarTimeSeriesLayer *layer =
            [[iTermStatusBarTimeSeriesLayer alloc] initWithLabel:key
                                                       rendition:rendition
                                           maximumNumberOfValues:self.maximumNumberOfValues
                                                         ceiling:ceiling];
            layer.frame = self.view.contentView.layer.bounds;
            layer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [self.view.contentView.layer addSublayer:layer];
            return layer;
        }];
        [self updateAccessories];
        return;
    }
    [_layers enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, iTermStatusBarTimeSeriesLayer * _Nonnull layer, BOOL * _Nonnull stop) {
        layer.frame = self.view.contentView.layer.bounds;
        [layer setRendition:model.timeSeriesDict[key]
                    ceiling:ceiling
                   animated:animated];
    }];
    [self updateAccessories];
}

- (CGFloat)textOffset {
    NSFont *font = self.advancedConfiguration.font ?: [iTermStatusBarAdvancedConfiguration defaultFont];
    const CGFloat containerHeight = self.view.bounds.size.height;
    const CGFloat capHeight = font.capHeight;
    const CGFloat descender = font.descender - font.leading;  // negative (distance from bottom of bounding box to baseline)
    const CGFloat frameY = (containerHeight - self.view.frame.size.height) / 2;
    const CGFloat origin = containerHeight / 2.0 - frameY + descender - capHeight / 2.0;
    const CGFloat fudge = -1;
    return origin + fudge;
}

- (void)updateAccessories {
    if (!_baseline) {
        _baseline = [[NSView alloc] init];
        _baseline.wantsLayer = YES;
        _baseline.layer = [[CALayer alloc] init];
        [self.view addSubview:_baseline];
    }

    NSString *leftText = self.leftText;
    if (leftText.length && !_leftTextView) {
        _leftTextView = [NSTextField labelWithString:leftText];
        [self.view addSubview:_leftTextView];
    }
    _leftTextView.attributedStringValue = [[NSAttributedString alloc] initWithString:leftText
                                                                          attributes:self.leftAttributes ?: @{}];
    [_leftTextView sizeToFit];
    _leftTextView.frame = NSMakeRect(0,
                                     -self.textOffset,
                                     _leftTextView.frame.size.width,
                                     self.view.frame.size.height);
    NSString *rightText = self.rightText;
    if (rightText.length && !_rightTextView) {
        _rightTextView = [NSTextField labelWithString:rightText];
        [self.view addSubview:_rightTextView];
    }
    _rightTextView.attributedStringValue = [[NSAttributedString alloc] initWithString:rightText
                                                                          attributes:self.rightAttributes ?: @{}];
    [_rightTextView sizeToFit];
    _rightTextView.frame = NSMakeRect(NSWidth(self.view.frame) - self.rightSize.width,
                                      -self.textOffset,
                                      _rightTextView.frame.size.width,
                                      self.view.frame.size.height);

    NSImage *leftImage = self.leftImage;
    if (!leftImage) {
        _leftImageView.hidden = YES;
    } else {
        if (!_leftImageView) {
            leftImage.template = YES;
            _leftImageView = [NSImageView imageViewWithImage:leftImage];
            [self.view addSubview:_rightImageView];
        }
        _leftImageView.contentTintColor = [self statusBarTextColor];
        _leftImageView.hidden = NO;
        _leftImageView.image = leftImage;
    }
    [_leftImageView sizeToFit];
    CGFloat margin = (self.view.frame.size.height - leftImage.size.height) / 2.0;
    _leftImageView.frame = NSMakeRect(2,
                                      margin,
                                      leftImage.size.width,
                                      leftImage.size.height);

    NSImage *rightImage = self.rightImage;
    if (!rightImage) {
        _rightImageView.hidden = YES;
    } else {
        if (!_rightImageView) {
            rightImage.template = YES;
            _rightImageView = [NSImageView imageViewWithImage:rightImage];
            [self.view addSubview:_rightImageView];
        }
        _rightImageView.contentTintColor = [self statusBarTextColor];
        _rightImageView.hidden = NO;
        _rightImageView.image = rightImage;
    }
    margin = (self.view.frame.size.height - rightImage.size.height) / 2.0;
    _rightImageView.frame = NSMakeRect(NSMaxX(self.view.bounds) - rightImage.size.width - 2,
                                       margin,
                                       rightImage.size.width,
                                       rightImage.size.height);

    CGFloat leftInset = 0;
    if (self.leftSize.width > 0) {
        leftInset = 4 + self.leftSize.width;
    }
    CGFloat rightInset = 0;
    if (self.rightSize.width > 0) {
        rightInset = 4 + self.rightSize.width;
    }
    CGFloat width = self.view.frame.size.width - leftInset - rightInset;
    const NSRect newFrame = NSMakeRect(leftInset,
                                       2.5,
                                       width,
                                       self.view.frame.size.height - 5);
    self.view.contentView.frame = newFrame;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _baseline.layer.backgroundColor = [self statusBarTextColor].CGColor;
    _baseline.alphaValue = 0.5;
    _baseline.frame = NSMakeRect(NSMinX(self.view.contentView.frame),
                                 NSMinY(self.view.contentView.frame) + iTermStatusBarSparklineBottomMargin,
                                 NSWidth(self.view.contentView.frame),
                                 1);
    [CATransaction commit];
}

- (void)invalidate {
    [self updateViewIfNeededAnimated:YES];
}

@end
