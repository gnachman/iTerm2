//
//  iTermWindowSpace.h
//  iTerm2
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// Remembers which Space (virtual desktop) a window is on and puts it back there.
//
// macOS has no public API for this, so it uses private CoreGraphics functions
// looked up at runtime. If any of them is missing, every method does nothing
// and the window stays wherever macOS opened it.
//
// A Space is identified by its UUID, which macOS keeps across reboots. Space
// IDs (ManagedSpaceID) are not stable and are never stored.
@interface iTermWindowSpace : NSObject

// A dictionary describing the Space the window is on, suitable for an
// arrangement, or nil if the window is not on exactly one ordinary desktop
// (for example when it is on all Spaces or in full screen).
+ (nullable NSDictionary *)arrangementValueForWindow:(NSWindow *)window;

// Moves the window to the Space described by a value from
// +arrangementValueForWindow:. Does nothing if that Space no longer exists.
+ (void)moveWindow:(NSWindow *)window toSpaceFromArrangementValue:(nullable NSDictionary *)value;

@end

NS_ASSUME_NONNULL_END
