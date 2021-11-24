//
//  NSScreen+iTerm.m
//  iTerm
//
//  Created by George Nachman on 6/28/14.
//
//

#import "NSScreen+iTerm.h"

#import "NSArray+iTerm.h"
#import "NSDate+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTermTuple.h"

static char iTermNSScreenSupportsHighFrameRatesCacheKey;

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

- (NSRect)frameExceptMenuBar {
    if ([[NSScreen screens] firstObject] == self || [NSScreen screensHaveSeparateSpaces]) {
        NSRect frame = self.frame;
        // NSApp.mainMenu.menuBarHeight used to return 0 when there's a Lion
        // fullscreen window in another display, and it still does if the menu bar is hidden.
        // Use a collection of hacks to make a better guess.
        const CGFloat hackyGuess = NSHeight(self.frame) - NSHeight(self.visibleFrame) - NSMinY(self.visibleFrame) + NSMinY(self.frame) - 1;
        CGFloat notchHeight = 0;
        if (@available(macOS 12.0, *)) {
            notchHeight = self.safeAreaInsets.top;
        }
        frame.size.height -= MAX(MAX(hackyGuess, NSApp.mainMenu.menuBarHeight), notchHeight);
        return frame;
    } else {
        return self.frame;
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

static io_service_t iTermGetIOService(CGDirectDisplayID displayID) {
    io_iterator_t serialPortIterator = 0;
    io_service_t ioServ = 0;
    CFMutableDictionaryRef matching = IOServiceMatching("IODisplayConnect");
    const kern_return_t kernResult = IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &serialPortIterator);
    if (kernResult != KERN_SUCCESS) {
        return 0;
    }
    if (serialPortIterator == 0) {
        return 0;
    }

    ioServ = IOIteratorNext(serialPortIterator);
    while (ioServ != 0) {
        NSDictionary *info = (__bridge_transfer NSDictionary *)IODisplayCreateInfoDictionary(ioServ, kIODisplayOnlyPreferredName);
        const unsigned int vendorID = [info[@kDisplayVendorID] unsignedIntValue];
        const unsigned int productID = [info[@kDisplayProductID] unsignedIntValue];
        const unsigned int serialNumber = [info[@kDisplaySerialNumber] unsignedIntValue];

        if (CGDisplayVendorNumber(displayID) == vendorID &&
            CGDisplayModelNumber(displayID) == productID &&
            CGDisplaySerialNumber(displayID) == serialNumber) {
            return ioServ;
        }

        ioServ = IOIteratorNext(serialPortIterator);
    }
    return 0;
}

- (NSString *)it_legacyNonUniqueName NS_DEPRECATED_MAC(10_14, 10_15) {
    const CGDirectDisplayID displayID = [self it_displayID];
    io_service_t ioServicePort = iTermGetIOService(displayID);
    if (ioServicePort == 0) {
        return [self it_fallbackName];
    }

    NSDictionary *info = (__bridge_transfer NSDictionary *)IODisplayCreateInfoDictionary(ioServicePort, kIODisplayOnlyPreferredName);
    if (!info) {
        return [self it_fallbackName];
    }

    NSDictionary *productName = info[@"DisplayProductName"];
    if (!productName.allValues.firstObject) {
        return [self it_fallbackName];
    }
    return productName.allValues.firstObject;
}

- (NSString *)it_nonUniqueName {
    if (@available(macOS 10.15, *)) {
        return [self localizedName];
    } else {
        return [self it_legacyNonUniqueName];
    }
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
        return NO;
    }
    NSSet<NSNumber *> *windowNumbers = [NSSet setWithArray:[[NSApp windows] mapWithBlock:^id(NSWindow *window) {
        return @(window.windowNumber);
    }]];
    NSArray<NSDictionary *> *allInfos = [NSScreen it_allWindowInfoDictionaries];
    return [allInfos anyWithBlock:^BOOL(NSDictionary *windowInfo) {
        const CGRect windowFrame = [NSScreen windowBoundsRectFromWindowInfoDictionary:windowInfo];
        if (!NSEqualRects(windowFrame, screenFrame)) {
            return NO;
        }
        if ([windowInfo[(__bridge NSString *)kCGWindowAlpha] doubleValue] <= 0) {
            return NO;
        }
        if (![windowInfo[(__bridge NSString *)kCGWindowIsOnscreen] boolValue]) {
            return NO;
        }
        NSNumber *windowNumber = windowInfo[(__bridge NSString *)kCGWindowNumber];
        if ([windowNumbers containsObject:windowNumber]) {
            // Is my own window.
            return NO;
        }
        return YES;
    }];
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
    const double refreshRate = CGDisplayModeGetRefreshRate(mode);
    CFRelease(mode);
    const BOOL result = refreshRate >= 120;
    [self it_setSupportsHighFrameRates:result];
    return result;
}

@end
