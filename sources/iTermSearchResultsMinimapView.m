//
//  iTermSearchResultsMinimapView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/14/20.
//

#import "iTermSearchResultsMinimapView.h"

#import "DebugLogging.h"
#import "iTermMalloc.h"
#import "iTermRateLimitedUpdate.h"

const CGFloat iTermSearchResultsMinimapViewItemHeight = 3;

typedef struct {
    CGColorRef outlineColor;
    CGColorRef fillColor;
    NSIndexSet *indexes;
} iTermMinimapSeries;

static NSString *const iTermBaseMinimapViewInvalidateNotification = @"iTermBaseMinimapViewInvalidateNotification";

@interface iTermBaseMinimapView()<CALayerDelegate>
@property (nonatomic, readonly) iTermRateLimitedUpdate *rateLimit;
@end

@implementation iTermBaseMinimapView {
    BOOL _invalid;
}

- (instancetype)init {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer = [[CALayer alloc] init];
        self.layer.opaque = NO;
        self.layer.backgroundColor = [[NSColor clearColor] CGColor];
        self.layer.opacity = 0.62;
        self.layer.delegate = self;
        self.hidden = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(performInvalidateIfNeeded)
                                                     name:iTermBaseMinimapViewInvalidateNotification
                                                   object:nil];
    }
    return self;
}

// Use a shared rate limit so all the minimaps update in sync.
- (iTermRateLimitedUpdate *)rateLimit {
    static iTermRateLimitedUpdate *rateLimit;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rateLimit = [[iTermRateLimitedUpdate alloc] initWithName:@"Minimap update"
                                                 minimumInterval:0.25];
    });
    return rateLimit;
}

- (void)setHasData:(BOOL)hasData {
    if (hasData) {
        DLog(@"Unhiding %@", self);
        self.hidden = NO;
        [self.layer setNeedsDisplay];
    } else if (!self.hidden) {
        DLog(@"Hiding %@", self);
        self.hidden = YES;
    }
}

#pragma mark - NSView

- (void)viewDidMoveToWindow {
    DLog(@"viewDidMoveToWindow:%@", self.window);
    if (self.window == nil) {
        return;
    }
    self.layer.contentsScale = MAX(1, self.window.backingScaleFactor);
    [self.layer setNeedsDisplay];
}

#pragma mark - Private

static inline void iTermSearchResultsMinimapViewDrawItem(CGFloat offset, CGFloat width, CGContextRef context) {
    const CGRect boundingRect = CGRectMake(0, offset, width, iTermSearchResultsMinimapViewItemHeight);
    const CGRect strokeRect = CGRectInset(boundingRect, 0.5, 0.5);
    CGContextStrokeRect(context, strokeRect);
    const CGRect fillRect = CGRectInset(boundingRect, 1, 1);
    CGContextFillRect(context, fillRect);
}

#pragma mark - CALayerDelegate

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
    DLog(@"drawLayer:%@", layer);
    for (NSInteger i = 0; i < self.numberOfSeries; i++) {
        iTermMinimapSeries series = [self seriesAtIndex:i];
        CGContextSetFillColorWithColor(ctx, series.fillColor);
        CGContextSetStrokeColorWithColor(ctx, series.outlineColor);
        NSIndexSet *indexes = series.indexes;
        const NSRange rangeOfVisibleLines = [self rangeOfVisibleLines];
        CGFloat numberOfLines = rangeOfVisibleLines.length;
        const CGFloat width = layer.bounds.size.width;
        const CGFloat layerHeight = layer.bounds.size.height;
        const CGFloat height = layerHeight - iTermSearchResultsMinimapViewItemHeight;
        __block CGFloat lastPointOffset = INFINITY;
        DLog(@"Draw %@ indexes in %@ lines with height %@ fill color %@",
             @([indexes countOfIndexesInRange:rangeOfVisibleLines]),
             @(rangeOfVisibleLines.length),
             @(height),
             series.fillColor);
        [indexes enumerateIndexesInRange:rangeOfVisibleLines options:0 usingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
            const CGFloat fraction = (CGFloat)(idx - rangeOfVisibleLines.location) / numberOfLines;
            const CGFloat flippedFraction = 1.0 - fraction;
            const CGFloat pointOffset = round(flippedFraction * height);
            if (pointOffset + 2 > lastPointOffset) {
                return;
            }
            iTermSearchResultsMinimapViewDrawItem(pointOffset, width, ctx);
            lastPointOffset = pointOffset;
        }];
    }
    [self didDraw];
}

#pragma mark - Subclassable

- (NSRange)rangeOfVisibleLines {
    return NSMakeRange(0, 0);
}

- (void)didDraw {
}

- (NSInteger)numberOfSeries {
    return 0;
}

- (iTermMinimapSeries)seriesAtIndex:(NSInteger)i {
    [self doesNotRecognizeSelector:_cmd];
    iTermMinimapSeries ignore = { 0 };
    return ignore;
}

