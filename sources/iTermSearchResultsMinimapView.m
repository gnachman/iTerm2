//
//  iTermSearchResultsMinimapView.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/14/20.
//

#import "iTermSearchResultsMinimapView.h"

#import "DebugLogging.h"
#import "iTermRateLimitedUpdate.h"

const CGFloat iTermSearchResultsMinimapViewItemHeight = 3;

@interface iTermSearchResultsMinimapView()<CALayerDelegate>
@end

@implementation iTermSearchResultsMinimapView {
    iTermRateLimitedUpdate *_rateLimit;
    CGColorRef _outlineColor;
    CGColorRef _fillColor;
    NSIndexSet *_indexes;
    NSRange _rangeOfVisibleLines;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.wantsLayer = YES;
        self.layer = [[CALayer alloc] init];
        self.layer.opaque = NO;
        self.layer.backgroundColor = [[NSColor clearColor] CGColor];
        self.layer.opacity = 0.5;
        self.layer.delegate = self;
        self.hidden = YES;
        _outlineColor = [[NSColor colorWithRed:0.5 green:0.5 blue:0 alpha:1] CGColor];
        CFRetain(_outlineColor);
        _fillColor = [[NSColor colorWithRed:1 green:1 blue:0 alpha:1] CGColor];
        CFRetain(_fillColor);
        _rateLimit = [[iTermRateLimitedUpdate alloc] init];
        _rateLimit.minimumInterval = 0.25;
    }
    return self;
}

- (void)dealloc {
    CFRelease(_outlineColor);
    CFRelease(_fillColor);
}

- (void)invalidate {
    DLog(@"Invalidate");
    [_rateLimit performRateLimitedSelector:@selector(maybeInvalidate) onTarget:self withObject:nil];
}

- (void)maybeInvalidate {
    _indexes = [self.delegate searchResultsMinimapViewLocations:self];
    _rangeOfVisibleLines = [self.delegate searchResultsMinimapViewRangeOfVisibleLines:self];
    const NSUInteger count = [_indexes countOfIndexesInRange:_rangeOfVisibleLines];
    if (count > 0) {
        DLog(@"Unhiding with %@ results", @(count));
        self.hidden = NO;
        [self.layer setNeedsDisplay];
    } else if (!self.hidden) {
        DLog(@"Hiding");
        self.hidden = YES;
    }
}

#pragma mark - NSView

- (void)viewDidMoveToWindow {
    if (self.window == nil) {
        return;
    }
    self.layer.contentsScale = MAX(1, self.window.backingScaleFactor);
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
    CGContextSetFillColorWithColor(ctx, _fillColor);
    CGContextSetStrokeColorWithColor(ctx, _outlineColor);
    NSIndexSet *indexes = _indexes ?: [self.delegate searchResultsMinimapViewLocations:self];
    const NSRange rangeOfVisibleLines = _indexes != nil ? _rangeOfVisibleLines : [self.delegate searchResultsMinimapViewRangeOfVisibleLines:self];
    CGFloat numberOfLines = rangeOfVisibleLines.length;
    _indexes = nil;
    const CGFloat width = layer.bounds.size.width;
    const CGFloat layerHeight = layer.bounds.size.height;
    const CGFloat height = layerHeight - iTermSearchResultsMinimapViewItemHeight;
    __block CGFloat lastPointOffset = INFINITY;
    DLog(@"Draw %@ indexes in %@ lines with height %@",
         @([indexes countOfIndexesInRange:rangeOfVisibleLines]),
         @(rangeOfVisibleLines.length),
         @(height));
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

@end
