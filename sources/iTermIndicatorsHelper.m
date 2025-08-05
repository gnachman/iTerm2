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
NSString *const kiTermIndicatorAIChatLinked = @"kiTermIndicatorAIChatLinked";
NSString *const kiTermIndicatorAIChatStreaming = @"kiTermIndicatorAIChatStreaming";
NSString *const kiTermIndicatorChannel = @"kiTermIndicatorChannel";

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

+ (NSDictionary<NSString *, NSString *> *)indicatorSFSymbolMap {
    static NSDictionary<NSString *, NSString *> *symbolMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Handle version-specific SF Symbols
        NSString *maximizedSymbol = @"square.arrowtriangle.4.outward";
        NSString *debugLoggingSymbol = @"ladybug.circle";
        
        if (@available(macOS 14, *)) {
            // Use newer symbols on macOS 14+
            maximizedSymbol = @"square.arrowtriangle.4.outward";
            debugLoggingSymbol = @"ladybug.circle";
        } else {
            // Use older symbols on macOS < 14
            maximizedSymbol = @"arrow.down.left.and.arrow.up.right.rectangle";
            debugLoggingSymbol = @"ant.circle";
        }
        
        symbolMap = @{
            kiTermIndicatorBell: @"bell",
            kiTermIndicatorWrapToTop: @"arrow.counterclockwise",
            kiTermIndicatorWrapToBottom: @"arrow.clockwise",
            kItermIndicatorBroadcastInput: @"dot.radiowaves.right",
            kiTermIndicatorMaximized: maximizedSymbol,
            kiTermIndicatorCoprocess: @"rectangle.2.swap",
            kiTermIndicatorAlert: @"eye",
            kiTermIndicatorAllOutputSuppressed: @"stop.circle",
            kiTermIndicatorZoomedIn: @"magnifyingglass.circle",
            kiTermIndicatorCopyMode: @"doc.on.doc",
            kiTermIndicatorDebugLogging: debugLoggingSymbol,
            kiTermIndicatorFilter: @"line.3.horizontal.decrease.circle",
            kiTermIndicatorSecureKeyboardEntry_Forced: @"key",
            kiTermIndicatorSecureKeyboardEntry_User: @"key",
            kiTermIndicatorPinned: @"pin",
            kiTermIndicatorAIChatLinked: @"brain",
            kiTermIndicatorAIChatStreaming: @"dot.radiowaves.right",
            kiTermIndicatorChannel: @"rectangle.stack"
        };
    });
    return symbolMap;
}



+ (iTermTuple<NSImage *, NSImage *> *)imagePairWithSFSymbol:(NSString *)sfSymbol
                                                      large:(BOOL)large
                                                       size:(CGFloat)size
                                               backgroundless:(BOOL)backgroundless {
    return [iTermTuple tupleWithObject:[self imageWithSFSymbol:sfSymbol
                                                         large:large
                                                          size:size
                                                darkBackground:YES
                                                  backgroundless:backgroundless]
                             andObject:[self imageWithSFSymbol:sfSymbol
                                                         large:large
                                                          size:size
                                                darkBackground:NO
                                                  backgroundless:backgroundless]];
}


