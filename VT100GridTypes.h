//
//  VT100GridTypes.h
//  iTerm
//
//  Created by George Nachman on 10/13/13.
//
//

#import <Foundation/Foundation.h>

typedef struct {
    int x;
    int y;
} VT100GridCoord;

typedef struct {
    int width;
    int height;
} VT100GridSize;

typedef struct {
    int location;
    int length;
} VT100GridRange;

typedef struct {
    VT100GridCoord origin;
    VT100GridSize size;
} VT100GridRect;

typedef struct {
    VT100GridCoord origin;
    int length;
} VT100GridRun;

typedef struct {
  VT100GridCoord start;
  VT100GridCoord end;
} VT100GridCoordRange;

@interface NSValue (VT100Grid)

+ (NSValue *)valueWithGridCoord:(VT100GridCoord)coord;
+ (NSValue *)valueWithGridSize:(VT100GridSize)size;
+ (NSValue *)valueWithGridRange:(VT100GridRange)range;
+ (NSValue *)valueWithGridRect:(VT100GridRect)rect;
+ (NSValue *)valueWithGridRun:(VT100GridRun)run;
+ (NSValue *)valueWithGridCoordRange:(VT100GridCoordRange)coordRange;

- (VT100GridCoord)gridCoordValue;
- (VT100GridSize)gridSizeValue;
- (VT100GridRange)gridRangeValue;
- (VT100GridRect)gridRectValue;
- (VT100GridRun)gridRunValue;
- (VT100GridCoordRange)gridCoordRangeValue;

@end

NSString *VT100GridCoordRangeDescription(VT100GridCoordRange range);

NS_INLINE VT100GridCoord VT100GridCoordMake(int x, int y) {
    VT100GridCoord coord;
    coord.x = x;
    coord.y = y;
    return coord;
}

NS_INLINE VT100GridSize VT100GridSizeMake(int width, int height) {
    VT100GridSize size;
    size.width = width;
    size.height = height;
    return size;
}

NS_INLINE VT100GridRange VT100GridRangeMake(int location, int length) {
    VT100GridRange range;
    range.location = location;
    range.length = length;
    return range;
}

NS_INLINE int VT100GridRangeMax(VT100GridRange range) {
    return range.location + range.length - 1;
}

NS_INLINE VT100GridRect VT100GridRectMake(int x, int y, int width, int height) {
    VT100GridRect rect;
    rect.origin = VT100GridCoordMake(x, y);
    rect.size = VT100GridSizeMake(width, height);
    return rect;
}

NS_INLINE BOOL VT100GridRectEquals(VT100GridRect a, VT100GridRect b) {
    return (a.origin.x == b.origin.x &&
            a.origin.y == b.origin.y &&
            a.size.width == b.size.width &&
            a.size.height == b.size.height);
}

NS_INLINE BOOL VT100GridCoordEquals(VT100GridCoord a, VT100GridCoord b) {
    return a.x == b.x && a.y == b.y;
}

NS_INLINE VT100GridRun VT100GridRunMake(int x, int y, int length) {
    VT100GridRun run;
    run.origin.x = x;
    run.origin.y = y;
    run.length = length;
    return run;
}

NS_INLINE VT100GridCoordRange VT100GridCoordRangeMake(int startX, int startY, int endX, int endY) {
    VT100GridCoordRange coordRange;
    coordRange.start.x = startX;
    coordRange.start.y = startY;
    coordRange.end.x = endX;
    coordRange.end.y = endY;
    return coordRange;
}

NS_INLINE int VT100GridCoordRangeLength(VT100GridCoordRange range, int gridWidth) {
    long long end = range.end.y;
    end *= gridWidth;
    end += range.end.x;

    long long start = range.start.y;
    start *= gridWidth;
    start += range.start.x;

    return end - start;
}

// Returns the coord of the last char inside the run.
NS_INLINE VT100GridCoord VT100GridRunMax(VT100GridRun run, int width) {
    VT100GridCoord coord = run.origin;
    coord.y += (coord.x + run.length - 1) / width;
    coord.x = (coord.x + run.length - 1) % width;
    return coord;
}

// Returns the coord of the bottom-right cell that is in the rect. The rect must not be 0-dimensioned.
NS_INLINE VT100GridCoord VT100GridRectMax(VT100GridRect rect) {
    VT100GridCoord coord = rect.origin;
    coord.x += rect.size.width - 1;
    coord.y += rect.size.height - 1;
    return coord;
}

// Returns if the coord is within the rect.
NS_INLINE BOOL VT100GridCoordInRect(VT100GridCoord coord, VT100GridRect rect) {
    return (coord.x >= rect.origin.x &&
            coord.y >= rect.origin.y &&
            coord.x < rect.origin.x + rect.size.width &&
            coord.y < rect.origin.y + rect.size.height);
}

// Creates a run between two coords, not inclusive of end.
VT100GridRun VT100GridRunFromCoords(VT100GridCoord start,
                                    VT100GridCoord end,
                                    int width);
