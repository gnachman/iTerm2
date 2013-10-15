#import "VT100GridTypes.h"

VT100GridRun VT100GridRunFromCoords(VT100GridCoord start,
                                    VT100GridCoord end,
                                    int width) {
    VT100GridRun run;
    run.origin = start;
    if (start.y == end.y) {
        run.length = end.x - start.x + 1;
    } else {
        run.length = width - start.x + end.x + 1 + width * (end.y - start.y - 1);
    }
    return run;
}

@implementation NSValue (VT100Grid)

+ (NSValue *)valueWithGridCoord:(VT100GridCoord)coord {
    return [[[NSValue alloc] initWithBytes:&coord objCType:@encode(VT100GridCoord)] autorelease];
}

+ (NSValue *)valueWithGridSize:(VT100GridSize)size {
    return [[[NSValue alloc] initWithBytes:&size objCType:@encode(VT100GridSize)] autorelease];
}

+ (NSValue *)valueWithGridRange:(VT100GridRange)range {
    return [[[NSValue alloc] initWithBytes:&range objCType:@encode(VT100GridRange)] autorelease];
}

+ (NSValue *)valueWithGridRect:(VT100GridRect)rect {
    return [[[NSValue alloc] initWithBytes:&rect objCType:@encode(VT100GridRect)] autorelease];
}

+ (NSValue *)valueWithGridRun:(VT100GridRun)run {
    return [[[NSValue alloc] initWithBytes:&run objCType:@encode(VT100GridRun)] autorelease];
}

- (VT100GridCoord)gridCoordValue {
    VT100GridCoord coord;
    [self getValue:&coord];
    return coord;
}

- (VT100GridSize)gridSizeValue {
    VT100GridSize size;
    [self getValue:&size];
    return size;
}

- (VT100GridRange)gridRangeValue {
    VT100GridRange range;
    [self getValue:&range];
    return range;
}

- (VT100GridRect)gridRectValue {
    VT100GridRect rect;
    [self getValue:&rect];
    return rect;
}

- (VT100GridRun)gridRunValue {
    VT100GridRun run;
    [self getValue:&run];
    return run;
}

@end

