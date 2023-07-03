//
//  NSScreen+iTerm.m
//  iTerm
//
//  Created by George Nachman on 6/28/14.
//
//

#import "NSScreen+iTerm.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTermTuple.h"
#import "iTerm2SharedARC-Swift.h"

static char iTermNSScreenSupportsHighFrameRatesCacheKey;

@interface iTermTuple(Array)
@property (nonatomic, readonly) NSPoint pointValue;
@end

@implementation iTermTuple(Array)

- (NSPoint)pointValue {
    return NSMakePoint([NSNumber castFrom:self.firstObject].doubleValue,
                       [NSNumber castFrom:self.secondObject].doubleValue);
}

@end

@implementation NSScreen (iTerm)

- (NSString *)it_description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ visibleFrame=%@ hasDock=%@>",
            NSStringFromClass(self.class), self, NSStringFromRect(self.frame),
            NSStringFromRect(self.visibleFrame), [self hasDock] ? @"YES" : @"NO"];
}

- (BOOL)containsCursor {
    NSRect frame = [self frame];
    NSPoint cursor = [NSEvent mouseLocation];
    return NSPointInRect(cursor, frame);
}

+ (NSScreen *)screenWithCursor {
    for (NSScreen *screen in [self screens]) {
        if ([screen containsCursor]) {
            return screen;
        }
    }
    return [self mainScreen];
}

+ (NSScreen *)screenWithFrame:(NSRect)frame {
    for (NSScreen *screen in self.screens) {
        if (NSEqualRects(frame, screen.frame)) {
            return screen;
        }
    }
    return nil;
}

static CGFloat iTermAreaOfIntersection(NSRect r1, NSRect r2) {
    const NSRect intersection = NSIntersectionRect(r1, r2);
    return intersection.size.width * intersection.size.height;
}

+ (double)fractionOfFrameOnAnyScreen:(NSRect)frame
                   recommendedOrigin:(NSPoint *)recommendedOriginPtr {
    __block double areaOnScreen = 0;
    [self.screens enumerateObjectsUsingBlock:^(NSScreen * _Nonnull screen, NSUInteger idx, BOOL * _Nonnull stop) {
        areaOnScreen += iTermAreaOfIntersection(screen.frame, frame);
    }];
    const double frameArea = frame.size.width * frame.size.height;
    const double fraction = areaOnScreen / frameArea;
    if (!recommendedOriginPtr) {
        return fraction;
    }
    *recommendedOriginPtr = frame.origin;
    if (frameArea <= areaOnScreen) {
        return fraction;
    }
    // Try to find a better origin.
    NSScreen *mainScreen = [self bestScreenForRect:frame];
    if (!mainScreen) {
        return fraction;
    }

    *recommendedOriginPtr = [mainScreen improvedOrigin:frame];
    return fraction;
}

+ (NSScreen *)bestScreenForRect:(NSRect)frame {
    return [self.screens maxWithBlock:^NSComparisonResult(NSScreen *obj1, NSScreen *obj2) {
        const CGFloat lhs = iTermAreaOfIntersection(obj1.frame, frame);
        const CGFloat rhs = iTermAreaOfIntersection(obj2.frame, frame);
        if (lhs != rhs) {
            return [@(lhs) compare:@(rhs)];
        }
        // Tiebreak by choosing leftmost screen so the comparison is stable.
        if (obj1.frame.origin.x != obj2.frame.origin.x) {
            return [@(obj1.frame.origin.x) compare:@(obj2.frame.origin.x)];
        }
        return [@(obj1.frame.origin.y)compare:@(obj2.frame.origin.y)];
    }];
}

