//
//  LineBufferHelpers.h
//  iTerm
//
//  Created by George Nachman on 11/21/13.
//
//

#import <Foundation/Foundation.h>
#import "VT100GridTypes.h"

@class MutableResultRange;

// When receiving search results, you'll get an array of this class. Positions
// can be converted to x,y coordinates with -convertPosition:withWidth:toX:toY.
// length gives the number of screen_char_t elements matching the search (which
// may differ from the number of code points in the search string because of
// the vagueries of unicode, or more obviously, for regex searches).
@interface ResultRange : NSObject {
@public
    int position;
    int length;
}
@property (nonatomic, readonly) int position;
@property (nonatomic, readonly) int length;
@property (nonatomic, readonly) int upperBound;

- (instancetype)initWithPosition:(int)position length:(int)length;
- (MutableResultRange *)mutableCopy;

@end

@interface MutableResultRange : ResultRange

@property (nonatomic, readwrite) int position;
@property (nonatomic, readwrite) int length;

@end

// Holds the state for a multi-line search that may span multiple LineBlocks.
// Used both as a return value and as input when resuming a search on a subsequent block.
@interface LineBlockMultiLineSearchState : NSObject

// When returning: the completed result if a full match was found, or nil if not found/incomplete.
// When passing in: should be nil (we're resuming an incomplete search).
@property (nonatomic, strong, nullable) MutableResultRange *result;

// When returning: YES if we ran out of lines in this block and need to continue on the next block.
// When passing in: not used.
@property (nonatomic) BOOL needsContinuation;

// When returning: the query line index we stopped at (only meaningful if needsContinuation is YES).
// When passing in: the query line index to resume from.
@property (nonatomic) NSInteger queryLineIndex;

// When returning: the partial range built so far (only meaningful if needsContinuation is YES).
// When passing in: the partial range to continue building from the previous block.
@property (nonatomic, strong, nullable) MutableResultRange *partialResult;

// The global position of the block where the partial match started.
// Set by LineBuffer when saving continuation state, used when completing the match.
@property (nonatomic) int startingBlockPosition;

// Convenience initializer for starting a fresh search (not resuming).
+ (instancetype)initialState;

// Convenience initializer for creating a "found" result.
+ (instancetype)stateWithResult:(MutableResultRange *)result;

// Convenience initializer for creating a "needs continuation" result.
+ (instancetype)stateNeedingContinuationAtIndex:(NSInteger)index
                                  partialResult:(MutableResultRange *)partialResult;

@end

@interface XYRange : NSObject {
@public
    int xStart;
    int yStart;
    int xEnd;
    int yEnd;
}

@property (nonatomic, readonly) int xStart;
@property (nonatomic, readonly) int yStart;
@property (nonatomic, readonly) int xEnd;
@property (nonatomic, readonly) int yEnd;

@property (nonatomic, readonly) VT100GridCoordRange coordRange;

@end

