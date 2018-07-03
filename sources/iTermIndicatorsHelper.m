//
//  iTermIndicatorsHelper.m
//  iTerm2
//
//  Created by George Nachman on 11/23/14.
//
//

#import "iTermIndicatorsHelper.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"

static NSDictionary *gIndicatorImages;

NSString *const kiTermIndicatorBell = @"kiTermIndicatorBell";
NSString *const kiTermIndicatorWrapToTop = @"kiTermIndicatorWrapToTop";
NSString *const kiTermIndicatorWrapToBottom = @"kiTermIndicatorWrapToBottom";
NSString *const kItermIndicatorBroadcastInput = @"kItermIndicatorBroadcastInput";
NSString *const kiTermIndicatorMaximized = @"kiTermIndicatorMaximized";
NSString *const kiTermIndicatorCoprocess = @"kiTermIndicatorCoprocess";
NSString *const kiTermIndicatorAlert = @"kiTermIndicatorAlert";
NSString *const kiTermIndicatorAllOutputSuppressed = @"kiTermIndicatorAllOutputSuppressed";
NSString *const kiTermIndicatorZoomedIn = @"kiTermIndicatorZoomedIn";
NSString *const kiTermIndicatorCopyMode = @"kiTermIndicatorCopyMode";

static const NSTimeInterval kFullScreenFlashDuration = 0.3;
static const NSTimeInterval kFlashDuration = 0.3;
CGFloat kiTermIndicatorStandardHeight = 20;

@interface iTermIndicator : NSObject
@property(nonatomic, retain) NSImage *image;
@property(nonatomic, readonly) CGFloat alpha;

- (void)startFlash;
@end

@implementation iTermIndicator {
    NSTimeInterval _flashStartTime;
}

- (void)dealloc {
    [_image release];
    [super dealloc];
}

- (void)startFlash {
    _flashStartTime = [NSDate timeIntervalSinceReferenceDate];
}

- (CGFloat)alpha {
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - _flashStartTime;
    return MAX(0, 1.0 - elapsed / kFlashDuration);
}

@end

@implementation iTermIndicatorsHelper {
    // Maps an identifier to a NSNumber in [0, 1]
    NSMutableDictionary *_visibleIndicators;
    NSTimeInterval _fullScreenFlashStartTime;
    // Rate limits calls to setNeedsDisplay: to not be faster than drawRect can be called.
    BOOL _haveSetNeedsDisplay;
}

+ (NSDictionary *)indicatorImages {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gIndicatorImages = @{ kiTermIndicatorBell: [NSImage imageNamed:@"bell"],
                              kiTermIndicatorWrapToTop: [NSImage imageNamed:@"wrap_to_top"],
                              kiTermIndicatorWrapToBottom: [NSImage imageNamed:@"wrap_to_bottom"],
                              kItermIndicatorBroadcastInput: [NSImage imageNamed:@"BroadcastInput"],
                              kiTermIndicatorMaximized: [NSImage imageNamed:@"Maximized"],
                              kiTermIndicatorCoprocess: [NSImage imageNamed:@"Coprocess"],
                              kiTermIndicatorAlert: [NSImage imageNamed:@"Alert"],
                              kiTermIndicatorAllOutputSuppressed: [NSImage imageNamed:@"SuppressAllOutput"],
                              kiTermIndicatorZoomedIn: [NSImage imageNamed:@"Zoomed"],
                              kiTermIndicatorCopyMode: [NSImage imageNamed:@"CopyMode"] };
        [gIndicatorImages retain];
    });

    return gIndicatorImages;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _visibleIndicators = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_visibleIndicators release];
    [super dealloc];
}

