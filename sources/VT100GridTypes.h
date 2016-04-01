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
    int x;
    long long y;
} VT100GridAbsCoord;

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

typedef struct {
    VT100GridAbsCoord start;
    VT100GridAbsCoord end;
} VT100GridAbsCoordRange;

typedef struct {
    VT100GridCoordRange coordRange;
    VT100GridRange columnWindow;
} VT100GridWindowedRange;

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

// Use for sorting array of VT100GridCoorRange's in NSValue*s by the start coord.
- (NSComparisonResult)compareGridCoordRangeStart:(NSValue *)other;

@end

NSString *VT100GridCoordRangeDescription(VT100GridCoordRange range);
NSString *VT100GridWindowedRangeDescription(VT100GridWindowedRange range);
NSString *VT100GridAbsCoordRangeDescription(VT100GridAbsCoordRange range);
NSString *VT100GridSizeDescription(VT100GridSize size);

NS_INLINE VT100GridCoord VT100GridCoordMake(int x, int y) {
    VT100GridCoord coord;
    coord.x = x;
    coord.y = y;
    return coord;
}

NS_INLINE VT100GridAbsCoord VT100GridAbsCoordMake(int x, long long y) {
    VT100GridAbsCoord coord;
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

NS_INLINE BOOL VT100GridRangeContains(VT100GridRange range, int value) {
    return value >= range.location && value < range.location + range.length;
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

NS_INLINE BOOL VT100GridSizeEquals(VT100GridSize a, VT100GridSize b) {
    return a.width == b.width && a.height == b.height;
}

NS_INLINE VT100GridWindowedRange VT100GridWindowedRangeMake(VT100GridCoordRange range,
                                                            int windowStart,
                                                            int windowWidth) {
    VT100GridWindowedRange windowedRange;
    windowedRange.coordRange = range;
    windowedRange.columnWindow.location = windowStart;
    windowedRange.columnWindow.length = windowWidth;
    return windowedRange;
}

NS_INLINE VT100GridCoord VT100GridWindowedRangeStart(VT100GridWindowedRange range) {
    VT100GridCoord coord = range.coordRange.start;
    if (range.columnWindow.length) {
        coord.x = MIN(MAX(coord.x, range.columnWindow.location),
                      range.columnWindow.location + range.columnWindow.length);
    }
    return coord;
}

NS_INLINE VT100GridCoord VT100GridWindowedRangeEnd(VT100GridWindowedRange range) {
    VT100GridCoord coord = range.coordRange.end;
    if (range.columnWindow.length) {
        coord.x = MIN(coord.x, VT100GridRangeMax(range.columnWindow) + 1);
    }
    return coord;
}

// Ascending: a < b
// Descending: a > b
// Same: a == b
NS_INLINE NSComparisonResult VT100GridCoordOrder(VT100GridCoord a, VT100GridCoord b) {
    if (a.y < b.y) {
        return NSOrderedAscending;
    }
    if (a.y > b.y) {
        return NSOrderedDescending;
    }
    if (a.x < b.x) {
        return NSOrderedAscending;
    }
    if (a.x > b.x) {
        return NSOrderedDescending;
    }

    return NSOrderedSame;
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

NS_INLINE VT100GridAbsCoordRange VT100GridAbsCoordRangeMake(int startX,
                                                            long long startY,
                                                            int endX,
                                                            long long endY) {
    VT100GridAbsCoordRange coordRange;
    coordRange.start.x = startX;
    coordRange.start.y = startY;
    coordRange.end.x = endX;
    coordRange.end.y = endY;
    return coordRange;
}

NS_INLINE NSString *VT100GridCoordDescription(VT100GridCoord c) {
    return [NSString stringWithFormat:@"(%d, %d)", c.x, c.y];
}

NS_INLINE NSString *VT100GridRangeDescription(VT100GridRange r) {
    return [NSString stringWithFormat:@"[%d, %d)", r.location, r.location + r.length];
}

NS_INLINE VT100GridCoord VT100GridCoordRangeMin(VT100GridCoordRange range) {
    if (VT100GridCoordOrder(range.start, range.end) == NSOrderedAscending) {
        return range.start;
    } else {
        return range.end;
    }
}

NS_INLINE VT100GridCoord VT100GridCoordRangeMax(VT100GridCoordRange range) {
    if (VT100GridCoordOrder(range.start, range.end) == NSOrderedAscending) {
        return range.end;
    } else {
        return range.start;
    }
}

NS_INLINE BOOL VT100GridCoordRangeContainsCoord(VT100GridCoordRange range, VT100GridCoord coord) {
  NSComparisonResult order = VT100GridCoordOrder(VT100GridCoordRangeMin(range), coord);
  if (order == NSOrderedDescending) {
    return NO;
  }

  order = VT100GridCoordOrder(VT100GridCoordRangeMax(range), coord);
  return (order == NSOrderedDescending);
}

NS_INLINE long long VT100GridCoordDistance(VT100GridCoord a, VT100GridCoord b, int gridWidth) {
    long long aPos = a.y;
    aPos *= gridWidth;
    aPos += a.x;

    long long bPos = b.y;
    bPos *= gridWidth;
    bPos += b.x;

    return llabs(aPos - bPos);
}

NS_INLINE long long VT100GridWindowedRangeLength(VT100GridWindowedRange range, int gridWidth) {
    if (range.coordRange.start.y == range.coordRange.end.y) {
        return VT100GridWindowedRangeEnd(range).x - VT100GridWindowedRangeStart(range).x;
    } else {
        int left = range.columnWindow.location;
        int right = left + range.columnWindow.length;
        int numFullLines = MAX(0, (range.coordRange.end.y - range.coordRange.start.y - 1));
        return ((right - VT100GridWindowedRangeStart(range).x) +  // Chars on first line
                (VT100GridWindowedRangeEnd(range).x - left) +  // Chars on second line
                range.columnWindow.length * numFullLines);  // Chars inbetween
    }
}

NS_INLINE long long VT100GridCoordRangeLength(VT100GridCoordRange range, int gridWidth) {
    return VT100GridCoordDistance(range.start, range.end, gridWidth);
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
