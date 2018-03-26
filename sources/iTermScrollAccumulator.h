//
//  iTermScrollAccumulator.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/24/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermScrollAccumulator : NSObject

// Add scrolling delta to the accumulator if needed and return the number of lines to scroll by.
- (CGFloat)deltaYForEvent:(NSEvent *)event lineHeight:(CGFloat)lineHeight;

// Legacy algorithm, to be kept around until the new algoirthm has been validated.
- (CGFloat)legacyDeltaYForEvent:(NSEvent *)theEvent lineHeight:(CGFloat)lineHeight;

// Resets the internal accumulator to 0.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
