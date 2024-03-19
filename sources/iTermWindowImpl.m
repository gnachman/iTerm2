#ifndef THE_CLASS
#define THE_CLASS ThisIsJustHereToMakeXCodeHappy
@interface THE_CLASS : NSWindow
@end
#endif

@class iTermThemeFrame;
@class NSTitlebarContainerView;

NS_ASSUME_NONNULL_BEGIN

@implementation THE_CLASS
{
    double blurRadius_;
    // Hack for a 10.16 issue. Once you set blur from >0 to 0 then it is broken and will never work again.
    int _minBlur;
    
    // If set, then windowWillShowInitial is not invoked.
    BOOL _layoutDone;

    // True while in -[NSWindow toggleFullScreen:].
    BOOL isTogglingLionFullScreen_;
    NSObject *restoreState_;
    NSInteger _uniqueNumber;

    // Time the occlusion cache was last updated
    NSTimeInterval _totalOcclusionCacheTime;

    // Cached value of the percentage of this window that is occluded by other nonpanel windows in this app.
    double _cachedTotalOcclusion;

    NSTimeInterval _timeOfLastWindowTitleChange;
    BOOL _needsInvalidateShadow;
    BOOL _it_restorableStateInvalid;
    BOOL _validatingMenuItems;
    BOOL _it_preventFrameChange;
#if BETA
    NSString *_lastAlphaChangeStack;
#endif
    BOOL _updatingDividerLayer;
    BOOL _isMovingScreen;
}

@synthesize it_openingSheet;
@synthesize it_becomingKey;
@synthesize it_accessibilityResizing;
@synthesize it_preventFrameChange;

- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSWindowStyleMask)aStyle
                            backing:(NSBackingStoreType)bufferingType
                              defer:(BOOL)flag
                             screen:(nullable NSScreen *)screen {
    self = [super initWithContentRect:contentRect
                            styleMask:aStyle
                              backing:bufferingType
                                defer:flag
                               screen:screen];
    if (self) {
        DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
        [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
        [self preventTitlebarDivider];
    }
    return self;
}

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backingStoreType defer:(BOOL)flag {
    self = [super initWithContentRect:contentRect
                            styleMask:style
                              backing:backingStoreType
                                defer:flag];
    if (self) {
        [self preventTitlebarDivider];
    }
    return self;
}

ITERM_WEAKLY_REFERENCEABLE

- (void)dealloc {
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
    // Not safe to call this from dealloc because can very indirectly try to retain this object.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
    });
    [restoreState_ release];
#if BETA
    [_lastAlphaChangeStack release];
#endif
    [super dealloc];

}

- (void)preventTitlebarDivider {
    if (@available(macOS 10.16, *)) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            static IMP originalImp;
            originalImp =
            [iTermSelectorSwizzler permanentlySwizzleSelector:@selector(_updateDividerLayerForController:animated:)
                                                    fromClass:NSClassFromString(@"NSTitlebarContainerView")
                                                    withBlock:^(id receiver, id controller, BOOL animated) {
                void (*f)(id, SEL, id, BOOL) = (void (*)(id, SEL, id, BOOL))originalImp;
                if (![controller respondsToSelector:@selector(window)]) {
                    f(receiver, @selector(_updateDividerLayerForController:animated:), controller, animated);
                    return;
                }
                NSWindow<PTYWindow> *window = (NSWindow<PTYWindow> *)[controller window];
                if (![window conformsToProtocol:@protocol(PTYWindow)]) {
                    f(receiver, @selector(_updateDividerLayerForController:animated:), controller, animated);
                    return;
                }

                [window setUpdatingDividerLayer:YES];
                f(receiver, @selector(_updateDividerLayerForController:animated:), controller, animated);
                [window setUpdatingDividerLayer:NO];
            }];
        });
    }
}

- (NSTitlebarSeparatorStyle)titlebarSeparatorStyle NS_AVAILABLE_MAC(10_16) {
    if (_updatingDividerLayer) {
        id<PTYWindow> ptywindow = (id<PTYWindow>)self;
        if ([ptywindow.ptyDelegate terminalWindowShouldHaveTitlebarSeparator]) {
            return NSTitlebarSeparatorStyleShadow;
        }
        return NSTitlebarSeparatorStyleNone;
    }
    return [super titlebarSeparatorStyle];
}

