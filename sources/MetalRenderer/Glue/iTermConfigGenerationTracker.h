//
//  iTermConfigGenerationTracker.h
//  iTerm2
//
//  Assigns a stable, collision-free generation to a set of row-build inputs by
//  exact comparison against the previous call (not by hashing). The generation
//  advances only when the inputs, color space, or font table actually change,
//  so unchanged frames keep the same value and a per-row cache keyed on it stays
//  valid. Because it compares rather than hashes, distinct inputs can never map
//  to the same generation (a collision would serve a stale cached row).
//
//  One instance per text view (the comparison is against that view's previous
//  frame). Not thread-safe; use from a single thread (the main thread).
//

#import <Foundation/Foundation.h>
#import "iTermRowRenderInputs.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermFontTable;

@interface iTermConfigGenerationTracker : NSObject

- (uint64_t)generationForRenderInputs:(const iTermRowRenderInputs *)inputs
                           colorSpace:(NSColorSpace *)colorSpace
                            fontTable:(nullable iTermFontTable *)fontTable;

@end

NS_ASSUME_NONNULL_END
