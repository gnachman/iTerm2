//
//  iTermScrollAccumulator.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/24/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermScrollAccumulator : NSObject

// Defaults to YES.
@property (nonatomic) BOOL isVertical;

// Defaults to 1. Use a smaller number to reduce sensitivity. Scrolling delta is multiplied by this value.
@property (nonatomic) double sensitivity;

// Add scrolling delta to the accumulator if needed and return the number of cells to scroll by.
- (CGFloat)deltaForEvent:(NSEvent *)event increment:(CGFloat)increment;

// Legacy algorithm, to be kept around until the new algorithm has been validated.
- (CGFloat)legacyDeltaForEvent:(NSEvent *)theEvent increment:(CGFloat)increment;

// Resets the internal accumulator to 0.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
