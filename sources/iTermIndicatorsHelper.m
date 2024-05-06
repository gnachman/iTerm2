//
//  iTermIndicatorsHelper.m
//  iTerm2
//
//  Created by George Nachman on 11/23/14.
//
//

#import "iTermIndicatorsHelper.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPreferences.h"
#import "iTermTuple.h"
#import "DebugLogging.h"
#import "NSImage+iTerm.h"

static NSDictionary<NSString *, iTermTuple<NSImage *, NSImage *> *> *gIndicatorImagePairs;

NSString *const kiTermIndicatorBell = @"kiTermIndicatorBell";
NSString *const kiTermIndicatorWrapToTop = @"kiTermIndicatorWrapToTop";
NSString *const kiTermIndicatorWrapToBottom = @"kiTermIndicatorWrapToBottom";
NSString *const kItermIndicatorBroadcastInput = @"kItermIndicatorBroadcastInput";
NSString *const kiTermIndicatorMaximized = @"kiTermIndicatorMaximized";
NSString *const kiTermIndicatorCoprocess = @"kiTermIndicatorCoprocess";
NSString *const kiTermIndicatorAlert = @"kiTermIndicatorAlert";
NSString *const kiTermIndicatorAllOutputSuppressed = @"kiTermIndicatorAllOutputSuppressed";
NSString *const kiTermIndicatorZoomedIn = @"kiTermIndicatorZoomedIn";
NSString *const kiTermIndicatorFilter = @"kiTermIndicatorFilter";
NSString *const kiTermIndicatorCopyMode = @"kiTermIndicatorCopyMode";
NSString *const kiTermIndicatorDebugLogging = @"kiTermIndicatorDebugLogging";
NSString *const kiTermIndicatorSecureKeyboardEntry_Forced = @"kiTermIndicatorSecureKeyboardEntry_Forced";
NSString *const kiTermIndicatorSecureKeyboardEntry_User = @"kiTermIndicatorSecureKeyboardEntry_User";
NSString *const kiTermIndicatorPinned = @"kiTermIndicatorPinned";

static const NSTimeInterval kFullScreenFlashDuration = 0.3;
static const NSTimeInterval kFlashDuration = 0.3;
CGFloat kiTermIndicatorStandardHeight = 20;

@interface iTermIndicator : NSObject
@property(nonatomic, strong) NSImage *image;
@property(nonatomic, readonly) CGFloat alpha;
@property(nonatomic) BOOL dark;

- (void)startFlash;
@end

@implementation iTermIndicator {
    NSTimeInterval _flashStartTime;
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
    NSMutableDictionary<NSString *, iTermIndicator *> *_visibleIndicators;
    NSTimeInterval _fullScreenFlashStartTime;
    // Rate limits calls to setNeedsDisplay: to not be faster than drawRect can be called.
    BOOL _haveSetNeedsDisplay;
    NSRect _lastFrame;
}

+ (NSDictionary<NSString *, iTermTuple<NSImage *, NSImage *> *> *)indicatorImagePairs {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gIndicatorImagePairs = @{
            kiTermIndicatorBell: [self imagePairWithLegacyName:@"bell"
                                                 modernOutline:@"bell"
                                                         large:NO],
            kiTermIndicatorWrapToTop: [self imagePairWithLegacyName:@"wrap_to_top"
                                                      modernOutline:@"arrow.counterclockwise"
                                                              large:YES],
            kiTermIndicatorWrapToBottom: [self imagePairWithLegacyName:@"wrap_to_bottom"
                                                         modernOutline:@"arrow.clockwise"
                                                                 large:YES],
            kItermIndicatorBroadcastInput: [self imagePairWithLegacyName:@"BroadcastInput"
                                                           modernOutline:@"dot.radiowaves.right"
                                                                   large:NO],
            kiTermIndicatorMaximized: [self imagePairWithLegacyName:@"Maximized"
                                                      modernOutline:@"square.arrowtriangle.4.outward"
                                                              large:NO],
            kiTermIndicatorCoprocess: [self imagePairWithLegacyName:@"Coprocess"
                                                      modernOutline:@"rectangle.2.swap"
                                                              large:NO],
            kiTermIndicatorAlert: [self imagePairWithLegacyName:@"Alert"
                                                  modernOutline:@"eye"
                                                          large:NO],
            kiTermIndicatorAllOutputSuppressed: [self imagePairWithLegacyName:@"SuppressAllOutput"
                                                                modernOutline:@"stop.circle"
                                                                        large:NO],
            kiTermIndicatorZoomedIn: [self imagePairWithLegacyName:@"Zoomed"
                                                     modernOutline:@"magnifyingglass.circle"
                                                             large:NO],
            kiTermIndicatorCopyMode: [self imagePairWithLegacyName:@"CopyMode"
                                                     modernOutline:@"doc.on.doc"
                                                             large:NO],
            kiTermIndicatorDebugLogging: [self imagePairWithLegacyName:@"DebugLogging"
                                                         modernOutline:@"ladybug.circle"
                                                                 large:NO],
            kiTermIndicatorFilter: [self imagePairWithLegacyName:@"FilterIndicator"
                                                   modernOutline:@"line.3.horizontal.decrease.circle"
                                                           large:NO],
            kiTermIndicatorSecureKeyboardEntry_Forced: [self imagePairWithLegacyName:@"SecureKeyboardEntry"
                                                                       modernOutline:@"key"
                                                                               large:NO],
            kiTermIndicatorSecureKeyboardEntry_User: [self imagePairWithLegacyName:@"SecureKeyboardEntry"
                                                                     modernOutline:@"key"
                                                                             large:NO],
            kiTermIndicatorPinned: [self imagePairWithLegacyName:@"PinnedIndicator"
                                                   modernOutline:@"pin"
                                                           large:NO],
        };
    });

    return gIndicatorImagePairs;
}