+ (NSImage *)imageWithSFSymbol:(NSString *)sfSymbol
                         large:(BOOL)large
                          size:(CGFloat)size
                darkBackground:(BOOL)darkBackground
                  backgroundless:(BOOL)backgroundless {
    // Since deployment target is macOS 12+, we always use SF Symbols
    // Create a symbol configuration for the desired size to avoid upscaling
    NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:size weight:NSFontWeightRegular scale:NSImageSymbolScaleMedium];
    NSImage *sfSymbolImage = [NSImage imageWithSystemSymbolName:sfSymbol accessibilityDescription:nil];
    if (@available(macOS 12.0, *)) {
        sfSymbolImage = [sfSymbolImage imageWithSymbolConfiguration:config];
    }
    
    if (backgroundless) {
        // For backgroundless mode, return the SF Symbol as a template image
        // so AppKit can color it appropriately for light/dark mode
        const NSSize imageSize = large ? NSMakeSize(64, 64) : NSMakeSize(size, size);
        
        // Resize the SF Symbol to the appropriate size while maintaining aspect ratio
        NSImage *resizedImage = [NSImage imageOfSize:imageSize drawBlock:^{
            NSSize sfSymbolSize = sfSymbolImage.size;
            
            // Calculate the scaling to fit the symbol within the imageSize while maintaining aspect ratio
            CGFloat scaleX = imageSize.width / sfSymbolSize.width;
            CGFloat scaleY = imageSize.height / sfSymbolSize.height;
            CGFloat scale = MIN(scaleX, scaleY);
            
            NSSize scaledSize = NSMakeSize(sfSymbolSize.width * scale, sfSymbolSize.height * scale);
            NSRect centeredRect = NSMakeRect((imageSize.width - scaledSize.width) / 2,
                                           (imageSize.height - scaledSize.height) / 2,
                                           scaledSize.width,
                                           scaledSize.height);
            
            [sfSymbolImage drawInRect:centeredRect
                             fromRect:NSZeroRect
                            operation:NSCompositingOperationSourceOver
                             fraction:1.0];
        }];
        
        resizedImage.template = YES;
        return resizedImage;
    }
    
    // For background mode, create composite image with background
    const NSSize imageSize = large ? NSMakeSize(64, 64) : NSMakeSize(size, size);
    const NSSize insetSize = large ? NSMakeSize(64, 64) : NSMakeSize(size - 4, size - 4);
    iTermCompositeImageBuilder *builder = [[iTermCompositeImageBuilder alloc] initWithSize:imageSize];

    NSImage *background = [NSImage imageOfSize:imageSize drawBlock:^{
        const CGFloat radiusFraction = 6;

        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(NSMakeRect(0,
                                                                                            0,
                                                                                            imageSize.width,
                                                                                            imageSize.height), 0.5, 0.5)
                                                             xRadius:imageSize.width / radiusFraction
                                                             yRadius:imageSize.height / radiusFraction];

        [darkBackground ? [NSColor blackColor] : [NSColor whiteColor] set];
        [path fill];

        [darkBackground ? [NSColor lightGrayColor] : [NSColor darkGrayColor] set];
        [path stroke];
    }];
    [builder addImage:background];

    // Add outline
    iTermTintedImage *tintedImage = [[iTermTintedImage alloc] initWithImage:sfSymbolImage];
    [builder addImage:[tintedImage imageTintedWithColor:darkBackground ? [NSColor whiteColor] : [NSColor blackColor]
                                                   size:[self fillingSizeFor:sfSymbolImage.size
                                                                     filling:insetSize]]];

    return [builder image];
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
        _backgroundlessMode = NO;
        _indicatorSize = 26.0; // Default size
    }
    return self;
}

- (void)setBackgroundlessMode:(BOOL)backgroundlessMode {
    if (_backgroundlessMode != backgroundlessMode) {
        _backgroundlessMode = backgroundlessMode;
        // Clear cache to force regeneration with new mode
        [_visibleIndicators removeAllObjects];
        [_delegate indicatorNeedsDisplay];
    }
}

- (void)setIndicatorSize:(CGFloat)indicatorSize {
    if (_indicatorSize != indicatorSize) {
        _indicatorSize = indicatorSize;
        // Clear cache to force regeneration with new size
        [_visibleIndicators removeAllObjects];
        [_delegate indicatorNeedsDisplay];
    }
}

