//
//  LineBufferSorting.h
//  iTerm2
//
//  Created by George Nachman on 4/12/22.
//

#import <Foundation/Foundation.h>
#import "VT100GridTypes.h"

@class ResultRange;

#if __cplusplus
extern "C"
#endif
int *SortedPositionsFromResultRanges(NSArray<ResultRange *> *ranges, BOOL includeEnds);

@interface LineBufferSearchIntermediateMap: NSObject
- (instancetype)initWithCapacity:(int)capacity NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)addCoordinate:(VT100GridCoord)coord forPosition:(int)position;
- (void)enumerateCoordPairsForRanges:(NSArray<ResultRange *> *)ranges
                               block:(void (^ NS_NOESCAPE)(VT100GridCoord, VT100GridCoord))block;

@end