- (void)setIndicator:(NSString *)identifier visible:(BOOL)visible {
    if (visible && !_visibleIndicators[identifier]) {
        iTermIndicator *indicator = [[[iTermIndicator alloc] init] autorelease];
        indicator.image = [[self class] indicatorImages][identifier];
        _visibleIndicators[identifier] = indicator;;
        [_delegate setNeedsDisplay:YES];
    } else if (!visible && _visibleIndicators[identifier]) {
        [_visibleIndicators removeObjectForKey:identifier];
        [_delegate setNeedsDisplay:YES];
    }
}

+ (NSArray *)flashingIndicatorIdentifiers {
    return @[ kiTermIndicatorBell,
              kiTermIndicatorWrapToTop,
              kiTermIndicatorWrapToBottom ];
}

+ (NSArray *)sequentiaIndicatorlIdentifiers {
    return @[ kiTermIndicatorMaximized,
              kItermIndicatorBroadcastInput,
              kiTermIndicatorCoprocess,
              kiTermIndicatorAlert,
              kiTermIndicatorAllOutputSuppressed,
              kiTermIndicatorZoomedIn,
              kiTermIndicatorCopyMode ];
}

- (void)enumerateTopRightIndicatorsInFrame:(NSRect)frame block:(void (^)(NSString *, NSImage *, NSRect))block {
    NSArray *sequentialIdentifiers = [iTermIndicatorsHelper sequentiaIndicatorlIdentifiers];
    const CGFloat vmargin = [iTermAdvancedSettingsModel terminalVMargin];
    const CGFloat kIndicatorTopMargin = MAX(5, vmargin);
    NSPoint point = NSMakePoint(frame.origin.x + frame.size.width,
                                frame.origin.y + kIndicatorTopMargin);
    for (NSString *identifier in sequentialIdentifiers) {
        iTermIndicator *indicator = _visibleIndicators[identifier];
        if (indicator) {
            static const CGFloat kInterIndicatorHorizontalMargin = 4;
            point.x -= indicator.image.size.width;
            point.x -= kInterIndicatorHorizontalMargin;
            NSImage *image = indicator.image;

            block(identifier, image, NSMakeRect(point.x, point.y, image.size.width, image.size.height));
            [image drawInRect:NSMakeRect(point.x, point.y, image.size.width, image.size.height)
                     fromRect:NSMakeRect(0, 0, image.size.width, image.size.height)
                    operation:NSCompositingOperationSourceOver
                     fraction:0.5
               respectFlipped:YES
                        hints:nil];
        }
    }
}

- (void)enumerateCenterIndicatorsInFrame:(NSRect)frame block:(void (^)(NSString *, NSImage *, NSRect, CGFloat))block {
    NSArray *centeredIdentifiers = [iTermIndicatorsHelper flashingIndicatorIdentifiers];
    for (NSString *identifier in centeredIdentifiers) {
        iTermIndicator *indicator = _visibleIndicators[identifier];
        CGFloat alpha = indicator.alpha;
        if (alpha > 0) {
            NSImage *image = indicator.image;
            NSSize size = [image size];
            NSRect destinationRect = NSMakeRect(frame.origin.x + frame.size.width / 2 - size.width / 2,
                                                frame.origin.y + frame.size.height / 2 - size.height / 2,
                                                size.width,
                                                size.height);
            block(identifier, image, destinationRect, alpha);
        }
    }
}

- (void)drawInFrame:(NSRect)frame {
    DLog(@"drawInFrame %@", NSStringFromRect(frame));

    // Draw top-right indicators.
    [self enumerateTopRightIndicatorsInFrame:frame block:^(NSString *identifier, NSImage *image, NSRect frame) {
        [image drawInRect:frame
                 fromRect:NSMakeRect(0, 0, image.size.width, image.size.height)
                operation:NSCompositingOperationSourceOver
                 fraction:0.5
           respectFlipped:YES
                    hints:nil];
    }];

    // Draw centered flashing indicators.
    [self enumerateCenterIndicatorsInFrame:frame block:^(NSString *identifier, NSImage *image, NSRect destinationRect, CGFloat alpha) {
        [image drawInRect:destinationRect
                 fromRect:NSMakeRect(0, 0, image.size.width, image.size.height)
                operation:NSCompositingOperationSourceOver
                 fraction:alpha
           respectFlipped:YES
                    hints:nil];
    }];

    // Draw full screen flash.
    if (_fullScreenAlpha > 0) {
        DLog(@"Drawing full screen flash overlay");
        [[[_delegate indicatorFullScreenFlashColor] colorWithAlphaComponent:_fullScreenAlpha] set];
        NSRectFillUsingOperation(frame, NSCompositingOperationSourceOver);
    } else if (_fullScreenFlashStartTime > 0 && _fullScreenAlpha == 0) {
        DLog(@"Not drawing full screen flash overlay");
    }
    [self didDraw];
}

