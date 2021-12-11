//
//  VT100ScreenState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/10/21.
//
// All state from VT100Screen should eventually migrate here to facilitate a division between
// mutable and immutable code paths.

#import <Foundation/Foundation.h>

#import "IntervalTree.h"

NS_ASSUME_NONNULL_BEGIN

@class IntervalTree;
@class VT100InlineImageHelper;
@class iTermOrderEnforcer;

@protocol VT100ScreenState<NSObject>

@property (nonatomic, readonly) BOOL audibleBell;
@property (nonatomic, readonly) BOOL showBellIndicator;
@property (nonatomic, readonly) BOOL flashBell;
@property (nonatomic, readonly) BOOL postUserNotifications;
@property (nonatomic, readonly) BOOL cursorBlinks;

// When set, strings, newlines, and linefeeds are appended to printBuffer_. When ANSICSI_PRINT
// with code 4 is received, it's sent for printing.
@property (nonatomic, readonly) BOOL collectInputForPrinting;

@property (nullable, nonatomic, strong, readonly) NSString *printBuffer;

// OK to report window title?
@property (nonatomic, readonly) BOOL allowTitleReporting;

@property (nonatomic, readonly) NSTimeInterval lastBell;

// Line numbers containing animated GIFs that need to be redrawn for the next frame.
@property (nonatomic, strong, readonly) NSIndexSet *animatedLines;

// base64 value to copy to pasteboard, being built up bit by bit.
@property (nullable, nonatomic, strong, readonly) NSString *pasteboardString;

// All currently visible marks and notes. Maps an interval of
//   (startx + absstarty * (width+1)) to (endx + absendy * (width+1))
// to an id<IntervalTreeObject>, which is either PTYNoteViewController or VT100ScreenMark.
@property (nonatomic, strong, readonly) id<IntervalTreeReading> intervalTree;

@end

@interface VT100ScreenMutableState: NSObject<VT100ScreenState, NSCopying>

@property (nonatomic, readwrite) BOOL audibleBell;
@property (nonatomic, readwrite) BOOL showBellIndicator;
@property (nonatomic, readwrite) BOOL flashBell;
@property (nonatomic, readwrite) BOOL postUserNotifications;
@property (nonatomic, readwrite) BOOL cursorBlinks;
@property (nonatomic, readwrite) BOOL collectInputForPrinting;
@property (nullable, nonatomic, strong, readwrite) NSMutableString *printBuffer;
@property (nonatomic, readwrite) BOOL allowTitleReporting;
@property (nullable, nonatomic, strong) VT100InlineImageHelper *inlineImageHelper;
@property (nonatomic, readwrite) NSTimeInterval lastBell;
@property (nonatomic, strong, readwrite) NSMutableIndexSet *animatedLines;
@property (nullable, nonatomic, strong, readwrite) NSMutableString *pasteboardString;
@property (nonatomic, strong, readwrite) iTermOrderEnforcer *setWorkingDirectoryOrderEnforcer;
@property (nonatomic, strong, readwrite) iTermOrderEnforcer *currentDirectoryDidChangeOrderEnforcer;
@property (nonatomic, strong, readwrite) IntervalTree *intervalTree;

- (id<VT100ScreenState>)copy;

@end

NS_ASSUME_NONNULL_END
