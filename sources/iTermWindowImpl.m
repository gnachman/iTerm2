#ifndef THE_CLASS
#define THE_CLASS ThisIsJustHereToMakeXCodeHappy
@interface THE_CLASS : NSWindow
@end
#endif

NS_ASSUME_NONNULL_BEGIN

@implementation THE_CLASS
{
    int blurFilter;
    double blurRadius_;
    
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
}

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
    }
    return self;
}

ITERM_WEAKLY_REFERENCEABLE

- (void)iterm_dealloc {
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
    [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
    [restoreState_ release];
    [super dealloc];

}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(performMiniaturize:)) {
        // This makes borderless windows miniaturizable.
        return ![self.ptyDelegate anyFullScreen];
    } else {
        return [super validateMenuItem:item];
    }
}

- (void)performMiniaturize:(nullable id)sender {
    if ([self.ptyDelegate anyFullScreen]) {
        [super performMiniaturize:sender];
    } else {
        // NSWindow's performMiniaturize gates miniaturization on the presence of a miniaturize button.
        [self miniaturize:self];
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ title=%@ alpha=%f isMain=%d isKey=%d isVisible=%d delegate=%p>",
            [self class],
            self,
            [NSValue valueWithRect:self.frame],
            self.title,
            self.alphaValue,
            (int)self.isMainWindow,
            (int)self.isKeyWindow,
            (int)self.isVisible,
            self.delegate];
}

- (NSString *)windowIdentifier {
    if (!_uniqueNumber) {
        static NSInteger nextUniqueNumber = 1;
        _uniqueNumber = nextUniqueNumber++;
    }
    return [NSString stringWithFormat:@"window-%ld", (long)_uniqueNumber];
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder {
    [super encodeRestorableStateWithCoder:coder];
    [coder encodeObject:restoreState_ forKey:kTerminalWindowStateRestorationWindowArrangementKey];
}

- (void)setRestoreState:(NSObject *)restoreState {
    [restoreState_ autorelease];
    restoreState_ = [restoreState retain];
}

- (void)enableBlur:(double)radius {
    const double kEpsilon = 0.001;
    if (blurFilter && fabs(blurRadius_ - radius) < kEpsilon) {
        return;
    }

    CGSConnectionID con = CGSMainConnectionID();
    if (!con) {
        return;
    }
    CGSSetWindowBackgroundBlurRadiusFunction* function = GetCGSSetWindowBackgroundBlurRadiusFunction();
    if (function) {
        function(con, [self windowNumber], (int)radius);
    } else {
        NSLog(@"Couldn't get blur function");
    }
    blurRadius_ = radius;
}

- (void)disableBlur {
    CGSConnectionID con = CGSMainConnectionID();
    if (!con) {
        return;
    }

    CGSSetWindowBackgroundBlurRadiusFunction* function = GetCGSSetWindowBackgroundBlurRadiusFunction();
    if (function) {
        function(con, [self windowNumber], 0);
    } else if (blurFilter) {
        CGSRemoveWindowFilter(con, (CGSWindowID)[self windowNumber], blurFilter);
        CGSReleaseCIFilter(CGSMainConnectionID(), blurFilter);
        blurFilter = 0;
    }
}

- (nullable id<PTYWindowDelegateProtocol>)ptyDelegate {
    return (id<PTYWindowDelegateProtocol>)[self delegate];
}

- (void)toggleFullScreen:(nullable id)sender {
    if (![[self ptyDelegate] lionFullScreen]  &&
        ![iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscren]) {
        // The user must have clicked on the toolbar arrow, but the pref is set
        // to use traditional fullscreen.
        [(id<PTYWindowDelegateProtocol>)[self delegate] toggleTraditionalFullScreenMode];
    } else {
        [super toggleFullScreen:sender];
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
    DLog(@"%@ makeKeyAndOrderFront: layoutDone=%@ %@", NSStringFromClass([self class]), @(_layoutDone), [NSThread callStackSymbols]);
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
    [super makeKeyAndOrderFront:sender];
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
    [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
    [super orderFrontRegardless];
}

- (void)orderFront:(nullable id)sender {
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
    [[iTermWindowOcclusionChangeMonitor sharedInstance] invalidateCachedOcclusion];
    [super orderFront:sender];
}

- (void)orderBack:(nullable id)sender {
    DLog(@"Invalidate cached occlusion: %@ %p", NSStringFromSelector(_cmd), self);
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
    [super setAlphaValue:alphaValue];
}

- (double)approximateFractionOccluded {
    if (_totalOcclusionCacheTime > [[iTermWindowOcclusionChangeMonitor sharedInstance] timeOfLastOcclusionChange]) {
        // -orderedWindows is expensive, so avoid doing anything here if nothing has changed.
        return _cachedTotalOcclusion;
    }

    NSArray *orderedWindows = [[NSApplication sharedApplication] orderedWindows];
    NSUInteger myIndex = [orderedWindows indexOfObject:self];
    CGFloat totalOcclusion = 0;
    if (myIndex != 0 && myIndex != NSNotFound) {
        const int kRows = 3;
        const int kCols = 3;
        typedef struct {
            NSRect rect;
            double occlusion;
        } OcclusionPart;
        OcclusionPart parts[kRows][kCols];
        NSRect myFrame = [self frame];
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
        // the window, as divded into a 3x3 grid). For each part, an occlusion
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
            if (totalOcclusion > 0.99) {
                totalOcclusion = 1;
                break;
            }
        }
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

NS_ASSUME_NONNULL_END

@end