- (void)didDraw {
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - _fullScreenFlashStartTime;
    DLog(@"elapsed=%@, fullScreenAlpha=%@", @(elapsed), @(_fullScreenAlpha));
    DLog(@"Set haveSetNeedsDisplay=NO");
    _haveSetNeedsDisplay = NO;
}

- (void)checkForFlashUpdate {
    DLog(@"Check for flash update. full screen flash start time is %@, haveSetNeedsDisplay=%@",
         @(_fullScreenFlashStartTime), @(_haveSetNeedsDisplay));
    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - _fullScreenFlashStartTime;
    if (_fullScreenFlashStartTime > 0 || [self haveFlashingIndicator]) {
        const CGFloat kMaxFullScreenFlashAlpha = 0.5;
        _fullScreenAlpha = MAX(0, 1.0 - elapsed / kFullScreenFlashDuration) * kMaxFullScreenFlashAlpha;
        DLog(@"Set fullScreenAlpha=%@", @(_fullScreenAlpha));
        if (!_haveSetNeedsDisplay) {
            DLog(@"Tell delegate %@ setNeedsDisplay", _delegate);
            [_delegate setNeedsDisplay:YES];
        }
        DLog(@"Set haveSetNeedsDisplay=YES");
        _haveSetNeedsDisplay = YES;

        // Ensure that the screen gets redrawn with alpha = 0.
        if (_fullScreenAlpha == 0) {
            DLog(@"Reset fullScreenFlashStartTime");
            _fullScreenFlashStartTime = 0;
        }
    }

    // Remove any indicators that became invisible since the last check.
    NSArray *visibleIdentifiers = [[_visibleIndicators.allKeys copy] autorelease];
    for (NSString *identifier in visibleIdentifiers) {
        if ([_visibleIndicators[identifier] alpha] == 0) {
            [_visibleIndicators removeObjectForKey:identifier];
        }
    }

    // Request another update if needed.
    if (_fullScreenFlashStartTime > 0 || [self haveFlashingIndicator]) {
        DLog(@"Schedule another call to checkForFlashUpdate");
        [self performSelector:@selector(checkForFlashUpdate) withObject:nil afterDelay:1 / 60.0];
    }
}

- (void)beginFlashingIndicator:(NSString *)identifier {
    assert([[iTermIndicatorsHelper flashingIndicatorIdentifiers] containsObject:identifier]);
    if (_visibleIndicators[identifier]) {
        return;
    }
    [self setIndicator:identifier visible:YES];
    [_visibleIndicators[identifier] startFlash];
    [self checkForFlashUpdate];
}

- (BOOL)haveFlashingIndicator {
    for (NSString *identifier in [iTermIndicatorsHelper flashingIndicatorIdentifiers]) {
        if (_visibleIndicators[identifier]) {
            return YES;
        }
    }
    return NO;
}

- (NSInteger)numberOfVisibleIndicators {
    return _visibleIndicators.count;
}

- (void)beginFlashingFullScreen {
    _fullScreenFlashStartTime = [NSDate timeIntervalSinceReferenceDate];
    [_delegate setNeedsDisplay:YES];
    [self checkForFlashUpdate];
}

@end