- (void)invalidate {
    DLog(@"Invalidate");
    _invalid = YES;
    [self.rateLimit performRateLimitedSelector:@selector(postInvalidateNotification)
                                      onTarget:[iTermBaseMinimapView class]
                                    withObject:nil];
}

+ (void)postInvalidateNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermBaseMinimapViewInvalidateNotification
                                                        object:nil];
}

// All minimaps get this called when any minimaps anywhere was invalidated.
- (void)performInvalidateIfNeeded {
    if (!_invalid) {
        return;
    }
    _invalid = NO;
    [self performInvalidate];
}

// Subclasses to override
- (void)performInvalidate {
    [self doesNotRecognizeSelector:_cmd];
}

@end

@implementation iTermSearchResultsMinimapView {
    NSRange _rangeOfVisibleLines;
    iTermMinimapSeries _series;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _series.outlineColor = [[NSColor colorWithRed:0.5 green:0.5 blue:0 alpha:1] CGColor];
        CFRetain(_series.outlineColor);
        _series.fillColor = [[NSColor colorWithRed:1 green:1 blue:0 alpha:1] CGColor];
        CFRetain(_series.fillColor);

    }
    return self;
}

- (void)dealloc {
    CFRelease(_series.fillColor);
    CFRelease(_series.outlineColor);
}

- (void)performInvalidate {
    _series.indexes = [self.delegate searchResultsMinimapViewLocations:self];
    _rangeOfVisibleLines = [self.delegate searchResultsMinimapViewRangeOfVisibleLines:self];
    const NSUInteger count = [_series.indexes countOfIndexesInRange:_rangeOfVisibleLines];
    DLog(@"Count is %@", @(count));
    [self setHasData:count > 0];
}

- (NSIndexSet *)indexSet {
    return _series.indexes ?: [self.delegate searchResultsMinimapViewLocations:self];
}

- (void)didDraw {
    _series.indexes = nil;
}

- (NSInteger)numberOfSeries {
    return 1;
}

- (iTermMinimapSeries)seriesAtIndex:(NSInteger)i {
    if (!_series.indexes) {
        _series.indexes = [self.delegate searchResultsMinimapViewLocations:self];
    }
    return _series;
}

- (NSRange)rangeOfVisibleLines {
    return _rangeOfVisibleLines;
}

@end

@implementation iTermIncrementalMinimapView {
    NSMutableDictionary<NSNumber *, NSMutableIndexSet *> *_sets;
    NSRange _visibleLines;
    iTermMinimapSeries *_series;
    NSInteger _numberOfSeries;
}

- (instancetype)initWithColors:(NSArray<iTermTuple<NSColor *, NSColor *> *> *)colors {
    self = [super init];
    if (self) {
        _sets = [NSMutableDictionary dictionary];
        _series = iTermMalloc(sizeof(*_series) * colors.count);
        _numberOfSeries = colors.count;
        memset((void *)_series, 0, sizeof(*_series) * colors.count);
        [colors enumerateObjectsUsingBlock:^(iTermTuple<NSColor *,NSColor *> * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            _series[idx].outlineColor = [colors[idx].firstObject CGColor];
            CFRetain(_series[idx].outlineColor);
            _series[idx].fillColor = [colors[idx].secondObject CGColor];
            CFRetain(_series[idx].fillColor);
        }];
    }
    return self;
}

- (void)dealloc {
    free(_series);
}

- (void)updateHidden {
    [self invalidate];
}

- (void)performInvalidate {
    for (NSMutableIndexSet *set in _sets.allValues) {
        if (set.count > 0) {
            [self setHasData:YES];
            [self.layer setNeedsDisplay];
            return;
        }
    }
    [self setHasData:NO];
}

- (void)addObjectOfType:(NSInteger)objectType onLine:(NSInteger)line {
    [_sets[@(objectType)] addIndex:line];
    [self updateHidden];
}

- (void)removeObjectOfType:(NSInteger)objectType fromLine:(NSInteger)line {
    [_sets[@(objectType)] removeIndex:line];
    [self updateHidden];
}

- (void)setFirstVisibleLine:(NSInteger)firstVisibleLine
       numberOfVisibleLines:(NSInteger)numberOfVisibleLines {
    assert(firstVisibleLine >= 0);
    _visibleLines = NSMakeRange(firstVisibleLine, numberOfVisibleLines);
    [self updateHidden];
}

- (void)removeAllObjects {
    _sets = [NSMutableDictionary dictionary];
    [self updateHidden];
}

- (void)setLines:(NSMutableIndexSet *)lines forType:(NSInteger)type {
    _sets[@(type)] = lines;
    [self updateHidden];
}

- (NSInteger)numberOfSeries {
    return _numberOfSeries;
}

- (iTermMinimapSeries)seriesAtIndex:(NSInteger)i {
    _series[i].indexes = _sets[@(i)];
    return _series[i];
}

- (NSRange)rangeOfVisibleLines {
    return _visibleLines;
}

@end