- (void)setIndicator:(NSString *)identifier visible:(BOOL)visible darkBackground:(BOOL)darkBackground {
    if (visible && (!_visibleIndicators[identifier] || _visibleIndicators[identifier].dark != darkBackground)) {
        iTermIndicator *indicator = [[iTermIndicator alloc] init];
        
        // Check if this is a large indicator
        NSSet *largeIndicators = [NSSet setWithObjects:kiTermIndicatorWrapToTop, kiTermIndicatorWrapToBottom, nil];
        BOOL isLarge = [largeIndicators containsObject:identifier];
        
        if (_backgroundlessMode) {
            // Create backgroundless image directly with configurable size
            NSString *sfSymbol = [[[self class] indicatorSFSymbolMap] objectForKey:identifier];
            iTermTuple<NSImage *, NSImage *> *tuple = [[self class] imagePairWithSFSymbol:sfSymbol
                                                                                     large:isLarge
                                                                                      size:_indicatorSize
                                                                             backgroundless:YES];
            indicator.image = darkBackground ? tuple.firstObject : tuple.secondObject;
        } else {
            // Create images with current size (with background)
            NSString *sfSymbol = [[[self class] indicatorSFSymbolMap] objectForKey:identifier];
            iTermTuple<NSImage *, NSImage *> *tuple = [[self class] imagePairWithSFSymbol:sfSymbol
                                                                                     large:isLarge
                                                                                      size:_indicatorSize
                                                                             backgroundless:NO];
            indicator.image = darkBackground ? tuple.firstObject : tuple.secondObject;
        }
        assert(indicator.image);
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
              kiTermIndicatorPinned,
              kiTermIndicatorAIChatLinked,
              kiTermIndicatorAIChatStreaming,
              kiTermIndicatorChannel];
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

- (NSString *)helpTextForIndicatorWithName:(NSString *)name sessionID:(NSString *)sessionID {
    // NOTE: These messages are interpreted as markdown.
    NSDictionary<NSString *, NSString *> *messages = @{
        kItermIndicatorBroadcastInput: @"Keyboard input gets broadcast to other sessions.",
        kiTermIndicatorMaximized: @"This is a maximized split pane.",
        kiTermIndicatorCoprocess: @"A coprocess is running.",
        kiTermIndicatorAlert: @"Will alert on next mark.",
        kiTermIndicatorAllOutputSuppressed: @"All output is currently suppressed.",
        kiTermIndicatorZoomedIn: @"Zoomed in.",
        kiTermIndicatorFilter: @"Filtering.",
        kiTermIndicatorCopyMode: @"In copy mode. See [documentation](https://iterm2.com/documentation-copymode.html) for details.",
        kiTermIndicatorDebugLogging: @"Debug logging is enabled.",
        kiTermIndicatorSecureKeyboardEntry_User: @"Secure Keyboard Entry is enabled. Select iTerm2 > Secure Keyboard Entry to disable.\n[Disable this indicator.](iterm2:disable-secure-keyboard-entry-indicator)",
        kiTermIndicatorSecureKeyboardEntry_Forced: @"Secure Keyboard Entry is enabled because another app has turned it on.\n[Disable this indicator.](iterm2:disable-secure-keyboard-entry-indicator)",
        kiTermIndicatorPinned: @"This Hotkey Window is pinned.",
        kiTermIndicatorAIChatLinked: [NSString stringWithFormat:@"AI Chats can view or control this session.\n * [Unlink from AI Chat](iterm2:unlink-session-chat?s=%@&t=%@)\n * [Reveal AI Chat](iterm2:reveal-chat-for-session?s=%@&t=%@)", sessionID, [[NSWorkspace sharedWorkspace] it_newToken], sessionID, [[NSWorkspace sharedWorkspace] it_newToken]],
        kiTermIndicatorAIChatStreaming: [NSString stringWithFormat:@"Commands run in this session are automatically sent to an AI chat, along with their output. [Stop sending](iterm2:disable-streaming-session-chat?s=%@&t=%@)",
                                         sessionID, [[NSWorkspace sharedWorkspace] it_newToken]],
        kiTermIndicatorChannel: [NSString stringWithFormat:@"This command is running within another session.\n * [Return to Enclosing Session](iterm2:pop-channel?s=%@&t=%@)", sessionID, [[NSWorkspace sharedWorkspace] it_newToken]]
    };
    return messages[name];
}

- (NSString *)helpTextForIndicatorAt:(NSPoint)point sessionID:(NSString *)sessionID {
    __block NSString *result = nil;
    [self enumerateTopRightIndicatorsInFrame:_lastFrame andDraw:NO block:^(NSString *name, NSImage *image, NSRect frame, BOOL dark) {
        if (NSPointInRect(point, frame)) {
            result = [self helpTextForIndicatorWithName:name sessionID:sessionID];
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

- (NSString *)modernOutlineForIdentifier:(NSString *)identifier {
    return [[[self class] indicatorSFSymbolMap] objectForKey:identifier];
}

- (void)configurationDidComplete {
    if (self.configurationObserver) {
        self.configurationObserver();
    }
}
@end
