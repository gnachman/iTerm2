//
//  iTermFullScreenUpdateDetector.h
//  iTerm2
//
//  Created by George Nachman on 4/23/15.
//
//

#import <Foundation/Foundation.h>

// The "explicit" property angers c++.
#if defined(__cplusplus)
@class iTermTemporaryDoubleBufferedGridController;
@protocol iTermTemporaryDoubleBufferedGridControllerDelegate;
@protocol iTermTemporaryDoubleBufferedGridControllerReading;
#else  // __cplusplus

#import "VT100GridTypes.h"
#import "PTYTextViewDataSource.h"

@class iTermColorMap;
@class VT100Grid;

@protocol iTermTemporaryDoubleBufferedGridControllerDelegate<NSObject>

// Returns current state to save
- (PTYTextViewSynchronousUpdateState *)temporaryDoubleBufferedGridSavedState;

// A saved grid that was drawn has expired. The view should be redrawn with the current grid.
- (void)temporaryDoubleBufferedGridDidExpire;

@end

@protocol iTermTemporaryDoubleBufferedGridControllerReading<NSObject>
@property(nonatomic, readonly) id<PTYTextViewSynchronousUpdateStateReading> savedState;

// Implicit is when it's based on cursor visibility. Explicit is from a sync update control sequence.
// Implicit cannot override explicit. Timing out resets explicit. -startExplicitly sets it to true.
// -resetExplicitly sets it to false. When true, -reset and -start are no-ops.
@property(nonatomic, readonly) BOOL explicit;

// True while the saved grid covers a prompt repaint that was proven to end by showing the cursor.
// See -startForPromptRepaint. Unlike the implicit mode, this applies even when Reduce Flicker is
// off.
@property(nonatomic, readonly) BOOL promptRepaint;

// True if the saved grid should be drawn even when Reduce Flicker is off.
@property(nonatomic, readonly) BOOL appliesWithoutReduceFlicker;

// Set this to use if you're drawing the view from the saved grid in order to get a notification
// when it expires.
@property(nonatomic, readonly) BOOL drewSavedGrid;
@end

@interface iTermTemporaryDoubleBufferedGridController : NSObject<iTermTemporaryDoubleBufferedGridControllerReading, NSCopying>

@property(nonatomic, weak) id<iTermTemporaryDoubleBufferedGridControllerDelegate> delegate;
@property(nonatomic, readonly) PTYTextViewSynchronousUpdateState *savedState;

// Implicit is when it's based on cursor visibility. Explicit is from a sync update control sequence.
// Implicit cannot override explicit. Timing out resets explicit. -startExplicitly sets it to true.
// -resetExplicitly sets it to false. When true, -reset and -start are no-ops.
@property(nonatomic, readonly) BOOL explicit;
@property(nonatomic, readonly) BOOL promptRepaint;

// Set this to use if you're drawing the view from the saved grid in order to get a notification
// when it expires.
@property(nonatomic) BOOL drewSavedGrid;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(atomic) BOOL dirty;

- (instancetype)initWithQueue:(dispatch_queue_t)queue NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// Save the grid if there isn't already a saved grid.
- (void)start;
- (void)startExplicitly;

// Save the grid when the cursor is hidden at the start of a shell's prompt repaint whose end (the
// cursor shown again) is already known to be on its way. -reset ends it like the implicit mode.
// Does nothing if there's already a saved grid.
- (void)startForPromptRepaint;

// Remove the saved grid.
- (void)reset;
- (void)resetExplicitly;

@end

#endif  // __cplusplus
