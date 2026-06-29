//
//  LineBufferSorting.cpp
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/12/22.
//

#include "LineBufferSorting.h"

#include <algorithm>
#include <unordered_map>

#import "LineBufferHelpers.h"
extern "C" {
#import "iTermMalloc.h"
}

extern "C" int *SortedPositionsFromResultRanges(NSArray<ResultRange *> *ranges,
                                                BOOL includeEnds) {
    const int count = ranges.count;
    const int resultCount = includeEnds ? count * 2 : count;
    int *result = (int *)iTermMalloc(sizeof(int) * resultCount);
    int o = 0;
    for (ResultRange *rr in ranges) {
        const int position = rr->position;
        result[o++] = position;
        if (includeEnds) {
            result[o++] = position + rr->length - 1;
        }
    }

    std::sort(result, result + resultCount);
    return result;
}


@implementation LineBufferSearchIntermediateMap {
    std::unordered_map<int, VT100GridCoord> _map;
}

- (instancetype)initWithCapacity:(int)capacity {
    self = [super init];
    if (self) {
        _map.reserve(capacity);
    }
    return self;
}

- (void)addCoordinate:(VT100GridCoord)coord forPosition:(int)position {
    _map[position] = coord;
}

- (void)enumerateCoordPairsForRanges:(NSArray<ResultRange *> *)ranges
                               block:(void (^ NS_NOESCAPE)(VT100GridCoord, VT100GridCoord))block {
    for (ResultRange *rr in ranges) {
        auto start_it = _map.find(rr->position);
        auto end_it = _map.find(rr->position + rr->length - 1);
        if (start_it == _map.end()) {
            continue;
        }
        if (end_it == _map.end()) {
            continue;
        }
        block(start_it->second, end_it->second);
    }
}

@end