- (NSPoint)improvedOrigin:(NSRect)frame {
    const NSRect myFrame = self.visibleFrame;
    NSArray<NSNumber *> *xOriginCandidates = @[
        @(NSMinX(myFrame)),
        @(NSMaxX(myFrame) - NSWidth(frame)),
        @(NSMinX(frame))
    ];;
    NSArray<NSNumber *> *yOriginCandidates = @[
        @(NSMinY(myFrame)),
        @(NSMaxY(myFrame) - NSHeight(frame)),
        @(NSMinY(frame))
    ];
    NSArray<iTermTuple<NSNumber *, NSNumber *> *> *tuples = [iTermTuple cartesianProductOfArray:xOriginCandidates
                                                                                           with:yOriginCandidates];
    double (^l2)(NSPoint, NSPoint) = ^double(NSPoint p1, NSPoint p2) {
        const double dx = p1.x - p2.x;
        const double dy = p1.y - p2.y;
        return sqrt(dx * dx + dy * dy);
    };
    iTermTuple<NSNumber *, NSNumber *> *best = [tuples maxWithBlock:^NSComparisonResult(iTermTuple<NSNumber *, NSNumber *> *v1,
                                                                                        iTermTuple<NSNumber *, NSNumber *> *v2) {
        const NSPoint p1 = v1.pointValue;
        const NSPoint p2 = v2.pointValue;

        const NSRect r1 = NSMakeRect(p1.x, p1.y, NSWidth(frame), NSHeight(frame));
        const NSRect r2 = NSMakeRect(p2.x, p2.y, NSWidth(frame), NSHeight(frame));

        const double a1 = iTermAreaOfIntersection(r1, myFrame);
        const double a2 = iTermAreaOfIntersection(r2, myFrame);

        if (a1 != a2) {
            return [@(a1) compare:@(a2)];
        }

        const CGFloat d1 = l2(p1, frame.origin);
        const CGFloat d2 = l2(p2, frame.origin);
        return [@(-d1) compare:@(-d2)];
    }];
    return best.pointValue;
}

- (NSRect)visibleFrameIgnoringHiddenDock {
  NSRect visibleFrame = [self visibleFrame];
  NSRect actualFrame = [self frame];

  CGFloat visibleLeft = CGRectGetMinX(visibleFrame);
  CGFloat visibleRight = CGRectGetMaxX(visibleFrame);
  CGFloat visibleBottom = CGRectGetMinY(visibleFrame);

  CGFloat actualLeft = CGRectGetMinX(actualFrame);
  CGFloat actualRight = CGRectGetMaxX(actualFrame);
  CGFloat actualBottom = CGRectGetMinY(actualFrame);

  CGFloat leftInset = fabs(visibleLeft - actualLeft);
  CGFloat rightInset = fabs(visibleRight - actualRight);
  CGFloat bottomInset = fabs(visibleBottom - actualBottom);

  NSRect visibleFrameIgnoringHiddenDock = visibleFrame;
  const CGFloat kHiddenDockSize = 4;
  if (leftInset == kHiddenDockSize) {
    visibleFrameIgnoringHiddenDock.origin.x -= kHiddenDockSize;
    visibleFrameIgnoringHiddenDock.size.width += kHiddenDockSize;
  } else if (rightInset == kHiddenDockSize) {
    visibleFrameIgnoringHiddenDock.size.width += kHiddenDockSize;
  } else if (bottomInset == kHiddenDockSize) {
    visibleFrameIgnoringHiddenDock.origin.y -= kHiddenDockSize;
    visibleFrameIgnoringHiddenDock.size.height += kHiddenDockSize;
  }

  return visibleFrameIgnoringHiddenDock;
}

- (BOOL)hasDock {
    const NSRect frame = self.frame;
    const NSRect visibleFrame = self.visibleFrame;

    const CGFloat leftInset = NSMinX(visibleFrame) - NSMinX(frame);
    if (leftInset > 0) {
        return YES;
    }
    const CGFloat bottomInset = NSMinY(visibleFrame) - NSMinY(frame);
    if (bottomInset > 0) {
        return YES;
    }
    const CGFloat rightInset = NSMaxX(frame) - NSMaxX(visibleFrame);
    if (rightInset > 0) {
        return YES;
    }

    return NO;
}