+ (iTermTuple<NSImage *, NSImage *> *)imagePairWithLegacyName:(NSString *)legacyName
                                                modernOutline:(NSString *)outline
                                                        large:(BOOL)large {
    return [iTermTuple tupleWithObject:[self imageWithLegacyName:legacyName
                                                   modernOutline:outline
                                                           large:large
                                                  darkBackground:YES]
                             andObject:[self imageWithLegacyName:legacyName
                                                   modernOutline:outline
                                                           large:large
                                                  darkBackground:NO]];
}


+ (NSImage *)imageWithLegacyName:(NSString *)legacyName
                   modernOutline:(NSString *)outline
                           large:(BOOL)large
                  darkBackground:(BOOL)darkBackground {
    if (@available(macOS 11, *)) {
        const NSSize size = large ? NSMakeSize(64, 64) : NSMakeSize(26, 26);
        iTermCompositeImageBuilder *builder = [[iTermCompositeImageBuilder alloc] initWithSize:size];

        NSImage *final = [NSImage imageOfSize:size drawBlock:^{
            [darkBackground ? [NSColor blackColor] : [NSColor whiteColor] set];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, size.width, size.height) xRadius:size.width / 8 yRadius:size.height / 8] fill];
        }];
        [builder addImage:final];

        // Add outline
        NSImage *sfSymbol = [NSImage imageWithSystemSymbolName:outline accessibilityDescription:nil];
        if (sfSymbol) {
            iTermTintedImage *tintedImage = [[iTermTintedImage alloc] initWithImage:sfSymbol];
            [builder addImage:[tintedImage imageTintedWithColor:darkBackground ? [NSColor whiteColor] : [NSColor blackColor]
                                                           size:[self fillingSizeFor:sfSymbol.size
                                                                             filling:size]]];

            NSImage *composite = [builder image];
            return composite;
        }
    }
    return [NSImage it_imageNamed:legacyName forClass:self.class];
}

+ (NSSize)fillingSizeFor:(NSSize)innerSize
                 filling:(NSSize)outerSize {
    if (innerSize.width < 1 || innerSize.height < 1) {
        return NSMakeSize(0, 0);
    }
    const CGFloat outerAspectRatio = outerSize.width / outerSize.height;
    const CGFloat innerAspectRatio = innerSize.width / innerSize.height;
    if (outerAspectRatio < innerAspectRatio) {
        // Center vertically, span horizontally
        return NSMakeSize(outerSize.width, outerSize.width / innerAspectRatio);
    } else {
        // Center horizontally, span vertically
        return NSMakeSize(outerSize.height * innerAspectRatio, outerSize.height);
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _visibleIndicators = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)setIndicator:(NSString *)identifier visible:(BOOL)visible darkBackground:(BOOL)darkBackground {
    if (visible && (!_visibleIndicators[identifier] || _visibleIndicators[identifier].dark != darkBackground)) {
        iTermIndicator *indicator = [[iTermIndicator alloc] init];
        iTermTuple<NSImage *, NSImage *> *tuple = [[self class] indicatorImagePairs][identifier];
        indicator.image = darkBackground ? tuple.firstObject : tuple.secondObject;
        indicator.dark = darkBackground;
        _visibleIndicators[identifier] = indicator;
        [_delegate indicatorNeedsDisplay];
    } else if (!visible && _visibleIndicators[identifier]) {
        [_visibleIndicators removeObjectForKey:identifier];
        [_delegate indicatorNeedsDisplay];
    }
}

+ (NSArray *)flashingIndicatorIdentifiers {
    return @[ kiTermIndicatorBell,
              kiTermIndicatorWrapToTop,
              kiTermIndicatorWrapToBottom ];
}

+ (NSArray *)sequentialIndicatorIdentifiers {
    return @[ kiTermIndicatorMaximized,
              kItermIndicatorBroadcastInput,
              kiTermIndicatorCoprocess,
              kiTermIndicatorAlert,
              kiTermIndicatorAllOutputSuppressed,
              kiTermIndicatorZoomedIn,
              kiTermIndicatorFilter,
              kiTermIndicatorCopyMode,
              kiTermIndicatorDebugLogging,
              kiTermIndicatorSecureKeyboardEntry_Forced,
              kiTermIndicatorSecureKeyboardEntry_User,
              kiTermIndicatorPinned];
}

- (void)enumerateTopRightIndicatorsInFrame:(NSRect)frame andDraw:(BOOL)shouldDraw block:(void (^)(NSString *, NSImage *, NSRect, BOOL))block {
    if ([iTermAdvancedSettingsModel disableTopRightIndicators]) {
        return;
    }
    NSArray *sequentialIdentifiers = [iTermIndicatorsHelper sequentialIndicatorIdentifiers];
    const CGFloat vmargin = [iTermPreferences intForKey:kPreferenceKeyTopBottomMargins];
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

            block(identifier, image, NSMakeRect(point.x, point.y, image.size.width, image.size.height), indicator.dark);
            if (shouldDraw) {
                [image drawInRect:NSMakeRect(point.x, point.y, image.size.width, image.size.height)
                         fromRect:NSMakeRect(0, 0, image.size.width, image.size.height)
                        operation:NSCompositingOperationSourceOver
                         fraction:0.5
                   respectFlipped:YES
                            hints:nil];
            }
        }
    }
}

