#import "VT100GridTypes.h"

NS_ASSUME_NONNULL_BEGIN

const VT100GridCoord VT100GridCoordInvalid = {
    .x = INT_MIN,
    .y = INT_MIN
};

const VT100GridCoordRange VT100GridCoordRangeInvalid = {
    .start = {
        .x = INT_MIN,
        .y = INT_MIN
    },
    .end = {
        .x = INT_MIN,
        .y = INT_MIN
    }
};

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

NSString *VT100GridAbsWindowedRangeDescription(VT100GridAbsWindowedRange range) {
    return [NSString stringWithFormat:@"<%@ restricted to cols %@>",
            VT100GridAbsCoordRangeDescription(range.coordRange),
            VT100GridRangeDescription(range.columnWindow)];
}

@implementation NSValue (VT100Grid)

+ (NSValue *)valueWithGridCoord:(VT100GridCoord)coord {
    return [[[NSValue alloc] initWithBytes:&coord objCType:@encode(VT100GridCoord)] autorelease];
}

+ (NSValue *)valueWithGridAbsCoord:(VT100GridAbsCoord)absCoord {
    return [[[NSValue alloc] initWithBytes:&absCoord objCType:@encode(VT100GridAbsCoord)] autorelease];
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

+ (NSValue *)valueWithGridAbsCoordRange:(VT100GridAbsCoordRange)absCoordRange {
    return [[[NSValue alloc] initWithBytes:&absCoordRange objCType:@encode(VT100GridAbsCoordRange)] autorelease];
}

- (VT100GridCoord)gridCoordValue {
    VT100GridCoord coord;
    [self getValue:&coord];
    return coord;
}

- (VT100GridAbsCoord)gridAbsCoordValue {
    VT100GridAbsCoord absCoord;
    [self getValue:&absCoord size:sizeof(absCoord)];
    return absCoord;
}

- (VT100GridSize)gridSizeValue {
    VT100GridSize size;
    [self getValue:&size size:sizeof(size)];
    return size;
}

- (VT100GridRange)gridRangeValue {
    VT100GridRange range;
    [self getValue:&range size:sizeof(range)];
    return range;
}

- (VT100GridRect)gridRectValue {
    VT100GridRect rect;
    [self getValue:&rect size:sizeof(rect)];
    return rect;
}

- (VT100GridRun)gridRunValue {
    VT100GridRun run;
    [self getValue:&run size:sizeof(run)];
    return run;
}

- (VT100GridCoordRange)gridCoordRangeValue {
  VT100GridCoordRange coordRange;
  [self getValue:&coordRange size:sizeof(coordRange)];
  return coordRange;
}

- (VT100GridAbsCoordRange)gridAbsCoordRangeValue {
    VT100GridAbsCoordRange absCoordRange;
    [self getValue:&absCoordRange size:sizeof(absCoordRange)];
    return absCoordRange;
}

- (NSComparisonResult)compareGridAbsCoordRangeStart:(NSValue *)other {
    return VT100GridAbsCoordOrder([self gridAbsCoordRangeValue].start, [other gridAbsCoordRangeValue].start);
}

@end

NS_ASSUME_NONNULL_END