- (CGFloat)notchHeight {
    if (@available(macOS 12.0, *)) {
        return self.safeAreaInsets.top;
    }
    return 0;
}

- (NSRect)frameExceptNotch {
    NSRect frame = self.frame;
    const CGFloat notchHeight = [self notchHeight];
    frame.size.height -= notchHeight;
    return frame;
}

- (CGFloat)it_menuBarHeight {
    if (@available(macOS 12, *)) {
        // When the "current" screen has a notch, there doesn't seem to be a way to get the height
        // of the menu bar on other screens :(
        return MAX(24, self.safeAreaInsets.top);
    }
    return NSApp.mainMenu.menuBarHeight;
}

- (NSRect)frameExceptMenuBar {
    if ([[NSScreen screens] firstObject] == self || [NSScreen screensHaveSeparateSpaces]) {
        NSRect frame = self.frame;
        // NSApp.mainMenu.menuBarHeight used to return 0 when there's a Lion
        // fullscreen window in another display, and it still does if the menu bar is hidden.
        // Use a collection of hacks to make a better guess.
        const CGFloat hackyGuess = NSHeight(self.frame) - NSHeight(self.visibleFrame) - NSMinY(self.visibleFrame) + NSMinY(self.frame) - 1;
        const CGFloat notchHeight = [self notchHeight];
        frame.size.height -= MAX(MAX(hackyGuess, [self it_menuBarHeight]), notchHeight);
        return frame;
    } else {
        return [self frameExceptNotch];
    }
}

- (iTermScreenIdentifier)it_identifier {
    const CGDirectDisplayID displayID = self.it_displayID;
    const iTermScreenIdentifier result = {
        .modelNumber = CGDisplayModelNumber(displayID),
        .vendorNumber = CGDisplayVendorNumber(displayID),
        .serialNumber = CGDisplaySerialNumber(displayID)
    };
    return result;
}

- (NSString *)it_uniqueKey {
    const iTermScreenIdentifier screenID = self.it_identifier;
    return [NSString stringWithFormat:@"UniqueDisplayKey: %u %u %u", screenID.modelNumber, screenID.vendorNumber, screenID.serialNumber];
}

- (CGDirectDisplayID)it_displayID {
    NSDictionary<NSDeviceDescriptionKey, id> *deviceDescription = self.deviceDescription;
    NSNumber *number = deviceDescription[@"NSScreenNumber"];
    return (CGDirectDisplayID)number.unsignedLongLongValue;
}

- (NSString *)it_nonUniqueName {
    return [self localizedName];
}

- (NSString *)it_fallbackName {
    NSArray<NSScreen *> *screens = [self it_sortedScreens];
    NSInteger index = [screens indexOfObjectPassingTest:^BOOL(NSScreen * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return [[obj it_uniqueKey] isEqualToString:[self it_uniqueKey]];
    }];
    if (index == NSNotFound) {
        return @"Display";
    }
    return [NSString stringWithFormat:@"Display %@", @(index + 1)];
}

- (NSArray<NSScreen *> *)it_sortedScreens {
    return [[NSScreen screens] sortedArrayUsingComparator:^NSComparisonResult(NSScreen * _Nonnull lhs, NSScreen * _Nonnull rhs) {
        return [lhs.it_uniqueKey compare:rhs.it_uniqueKey];
    }];
}

