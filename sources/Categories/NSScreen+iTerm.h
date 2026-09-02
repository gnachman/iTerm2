//
//  NSScreen+iTerm.h
//  iTerm
//
//  Created by George Nachman on 6/28/14.
//
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSScreen (iTerm)

// Returns the screen that includes the mouse pointer.
+ (NSScreen *)screenWithCursor;
+ (NSScreen * _Nullable)screenWithFrame:(NSRect)frame;
+ (NSScreen * _Nullable)it_screenWithUniqueKey:(NSString *)key;
+ (BOOL)it_stringLooksLikeUniqueKey:(NSString *)string;
+ (double)fractionOfFrameOnAnyScreen:(NSRect)frame
                   recommendedOrigin:(NSPoint *)recommendedOriginPtr;
+ (NSScreen * _Nullable)screenContainingCoordinate:(NSPoint)point;

// Returns the visible frame modified to not include the 4 pixel boundary given to a hidden dock.
// Kind of a gross hack since the magic 4 pixel number could change in the future.
- (NSRect)visibleFrameIgnoringHiddenDock;

- (NSRect)frameExceptMenuBar;
- (NSRect)frameExceptNotch;
- (BOOL)hasDock;
- (NSString *)it_description;

typedef struct iTermScreenIdentifier {
    uint32_t modelNumber;
    uint32_t vendorNumber;
    uint32_t serialNumber;
} iTermScreenIdentifier;

- (iTermScreenIdentifier)it_identifier;
- (NSString *)it_uniqueName;
- (NSString *)it_uniqueKey;

- (BOOL)it_hasAnotherAppsFullScreenWindow;
- (BOOL)it_supportsHighFrameRates;

- (CGFloat)it_menuBarHeight;

// YES if the display can show content brighter than reference white, i.e. it has
// extended-dynamic-range headroom. Uses the potential (not current) headroom: on
// a reference-mode XDR display the current headroom reads 1.0 even while the panel
// can display EDR content. This is the single predicate shared by every HDR path.
- (BOOL)it_hasEDRHeadroom;

// An extended-range color space matching the display's gamut (extended Display P3
// on a wide-gamut panel, otherwise extended sRGB). Content above 1.0 is only
// preserved (rather than clamped) in an extended color space; matching the gamut
// avoids shifting in-gamut color reproduction. Returns nil if none can be made.
- (nullable CGColorSpaceRef)it_extendedDynamicRangeColorSpace CF_RETURNS_NOT_RETAINED;

@end

NS_ASSUME_NONNULL_END