- (void)setUpdatingDividerLayer:(BOOL)value {
    _updatingDividerLayer = value;
}

- (void)setDocumentEdited:(BOOL)documentEdited {
    [super setDocumentEdited:documentEdited];
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermWindowDocumentedEditedDidChange object:self];
}

- (BOOL)titleChangedRecently {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    return (now > _timeOfLastWindowTitleChange && now - _timeOfLastWindowTitleChange < iTermWindowTitleChangeMinimumInterval);
}

- (void)setTitle:(NSString *)title {
    [super setTitle:title];
    _timeOfLastWindowTitleChange = [NSDate timeIntervalSinceReferenceDate];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(performMiniaturize:)) {
        // Can miniaturize borderless windows
        return ![self.ptyDelegate lionFullScreen];
    } else {
        _validatingMenuItems = YES;
        const BOOL result = [super validateMenuItem:item];
        _validatingMenuItems = NO;
        return result;
    }
}

- (void)performWindowDragWithEvent:(NSEvent *)event {
    if ([self.ptyDelegate ptyWindowIsDraggable:self]) {
        [super performWindowDragWithEvent:event];
    }
}

- (void)performMiniaturize:(nullable id)sender {
    if ([self.ptyDelegate anyFullScreen]) {
        [super miniaturize:sender];
    } else {
        DLog(@"performMiniaturize calling [self miniaturize:]");
        [self miniaturize:self];
    }
}

- (NSString *)description {
    NSString *extra = @"";
#if BETA
    if (_lastAlphaChangeStack) {
        extra = [NSString stringWithFormat:@" Alpha last changed from:\n%@\n", _lastAlphaChangeStack];
    }
#endif
    return [NSString stringWithFormat:@"<%@: %p frame=%@ title=%@ alpha=%f isMain=%d isKey=%d isVisible=%d collectionBehavior=%@ styleMask=%@ delegate=%p%@>",
            [self class],
            self,
            [NSValue valueWithRect:self.frame],
            self.title,
            self.alphaValue,
            (int)self.isMainWindow,
            (int)self.isKeyWindow,
            (int)self.isVisible,
            @(self.collectionBehavior),
            @(self.styleMask),
            self.delegate,
            extra];
}

- (void)setCollectionBehavior:(NSWindowCollectionBehavior)collectionBehavior {
    DLog(@"%@: setCollectionBehavior=%@\n%@", self, @(collectionBehavior), [NSThread callStackSymbols]);
    [super setCollectionBehavior:collectionBehavior];
}

- (NSString *)windowIdentifier {
    if (!_uniqueNumber) {
        static NSInteger nextUniqueNumber = 1;
        _uniqueNumber = nextUniqueNumber++;
    }
    return [NSString stringWithFormat:@"window-%ld", (long)_uniqueNumber];
}

- (void)setIt_restorableStateInvalid:(BOOL)it_restorableStateInvalid {
    _it_restorableStateInvalid = NO;
}

- (BOOL)it_restorableStateInvalid {
    return _it_restorableStateInvalid;
}