- (NSString *)it_uniqueName {
    NSArray<NSScreen *> *sorted = [self it_sortedScreens];

    // Detect dups. These get a number suffix.
    NSCountedSet *set = [[NSCountedSet alloc] init];
    for (NSScreen *screen in sorted) {
        [set addObject:screen.it_nonUniqueName];
    }

    // Iterate over screens and increment last[non-unique-name] as you go until you find this screen.
    // Then you'll know its number, if any, based on the value in last.
    NSMutableDictionary<NSString *, NSNumber *> *last = [NSMutableDictionary dictionary];
    for (NSScreen *screen in sorted) {
        NSString *nonUniqueName = [screen it_nonUniqueName];
        const NSInteger count = [set countForObject:nonUniqueName];
        const BOOL isMe = ([[screen it_uniqueKey] isEqualToString:[self it_uniqueKey]]);
        if (count > 1) {
            NSNumber *n = last[nonUniqueName] ?: @0;
            if (isMe) {
                return [NSString stringWithFormat:@"%@ (%@)", nonUniqueName, @(n.integerValue + 1)];
            }
            last[nonUniqueName] = @(n.integerValue + 1);
        } else {
            if (isMe) {
                return nonUniqueName;
            }
        }
    }
    return [self it_fallbackName];
}

+ (NSScreen *)it_screenWithUniqueKey:(NSString *)key {
    return [[NSScreen screens] objectPassingTest:^BOOL(NSScreen *candidate, NSUInteger index, BOOL *stop) {
        return [[candidate it_uniqueKey] isEqualToString:key];
    }];
}

+ (BOOL)it_stringLooksLikeUniqueKey:(NSString *)string {
    return [string hasPrefix:@"UniqueDisplayKey:"];
}

+ (NSArray<NSDictionary *> *)it_allWindowInfoDictionaries {
    const CGWindowListOption options = (kCGWindowListExcludeDesktopElements |
                                        kCGWindowListOptionOnScreenOnly);
    NSArray<NSDictionary *> *windowInfos = (__bridge_transfer NSArray *)CGWindowListCopyWindowInfo(options,
                                                                                          kCGNullWindowID);
    return windowInfos;
}

+ (CGRect)windowBoundsRectFromWindowInfoDictionary:(NSDictionary *)dictionary {
    CGRect rect = CGRectMake(NAN, NAN, 0, 0);
    BOOL ok = NO;
    if (dictionary) {
        ok = CGRectMakeWithDictionaryRepresentation((CFDictionaryRef)dictionary[(id)kCGWindowBounds],
                                                    &rect);
    }
    if (!ok) {
        rect = CGRectMake(NAN, NAN, 0, 0);
    }
    return [self rectInCGSpace:rect];
}

+ (NSRect)rectInCGSpace:(NSRect)frame {
    CGRect firstScreenFrame = [[[NSScreen screens] firstObject] frame];
    // Window frames are flipped versus screen frames, and are relative to the first screen.
    // A menu bar y coordinate of 0 equals the top of the first screen.
    // A screen y coordinate of 0 equals the bottom of the first screen.
    NSRect result = frame;
    result.origin.y = firstScreenFrame.size.height - frame.size.height - frame.origin.y;
    return result;
}