- (NSString *)helpTextForIndicatorWithName:(NSString *)name {
    NSDictionary<NSString *, NSString *> *messages = @{
        kItermIndicatorBroadcastInput: @"Keyboard input gets broadcast to other sessions.",
        kiTermIndicatorMaximized: @"This is a maximized split pane.",
        kiTermIndicatorCoprocess: @"A coprocess is running.",
        kiTermIndicatorAlert: @"Will alert on next mark.",
        kiTermIndicatorAllOutputSuppressed: @"All output is currently suppressed.",
        kiTermIndicatorZoomedIn: @"Zoomed in.",
        kiTermIndicatorFilter: @"Filtering.",
        kiTermIndicatorCopyMode: @"In copy mode.",
        kiTermIndicatorDebugLogging: @"Debug logging is enabled.",
        kiTermIndicatorSecureKeyboardEntry_User: @"Secure Keyboard Entry is enabled. Select iTerm2 > Secure Keyboard Entry to disable.",
        kiTermIndicatorSecureKeyboardEntry_Forced: @"Secure Keyboard Entry is enabled because another app has turned it on.",
        kiTermIndicatorPinned: @"This Hotkey Window is pinned."
    };
    return messages[name];
}

- (NSString *)helpTextForIndicatorAt:(NSPoint)point {
    __block NSString *result = nil;
    [self enumerateTopRightIndicatorsInFrame:_lastFrame andDraw:NO block:^(NSString *name, NSImage *image, NSRect frame, BOOL dark) {
        if (NSPointInRect(point, frame)) {
            result = [self helpTextForIndicatorWithName:name];
        }
    }];
    return result;
}

- (void)enumerateCenterIndicatorsInFrame:(NSRect)frame block:(void (^)(NSString *, NSImage *, NSRect, CGFloat, BOOL))block {
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
            block(identifier, image, destinationRect, alpha, indicator.dark);
        }
    }
}

- (void)drawInFrame:(NSRect)frame {
    DLog(@"drawInFrame %@", NSStringFromRect(frame));
    _lastFrame = frame;

    // Draw top-right indicators.
    [self enumerateTopRightIndicatorsInFrame:frame andDraw:YES block:^(NSString *identifier, NSImage *image, NSRect frame, BOOL dark) {
        [image drawInRect:frame
                 fromRect:NSMakeRect(0, 0, image.size.width, image.size.height)
                operation:NSCompositingOperationSourceOver
                 fraction:0.5
           respectFlipped:YES
                    hints:nil];
    }];

    // Draw centered flashing indicators.
    [self enumerateCenterIndicatorsInFrame:frame block:^(NSString *identifier, NSImage *image, NSRect destinationRect, CGFloat alpha, BOOL dark) {
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
        const CGFloat kMaxFullScreenFlashAlpha = [iTermAdvancedSettingsModel indicatorFlashInitialAlpha];
        _fullScreenAlpha = MAX(0, 1.0 - elapsed / kFullScreenFlashDuration) * kMaxFullScreenFlashAlpha;
        DLog(@"Set fullScreenAlpha=%@", @(_fullScreenAlpha));
        if (!_haveSetNeedsDisplay) {
            DLog(@"Tell delegate %@ setNeedsDisplay", _delegate);
            [_delegate indicatorNeedsDisplay];
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
    NSArray *visibleIdentifiers = [_visibleIndicators.allKeys copy];
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

- (void)beginFlashingIndicator:(NSString *)identifier darkBackground:(BOOL)darkBackground {
    assert([[iTermIndicatorsHelper flashingIndicatorIdentifiers] containsObject:identifier]);
    if (_visibleIndicators[identifier]) {
        return;
    }
    [self setIndicator:identifier visible:YES darkBackground:darkBackground];
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
    [_delegate indicatorNeedsDisplay];
    [self checkForFlashUpdate];
}

@end