- (void)invalidateRestorableState {
    self.it_restorableStateInvalid = YES;
    [super invalidateRestorableState];
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder backgroundQueue:(NSOperationQueue *)queue {
    self.it_restorableStateInvalid = NO;
    [super encodeRestorableStateWithCoder:coder backgroundQueue:queue];
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder {
    self.it_restorableStateInvalid = NO;
    [super encodeRestorableStateWithCoder:coder];
    [coder encodeObject:restoreState_ forKey:kTerminalWindowStateRestorationWindowArrangementKey];
}

- (void)setRestoreState:(NSObject *)restoreState {
    [restoreState_ autorelease];
    restoreState_ = [restoreState retain];
}

- (void)enableBlur:(double)radius {
    CGSConnectionID con = CGSDefaultConnectionForThread();
    if (!con) {
        return;
    }
    CGSSetWindowBackgroundBlurRadiusFunction* function = GetCGSSetWindowBackgroundBlurRadiusFunction();
    if (function) {
        if (@available(macOS 10.16, *)) {
            if (radius >= 1) {
                _minBlur = 1;
            }
        }
        DLog(@"enable blur with radius %@ for window %@", @(MAX(_minBlur, radius)), self);
        function(con, [self windowNumber], (int)MAX(_minBlur, radius));
    } else {
        NSLog(@"Couldn't get blur function");
    }
    blurRadius_ = radius;
}

- (void)disableBlur {
    CGSConnectionID con = CGSDefaultConnectionForThread();
    if (!con) {
        return;
    }

    CGSSetWindowBackgroundBlurRadiusFunction* function = GetCGSSetWindowBackgroundBlurRadiusFunction();
    if (function) {
        DLog(@"disable blur for window %@", self);
        function(con, [self windowNumber], MAX(_minBlur, 0));
    }
}

- (nullable id<PTYWindowDelegateProtocol>)ptyDelegate {
    return (id<PTYWindowDelegateProtocol>)[self delegate];
}

- (void)toggleFullScreen:(nullable id)sender {
    if ([self.ptyDelegate toggleFullScreenShouldUseLionFullScreen]) {
        [super toggleFullScreen:sender];
    } else {
        [(id<PTYWindowDelegateProtocol>)[self delegate] toggleTraditionalFullScreenMode];
    }
}

- (BOOL)isTogglingLionFullScreen {
    return isTogglingLionFullScreen_;
}

- (int)screenNumber {
    return [[[[self screen] deviceDescription] objectForKey:@"NSScreenNumber"] intValue];
}

- (CGFloat)sumOfIntersectingAreaOfRect:(NSRect)rect withRects:(NSArray<NSValue *> *)rects {
    CGFloat totalArea = 0;
    for (NSValue *value in rects) {
        NSRect aRect = [value rectValue];
        NSRect intersection = NSIntersectionRect(aRect, rect);
        totalArea += (intersection.size.width * intersection.size.height);
    }
    return totalArea;
}

- (void)smartLayout {
    DLog(@"Begin smartLayout");

    int currentScreen = [self screenNumber];
    NSRect screenRect = [[self screen] visibleFrame];

    // Get a list of relevant windows, same screen & workspace
    NSArray<NSWindow *> *windows = [[(iTermApplication *)NSApp orderedWindowsPlusVisibleHotkeyPanels] filteredArrayUsingBlock:^BOOL(id window) {
        return (window != self &&
                [window isVisible] &&
                [window conformsToProtocol:@protocol(PTYWindow)] &&
                [window screenNumber] == currentScreen &&
                [window isOnActiveSpace]);
    }];

    NSArray<NSValue *> *frames = [windows mapWithBlock:^id(NSWindow *window) {
        return [NSValue valueWithRect:window.frame];
    }];

    double lowestCost = INFINITY;
    NSRect bestFrame = self.frame;
    const CGFloat widthToScan = screenRect.size.width - self.frame.size.width;
    const CGFloat heightToScan = screenRect.size.height - self.frame.size.height;
    const CGFloat stride = 50;
    const NSPoint screenCenter = NSMakePoint(NSMidX(screenRect), NSMidY(screenRect));
    const CGFloat maxDistance = sqrt(pow(screenRect.size.width, 2) + pow(screenRect.size.height, 2));
    for (CGFloat xOffset = 0; xOffset < widthToScan; xOffset += stride) {
        for (CGFloat yOffset = 0; yOffset < heightToScan; yOffset += stride) {
            NSRect proposedRect = NSMakeRect(screenRect.origin.x + xOffset,
                                             screenRect.origin.y + yOffset,
                                             self.frame.size.width,
                                             self.frame.size.height);
            // Ensure distance from screen center is less than 1 so any amount of overlap dominates even the
            // greatest cost from additional distance
            const NSPoint proposedCenter = NSMakePoint(NSMidX(proposedRect), NSMidY(proposedRect));
            CGFloat distanceFromScreenCenter = sqrt(pow(proposedCenter.x - screenCenter.x, 2) +
                                                    pow(proposedCenter.y - screenCenter.y, 2)) / maxDistance;
            const CGFloat cost = [self sumOfIntersectingAreaOfRect:proposedRect withRects:frames] + distanceFromScreenCenter;

            if (cost < lowestCost) {
                lowestCost = cost;
                bestFrame = proposedRect;
            }
        }
    }

    DLog(@"Using smart layout place window at %@ given frames %@", NSStringFromRect(bestFrame), frames);
    [self setFrameOrigin:bestFrame.origin];
}

- (void)setLayoutDone {
    DLog(@"setLayoutDone %@", [NSThread callStackSymbols]);
    _layoutDone = YES;
}

- (void)makeKeyAndOrderFront:(nullable id)sender {
    DLog(@"%@ makeKeyAndOrderFront: layoutDone=%@ %@", self, @(_layoutDone), [NSThread callStackSymbols]);
    if (!_layoutDone) {
        DLog(@"try to call windowWillShowInitial");
        [self setLayoutDone];
        if ([[self delegate] respondsToSelector:@selector(windowWillShowInitial)]) {
            [[self delegate] performSelector:@selector(windowWillShowInitial)];
        } else {
            DLog(@"delegate %@ does not respond", [self delegate]);
        }
    }
    DLog(@"%@ - calling makeKeyAndOrderFont, which triggers a window resize", NSStringFromClass([self class]));
    DLog(@"The current window frame is %fx%f", [self frame].size.width, [self frame].size.height);
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
    [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
    self.it_becomingKey = YES;
    [super makeKeyAndOrderFront:sender];
    [self.ptyDelegate ptyWindowDidMakeKeyAndOrderFront:self];
    self.it_becomingKey = NO;
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

- (void)orderWindow:(NSWindowOrderingMode)place relativeTo:(NSInteger)otherWin {
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
    [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
    [super orderWindow:place relativeTo:otherWin];
}

- (void)orderFrontRegardless {
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
    DLog(@"%@\n%@", NSStringFromSelector(_cmd), [NSThread callStackSymbols]);
    [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
    [super orderFrontRegardless];
}

- (void)orderFront:(nullable id)sender {
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
    DLog(@"%@\n%@", NSStringFromSelector(_cmd), [NSThread callStackSymbols]);
    [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
    [super orderFront:sender];
}

- (void)orderBack:(nullable id)sender {
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
    DLog(@"%@\n%@", NSStringFromSelector(_cmd), [NSThread callStackSymbols]);
    [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
    [super orderBack:sender];
}

- (void)orderOut:(nullable id)sender {
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
    [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
    [super orderOut:sender];
}

- (void)setOrderedIndex:(NSInteger)orderedIndex {
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
    [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
    [super setOrderedIndex:orderedIndex];
}

- (void)setAlphaValue:(CGFloat)alphaValue {
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
    [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
#if BETA
    if (alphaValue < 0.01 && !_lastAlphaChangeStack) {
        _lastAlphaChangeStack = [[[NSThread callStackSymbols] componentsJoinedByString:@"\n"] copy];
    } else if (alphaValue > 0.01) {
        [_lastAlphaChangeStack release];
        _lastAlphaChangeStack = nil;
    }
#endif
    [super setAlphaValue:alphaValue];
}

- (double)approximateFractionOccluded {
    if (_totalOcclusionCacheTime > [[iTermWindowOcclusionChangeMonitor sharedInstance] timeOfLastOcclusionChange]) {
        // -orderedWindows is expensive, so avoid doing anything here if nothing has changed.
        return _cachedTotalOcclusion;
    }

    NSArray *orderedWindows = [[NSApplication sharedApplication] orderedWindows];
    NSUInteger myIndex = [orderedWindows indexOfObject:self];
    NSRect myFrame = [self frame];
    double onScreenFraction = 0;
    const double myArea = myFrame.size.width * myFrame.size.height;
    if (myArea >= 1) {
        for (NSScreen *screen in [NSScreen screens]) {
            const NSRect screenFrame = screen.frame;
            const NSRect onscreenFrame = NSIntersectionRect(myFrame, screenFrame);
            const CGFloat onscreenArea = (onscreenFrame.size.width * onscreenFrame.size.height);
            onScreenFraction += onscreenArea / myArea;
        }
    }
    const double offscreenFraction = MAX(MIN(1, 1 - onScreenFraction), 0);
    CGFloat totalOcclusion = 0;
    if (myIndex != 0 && myIndex != NSNotFound) {
        const int kRows = 3;
        const int kCols = 3;
        typedef struct {
            NSRect rect;
            double occlusion;
        } OcclusionPart;
        OcclusionPart parts[kRows][kCols];

        NSSize partSize = NSMakeSize(myFrame.size.width / kCols, myFrame.size.height / kRows);
        for (int y = 0; y < kRows; y++) {
            for (int x = 0; x < kCols; x++) {
                parts[y][x].rect = NSMakeRect(myFrame.origin.x + x * partSize.width,
                                              myFrame.origin.y + y * partSize.height,
                                              partSize.width,
                                              partSize.height);
                parts[y][x].occlusion = 0;
            }
        }
        CGFloat pixelsInPart = partSize.width * partSize.height;

        // This loop iterates over each window in front of this one and measures
        // how much of it intersects each part of this one (a part is one 9th of
        // the window, as divided into a 3x3 grid). For each part, an occlusion
        // fraction is tracked, which is the fraction of that part which is covered
        // by another window. It's approximate because it's the maximum occlusion
        // for that part by all other windows, so it could be too low (if two
        // windows each cover different halves of a part, for example).
        for (NSUInteger i = 0; i < myIndex; i++) {
            NSWindow *other = orderedWindows[i];
            if ([other isMiniaturized] || other.alphaValue < 0.1) {
                // The other window is almost transparent or miniaturized, so short circuit.
                continue;
            }
            NSRect otherFrame = [other frame];
            NSRect overallIntersection = NSIntersectionRect(otherFrame, myFrame);
            if (overallIntersection.size.width < 1 &&
                overallIntersection.size.height < 1) {
                // Short circuit--there is no overlap at all.
                continue;
            }
            totalOcclusion = 0;
            for (int y = 0; y < kRows; y++) {
                for (int x = 0; x < kCols; x++) {
                    if (parts[y][x].occlusion != 1) {
                        NSRect intersection = NSIntersectionRect(parts[y][x].rect, otherFrame);
                        CGFloat pixelsOfOcclusion = intersection.size.width * intersection.size.height;
                        parts[y][x].occlusion = MAX(parts[y][x].occlusion,
                                                    pixelsOfOcclusion / pixelsInPart);
                    }
                    totalOcclusion += parts[y][x].occlusion / (kRows * kCols);
                }
            }
            totalOcclusion = MAX(totalOcclusion, offscreenFraction);
            if (totalOcclusion > 0.99) {
                totalOcclusion = 1;
                break;
            }
        }
    } else {
        totalOcclusion = offscreenFraction;
    }

    _totalOcclusionCacheTime = [NSDate timeIntervalSinceReferenceDate];
    _cachedTotalOcclusion = totalOcclusion;
    return totalOcclusion;
}

- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(nullable NSScreen *)screen {
    if ([self.ptyDelegate terminalWindowShouldConstrainFrameToScreen]) {
        return [super constrainFrameRect:frameRect toScreen:screen];
    } else {
        return frameRect;
    }
}

- (BOOL)makeFirstResponder:(nullable NSResponder *)responder {
    DLog(@"%p makeFirstResponder:%@", self, responder);
    DLog(@"%@", [NSThread callStackSymbols]);
    return [super makeFirstResponder:responder];
}

- (NSWindowTabbingMode)tabbingMode {
    return NSWindowTabbingModeDisallowed;
}

- (void)_moveToScreen:(id)sender {
    if (![[THE_CLASS superclass] instancesRespondToSelector:_cmd]) {
        return;
    }
    if ([sender isKindOfClass:[NSScreen class]]) {
        [self.ptyDelegate terminalWindowWillMoveToScreen:sender];
    }
    DLog(@"_isMovingScreen = YES");
    _isMovingScreen = YES;
    [super _moveToScreen:sender];
    _isMovingScreen = NO;
    DLog(@"_isMovingScreen = NO");
    if ([sender isKindOfClass:[NSScreen class]]) {
        [self.ptyDelegate terminalWindowDidMoveToScreen:sender];
    }
}

- (BOOL)it_isMovingScreen {
    return _isMovingScreen;
}

- (void)setFrame:(NSRect)frameRect display:(BOOL)flag {
    DLog(@"setFrame:%@ display:%@ maxy=%@ of %@ from\n%@",
         NSStringFromRect(frameRect), @(flag), @(NSMaxY(frameRect)),
          self.delegate,
         [NSThread callStackSymbols]);
    if (self.it_preventFrameChange) {
        // This is a terrible hack.
        // When you restart and choose to restore windows after logging back in, appkit sets the
        // window size from the restoration completion block. This has the effect of reversing the
        // width adjustment that we make to the window to account for a change in the scrollbar
        // style change. See _widthAdjustment in PseudoTerminal.m for details. Issue 9877
        DLog(@"Disregarding frame change");
        return;
    }
    [super setFrame:frameRect display:flag];
}

- (void)setFrameOrigin:(NSPoint)point {
    DLog(@"Set frame origin to %@", NSStringFromPoint(point));
    [super setFrameOrigin:point];
    DLog(@"Frame maxy=%@ now", @(NSMaxY(self.frame)));
}

#if ENABLE_COMPACT_WINDOW_HACK
- (BOOL)isCompact {
    return YES;
}

+ (Class)frameViewClassForStyleMask:(NSUInteger)windowStyle {
    return [iTermThemeFrame class] ?: [super frameViewClassForStyleMask:windowStyle];
}

// https://chromium.googlesource.com/chromium/src/+/refs/tags/73.0.3683.86/ui/views_bridge_mac/native_widget_mac_nswindow.mm#169
// The base implementation returns YES if the window's frame view is a custom
// class, which causes undesirable changes in behavior. AppKit NSWindow
// subclasses are known to override it and return NO.
//
// In particular, this fixes issue 8478 (traffic light buttons vertically off-center in native full screen).
- (BOOL)_usesCustomDrawing {
    return NO;
}
#else
- (BOOL)isCompact {
    return NO;
}
#endif

- (void)accessibilitySetSizeAttribute:(id)arg1 {
    self.it_accessibilityResizing += 1;
    [super accessibilitySetSizeAttribute:arg1];
    self.it_accessibilityResizing -= 1;
}

- (NSColor *)it_terminalWindowDecorationBackgroundColor {
    return [self.ptyDelegate terminalWindowDecorationBackgroundColor];
}

- (id<PSMTabStyle>)it_tabStyle {
    return [self.ptyDelegate terminalWindowTabStyle];
}

- (NSColor *)it_terminalWindowDecorationTextColorForBackgroundColor:(NSColor *)backgroundColor {
    return [self.ptyDelegate terminalWindowDecorationTextColorForBackgroundColor:(NSColor *)backgroundColor];
}

- (NSColor *)it_terminalWindowDecorationControlColor {
    return [self.ptyDelegate terminalWindowDecorationControlColor];
}

- (BOOL)it_terminalWindowUseMinimalStyle {
    return [self.ptyDelegate terminalWindowUseMinimalStyle];
}

- (void)beginSheet:(NSWindow *)sheetWindow completionHandler:(void (^ _Nullable)(NSModalResponse))handler {
    self.it_openingSheet = self.it_openingSheet + 1;
    [super beginSheet:sheetWindow completionHandler:handler];
    self.it_openingSheet = self.it_openingSheet - 1;
}

- (void)it_setNeedsInvalidateShadow {
    _needsInvalidateShadow = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        _needsInvalidateShadow = NO;
        [self invalidateShadow];
    });
}

- (BOOL)isMovable {
    return _validatingMenuItems || [super isMovable];
}

NS_ASSUME_NONNULL_END

@end