- (BOOL)it_hasAnotherAppsFullScreenWindow {
    const NSRect screenFrame = self.frame;
    const BOOL myWindowIsFullScreenOnThisScreen = [[NSApp windows] anyWithBlock:^BOOL(NSWindow *anObject) {
        if (anObject.alphaValue <= 0) {
            return NO;
        }
        if (!NSEqualRects(anObject.frame, screenFrame)) {
            return NO;
        }
        if (!(anObject.styleMask & NSWindowStyleMaskFullScreen)) {
            return NO;
        }
        if (![anObject isOnActiveSpace]) {
            return NO;
        }
        return YES;
    }];
    if (myWindowIsFullScreenOnThisScreen) {
        DLog(@"No - one of my windows is fullscreen on %@", self);
        return NO;
    }
    NSSet<NSNumber *> *windowNumbers = [NSSet setWithArray:[[NSApp windows] mapWithBlock:^id(NSWindow *window) {
        return @(window.windowNumber);
    }]];
    NSArray<NSDictionary *> *allInfos = [NSScreen it_allWindowInfoDictionaries];
    NSArray<NSDictionary *> *relevantInfos = [allInfos filteredArrayUsingBlock:^BOOL(NSDictionary *windowInfo) {
        DLog(@"Consider %@", windowInfo);
        if ([windowInfo[(__bridge NSString *)kCGWindowAlpha] doubleValue] <= 0) {
            DLog(@"Reject: Nonpositive alpha");
            return NO;
        }
        if (![windowInfo[(__bridge NSString *)kCGWindowIsOnscreen] boolValue]) {
            DLog(@"Reject: not on screen");
            return NO;
        }
        NSNumber *windowNumber = windowInfo[(__bridge NSString *)kCGWindowNumber];
        if ([windowNumbers containsObject:windowNumber]) {
            DLog(@"Reject: this is my window");
            // Is my own window.
            return NO;
        }
        if ([windowInfo[(__bridge  NSString *)kCGWindowOwnerName] isEqual:@"Window Server"] &&
            [windowInfo[(__bridge  NSString *)kCGWindowName] isEqual:@"Menubar"]) {
            DLog(@"Accept: is menu bar");
            return YES;
        }
        if ([windowInfo[(__bridge NSString *)kCGWindowLayer] doubleValue] > 0) {
            DLog(@"Reject: Higher layer");
            return NO;
        }
        const CGRect windowFrame = [NSScreen windowBoundsRectFromWindowInfoDictionary:windowInfo];
        if (!NSIntersectsRect(windowFrame, screenFrame)) {
            DLog(@"Reject: Not on this screen");
            return NO;
        }
        return YES;
    }];
    return [self windowInfos:relevantInfos framesTileScreenFrame:screenFrame];
}

- (BOOL)windowInfos:(NSArray<NSDictionary *> *)infos framesTileScreenFrame:(NSRect)screenFrame {
    iTermTilingChecker *checker = [[iTermTilingChecker alloc] init];
    for (NSDictionary *windowInfo in infos) {
        const CGRect windowFrame = [NSScreen windowBoundsRectFromWindowInfoDictionary:windowInfo];
        [checker addRect:windowFrame];
    }
    // For some reason there's a 1 pixel margin on the left that goes unused (at least in Ventura)
    // This is a terrible hack but I can't find any other way to determine if you're on a desktop
    // for some other app's fullscren window and this tiling BS is needed for split screen FS windows.
    [checker addRect:NSMakeRect(screenFrame.origin.x, screenFrame.origin.y, 1, screenFrame.size.height)];
    return [checker tilesFrame:screenFrame];
}

- (NSNumber *)it_cachedSupportsHighFrameRates {
    iTermTuple<NSNumber *, NSNumber *> *tuple = [self it_associatedObjectForKey:&iTermNSScreenSupportsHighFrameRatesCacheKey];
    if (!tuple) {
        return nil;
    }
    const NSTimeInterval now = [NSDate it_timeSinceBoot];
    const NSTimeInterval age = now - tuple.secondObject.doubleValue;
    if (age > 1) {
        return nil;
    }
    return tuple.firstObject;
}

- (void)it_setSupportsHighFrameRates:(BOOL)value {
    iTermTuple<NSNumber *, NSNumber *> *tuple = [iTermTuple tupleWithObject:@(value)
                                                                  andObject:@([NSDate it_timeSinceBoot])];
    [self it_setAssociatedObject:tuple forKey:&iTermNSScreenSupportsHighFrameRatesCacheKey];
}

- (BOOL)it_supportsHighFrameRates {
    NSNumber *cached = [self it_cachedSupportsHighFrameRates];
    if (cached) {
        return [cached boolValue];
    }
    CGDirectDisplayID displayID = [self it_displayID];
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayID);
    const double refreshRate = mode ? CGDisplayModeGetRefreshRate(mode) : 60;
    CGDisplayModeRelease(mode);
    const BOOL result = refreshRate >= 120;
    [self it_setSupportsHighFrameRates:result];
    return result;
}

+ (NSScreen *)screenContainingCoordinate:(NSPoint)point {
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSPointInRect(point, screen.frame)) {
            return screen;
        }
    }
    return nil;
}

@end
