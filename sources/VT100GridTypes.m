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

NSString *VT100GridCoordRangeDescription(VT100GridCoordRange range) {
    return [NSString stringWithFormat:@"((%d, %d) to (%d, %d))",
            range.start.x,
            range.start.y,
            range.end.x,
            range.end.y];
}

NSString *VT100GridWindowedRangeDescription(VT100GridWindowedRange range) {
    return [NSString stringWithFormat:@"<%@ restricted to cols [%d, %d]>",
            VT100GridCoordRangeDescription(range.coordRange),
            range.columnWindow.location,
            range.columnWindow.location + range.columnWindow.length - 1];
}

NSString *VT100GridAbsCoordRangeDescription(VT100GridAbsCoordRange range) {
    return [NSString stringWithFormat:@"<(%d, %lld) to (%d, %lld)>",
            range.start.x,
            range.start.y,
            range.end.x,
            range.end.y];
}

NSString *VT100GridSizeDescription(VT100GridSize size) {
    return [NSString stringWithFormat:@"%d x %d", size.width, size.height];
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

+ (NSValue *)valueWithGridCoordRange:(VT100GridCoordRange)coordRange {
    return [[[NSValue alloc] initWithBytes:&coordRange objCType:@encode(VT100GridCoordRange)] autorelease];
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

- (VT100GridCoordRange)gridCoordRangeValue {
  VT100GridCoordRange coordRange;
  [self getValue:&coordRange];
  return coordRange;
}

- (NSComparisonResult)compareGridCoordRangeStart:(NSValue *)other {
    return VT100GridCoordOrder([self gridCoordRangeValue].start, [other gridCoordRangeValue].start);
}

@end

