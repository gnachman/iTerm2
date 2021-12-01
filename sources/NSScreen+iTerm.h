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

@end

NS_ASSUME_NONNULL_END
