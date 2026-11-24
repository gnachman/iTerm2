//
//  iTermWindowSpace.m
//  iTerm2
//

#import "iTermWindowSpace.h"

#import "DebugLogging.h"
#import "FutureMethods.h"

static NSString *const iTermWindowSpaceUUIDKey = @"UUID";

// CGSCopySpacesForWindows mask meaning “all Spaces the window is on”.
static const int iTermWindowSpaceAllSpacesMask = 7;

// The "type" of an ordinary desktop in CGSCopyManagedDisplaySpaces. Full screen
// Spaces have other types and are left to macOS.
static const int iTermWindowSpaceTypeDesktop = 0;

@implementation iTermWindowSpace

// Maps ManagedSpaceID to UUID for every ordinary desktop on every display.
+ (nullable NSDictionary<NSNumber *, NSString *> *)desktopUUIDsBySpaceID {
    CGSCopyManagedDisplaySpacesFunction *copyDisplaySpaces = GetCGSCopyManagedDisplaySpacesFunction();
    if (!copyDisplaySpaces) {
        DLog(@"CGSCopyManagedDisplaySpaces is not available");
        return nil;
    }
    NSArray *displays = CFBridgingRelease(copyDisplaySpaces(CGSMainConnectionID()));
    NSMutableDictionary<NSNumber *, NSString *> *result = [NSMutableDictionary dictionary];
    for (NSDictionary *display in displays) {
        if (![display isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSArray *spaces = display[@"Spaces"];
        if (![spaces isKindOfClass:[NSArray class]]) {
            continue;
        }
        for (NSDictionary *space in spaces) {
            if (![space isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSNumber *spaceID = space[@"ManagedSpaceID"];
            NSString *uuid = space[@"uuid"];
            NSNumber *type = space[@"type"];
            if (![spaceID isKindOfClass:[NSNumber class]] ||
                ![uuid isKindOfClass:[NSString class]] ||
                uuid.length == 0 ||
                ![type isKindOfClass:[NSNumber class]] ||
                type.intValue != iTermWindowSpaceTypeDesktop) {
                continue;
            }
            result[spaceID] = uuid;
        }
    }
    return result;
}

+ (nullable NSDictionary *)arrangementValueForWindow:(NSWindow *)window {
    CGSCopySpacesForWindowsFunction *copySpacesForWindows = GetCGSCopySpacesForWindowsFunction();
    if (!copySpacesForWindows || window.windowNumber <= 0) {
        return nil;
    }
    if (window.collectionBehavior & NSWindowCollectionBehaviorCanJoinAllSpaces) {
        return nil;
    }
    NSArray *windowIDs = @[ @(window.windowNumber) ];
    NSArray<NSNumber *> *spaceIDs = CFBridgingRelease(copySpacesForWindows(CGSMainConnectionID(),
                                                                           iTermWindowSpaceAllSpacesMask,
                                                                           (__bridge CFArrayRef)windowIDs));
    if (spaceIDs.count != 1) {
        DLog(@"Window %@ is on %@ Spaces; not saving one", window, @(spaceIDs.count));
        return nil;
    }
    NSString *uuid = [self desktopUUIDsBySpaceID][spaceIDs.firstObject];
    if (!uuid) {
        DLog(@"Space %@ of window %@ is not an ordinary desktop", spaceIDs.firstObject, window);
        return nil;
    }
    return @{ iTermWindowSpaceUUIDKey: uuid };
}

+ (void)moveWindow:(NSWindow *)window toSpaceFromArrangementValue:(nullable NSDictionary *)value {
    if (![value isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSString *uuid = value[iTermWindowSpaceUUIDKey];
    if (![uuid isKindOfClass:[NSString class]] || uuid.length == 0) {
        return;
    }
    CGSMoveWindowsToManagedSpaceFunction *moveWindows = GetCGSMoveWindowsToManagedSpaceFunction();
    if (!moveWindows || window.windowNumber <= 0) {
        return;
    }
    NSDictionary<NSNumber *, NSString *> *uuids = [self desktopUUIDsBySpaceID];
    NSNumber *spaceID = [[uuids allKeysForObject:uuid] firstObject];
    if (!spaceID) {
        DLog(@"Space %@ no longer exists; leaving window %@ where it is", uuid, window);
        return;
    }
    DLog(@"Move window %@ to Space %@ (%@)", window, spaceID, uuid);
    moveWindows(CGSMainConnectionID(),
                (__bridge CFArrayRef)@[ @(window.windowNumber) ],
                spaceID.unsignedLongLongValue);
}

@end
